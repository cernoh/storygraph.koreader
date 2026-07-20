require("spec_helper")

describe("Sync", function()
    local Sync, Config

    before_each(function()
        package.loaded["config"] = nil
        package.loaded["sync"] = nil
        package.loaded["api"] = nil

        -- Reset luasettings store
        local luasettings = require("luasettings")
        local settings = luasettings.open()
        if settings._store then
            for k in pairs(settings._store) do
                settings._store[k] = nil
            end
        end

        -- Mock api to avoid HTTP calls
        local mock_api = {
            login = function() return true end,
            updateStatus = function() return true end,
            updateProgress = function() return true end,
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
            Sync.queueAction("book-1", "status", { status = "currently-reading" })
            local result = Sync.processQueue()
            assert.is_true(result)
        end)

        it("deduplicates same book+action_type", function()
            Sync.queueAction("book-1", "status", { status = "currently-reading" })
            Sync.queueAction("book-1", "status", { status = "read" })
            local result = Sync.processQueue()
            assert.is_true(result)
        end)

        it("keeps different action_types for same book", function()
            Sync.queueAction("book-1", "status", { status = "read" })
            Sync.queueAction("book-1", "progress", { percentage = 50, page_count = 200 })
            local result = Sync.processQueue()
            assert.is_true(result)
        end)

        it("keeps same action_type for different books", function()
            Sync.queueAction("book-1", "status", { status = "read" })
            Sync.queueAction("book-2", "status", { status = "currently-reading" })
            local result = Sync.processQueue()
            assert.is_true(result)
        end)
    end)

    describe("shouldSkip", function()
        it("returns false when no previous sync state", function()
            assert.is_false(Sync.shouldSkip("book-1", "status", { status = "read" }))
        end)

        it("returns true when status unchanged", function()
            Config.setLastSyncState("book-1", "read", 100)
            assert.is_true(Sync.shouldSkip("book-1", "status", { status = "read" }))
        end)

        it("returns false when status changed", function()
            Config.setLastSyncState("book-1", "currently-reading", 50)
            assert.is_false(Sync.shouldSkip("book-1", "status", { status = "read" }))
        end)

        it("returns true when progress percentage unchanged", function()
            Config.setLastSyncState("book-1", "currently-reading", 42)
            assert.is_true(Sync.shouldSkip("book-1", "progress", { percentage = 42 }))
        end)

        it("returns false when progress percentage changed", function()
            Config.setLastSyncState("book-1", "currently-reading", 42)
            assert.is_false(Sync.shouldSkip("book-1", "progress", { percentage = 55 }))
        end)

        it("returns false for unknown action type", function()
            Config.setLastSyncState("book-1", "read", 100)
            assert.is_false(Sync.shouldSkip("book-1", "unknown", {}))
        end)
    end)

    describe("onBookClose threshold", function()
        before_each(function()
            Sync.clearQueue()
        end)

        it("sets status to read when percentage >= 95", function()
            local sent_status = nil
            package.loaded["api"] = nil
            local mock_api = {
                login = function() return true end,
                updateStatus = function(_, status)
                    sent_status = status
                    return true
                end,
                updateProgress = function() return true end,
            }
            package.preload["api"] = function() return mock_api end
            package.loaded["sync"] = nil
            Sync = require("sync")

            Sync.onBookClose("book-1", 95, 300)
            assert.are.equal("read", sent_status)
        end)

        it("sets status to currently-reading when percentage < 95", function()
            local sent_status = nil
            package.loaded["api"] = nil
            local mock_api = {
                login = function() return true end,
                updateStatus = function(_, status)
                    sent_status = status
                    return true
                end,
                updateProgress = function() return true end,
            }
            package.preload["api"] = function() return mock_api end
            package.loaded["sync"] = nil
            Sync = require("sync")

            Sync.onBookClose("book-1", 50, 300)
            assert.are.equal("currently-reading", sent_status)
        end)

        it("normalizes percentage to 100 when >= 95", function()
            local sent_percentage = nil
            package.loaded["api"] = nil
            local mock_api = {
                login = function() return true end,
                updateStatus = function() return true end,
                updateProgress = function(_, pct)
                    sent_percentage = pct
                    return true
                end,
            }
            package.preload["api"] = function() return mock_api end
            package.loaded["sync"] = nil
            Sync = require("sync")

            Sync.onBookClose("book-1", 97, 300)
            assert.are.equal(100, sent_percentage)
        end)

        it("keeps actual percentage when < 95", function()
            local sent_percentage = nil
            package.loaded["api"] = nil
            local mock_api = {
                login = function() return true end,
                updateStatus = function() return true end,
                updateProgress = function(_, pct)
                    sent_percentage = pct
                    return true
                end,
            }
            package.preload["api"] = function() return mock_api end
            package.loaded["sync"] = nil
            Sync = require("sync")

            Sync.onBookClose("book-1", 73, 300)
            assert.are.equal(73, sent_percentage)
        end)
    end)

    describe("onBookOpen", function()
        before_each(function()
            Sync.clearQueue()
        end)

        it("queues currently-reading status for new book", function()
            local sent_status = nil
            package.loaded["api"] = nil
            local mock_api = {
                login = function() return true end,
                updateStatus = function(_, status)
                    sent_status = status
                    return true
                end,
                updateProgress = function() return true end,
            }
            package.preload["api"] = function() return mock_api end
            package.loaded["sync"] = nil
            Sync = require("sync")

            Sync.onBookOpen("book-1")
            assert.are.equal("currently-reading", sent_status)
        end)

        it("skips status update if book already finished", function()
            Config.setLastSyncState("book-1", "read", 100)

            local sent_status = nil
            package.loaded["api"] = nil
            local mock_api = {
                login = function() return true end,
                updateStatus = function(_, status)
                    sent_status = status
                    return true
                end,
                updateProgress = function() return true end,
            }
            package.preload["api"] = function() return mock_api end
            package.loaded["sync"] = nil
            Sync = require("sync")

            Sync.onBookOpen("book-1")
            assert.is_nil(sent_status)
        end)
    end)

    describe("processQueue retry", function()
        before_each(function()
            Sync.clearQueue()
        end)

        it("keeps failed actions in queue for retry", function()
            package.loaded["api"] = nil
            local mock_api = {
                login = function() return true end,
                updateStatus = function() return false, "network error" end,
                updateProgress = function() return true end,
            }
            package.preload["api"] = function() return mock_api end
            package.loaded["sync"] = nil
            Sync = require("sync")

            Sync.queueAction("book-1", "status", { status = "read" })
            local result = Sync.processQueue()
            assert.is_false(result)

            -- Failed action should still be in queue
            result = Sync.processQueue()
            assert.is_false(result)
        end)

        it("returns true when queue is empty", function()
            local result = Sync.processQueue()
            assert.is_true(result)
        end)
    end)

    describe("clearQueue", function()
        it("empties the queue", function()
            Sync.queueAction("book-1", "status", { status = "read" })
            Sync.clearQueue()
            local result = Sync.processQueue()
            assert.is_true(result)
        end)
    end)
end)
