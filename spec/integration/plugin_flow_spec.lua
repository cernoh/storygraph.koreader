-- Integration test: full plugin flow with real KOReader modules
-- Tests onBookOpen → queue → onBookClose → processQueue with real storage

require("spec_helper")

describe("Plugin flow with real KOReader", function()
    local Sync, Config, helper

    before_each(function()
        helper = require("spec.integration.spec_helper")
        helper.full_reset()

        -- Mock API (no real HTTP)
        local api_calls = {}
        local mock_api = {
            login = function() return true end,
            updateStatus = function(book_id, status)
                table.insert(api_calls, { type = "status", book_id = book_id, status = status })
                return true
            end,
            updateProgress = function(book_id, pct, pages, last_pct)
                table.insert(api_calls, { type = "progress", book_id = book_id, pct = pct })
                return true
            end,
            searchByISBN = function() return {} end,
        }
        package.preload["api"] = function() return mock_api end

        Config = require("config")
        Sync = require("sync")
        -- Expose api_calls for assertions via upvalue
        _G._api_calls = api_calls
    end)

    after_each(function()
        _G._api_calls = nil
    end)

    describe("full read session", function()
        it("queues status on open, status+progress on close", function()
            Sync.onBookOpen("isbn:123")
            Sync.onBookClose("isbn:123", 50, 300)

            local state = Config.getLastSyncState("isbn:123")
            assert.truthy(state)
            assert.are.equal("currently-reading", state.status)
            assert.are.equal(50, state.percentage)
        end)

        it("marks book as finished at 95% threshold", function()
            Sync.onBookOpen("isbn:456")
            Sync.onBookClose("isbn:456", 96, 200)

            local state = Config.getLastSyncState("isbn:456")
            assert.truthy(state)
            assert.are.equal("read", state.status)
            assert.are.equal(100, state.percentage)
        end)

        it("sends API calls on book close", function()
            Sync.onBookClose("isbn:789", 30, 400)
            assert.truthy(#_G._api_calls >= 1, "should have made at least one API call")
        end)
    end)

    describe("stays read invariant", function()
        it("reopening a finished book does not change status", function()
            Sync.onBookClose("isbn:done", 97, 300)
            local state = Config.getLastSyncState("isbn:done")
            assert.are.equal("read", state.status)
            assert.are.equal(100, state.percentage)

            -- Reopen the book
            Sync.onBookOpen("isbn:done")

            -- Status should still be "read"
            state = Config.getLastSyncState("isbn:done")
            assert.are.equal("read", state.status)
            assert.are.equal(100, state.percentage)
        end)
    end)

    describe("queue deduplication", function()
        it("multiple opens only queue one status update", function()
            Sync.onBookOpen("isbn:dedup")
            Sync.onBookOpen("isbn:dedup")
            Sync.onBookOpen("isbn:dedup")
            -- All should deduplicate — no crash, state should be consistent
            local state = Config.getLastSyncState("isbn:dedup")
            assert.truthy(state)
            assert.are.equal("currently-reading", state.status)
        end)
    end)

    describe("retry piggyback", function()
        it("failed actions retry on next book open", function()
            -- Set session cookies so processQueue doesn't call login
            Config.setSessionCookies({ _storygraph_session = "test_session" })

            local call_count = 0
            package.preload["api"] = function()
                return {
                    login = function() return true end,
                    updateStatus = function()
                        call_count = call_count + 1
                        if call_count <= 1 then
                            return false, "network error"
                        end
                        return true
                    end,
                    updateProgress = function() return true end,
                    searchByISBN = function() return {} end,
                }
            end
            package.loaded["sync"] = nil
            package.loaded["api"] = nil
            Sync = require("sync")

            -- First open: status update fails, stays in queue
            Sync.onBookOpen("isbn:retry")
            local first_count = call_count
            assert.truthy(first_count >= 1, "should have attempted API call")

            -- Second open: retries the failed action
            Sync.onBookOpen("isbn:retry")
            assert.truthy(call_count > first_count, "should have retried")
        end)
    end)

    describe("state persists across module reloads", function()
        it("sync state survives reload", function()
            Sync.onBookClose("isbn:persist", 75, 200)
            local state_before = Config.getLastSyncState("isbn:persist")
            assert.truthy(state_before)

            -- Reload modules (files stay on disk)
            helper.reset()
            Config = require("config")

            local state_after = Config.getLastSyncState("isbn:persist")
            assert.truthy(state_after, "state should persist to disk")
            assert.are.equal(state_before.status, state_after.status)
            assert.are.equal(state_before.percentage, state_after.percentage)
        end)
    end)
end)
