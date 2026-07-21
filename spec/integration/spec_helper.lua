-- spec/integration/spec_helper.lua
-- Integration test setup: uses REAL KOReader modules, not mocks
-- KO_HOME and KOREADER_PATH must be set by the test runner before busted starts

local spec_dir = debug.getinfo(1, "S").source:match("@(.+)/spec_helper%.lua$") or "."
local project_dir = spec_dir .. "/../.."

-- KO_HOME must be set externally (by run-tests script or nix shell)
local test_home = os.getenv("KO_HOME")
if not test_home then
    error("KO_HOME not set — run tests via 'test' command in nix develop")
end

-- Find KOReader install path
local koreader_path = os.getenv("KOREADER_PATH")
if not koreader_path then
    error("KOREADER_PATH not set — run tests via 'test' command in nix develop")
end

local koreader_lib = koreader_path .. "/lib/koreader"

-- Add KOReader Lua paths to package.path
-- KOReader requires modules like "libs/libkoreader-lfs" so paths must resolve from koreader_lib root
package.path = project_dir .. "/?.lua;"
    .. koreader_lib .. "/?.lua;"
    .. koreader_lib .. "/frontend/?.lua;"
    .. koreader_lib .. "/libs/?.lua;"
    .. koreader_lib .. "/common/?.lua;"
    .. package.path

-- Add KOReader C library paths
-- Same: requires use "libs/..." prefix, so ? must match from koreader_lib root
package.cpath = koreader_lib .. "/?.so;"
    .. koreader_lib .. "/?.dll;"
    .. package.cpath

-- Mock socket modules (no real HTTP in integration tests)
package.preload["socket.http"] = function()
    return { request = function() return nil, nil, nil end }
end

package.preload["ssl.https"] = function()
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

-- Reload plugin modules only (keep KOReader modules cached for file persistence)
local function reset_modules()
    package.loaded["config"] = nil
    package.loaded["sync"] = nil
    package.loaded["api"] = nil
    package.loaded["main"] = nil
end

-- Full reset: wipe files AND reload modules
local function reset_environment()
    os.execute("rm -rf " .. test_home .. "/*")
    reset_modules()
end

return {
    reset = reset_modules,
    full_reset = reset_environment,
    test_home = test_home,
    koreader_path = koreader_path,
}
