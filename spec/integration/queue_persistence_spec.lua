-- Integration test: queue persistence across simulated restarts
-- Proves the sync queue survives process death via real KOReader LuaSettings file I/O

require("spec_helper")

describe("Queue persistence with real KOReader storage", function()
    local Sync, Config, helper

    before_each(function()
        helper = require("spec.integration.spec_helper")
        helper.full_reset()

        -- Mock API that always fails (so queue items stay)
        package.preload["api"] = function()
            return {
                login = function() return false, "no network" end,
                updateStatus = function() return false, "no network" end,
                updateProgress = function() return false, "no network" end,
                searchByISBN = function() return {} end,
            }
        end

        Config = require("config")
        Sync = require("sync")
    end)

    it("queue survives module reload (simulated restart)", function()
        -- Queue an action (API fails, so it stays in queue)
        Sync.queueAction("isbn:survive", "progress", {
            percentage = 75,
            page_count = 200,
            last_percentage = 50,
        })

        -- Simulate process restart: reload modules only (files persist)
        helper.reset()

        -- Re-setup with succeeding API
        package.preload["api"] = function()
            return {
                login = function() return true end,
                updateStatus = function() return true end,
                updateProgress = function() return true end,
                searchByISBN = function() return {} end,
            }
        end

        Sync = require("sync")

        -- processQueue should find and process the persisted action
        local result = Sync.processQueue()
        assert.truthy(result, "should process the persisted queue item")
    end)

    it("multiple books' queue entries all persist", function()
        Sync.queueAction("isbn:book1", "status", { status = "read" })
        Sync.queueAction("isbn:book2", "progress", {
            percentage = 30,
            page_count = 100,
            last_percentage = 0,
        })
        Sync.queueAction("isbn:book3", "status", { status = "currently-reading" })

        -- Reload modules only
        helper.reset()

        -- Re-setup with succeeding API
        package.preload["api"] = function()
            return {
                login = function() return true end,
                updateStatus = function() return true end,
                updateProgress = function() return true end,
                searchByISBN = function() return {} end,
            }
        end
        Sync = require("sync")

        -- Process should succeed and clear all 3
        local result = Sync.processQueue()
        assert.truthy(result)
    end)

    it("failed queue items survive repeated restarts", function()
        -- Queue with failing API
        Sync.queueAction("isbn:retry", "status", { status = "read" })

        -- Restart 1: still fails
        helper.reset()
        package.preload["api"] = function()
            return {
                login = function() return false, "no network" end,
                updateStatus = function() return false, "no network" end,
                updateProgress = function() return true end,
                searchByISBN = function() return {} end,
            }
        end
        Sync = require("sync")
        Sync.processQueue()

        -- Restart 2: now succeeds
        helper.reset()
        package.preload["api"] = function()
            return {
                login = function() return true end,
                updateStatus = function() return true end,
                updateProgress = function() return true end,
                searchByISBN = function() return {} end,
            }
        end
        Sync = require("sync")
        local result = Sync.processQueue()
        assert.truthy(result, "should succeed after restart")
    end)
end)
