require("spec_helper")

describe("Config", function()
    local Config

    before_each(function()
        -- Reset all cached modules to get fresh state
        package.loaded["config"] = nil
        package.loaded["sync"] = nil
        -- Reset luasettings store
        local luasettings = require("luasettings")
        local settings = luasettings.open()
        if settings._store then
            for k in pairs(settings._store) do
                settings._store[k] = nil
            end
        end
        Config = require("config")
    end)

    describe("credentials", function()
        it("returns empty strings when no credentials set", function()
            local creds = Config.getCredentials()
            assert.are.equal("", creds.email)
            assert.are.equal("", creds.password)
        end)

        it("roundtrips email and password", function()
            Config.setCredentials("user@example.com", "secret123")
            local creds = Config.getCredentials()
            assert.are.equal("user@example.com", creds.email)
            assert.are.equal("secret123", creds.password)
        end)

        it("overwrites previous credentials", function()
            Config.setCredentials("old@example.com", "old")
            Config.setCredentials("new@example.com", "new")
            local creds = Config.getCredentials()
            assert.are.equal("new@example.com", creds.email)
            assert.are.equal("new", creds.password)
        end)
    end)

    describe("sync state", function()
        it("returns nil for unknown book", function()
            assert.is_nil(Config.getLastSyncState("unknown-book"))
        end)

        it("stores and retrieves sync state for a book", function()
            Config.setLastSyncState("book-1", "currently-reading", 42)
            local state = Config.getLastSyncState("book-1")
            assert.are.equal("currently-reading", state.status)
            assert.are.equal(42, state.percentage)
            assert.is_not_nil(state.timestamp)
        end)

        it("tracks multiple books independently", function()
            Config.setLastSyncState("book-1", "currently-reading", 30)
            Config.setLastSyncState("book-2", "read", 100)

            local s1 = Config.getLastSyncState("book-1")
            local s2 = Config.getLastSyncState("book-2")

            assert.are.equal("currently-reading", s1.status)
            assert.are.equal(30, s1.percentage)
            assert.are.equal("read", s2.status)
            assert.are.equal(100, s2.percentage)
        end)

        it("overwrites previous state for same book", function()
            Config.setLastSyncState("book-1", "currently-reading", 30)
            Config.setLastSyncState("book-1", "read", 100)
            local state = Config.getLastSyncState("book-1")
            assert.are.equal("read", state.status)
            assert.are.equal(100, state.percentage)
        end)
    end)

    describe("session cookies", function()
        it("returns empty table when no cookies set", function()
            local cookies = Config.getSessionCookies()
            local count = 0
            for _ in pairs(cookies) do count = count + 1 end
            assert.are.equal(0, count)
        end)

        it("stores and retrieves cookies", function()
            Config.setSessionCookies({ _storygraph_session = "abc123" })
            local cookies = Config.getSessionCookies()
            assert.are.equal("abc123", cookies._storygraph_session)
        end)
    end)

    describe("csrf token", function()
        it("returns empty string when no token set", function()
            assert.are.equal("", Config.getCsrfToken())
        end)

        it("stores and retrieves csrf token", function()
            Config.setCsrfToken("token-xyz")
            assert.are.equal("token-xyz", Config.getCsrfToken())
        end)
    end)

    describe("clearSession", function()
        it("removes session cookies and csrf token", function()
            Config.setSessionCookies({ _storygraph_session = "abc" })
            Config.setCsrfToken("tok")
            Config.clearSession()
            assert.are.equal("", Config.getCsrfToken())
        end)
    end)

    describe("book mapping", function()
        it("returns nil for unmapped book", function()
            assert.is_nil(Config.getBookMapping("local-id-1"))
        end)

        it("stores and retrieves book mapping", function()
            Config.setBookMapping("isbn:123", "uuid-abc")
            assert.are.equal("uuid-abc", Config.getBookMapping("isbn:123"))
        end)

        it("maps multiple books", function()
            Config.setBookMapping("local-1", "uuid-1")
            Config.setBookMapping("local-2", "uuid-2")
            assert.are.equal("uuid-1", Config.getBookMapping("local-1"))
            assert.are.equal("uuid-2", Config.getBookMapping("local-2"))
        end)
    end)
end)
