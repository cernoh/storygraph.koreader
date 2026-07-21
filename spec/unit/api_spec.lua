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
            local html = '<meta name="csrf-token" content="abc123xyz">'
            local token = Api._extractCsrfToken(html)
            assert.are.equal("abc123xyz", token)
        end)

        it("returns nil when no meta tag present", function()
            local html = "<html><body>No token here</body></html>"
            local token = Api._extractCsrfToken(html)
            assert.is_nil(token)
        end)

        it("handles multiple meta tags", function()
            local html = [[
                <meta name="viewport" content="width=device-width">
                <meta name="csrf-token" content="token456">
                <meta name="description" content="test">
            ]]
            local token = Api._extractCsrfToken(html)
            assert.are.equal("token456", token)
        end)
    end)

    describe("_parseCookies", function()
        it("parses Set-Cookie headers", function()
            local headers = {
                ["set-cookie"] = "_storygraph_session=abc123; path=/; HttpOnly",
            }
            local cookies = Api._parseCookies(headers)
            assert.are.equal("abc123", cookies["_storygraph_session"])
        end)

        it("parses multiple cookies", function()
            local headers = {
                ["set-cookie"] = "_storygraph_session=abc123; path=/",
                ["set-cookie"] = "remember_user_token=xyz789; path=/",
            }
            local cookies = Api._parseCookies(headers)
            -- Note: Lua tables can't have duplicate keys, so only last one wins
            -- This test documents the limitation
            assert.truthy(cookies["remember_user_token"] or cookies["_storygraph_session"])
        end)

        it("returns empty table for no cookies", function()
            local headers = {}
            local cookies = Api._parseCookies(headers)
            assert.are.same({}, cookies)
        end)
    end)

    describe("_buildCookieHeader", function()
        it("builds header from single cookie", function()
            local cookies = { _storygraph_session = "abc123" }
            local header = Api._buildCookieHeader(cookies)
            assert.are.equal("_storygraph_session=abc123", header)
        end)

        it("builds header from multiple cookies", function()
            local cookies = {
                _storygraph_session = "abc",
                remember_user_token = "xyz",
            }
            local header = Api._buildCookieHeader(cookies)
            -- Order may vary, so check both are present
            assert.truthy(header:find("_storygraph_session=abc"))
            assert.truthy(header:find("remember_user_token=xyz"))
            assert.truthy(header:find("; "))
        end)

        it("returns empty string for no cookies", function()
            local header = Api._buildCookieHeader({})
            assert.are.equal("", header)
        end)
    end)
end)
