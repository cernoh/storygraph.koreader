-- api.lua — StoryGraph HTTP client
-- Reverse-engineered endpoints for login, ISBN search, status/progress updates

local http = require("socket.http")
local ltn12 = require("ltn12")
local https = require("ssl.https")
local Config = require("config")
local logger = require("logger")

local Api = {}

local BASE_URL = "https://app.thestorygraph.com"

-- Helper: URL encode
local function urlencode(str)
    if str then
        str = str:gsub("\r?\n", "\r\n")
        str = str:gsub("([^%w %-%_%.%~])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = str:gsub(" ", "%%20")
    end
    return str
end

-- Helper: Extract CSRF token from HTML
local function extractCsrfToken(html)
    local token = html:match('<meta name="csrf%-token" content="([^"]+)"')
    return token
end

-- Helper: Parse cookies from Set-Cookie headers
local function parseCookies(response_headers)
    local cookies = {}
    if response_headers then
        for k, v in pairs(response_headers) do
            if k:lower() == "set-cookie" then
                local name, value = v:match("^([^=]+)=([^;]+)")
                if name and value then
                    cookies[name] = value
                end
            end
        end
    end
    return cookies
end

-- Helper: Build cookie header string
local function buildCookieHeader(cookies)
    local parts = {}
    for name, value in pairs(cookies) do
        table.insert(parts, name .. "=" .. value)
    end
    return table.concat(parts, "; ")
end

-- Helper: Format HTTP failure, surfacing Cloudflare-specific codes
local function formatHttpError(action, code, body, response_headers)
    local cf_error, cf_ray
    if response_headers then
        for k, v in pairs(response_headers) do
            if k:lower() == "cf-ray" then
                cf_ray = v
                break
            end
        end
    end
    if body then
        cf_error = body:match("Error%s+(%d%d%d%d?)")
            or body:match("error%s+code[%s:]*(%d%d%d%d?)")
            or body:match("cloudflare.-(%d%d%d%d?)")
    end

    local parts = { action .. " failed" }
    if cf_error then
        table.insert(parts, "Cloudflare error " .. cf_error)
    elseif cf_ray then
        table.insert(parts, "Cloudflare blocked request")
    end
    if cf_ray then
        table.insert(parts, "ray " .. cf_ray)
    end
    table.insert(parts, "HTTP " .. tostring(code or "unknown"))

    return table.concat(parts, " — ")
end

-- Helper: HTTP GET request
local function httpGet(url, cookies)
    local response_body = {}
    local headers = {
        ["Cookie"] = buildCookieHeader(cookies or {}),
        ["User-Agent"] = "KOReader/StoryGraph Plugin",
    }

    local res, code, response_headers = https.request{
        url = url,
        headers = headers,
        sink = ltn12.sink.table(response_body),
    }

    return table.concat(response_body), code, response_headers
end

-- Helper: HTTP POST request
local function httpPost(url, body, cookies, csrf_token)
    local response_body = {}
    local headers = {
        ["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8",
        ["Content-Length"] = #body,
        ["Cookie"] = buildCookieHeader(cookies or {}),
        ["User-Agent"] = "KOReader/StoryGraph Plugin",
        ["Origin"] = BASE_URL,
        ["Referer"] = BASE_URL,
    }

    if csrf_token then
        headers["x-csrf-token"] = csrf_token
        headers["x-requested-with"] = "XMLHttpRequest"
    end

    local res, code, response_headers = https.request{
        url = url,
        method = "POST",
        headers = headers,
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(response_body),
    }

    return table.concat(response_body), code, response_headers
end

-- Login to StoryGraph
function Api.login()
    local creds = Config.getCredentials()
    if not creds.email or not creds.password then
        return false, "No credentials configured"
    end

    -- Step 1: GET login page to get initial CSRF token
    local html, code, headers = httpGet(BASE_URL .. "/users/sign_in")
    if not html or code ~= 200 then
        return false, formatHttpError("Login page load", code, html, headers)
    end

    local csrf_token = extractCsrfToken(html)
    if not csrf_token then
        return false, "Could not extract CSRF token"
    end

    -- Step 2: POST login
    local body = string.format(
        "authenticity_token=%s&user[email]=%s&user[password]=%s&user[remember_me]=1&return_to=",
        urlencode(csrf_token),
        urlencode(creds.email),
        urlencode(creds.password)
    )

    local response, status, post_headers = httpPost(BASE_URL .. "/users/sign_in", body, {})

    if status ~= 303 and status ~= 200 then
        return false, formatHttpError("Login", status, response, post_headers)
    end

    -- Step 3: Extract session cookies
    local cookies = parseCookies(post_headers)
    if not cookies["_storygraph_session"] then
        return false, "Login failed: no session cookie"
    end

    Config.setSessionCookies(cookies)

    -- Step 4: Follow redirect to get new CSRF token
    local home_html, home_code = httpGet(BASE_URL .. "/", cookies)
    if home_html and home_code == 200 then
        local new_csrf = extractCsrfToken(home_html)
        if new_csrf then
            Config.setCsrfToken(new_csrf)
        end
    end

    logger.info("StoryGraph: Login successful")
    return true
end

-- Search for book by ISBN
function Api.searchByISBN(isbn)
    local cookies = Config.getSessionCookies()
    local url = BASE_URL .. "/search?search_term=" .. urlencode(isbn) .. "&button="

    local html, code, headers = httpGet(url, cookies)
    if not html or code ~= 200 then
        return nil, formatHttpError("Search", code, html, headers)
    end

    -- Extract book UUIDs from search results
    local books = {}
    for uuid, title_info in html:gmatch('href="/books/([a-f0-9%-]+)"[^>]*>.-<h1[^>]*>(.-)</h1>') do
        local title, author = title_info:match("^(.-) by (.+)$")
        if title and author then
            table.insert(books, {
                uuid = uuid,
                title = title,
                author = author,
            })
        end
    end

    if #books == 0 then
        return nil, "No books found for ISBN"
    end

    return books
end

-- Update reading status
function Api.updateStatus(book_id, status)
    local cookies = Config.getSessionCookies()
    local csrf_token = Config.getCsrfToken()

    local url = string.format("%s/update-status.js?book_id=%s&status=%s",
        BASE_URL, book_id, urlencode(status))

    local body = "authenticity_token=" .. urlencode(csrf_token)

    local response, code, headers = httpPost(url, body, cookies, csrf_token)

    if code ~= 200 then
        return false, formatHttpError("Status update", code, response, headers)
    end

    logger.info("StoryGraph: Updated status to " .. status)
    return true
end

-- Update reading progress
function Api.updateProgress(book_id, percentage, page_count, last_percentage)
    local cookies = Config.getSessionCookies()
    local csrf_token = Config.getCsrfToken()

    local body = string.format(
        "read_status[progress_number]=%d&read_status[progress_type]=percentage&read_status[book_num_of_pages]=%d&read_status[last_reached_percent]=%d&book_id=%s&on_book_page=true&commit=Save",
        percentage,
        page_count,
        last_percentage or 0,
        book_id
    )

    local response, code, headers = httpPost(BASE_URL .. "/update-progress", body, cookies, csrf_token)

    if code ~= 200 then
        return false, formatHttpError("Progress update", code, response, headers)
    end

    logger.info("StoryGraph: Updated progress to " .. percentage .. "%")
    return true
end

-- Export helpers for testing
Api._urlencode = urlencode
Api._extractCsrfToken = extractCsrfToken
Api._parseCookies = parseCookies
Api._buildCookieHeader = buildCookieHeader
Api._formatHttpError = formatHttpError

return Api
