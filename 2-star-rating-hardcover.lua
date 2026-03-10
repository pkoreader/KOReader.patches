--[[ User patch for KOReader: Hardcover Star Overlay (Perfect Sync & Match) ]]--

local userpatch = require("userpatch")
local Screen = require("device").screen
local IconWidget = require("ui/widget/iconwidget")
local Notification = require("ui/widget/notification")
local logger = require("logger")

if not _G.HardcoverRatingsCache then
    _G.HardcoverRatingsCache = {}
end

local function normalizeTitle(t)
    if type(t) ~= "string" then return "" end
    return string.gsub(string.lower(t), "[%W_]", "")
end

local function patchStarRating()
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    
    if not MosaicMenuItem then return end
    if MosaicMenuItem.patched_hardcover_stars then return end
    MosaicMenuItem.patched_hardcover_stars = true

    local orig_paint = MosaicMenuItem.paintTo
    local corner_mark_size = userpatch.getUpValue(orig_paint, "corner_mark_size") or Screen:scaleBySize(20)

    local init_done = false
    local DataStorage, UIManager, NetworkManager

    function MosaicMenuItem:paintTo(bb, x, y)
        orig_paint(self, bb, x, y)

        local ok, err = pcall(function()
            if not init_done then
                DataStorage = require("datastorage")
                UIManager = require("ui/uimanager")
                NetworkManager = require("ui/network/manager")
                init_done = true
            end

            -- TRIGGER BACKGROUND FETCH
            if not _G.HardcoverFetchStarted and NetworkManager and NetworkManager:isConnected() then
                _G.HardcoverFetchStarted = true 
                
                UIManager:show(Notification:new{text="Hardcover: Fetching actual ratings..."})
                
                UIManager:scheduleIn(0.1, function()
                    local net_ok, net_err = pcall(function()
                        local https_ok, https = pcall(require, "ssl.https")
                        local http_client = https_ok and https or require("socket.http")
                        local ltn12 = require("ltn12")
                        local json = require("json")

                        local base_dir = DataStorage:getDataDir()
                        local config_paths = {
                            base_dir .. "/plugins/hardcoverapp.koplugin/hardcover_config.lua",
                            DataStorage:getSettingsDir() .. "/hardcover_config.lua"
                        }
                        
                        local config_path = nil
                        for _, path in ipairs(config_paths) do
                            local cf = io.open(path, "r")
                            if cf then
                                cf:close()
                                config_path = path
                                break
                            end
                        end

                        if not config_path then return end

                        local cok, config = pcall(dofile, config_path)
                        if not cok or type(config) ~= "table" or not config.token then return end

                        local query = '{"query": "{ me { user_books { book { id title } rating } } }"}'
                        local response_body = {}
                        
                        local res, code = http_client.request{
                            url = "https://api.hardcover.app/v1/graphql",
                            method = "POST",
                            headers = {
                                ["Authorization"] = "Bearer " .. config.token,
                                ["Content-Type"] = "application/json",
                                ["Content-Length"] = tostring(#query)
                            },
                            source = ltn12.source.string(query),
                            sink = ltn12.sink.table(response_body)
                        }

                        if code == 200 then
                            local raw_json = table.concat(response_body)
                            local success, parsed = pcall(json.decode, raw_json)
                            
                            if success and parsed and parsed.data and parsed.data.me then
                                local me_data = parsed.data.me
                                if type(me_data) == "table" and me_data[1] then me_data = me_data[1] end
                                
                                local count = 0
                                if me_data.user_books then
                                    for _, read_data in ipairs(me_data.user_books) do
                                        -- STRICT FILTER: Only cache and count if rating is greater than 0
                                        if read_data.book and read_data.rating then
                                            local r = tonumber(read_data.rating)
                                            if r and r > 0 then
                                                count = count + 1
                                                if read_data.book.id then
                                                    _G.HardcoverRatingsCache[tostring(read_data.book.id)] = r
                                                end
                                                if read_data.book.title then
                                                    _G.HardcoverRatingsCache[normalizeTitle(read_data.book.title)] = r
                                                end
                                            end
                                        end
                                    end
                                    UIManager:show(Notification:new{text="Hardcover: Successfully loaded " .. count .. " ratings!"})
                                    UIManager:setDirty(nil, "ui")
                                end
                            end
                        else
                            _G.HardcoverFetchStarted = false
                        end
                    end)
                    if not net_ok then _G.HardcoverFetchStarted = false end
                end)
            end

            -- Ensure it's drawing inside the cover boundaries
            local target = self[1] and self[1][1] and self[1][1][1]
            if not target or not target.dimen then return end

            local rating = nil
            
            -- LOAD HARDCOVER SYNC SETTINGS (Just like main.lua does!)
            if not _G.HardcoverLinkedBooksCache then
                local sync_path = DataStorage:getSettingsDir() .. "/hardcoversync_settings.lua"
                local ok_sync, sync_data = pcall(dofile, sync_path)
                if ok_sync and type(sync_data) == "table" then
                    _G.HardcoverLinkedBooksCache = sync_data.books or sync_data
                else
                    _G.HardcoverLinkedBooksCache = {}
                end
            end

            -- EXACT ID MATCH
            if _G.HardcoverLinkedBooksCache[self.filepath] then
                local book_data = _G.HardcoverLinkedBooksCache[self.filepath]
                if type(book_data) == "table" and book_data.book_id then
                    rating = _G.HardcoverRatingsCache[tostring(book_data.book_id)]
                end
            end

            -- TITLE FALLBACK MATCH
            if not rating then
                local ok_info, book_info = pcall(function() return self.menu.getBookInfo(self.filepath) end)
                if ok_info and book_info and book_info.title then
                    local safe_title = normalizeTitle(book_info.title)
                    rating = _G.HardcoverRatingsCache[safe_title]
                end
            end

            -- Stop if book has no rating on Hardcover
            if not rating or rating <= 0 then return end

            -- DRAW THE STARS
            local max_stars = 5
            local star_size = math.floor(corner_mark_size)
            local stars_width = max_stars * star_size 
            local margin = math.floor((target.dimen.w - stars_width) / 2)
            local pos_x = x + math.ceil((self.width - target.dimen.w) / 2) + margin
            local bottom_margin = Screen:scaleBySize(6)
            local pos_y = y + self.height - math.ceil((self.height - target.dimen.h) / 2) - corner_mark_size - bottom_margin

            for i = 1, max_stars do
                local icon_name = "star.empty"
                
                if rating >= i then
                    icon_name = "star.full"
                elseif rating >= (i - 0.5) then
                    icon_name = "star.half"
                end
                
                local star_icon = IconWidget:new{
                    icon = icon_name,
                    width = star_size,
                    height = star_size,
                    alpha = true,
                }
                star_icon:paintTo(bb, pos_x + (i-1)*star_size, pos_y)
                star_icon:free()
            end
        end)

        if not ok then
            logger.warn("Hardcover stars failed to draw: " .. tostring(err))
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchStarRating)
userpatch.registerPatchPluginFunc("projecttitle", patchStarRating)

return true
