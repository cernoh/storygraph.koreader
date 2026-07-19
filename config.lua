-- config.lua — StoryGraph plugin configuration
-- Stores credentials and last-sync state in KOReader settings

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local logger = require("logger")

local Config = {}

local CONFIG_FILE = DataStorage:getSettingsDir() .. "/storygraph.lua"
local settings = LuaSettings:open(CONFIG_FILE)

function Config.getCredentials()
    return {
        email = settings:readSetting("storygraph_email", ""),
        password = settings:readSetting("storygraph_password", ""),
    }
end

function Config.setCredentials(email, password)
    settings:saveSetting("storygraph_email", email)
    settings:saveSetting("storygraph_password", password)
    settings:flush()
end

function Config.getLastSyncState(book_id)
    local sync_states = settings:readSetting("storygraph_sync_states", {})
    return sync_states[book_id]
end

function Config.setLastSyncState(book_id, status, percentage)
    local sync_states = settings:readSetting("storygraph_sync_states", {})
    sync_states[book_id] = {
        status = status,
        percentage = percentage,
        timestamp = os.time(),
    }
    settings:saveSetting("storygraph_sync_states", sync_states)
    settings:flush()
end

function Config.getSessionCookies()
    return settings:readSetting("storygraph_session_cookies", {})
end

function Config.setSessionCookies(cookies)
    settings:saveSetting("storygraph_session_cookies", cookies)
    settings:flush()
end

function Config.getCsrfToken()
    return settings:readSetting("storygraph_csrf_token", "")
end

function Config.setCsrfToken(token)
    settings:saveSetting("storygraph_csrf_token", token)
    settings:flush()
end

function Config.clearSession()
    settings:delSetting("storygraph_session_cookies")
    settings:delSetting("storygraph_csrf_token")
    settings:flush()
end


function Config.getBookMapping(local_id)
    local mappings = settings:readSetting("storygraph_book_mappings", {})
    return mappings[local_id]
end

function Config.setBookMapping(local_id, storygraph_id)
    local mappings = settings:readSetting("storygraph_book_mappings", {})
    mappings[local_id] = storygraph_id
    settings:saveSetting("storygraph_book_mappings", mappings)
    settings:flush()
end

return Config
