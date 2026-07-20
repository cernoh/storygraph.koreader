require("spec_helper")

describe("Api pure helpers", function()
    local Api

    before_each(function()
        package.loaded["api"] = nil
        Api = require("api")
    end)

    describe("_urlencode", function()
        it("passes through alphanumeric strings", function()
            assert.are.equal("hello", Api._urlencode("hello"))
        end)

        it("encodes spaces as %20", function()
            assert.are.equal("hello%20world", Api._urlencode("hello world"))
        end)

        it("encodes special characters", function()
            assert.are.equal("%40%23%24", Api._urlencode("@#$"))
        end)

        it("preserves unreserved characters", function()
            assert.are.equal("a-b.c_d~e", Api._urlencode("a-b.c_d~e"))
        end)

        it("handles nil input", function()
            assert.is_nil(Api._urlencode(nil))
        end)

        it("converts newlines to CRLF before encoding", function()
            local result = Api._urlencode("a\nb")
            assert.are.equal("a%0D%0Ab", result)
        end)

        it("encodes square brackets", function()
            local result = Api._urlencode("user[email]")
            assert.are.equal("user%5Bemail%5D", result)
        end)
    end)

    describe("_extractCsrfToken", function()
        it("extracts token from meta tag", function()
            local html = '<meta name="csrf-token" content="abc123token">'
            assert.are.equal("abc123token", Api._extractCsrfToken(html))
        end)

        it("returns nil when no meta tag present", function()
            local html = "<html><body>no token here</body></html>"
            assert.is_nil(Api._extractCsrfToken(html))
        end)

        it("extracts from HTML with surrounding content", function()
            local html = [[
<html>
<head>
<meta name="csrf-token" content="tokenXYZ==">
<title>Login</title>
</head>
</html>]]
            assert.are.equal("tokenXYZ==", Api._extractCsrfToken(html))
        end)

        it("handles token with special characters", function()
            local html = '<meta name="csrf-token" content="a+b/c=d">'
            assert.are.equal("a+b/c=d", Api._extractCsrfToken(html))
        end)
    end)

    describe("_parseCookies", function()
        it("parses Set-Cookie headers", function()
            local headers = {
                ["set-cookie"] = "_storygraph_session=abc123; Path=/; HttpOnly",
            }
            local cookies = Api._parseCookies(headers)
            assert.are.equal("abc123", cookies._storygraph_session)
        end)

        it("returns empty table for headers without cookies", function()
            local headers = { ["content-type"] = "text/html" }
            local cookies = Api._parseCookies(headers)
            local count = 0
            for _ in pairs(cookies) do count = count + 1 end
            assert.are.equal(0, count)
        end)

        it("strips cookie attributes after semicolon", function()
            local headers = {
                ["set-cookie"] = "session=abc; Path=/; HttpOnly; Secure",
            }
            local cookies = Api._parseCookies(headers)
            assert.are.equal("abc", cookies.session)
        end)
    end)

    describe("_buildCookieHeader", function()
        it("builds header from single cookie", function()
            local result = Api._buildCookieHeader({ session = "abc" })
            assert.are.equal("session=abc", result)
        end)

        it("joins multiple cookies with semicolon-space", function()
            local result = Api._buildCookieHeader({ a = "1", b = "2" })
            assert.is_truthy(result:find("a=1"))
            assert.is_truthy(result:find("b=2"))
            assert.is_truthy(result:find("; "))
        end)

        it("returns empty string for empty table", function()
            assert.are.equal("", Api._buildCookieHeader({}))
        end)
    end)
end)
