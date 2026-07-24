require("spec_helper")

describe("Sync", function()
    local Sync, Config

    before_each(function()
        local helper = require("spec_helper")
        helper.reset()

        -- Mock api to avoid HTTP calls
        local mock_api = {
            login = function() return true end,
            updateStatus = function() return true end,
            updateProgress = function() return true end,
            searchByISBN = function() return {} end,
        }
        package.preload["api"] = function() return mock_api end

        Config = require("config")
        Sync = require("sync")
    end)

    describe("queueAction", function()
        before_each(function()
            Sync.clearQueue()
        end)

        it("adds action to empty queue", function()
            Sync.queueAction("book1", "status", { status = "currently-reading" })
            local queue = require("luasettings").open():readSetting("storygraph_queue", {})
            assert.are.equal(1, #queue)
            assert.are.equal("book1", queue[1].book_id)
            assert.are.equal("status", queue[1].action_type)
        end)

        it("deduplicates same book+action_type", function()
            Sync.queueAction("book1", "status", { status = "currently-reading" })
            Sync.queueAction("book1", "status", { status = "read" })
            local queue = require("luasettings").open():readSetting("storygraph_queue", {})
            assert.are.equal(1, #queue)
            assert.are.equal("read", queue[1].data.status)
        end)

        it("allows different action_types for same book", function()
            Sync.queueAction("book1", "status", { status = "read" })
            Sync.queueAction("book1", "progress", { percentage = 50 })
            local queue = require("luasettings").open():readSetting("storygraph_queue", {})
            assert.are.equal(2, #queue)
        end)

        it("allows same action_type for different books", function()
            Sync.queueAction("book1", "status", { status = "read" })
            Sync.queueAction("book2", "status", { status = "currently-reading" })
            local queue = require("luasettings").open():readSetting("storygraph_queue", {})
            assert.are.equal(2, #queue)
        end)
    end)

    describe("shouldSkip", function()
        it("returns false when no previous sync state", function()
            local should_skip = Sync.shouldSkip("book1", "status", { status = "read" })
            assert.falsy(should_skip)
        end)

        it("returns true when status unchanged", function()
            Config.setLastSyncState("book1", "read", 100)
            local should_skip = Sync.shouldSkip("book1", "status", { status = "read" })
            assert.truthy(should_skip)
        end)

        it("returns false when status changed", function()
            Config.setLastSyncState("book1", "currently-reading", 50)
            local should_skip = Sync.shouldSkip("book1", "status", { status = "read" })
            assert.falsy(should_skip)
        end)

        it("returns true when percentage unchanged", function()
            Config.setLastSyncState("book1", "currently-reading", 50)
            local should_skip = Sync.shouldSkip("book1", "progress", { percentage = 50 })
            assert.truthy(should_skip)
        end)

        it("returns false when percentage changed", function()
            Config.setLastSyncState("book1", "currently-reading", 50)
            local should_skip = Sync.shouldSkip("book1", "progress", { percentage = 75 })
            assert.falsy(should_skip)
        end)
    end)

    describe("onBookClose threshold", function()
        before_each(function()
            Sync.clearQueue()
        end)

        it("marks as 'read' when percentage >= 95", function()
            Sync.onBookClose("book1", 95, 300)
            local state = Config.getLastSyncState("book1")
            assert.are.equal("read", state.status)
            assert.are.equal(100, state.percentage)
        end)

        it("marks as 'read' when percentage > 95", function()
            Sync.onBookClose("book1", 98, 300)
            local state = Config.getLastSyncState("book1")
            assert.are.equal("read", state.status)
            assert.are.equal(100, state.percentage)
        end)

        it("marks as 'currently-reading' when percentage < 95", function()
            Sync.onBookClose("book1", 94, 300)
            local state = Config.getLastSyncState("book1")
            assert.are.equal("currently-reading", state.status)
            assert.are.equal(94, state.percentage)
        end)

        it("normalizes percentage to 100 when threshold reached", function()
            Sync.onBookClose("book1", 96, 300)
            local state = Config.getLastSyncState("book1")
            assert.are.equal(100, state.percentage)
        end)
    end)

    describe("onBookOpen", function()
        before_each(function()
            Sync.clearQueue()
        end)

        it("sets status to 'currently-reading'", function()
            Sync.onBookOpen("book1")
            local state = Config.getLastSyncState("book1")
            assert.are.equal("currently-reading", state.status)
        end)

        it("does not overwrite 'read' status", function()
            Config.setLastSyncState("book1", "read", 100)
            Sync.onBookOpen("book1")
            local state = Config.getLastSyncState("book1")
            assert.are.equal("read", state.status)
            assert.are.equal(100, state.percentage)
        end)

        it("does not overwrite 'finished' status", function()
            Config.setLastSyncState("book1", "finished", 100)
            Sync.onBookOpen("book1")
            local state = Config.getLastSyncState("book1")
            assert.are.equal("finished", state.status)
        end)

        it("overwrites 'currently-reading' status", function()
            Config.setLastSyncState("book1", "currently-reading", 50)
            Sync.onBookOpen("book1")
            local state = Config.getLastSyncState("book1")
            assert.are.equal("currently-reading", state.status)
        end)
    end)

    describe("processQueue retry", function()
        before_each(function()
            Sync.clearQueue()
        end)

        it("removes successful actions from queue", function()
            Sync.queueAction("book1", "status", { status = "read" })
            Sync.processQueue()
            local queue = require("luasettings").open():readSetting("storygraph_queue", {})
            assert.are.equal(0, #queue)
        end)

        it("keeps failed actions in queue", function()
            -- Mock API to fail
            package.loaded["api"] = nil
            package.preload["api"] = function()
                return {
                    login = function() return true end,
                    updateStatus = function() return false, "network error" end,
                    updateProgress = function() return true end,
                }
            end
            package.loaded["sync"] = nil
            Sync = require("sync")

            Sync.queueAction("book1", "status", { status = "read" })
            Sync.processQueue()
            local queue = require("luasettings").open():readSetting("storygraph_queue", {})
            assert.are.equal(1, #queue)
        end)

        it("retries failed actions on next processQueue", function()
            local call_count = 0
            package.loaded["api"] = nil
            package.preload["api"] = function()
                return {
                    login = function() return true end,
                    updateStatus = function()
                        call_count = call_count + 1
                        if call_count == 1 then
                            return false, "network error"
                        end
                        return true
                    end,
                    updateProgress = function() return true end,
                }
            end
            package.loaded["sync"] = nil
            Sync = require("sync")

            Sync.queueAction("book1", "status", { status = "read" })
            Sync.processQueue()
            local queue = require("luasettings").open():readSetting("storygraph_queue", {})
            assert.are.equal(1, #queue)

            Sync.processQueue()
            queue = require("luasettings").open():readSetting("storygraph_queue", {})
            assert.are.equal(0, #queue)
        end)

        it("returns the first error message when actions fail", function()
            package.loaded["api"] = nil
            package.preload["api"] = function()
                return {
                    login = function() return true end,
                    updateStatus = function() return false, "Cloudflare error 1020 — HTTP 403" end,
                    updateProgress = function() return true end,
                }
            end
            package.loaded["sync"] = nil
            Sync = require("sync")

            Sync.queueAction("book1", "status", { status = "read" })
            local ok, err = Sync.processQueue()
            assert.is_false(ok)
            assert.are.equal("Cloudflare error 1020 — HTTP 403", err)
        end)
    end)

    describe("clearQueue", function()
        it("empties the queue", function()
            Sync.queueAction("book1", "status", { status = "read" })
            Sync.clearQueue()
            local queue = require("luasettings").open():readSetting("storygraph_queue", {})
            assert.are.equal(0, #queue)
        end)
    end)
end)
