-- spec/spec_helper.lua
-- Sets up package.path to find project modules and mocks KOReader dependencies

local spec_dir = debug.getinfo(1, "S").source:match("@(.+)/spec_helper") or "."
local project_dir = spec_dir .. "/.."

-- Add project root to package.path so require("api") finds ./api.lua
package.path = project_dir .. "/?.lua;" .. project_dir .. "/?/init.lua;" .. package.path

-- In-memory settings backend for config.lua / sync.lua tests
local function make_memory_settings()
    local store = {}
    return {
        readSetting = function(_, key, default)
            if store[key] ~= nil then return store[key] end
            return default
        end,
        saveSetting = function(_, key, value)
            store[key] = value
        end,
        delSetting = function(_, key)
            store[key] = nil
        end,
        flush = function() end,
        open = function() return make_memory_settings() end,
        _store = store,
    }
end

-- Mock datastorage: dummy path (luasettings is fully in-memory)
local mock_settings_dir = "/mock/settings/dir"

package.preload["datastorage"] = function()
    return {
        getSettingsDir = function() return mock_settings_dir end,
        getDataDir = function() return mock_settings_dir end,
    }
end

-- Mock luasettings: returns in-memory settings
package.preload["luasettings"] = function()
    local settings = make_memory_settings()
    return {
        open = function() return settings end,
        _new = make_memory_settings,
    }
end

-- Mock logger: silent by default
package.preload["logger"] = function()
    return {
        info = function() end,
        warn = function() end,
        err = function() end,
        dbg = function() end,
    }
end

-- Mock KOReader UI modules
package.preload["ui/widget/infomessage"] = function()
    return { extend = function(_, t) return t or {} end }
end

package.preload["ui/widget/inputdialog"] = function()
    return { extend = function(_, t) return t or {} end }
end

package.preload["ui/uimanager"] = function()
    return {
        show = function() end,
        close = function() end,
        scheduleIn = function() end,
    }
end

package.preload["ui/widget/container/widgetcontainer"] = function()
    return {
        extend = function(_, t)
            local obj = t or {}
            obj.init = obj.init or function() end
            return obj
        end,
    }
end

-- Mock socket modules (loaded by api.lua but never called in unit tests)
package.preload["socket.http"] = function()
    return { request = function() return nil, nil, nil end }
end

package.preload["ltn12"] = function()
    return {
        sink = { table = function() return function() end end },
        source = { string = function() return function() end end },
    }
end

package.preload["ssl.https"] = function()
    return { request = function() return nil, nil, nil end }
end

-- Reset config files between tests
local function reset_config()
    -- Wipe the in-memory store for luasettings
    local luasettings = require("luasettings")
    local settings = luasettings.open()
    if settings._store then
        for k, _ in pairs(settings._store) do
            settings._store[k] = nil
        end
    end
    -- Force config module reload
    package.loaded["config"] = nil
    package.loaded["sync"] = nil
end

return {
    reset_config = reset_config,
    settings_dir = mock_settings_dir,
}
