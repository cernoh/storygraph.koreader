-- spec/spec_helper.lua
-- Sets up package.path to find project modules and mocks KOReader dependencies
-- Combines unit test mocks with integration test enhancements

local spec_dir = debug.getinfo(1, "S").source:match("@(.+)/spec_helper") or "."
local project_dir = spec_dir .. "/.."

-- Add project root to package.path so require("api") finds ./api.lua
package.path = project_dir .. "/?.lua;" .. project_dir .. "/?/init.lua;" .. package.path

-- In-memory settings backend for config.lua / sync.lua tests
local function make_memory_settings()
    local store = {}
    return {
        open = function(self, path)
            return setmetatable({}, {
                __index = {
                    readSetting = function(_, key, default)
                        if store[key] ~= nil then
                            return store[key]
                        end
                        return default
                    end,
                    saveSetting = function(_, key, value)
                        store[key] = value
                    end,
                    delSetting = function(_, key)
                        store[key] = nil
                    end,
                    flush = function() end,
                    _store = store,
                },
            })
        end,
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
        _store = store,
    }
end

-- Mock datastorage: use real tmpdir for integration tests
local mock_settings_dir = os.tmpname()
os.remove(mock_settings_dir)
os.execute("mkdir -p " .. mock_settings_dir)

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
        open = function(path)
            return settings:open(path)
        end,
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
            function obj:new(o)
                o = o or {}
                setmetatable(o, self)
                self.__index = self
                return o
            end
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
        sink = {
            table = function(t)
                return function(chunk)
                    if chunk then table.insert(t, chunk) end
                    return 1
                end
            end,
        },
        source = {
            string = function(s)
                local done = false
                return function()
                    if not done then
                        done = true
                        return s
                    end
                    return nil
                end
            end,
        },
    }
end

package.preload["ssl.https"] = function()
    return { request = function() return nil, nil, nil end }
end

-- Reset helper: clears module cache and settings between tests
local function reset_modules()
    package.loaded["config"] = nil
    package.loaded["sync"] = nil
    package.loaded["api"] = nil
    local luasettings = require("luasettings")
    local settings = luasettings.open()
    if settings._store then
        for k in pairs(settings._store) do
            settings._store[k] = nil
        end
    end
end

return {
    reset = reset_modules,
    reset_config = reset_modules,
    settings_dir = mock_settings_dir,
}
