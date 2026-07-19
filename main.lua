-- main.lua — StoryGraph KOReader plugin entry point
-- Syncs reading progress and status to StoryGraph

local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Sync = require("sync")
local Api = require("api")
local Config = require("config")
local logger = require("logger")

local StoryGraphPlugin = WidgetContainer:extend{
    name = "storygraph",
}

function StoryGraphPlugin:init()
    self.ui.menu:registerToMainMenu(self)
    
    -- Register event handlers
end


function StoryGraphPlugin:onReaderReady()
    logger.info("StoryGraph: Book opened")
    local book_id = self:getBookId()
    if book_id then
        -- Resolve ISBN to StoryGraph edition UUID
        local storygraph_id = self:resolveStoryGraphId(book_id)
        Sync.onBookOpen(storygraph_id or book_id)
    end
end


function StoryGraphPlugin:onCloseDocument()
    -- Book closed - queue status + progress updates
    local book_id = self:getBookId()
    if book_id then
        local percentage = self:getReadingPercentage()
        local page_count = self:getPageCount()
        -- Resolve ISBN to StoryGraph edition UUID
        local storygraph_id = self:resolveStoryGraphId(book_id)
        Sync.onBookClose(storygraph_id or book_id, percentage, page_count)
    end
end

-- Get book ID (ISBN or title+author hash)
function StoryGraphPlugin:getBookId()
    local props = self.ui.document:getProps()
    
    -- Try ISBN first
    if props.isbn and props.isbn ~= "" then
        return "isbn:" .. props.isbn
    end
    
    -- Fallback to title+author hash
    local key = (props.title or "") .. (props.authors or "")
    if key ~= "" then
        -- Simple hash for identification
        local hash = 0
        for i = 1, #key do
            hash = (hash * 31 + string.byte(key, i)) % 2^32
        end
        return "hash:" .. string.format("%08x", hash)
    end
    
    return nil
end

-- Resolve local book ID to StoryGraph edition UUID
function StoryGraphPlugin:resolveStoryGraphId(local_id)
    -- Check cache first
    local cached = Config.getBookMapping(local_id)
    if cached then
        return cached
    end
    
    -- If it's an ISBN, look it up
    local isbn = local_id:match("^isbn:(.+)$")
    if isbn then
        local books = Api.searchByISBN(isbn)
        if books and #books > 0 then
            local uuid = books[1].uuid
            Config.setBookMapping(local_id, uuid)
            return uuid
        end
    end
    
    -- Fallback to local ID
    return nil
end

-- Get current reading percentage (0-100)
function StoryGraphPlugin:getReadingPercentage()
    local current_page = self.ui.document:getCurrentPage()
    local total_pages = self.ui.document:getPageCount()
    
    if total_pages and total_pages > 0 then
        return math.floor((current_page / total_pages) * 100)
    end
    
    return 0
end

-- Get total page count
function StoryGraphPlugin:getPageCount()
    return self.ui.document:getPageCount() or 0
end

-- Add to main menu
function StoryGraphPlugin:addToMainMenu(menu_items)
    menu_items.storygraph = {
        text = "StoryGraph sync",
        sub_item_table = {
            {
                text = "Configure credentials",
                callback = function()
                    self:showCredentialsDialog()
                end,
            },
            {
                text = "Sync now",
                callback = function()
                    self:manualSync()
                end,
            },
            {
                text = "Clear sync queue",
                callback = function()
                    Sync.clearQueue()
                    UIManager:show(InfoMessage:new{
                        text = "Sync queue cleared",
                    })
                end,
            },
        },
    }
end

-- Show credentials input dialog
function StoryGraphPlugin:showCredentialsDialog()
    local creds = Config.getCredentials()
    
    self.credentials_dialog = InputDialog:new{
        title = "StoryGraph Credentials",
        fields = {
            {
                text = creds.email or "",
                hint = "Email",
            },
            {
                text = creds.password or "",
                hint = "Password",
                secret = true,
            },
        },
        buttons = {
            {
                {
                    text = "Cancel",
                    callback = function()
                        UIManager:close(self.credentials_dialog)
                    end,
                },
                {
                    text = "Save & Test",
                    is_enter_default = true,
                    callback = function()
                        local fields = self.credentials_dialog:getFields()
                        local email = fields[1]
                        local password = fields[2]
                        
                        Config.setCredentials(email, password)
                        
                        -- Test login
                        local success, err = Api.login()
                        UIManager:close(self.credentials_dialog)
                        
                        if success then
                            UIManager:show(InfoMessage:new{
                                text = "Credentials saved and verified",
                            })
                        else
                            UIManager:show(InfoMessage:new{
                                text = "Login failed: " .. (err or "unknown error"),
                            })
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(self.credentials_dialog)
    self.credentials_dialog:onShowKeyboard()
end

-- Manual sync trigger
function StoryGraphPlugin:manualSync()
    local success = Sync.processQueue()
    if success then
        UIManager:show(InfoMessage:new{
            text = "Sync successful",
        })
    else
        UIManager:show(InfoMessage:new{
            text = "Sync failed - will retry later",
        })
    end
end

return StoryGraphPlugin
