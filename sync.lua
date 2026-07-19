-- sync.lua — Sync queue and retry logic
-- Batches actions on book close, retries on next action

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local Api = require("api")
local Config = require("config")
local logger = require("logger")

local Sync = {}

local QUEUE_FILE = DataStorage:getSettingsDir() .. "/storygraph_queue.lua"
local queue_settings = LuaSettings:open(QUEUE_FILE)

-- Progress threshold: 95% KOReader = 100% StoryGraph
local FINISHED_THRESHOLD = 95

-- Get pending actions queue
local function getQueue()
    return queue_settings:readSetting("storygraph_queue", {})
end

-- Save queue
local function saveQueue(queue)
    queue_settings:saveSetting("storygraph_queue", queue)
    queue_settings:flush()
end

-- Add action to queue
function Sync.queueAction(book_id, action_type, data)
    local queue = getQueue()
    
    -- Deduplicate: remove any existing actions for this book+action_type
    local filtered = {}
    for _, item in ipairs(queue) do
        if not (item.book_id == book_id and item.action_type == action_type) then
            table.insert(filtered, item)
        end
    end
    
    -- Add new action
    table.insert(filtered, {
        book_id = book_id,
        action_type = action_type,
        data = data,
        timestamp = os.time(),
    })
    
    saveQueue(filtered)
    logger.info("StoryGraph: Queued " .. action_type .. " for book " .. book_id)
end

-- Check if action should be skipped (state unchanged)
function Sync.shouldSkip(book_id, action_type, new_data)
    local last_sync = Config.getLastSyncState(book_id)
    if not last_sync then
        return false
    end
    
    if action_type == "status" then
        return last_sync.status == new_data.status
    elseif action_type == "progress" then
        return last_sync.percentage == new_data.percentage
    end
    
    return false
end

-- Process queue: attempt to sync all pending actions
function Sync.processQueue()
    local queue = getQueue()
    if #queue == 0 then
        return true
    end
    
    logger.info("StoryGraph: Processing queue with " .. #queue .. " actions")
    
    -- Ensure we're logged in
    local cookies = Config.getSessionCookies()
    if not cookies["_storygraph_session"] then
        local ok, err = Api.login()
        if not ok then
            logger.warn("StoryGraph: Login failed, queue will retry later: " .. err)
            return false
        end
    end
    
    local failed = {}
    local succeeded = {}
    
    for _, item in ipairs(queue) do
        local ok, err
        
        if item.action_type == "status" then
            ok, err = Api.updateStatus(item.book_id, item.data.status)
            if ok then
                Config.setLastSyncState(item.book_id, item.data.status, nil)
            end
        elseif item.action_type == "progress" then
            ok, err = Api.updateProgress(
                item.book_id,
                item.data.percentage,
                item.data.page_count,
                item.data.last_percentage
            )
            if ok then
                local last_sync = Config.getLastSyncState(item.book_id)
                local current_status = last_sync and last_sync.status or "currently-reading"
                Config.setLastSyncState(item.book_id, current_status, item.data.percentage)
            end
        end
        
        if ok then
            table.insert(succeeded, item)
        else
            logger.warn("StoryGraph: Action failed, will retry: " .. tostring(err))
            table.insert(failed, item)
        end
    end
    
    -- Keep only failed actions in queue
    saveQueue(failed)
    
    if #succeeded > 0 then
        logger.info("StoryGraph: Synced " .. #succeeded .. " actions")
    end
    
    return #failed == 0
end

-- Queue book open event (status: currently-reading)
function Sync.onBookOpen(book_id)
    -- Don't overwrite "read" status if book was already finished
    local last_sync = Config.getLastSyncState(book_id)
    if last_sync and (last_sync.status == "read" or last_sync.status == "finished") then
        logger.info("StoryGraph: Book already finished, skipping status update")
        return
    end
    
    local data = { status = "currently-reading" }
    
    if not Sync.shouldSkip(book_id, "status", data) then
        Sync.queueAction(book_id, "status", data)
    end
    
    -- Retry any failed actions from previous sessions
    Sync.processQueue()
end

-- Queue book close event (status + progress)
function Sync.onBookClose(book_id, percentage, page_count)
    -- Determine status based on threshold
    local status = "currently-reading"
    if percentage >= FINISHED_THRESHOLD then
        status = "read"
        percentage = 100  -- Normalize to 100% for StoryGraph
    end
    
    -- Queue status update
    local status_data = { status = status }
    if not Sync.shouldSkip(book_id, "status", status_data) then
        Sync.queueAction(book_id, "status", status_data)
    end
    
    -- Queue progress update
    local last_sync = Config.getLastSyncState(book_id)
    local last_percentage = last_sync and last_sync.percentage or 0
    
    local progress_data = {
        percentage = percentage,
        page_count = page_count,
        last_percentage = last_percentage,
    }
    
    if not Sync.shouldSkip(book_id, "progress", progress_data) then
        Sync.queueAction(book_id, "progress", progress_data)
    end
    
    -- Process queue immediately on book close
    Sync.processQueue()
end

-- Clear queue (for testing or manual reset)
function Sync.clearQueue()
    saveQueue({})
end

return Sync
