-- No Delete Addon for WoW Classic MoP
-- Protects items from accidental deletion/selling

local NoDelete = CreateFrame("Frame", "NoDelete", UIParent)
NoDelete:RegisterEvent("ADDON_LOADED")
NoDelete:RegisterEvent("PLAYER_LOGIN")

-- Default saved variables
NoDeleteDB = NoDeleteDB or {}
NoDeleteDB.lockedItems = NoDeleteDB.lockedItems or {}
NoDeleteDB.debugInfo = NoDeleteDB.debugInfo or {}

-- UI Variables
local NoDeleteFrame = nil
local itemButtons = {}

-- API Compatibility Layer (inspired by RXPGuides)
local GetContainerNumSlots = C_Container and C_Container.GetContainerNumSlots or _G.GetContainerNumSlots
local GetContainerItemID = C_Container and C_Container.GetContainerItemID or _G.GetContainerItemID
local UseContainerItem = C_Container and C_Container.UseContainerItem or _G.UseContainerItem
local PickupContainerItem = C_Container and C_Container.PickupContainerItem or _G.PickupContainerItem

local GetContainerItemInfo
if C_Container and C_Container.GetContainerItemInfo then
    GetContainerItemInfo = function(...)
        local itemTable = C_Container.GetContainerItemInfo(...)
        if itemTable then
            return itemTable.iconFileID or itemTable.texture,
                   itemTable.stackCount,
                   itemTable.isLocked,
                   itemTable.quality,
                   itemTable.isReadable,
                   itemTable.hasLoot,
                   itemTable.hyperlink,
                   itemTable.isFiltered,
                   itemTable.hasNoValue,
                   itemTable.itemID,
                   itemTable.isBound
        end
    end
else
    GetContainerItemInfo = _G.GetContainerItemInfo
end

-- Helper function to get item key
local function GetItemKey(bag, slot)
    return bag .. "_" .. slot
end

-- Helper function to get item link from bag/slot
local function GetItemFromBagSlot(bag, slot)
    local _, _, _, _, _, _, itemLink = GetContainerItemInfo(bag, slot)
    return itemLink
end

-- Helper function to get number of slots in bag
local function GetBagNumSlots(bag)
    return GetContainerNumSlots(bag) or 0
end

-- Scan all bag items
local function ScanAllItems()
    local items = {}
    
    -- Scan all bags (0-4)
    for bag = 0, 4 do
        local numSlots = GetBagNumSlots(bag)
        for slot = 1, numSlots do
            local texture, stackCount, locked, quality, readable, lootable, itemLink, filtered, hasNoValue, itemID, isBound = GetContainerItemInfo(bag, slot)
            if itemLink and itemID then
                local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
                if itemName then
                    table.insert(items, {
                        bag = bag,
                        slot = slot,
                        itemID = itemID,
                        itemName = itemName,
                        itemLink = itemLink,
                        texture = itemTexture or texture,
                        quality = itemQuality or quality,
                        stackCount = stackCount,
                        isLocked = NoDeleteDB.lockedItems[itemID] ~= nil
                    })
                end
            end
        end
    end
    
    return items
end

-- Check if an item ID is locked
function NoDelete:IsItemIDLocked(itemID)
    return NoDeleteDB.lockedItems[itemID] ~= nil
end

-- Check if an item in a bag slot is locked
function NoDelete:IsItemLocked(bag, slot)
    local itemLink = GetItemFromBagSlot(bag, slot)
    if not itemLink then return false end
    
    local itemID = tonumber(itemLink:match("item:(%d+)"))
    return self:IsItemIDLocked(itemID)
end

-- Lock an item by ID
function NoDelete:LockItemByID(itemID, itemName)
    NoDeleteDB.lockedItems[itemID] = itemName or GetItemInfo(itemID)
    print("|cff00ff00NoDelete:|r Item '" .. (itemName or "Unknown") .. "' is now protected from deletion/selling.")
    self:UpdateBagButtons()
end

-- Close any protection popups for a specific item
local function CloseProtectionPopup(itemID)
    for i = 1, 4 do
        local popup = _G["StaticPopup" .. i]
        if popup and popup:IsShown() and popup.which == "NODELETE_ITEM_PROTECTED_SELL" then
            if popup.nodelete_itemID == itemID then
                popup:Hide()
            end
        end
    end
end

-- Close all protection popups
local function CloseAllProtectionPopups()
    for i = 1, 4 do
        local popup = _G["StaticPopup" .. i]
        if popup and popup:IsShown() and popup.which == "NODELETE_ITEM_PROTECTED_SELL" then
            popup:Hide()
        end
    end
end

-- Unlock an item by ID
function NoDelete:UnlockItemByID(itemID, itemName)
    NoDeleteDB.lockedItems[itemID] = nil
    print("|cffff0000NoDelete:|r Item '" .. (itemName or "Unknown") .. "' is no longer protected.")
    self:UpdateBagButtons()
    
    -- Close any protection popup for this item
    CloseProtectionPopup(itemID)
end

-- Update visual indicators (removed border code that was causing issues)
function NoDelete:UpdateBagButtons()
    -- No visual indicators in bags for now - just use tooltip
end

-- Hook into GameTooltip to add protection info
local function OnTooltipSetItem(tooltip)
    local _, itemLink = tooltip:GetItem()
    if itemLink then
        local itemID = tonumber(itemLink:match("item:(%d+)"))
        if itemID and NoDelete:IsItemIDLocked(itemID) then
            tooltip:AddLine(" ")
            tooltip:AddLine("|cffff6666[PROTECTED BY NODELETE]|r", 1, 1, 1)
            tooltip:AddLine("|cffccccccThis item cannot be deleted or sold|r", 0.8, 0.8, 0.8)
            tooltip:Show()
        end
    end
end

-- Register tooltip hook
if GameTooltip:HasScript("OnTooltipSetItem") then
    GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
end

-- Removed problematic container button hooks that interfere with bag addons like Bagnon

-- Create the main UI frame
function NoDelete:CreateUI()
    if NoDeleteFrame then return end
    
    -- Main frame
    NoDeleteFrame = CreateFrame("Frame", "NoDeleteFrame", UIParent, "BasicFrameTemplateWithInset")
    NoDeleteFrame:SetSize(400, 500)
    NoDeleteFrame:SetPoint("CENTER")
    NoDeleteFrame:SetMovable(true)
    NoDeleteFrame:EnableMouse(true)
    NoDeleteFrame:RegisterForDrag("LeftButton")
    NoDeleteFrame:SetScript("OnDragStart", NoDeleteFrame.StartMoving)
    NoDeleteFrame:SetScript("OnDragStop", NoDeleteFrame.StopMovingOrSizing)
    
    -- Make frame closable with ESC key
    NoDeleteFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
            self:SetPropagateKeyboardInput(false) -- Don't let ESC propagate to game menu
        end
    end)
    
    -- Enable keyboard input and make sure frame can receive focus
    NoDeleteFrame:SetScript("OnShow", function(self)
        self:EnableKeyboard(true)
        self:SetPropagateKeyboardInput(false) -- Don't propagate keyboard input to prevent ESC menu
    end)
    
    NoDeleteFrame:SetScript("OnHide", function(self)
        self:EnableKeyboard(false)
    end)
    
    NoDeleteFrame:Hide()
    
    -- Title
    NoDeleteFrame.title = NoDeleteFrame:CreateFontString(nil, "OVERLAY")
    NoDeleteFrame.title:SetFontObject("GameFontHighlight")
    NoDeleteFrame.title:SetPoint("CENTER", NoDeleteFrame.TitleBg, "CENTER", 0, 0)
    NoDeleteFrame.title:SetText("No Delete - Item Protection")
    
    -- Close button is already created by BasicFrameTemplateWithInset
    
    -- Button bar at bottom (made taller for two lines of text)
    local buttonBar = CreateFrame("Frame", "NoDeleteButtonBar", NoDeleteFrame)
    buttonBar:SetSize(380, 50)
    buttonBar:SetPoint("BOTTOM", 0, 5)
    
    -- Refresh button
    local refreshButton = CreateFrame("Button", "NoDeleteRefreshButton", buttonBar, "GameMenuButtonTemplate")
    refreshButton:SetSize(80, 25)
    refreshButton:SetPoint("LEFT", 10, 0)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", function() NoDelete:RefreshItemList() end)
    
    -- Clear All button
    local clearAllButton = CreateFrame("Button", "NoDeleteClearAllButton", buttonBar, "GameMenuButtonTemplate")
    clearAllButton:SetSize(80, 25)
    clearAllButton:SetPoint("CENTER", 0, 0)
    clearAllButton:SetText("Clear All")
    clearAllButton:SetScript("OnClick", function() NoDelete:ClearAllLocks() end)
    
    -- Close button
    local closeButton = CreateFrame("Button", "NoDeleteCloseButton", buttonBar, "GameMenuButtonTemplate")
    closeButton:SetSize(60, 25)
    closeButton:SetPoint("RIGHT", -10, 0)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function() NoDeleteFrame:Hide() end)
    
    -- Info text at top of frame
    local infoText = NoDeleteFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT", NoDeleteFrame, "TOPLEFT", 15, -35)
    infoText:SetText("Check items to protect")
    infoText:SetTextColor(0.7, 0.7, 0.7)
    
    -- Shortcut info text at top of frame
    local shortcutText = NoDeleteFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    shortcutText:SetPoint("TOPLEFT", NoDeleteFrame, "TOPLEFT", 15, -50)
    shortcutText:SetText("Ctrl+Alt+Right-click in bags to toggle")
    shortcutText:SetTextColor(0.5, 0.8, 0.5)
    
    -- Scroll frame for items (leave space for text at top and button bar at bottom)
    local scrollFrame = CreateFrame("ScrollFrame", "NoDeleteScrollFrame", NoDeleteFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -65)  -- Start below the text
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 60) -- Leave space for button bar
    
    -- Content frame
    local contentFrame = CreateFrame("Frame", "NoDeleteContentFrame", scrollFrame)
    contentFrame:SetSize(360, 1)
    scrollFrame:SetScrollChild(contentFrame)
    
    -- Store references
    NoDeleteFrame.scrollFrame = scrollFrame
    NoDeleteFrame.contentFrame = contentFrame
    NoDeleteFrame.buttonBar = buttonBar
end

-- Show/Hide the UI
function NoDelete:ToggleUI()
    if not NoDeleteFrame then
        self:CreateUI()
    end
    
    if NoDeleteFrame:IsShown() then
        NoDeleteFrame:Hide()
    else
        NoDeleteFrame:Show()
        self:RefreshItemList()
    end
end

-- Clear all item locks
function NoDelete:ClearAllLocks()
    StaticPopup_Show("NODELETE_CONFIRM_CLEAR_ALL")
end

-- Refresh the item list in the UI
function NoDelete:RefreshItemList()
    if not NoDeleteFrame then return end
    
    -- Clear existing buttons
    for _, button in pairs(itemButtons) do
        button:Hide()
        button:SetParent(nil)
    end
    wipe(itemButtons)
    
    local yOffset = 0
    local buttonHeight = 32
    
    -- Scan all bag items
    local items = ScanAllItems()
    
    -- Sort items by name
    table.sort(items, function(a, b) return a.itemName < b.itemName end)
    
    -- Create UI elements for each item
    for i, item in ipairs(items) do
        local button = CreateFrame("Frame", "NoDeleteItem"..i, NoDeleteFrame.contentFrame)
        button:SetSize(350, buttonHeight - 2)
        button:SetPoint("TOPLEFT", 5, -yOffset)
        
        -- Background (alternating colors)
        button.bg = button:CreateTexture(nil, "BACKGROUND")
        button.bg:SetAllPoints()
        if i % 2 == 0 then
            button.bg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
        else
            button.bg:SetColorTexture(0.05, 0.05, 0.05, 0.3)
        end
        
        -- Item icon
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(24, 24)
        button.icon:SetPoint("LEFT", 4, 0)
        button.icon:SetTexture(item.texture)
        
        -- Quality border for icon
        local r, g, b = GetItemQualityColor(item.quality)
        button.iconBorder = button:CreateTexture(nil, "OVERLAY")
        button.iconBorder:SetSize(28, 28)
        button.iconBorder:SetPoint("CENTER", button.icon, "CENTER")
        button.iconBorder:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
        button.iconBorder:SetVertexColor(r, g, b, 1)
        
        -- Red border for locked items in UI
        if item.isLocked then
            button.iconBorder:SetVertexColor(1, 0, 0, 1)
        end
        
        -- Item name with stack count
        local nameText = item.itemName
        if item.stackCount and item.stackCount > 1 then
            nameText = nameText .. " (" .. item.stackCount .. ")"
        end
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.text:SetPoint("LEFT", button.icon, "RIGHT", 8, 0)
        button.text:SetPoint("RIGHT", -100, 0)
        button.text:SetJustifyH("LEFT")
        button.text:SetText(nameText)
        button.text:SetTextColor(r, g, b)
        
        -- Checkbox
        button.checkbox = CreateFrame("CheckButton", "NoDeleteCheckbox"..i, button, "UICheckButtonTemplate")
        button.checkbox:SetSize(24, 24)
        button.checkbox:SetPoint("RIGHT", -10, 0)
        button.checkbox:SetChecked(item.isLocked)
        
        -- Store item data
        button.itemData = item
        
        -- Checkbox click handler
        button.checkbox:SetScript("OnClick", function(self)
            local isChecked = self:GetChecked()
            if isChecked then
                NoDelete:LockItemByID(button.itemData.itemID, button.itemData.itemName)
                button.iconBorder:SetVertexColor(1, 0, 0, 1)
            else
                NoDelete:UnlockItemByID(button.itemData.itemID, button.itemData.itemName)
                local r, g, b = GetItemQualityColor(button.itemData.quality)
                button.iconBorder:SetVertexColor(r, g, b, 1)
            end
        end)
        
        -- Enhanced tooltip
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(item.itemLink)
            
            -- Add lock status to tooltip
            if item.isLocked then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cffff6666[PROTECTED BY NODELETE]|r", 1, 1, 1)
                GameTooltip:AddLine("|cffccccccThis item is protected from deletion and selling|r", 0.8, 0.8, 0.8)
            else
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cff888888Not protected - can be deleted/sold|r", 0.7, 0.7, 0.7)
            end
            
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        table.insert(itemButtons, button)
        yOffset = yOffset + buttonHeight
    end
    
    -- Update content frame height
    NoDeleteFrame.contentFrame:SetHeight(math.max(yOffset, 400))
end

-- Lock item by ID
function NoDelete:LockItemByID(itemID, itemName)
    NoDeleteDB.lockedItems[itemID] = itemName or GetItemInfo(itemID)
    print("|cff00ff00NoDelete:|r Item '" .. (itemName or "Unknown") .. "' is now protected from deletion/selling.")
    self:UpdateBagButtons()
end

-- Unlock item by ID
function NoDelete:UnlockItemByID(itemID, itemName)
    NoDeleteDB.lockedItems[itemID] = nil
    print("|cffff0000NoDelete:|r Item '" .. (itemName or "Unknown") .. "' is no longer protected.")
    self:UpdateBagButtons()
end

-- Hook merchant selling functions
local itemBeingPickedUp = nil

-- Hook for Ctrl+Alt+Right-click toggle functionality
local function HookModifiedClick()
    -- Use secure hook for OnModifiedClick which works with bag addons
    if _G["ContainerFrameItemButton_OnModifiedClick"] then
        hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, button)
            -- Check for Ctrl+Alt+Right-click to toggle protection
            if button == "RightButton" and IsControlKeyDown() and IsAltKeyDown() then
                local bag = self:GetParent():GetID()
                local slot = self:GetID()
                local itemLink = GetItemFromBagSlot(bag, slot)
                
                if itemLink then
                    local itemID = tonumber(itemLink:match("item:(%d+)"))
                    if itemID then
                        local itemName = GetItemInfo(itemID)
                        local isLocked = NoDelete:IsItemIDLocked(itemID)
                        
                        if isLocked then
                            NoDelete:UnlockItemByID(itemID, itemName)
                        else
                            NoDelete:LockItemByID(itemID, itemName)
                        end
                        
                        -- Refresh the UI if it's open
                        if NoDeleteFrame and NoDeleteFrame:IsShown() then
                            NoDelete:RefreshItemList()
                        end
                    end
                end
            end
        end)
    end
end

-- Removed problematic vendor hooks - keeping only SellCursorItem protection

local function HookSellCursorItem()
    -- Hook SellCursorItem as backup protection
    if SellCursorItem then
        local originalSellCursorItem = SellCursorItem
        
        SellCursorItem = function(...)
            print("|cffffff00NoDelete Debug:|r SellCursorItem called")
            -- Check what's on the cursor
            local cursorType, itemID = GetCursorInfo()
            print("|cffffff00NoDelete Debug:|r Cursor has: " .. tostring(cursorType) .. " itemID: " .. tostring(itemID))
            
            if cursorType == "item" and itemID and NoDelete:IsItemIDLocked(itemID) then
                local itemName = GetItemInfo(itemID)
                print("|cffff0000NoDelete:|r BLOCKING cursor sale of protected item: " .. (itemName or "Unknown"))
                StaticPopup_Show("NODELETE_ITEM_PROTECTED_SELL", itemName)
                return
            end
            
            originalSellCursorItem(...)
        end
    end
    
    -- Hook UseContainerItem which is used for right-clicking items
    if UseContainerItem then
        local originalUseContainerItem = UseContainerItem
        UseContainerItem = function(bagID, slot, ...)
            print("|cffffff00NoDelete Debug:|r UseContainerItem called: bag=" .. tostring(bagID) .. " slot=" .. tostring(slot))
            
            -- Only check at vendors
            if MerchantFrame and MerchantFrame:IsShown() then
                print("|cffffff00NoDelete Debug:|r Merchant open, checking item protection")
                if bagID and slot and NoDelete:IsItemLocked(bagID, slot) then
                    local itemLink = GetItemFromBagSlot(bagID, slot)
                    if itemLink then
                        local itemName = GetItemInfo(itemLink:match("item:(%d+)"))
                        print("|cffff0000NoDelete:|r BLOCKING UseContainerItem sale of protected item: " .. (itemName or "Unknown"))
                        StaticPopup_Show("NODELETE_ITEM_PROTECTED_SELL", itemName)
                        return
                    end
                end
            end
            
            return originalUseContainerItem(bagID, slot, ...)
        end
    end
    
    -- Hook PickupContainerItem for drag-and-drop selling
    if PickupContainerItem then
        local originalPickupContainerItem = PickupContainerItem
        PickupContainerItem = function(bagID, slot, ...)
            print("|cffffff00NoDelete Debug:|r PickupContainerItem called: bag=" .. tostring(bagID) .. " slot=" .. tostring(slot))
            
            -- Only check at vendors
            if MerchantFrame and MerchantFrame:IsShown() then
                print("|cffffff00NoDelete Debug:|r Merchant open, checking pickup protection")
                if bagID and slot and NoDelete:IsItemLocked(bagID, slot) then
                    local itemLink = GetItemFromBagSlot(bagID, slot)
                    if itemLink then
                        local itemName = GetItemInfo(itemLink:match("item:(%d+)"))
                        print("|cffff0000NoDelete:|r BLOCKING PickupContainerItem of protected item at vendor: " .. (itemName or "Unknown"))
                        StaticPopup_Show("NODELETE_ITEM_PROTECTED_SELL", itemName)
                        return
                    end
                end
            end
            
            return originalPickupContainerItem(bagID, slot, ...)
        end
    end
end


-- Hook other possible vendor functions
local function HookVendorFunctions()
    -- Hook SellCursorItem for drag-and-drop selling protection
    if SellCursorItem then
        local originalSellCursorItem = SellCursorItem
        SellCursorItem = function(...)
            -- Check what's on cursor
            local type, itemID = GetCursorInfo()
            if type == "item" and NoDelete:IsItemIDLocked(itemID) then
                local itemName = GetItemInfo(itemID)
                StaticPopup_Show("NODELETE_ITEM_PROTECTED_SELL", itemName, nil, {itemID = itemID})
                return
            end
            return originalSellCursorItem(...)
        end
    end
end

-- Track items before merchant interactions
local itemsBeforeMerchant = {}

local function ScanItemsBeforeMerchant()
    itemsBeforeMerchant = {}
    for bag = 0, 4 do
        itemsBeforeMerchant[bag] = {}
        local numSlots = GetBagNumSlots(bag)
        for slot = 1, numSlots do
            local itemLink = GetItemFromBagSlot(bag, slot)
            if itemLink then
                local itemID = tonumber(itemLink:match("item:(%d+)"))
                -- Only track items that are currently protected
                if NoDelete:IsItemIDLocked(itemID) then
                    itemsBeforeMerchant[bag][slot] = {
                        itemID = itemID,
                        itemLink = itemLink,
                        isProtected = true
                    }
                end
            end
        end
    end
end

local function CheckForSoldProtectedItems()
    for bag = 0, 4 do
        if itemsBeforeMerchant[bag] then
            local numSlots = GetBagNumSlots(bag)
            for slot = 1, numSlots do
                local beforeItem = itemsBeforeMerchant[bag][slot]
                if beforeItem and beforeItem.isProtected then
                    local currentLink = GetItemFromBagSlot(bag, slot)
                    -- If item was there before but is gone now, it was sold
                    if not currentLink then
                        local itemName = GetItemInfo(beforeItem.itemID)
                        
                        -- Only buy back if the item is STILL protected (in case user unprotected it quickly)
                        if NoDelete:IsItemIDLocked(beforeItem.itemID) then
                            -- Try to buy it back with multiple attempts for reliability
                            local attempts = 0
                            local maxAttempts = 3
                            
                            local function TryBuyback()
                                attempts = attempts + 1
                                
                                -- Check if item is still protected before each attempt
                                if not NoDelete:IsItemIDLocked(beforeItem.itemID) then
                                    return -- Item was unprotected, don't buy back
                                end
                                
                                local foundItem = false
                                for i = 1, GetNumBuybackItems() do
                                    local buybackName, _, _, _, _, _, _, _, _ = GetBuybackItemInfo(i)
                                    local buybackLink = GetBuybackItemLink(i)
                                    
                                    -- Match by name or try to match by item ID from link
                                    local nameMatch = (buybackName == itemName)
                                    local idMatch = false
                                    if buybackLink then
                                        local buybackItemID = tonumber(buybackLink:match("item:(%d+)"))
                                        idMatch = (buybackItemID == beforeItem.itemID)
                                    end
                                    
                                    if nameMatch or idMatch then
                                        BuybackItem(i)
                                        print("|cff00ff00NoDelete:|r Protected item '" .. itemName .. "' has been bought back automatically!")
                                        foundItem = true
                                        break
                                    end
                                end
                                
                                -- If we didn't find the item and haven't exceeded max attempts, try again
                                if not foundItem and attempts < maxAttempts then
                                    C_Timer.After(0.2, TryBuyback)
                                end
                            end
                            
                            -- Start first attempt after a short delay
                            C_Timer.After(0.1, TryBuyback)
                        end
                    end
                end
            end
        end
    end
end

-- Hook vendor selling using secure hooks that don't break normal functionality
local function HookVendorProtection()
    -- Use hooksecurefunc instead of replacing functions to avoid breaking normal usage
    if _G["ContainerFrameItemButton_OnClick"] then
        hooksecurefunc("ContainerFrameItemButton_OnClick", function(self, button, ...)
            -- Only interfere with right-clicks at merchants for protected items
            if button == "RightButton" and MerchantFrame and MerchantFrame:IsShown() then
                local bag = self:GetParent() and self:GetParent():GetID() or nil
                local slot = self:GetID() or nil
                
                -- Use a small delay to check protection status after any toggle operations
                C_Timer.After(0.05, function()
                    if bag and slot and NoDelete:IsItemLocked(bag, slot) then
                        local itemLink = GetItemFromBagSlot(bag, slot)
                        if itemLink then
                            local itemID = tonumber(itemLink:match("item:(%d+)"))
                            local itemName = GetItemInfo(itemID)
                            StaticPopup_Show("NODELETE_ITEM_PROTECTED_SELL", itemName, nil, {itemID = itemID})
                        end
                    end
                end)
            end
        end)
    end
    
    -- Hook multiple possible selling functions to catch the actual one being used
    local functionsToHook = {
        "UseContainerItem",
        "PickupContainerItem", 
        "SellCursorItem"
    }
    
    for _, funcName in ipairs(functionsToHook) do
        if _G[funcName] then
            local originalFunc = _G[funcName]
            _G[funcName] = function(...)
                local args = {...}
                
                -- Only interfere at merchants
                if MerchantFrame and MerchantFrame:IsShown() then
                    if funcName == "UseContainerItem" or funcName == "PickupContainerItem" then
                        local bagID, slot = args[1], args[2]
                        if bagID and slot and NoDelete:IsItemLocked(bagID, slot) then
                            local itemLink = GetItemFromBagSlot(bagID, slot)
                            if itemLink then
                                local itemID = tonumber(itemLink:match("item:(%d+)"))
                                local itemName = GetItemInfo(itemID)
                                StaticPopup_Show("NODELETE_ITEM_PROTECTED_SELL", itemName, nil, {itemID = itemID})
                                return -- Block the function
                            end
                        end
                    elseif funcName == "SellCursorItem" then
                        local cursorType, itemID = GetCursorInfo()
                        if cursorType == "item" and itemID and NoDelete:IsItemIDLocked(itemID) then
                            local itemName = GetItemInfo(itemID)
                            StaticPopup_Show("NODELETE_ITEM_PROTECTED_SELL", itemName, nil, {itemID = itemID})
                            return -- Block the function
                        end
                    end
                end
                
                return originalFunc(...)
            end
        end
    end
end

-- Event handler
NoDelete:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "NoDelete" then
            print("|cff00ff00NoDelete|r loaded! Type /nodelete to open the protection window.")
            
            -- Hook vendor functions to prevent selling protected items
            HookModifiedClick()
            HookSellCursorItem()
            HookVendorFunctions()
            
            -- Hook vendor protection after other addons load
            C_Timer.After(2, function()
                HookVendorProtection()
            end)
        end
    elseif event == "PLAYER_LOGIN" then
        -- Hook into bag updates and merchant events
        self:RegisterEvent("BAG_UPDATE")
        self:RegisterEvent("MERCHANT_SHOW")
        self:RegisterEvent("MERCHANT_CLOSED")
        self:RegisterEvent("UI_INFO_MESSAGE")
        self:UpdateBagButtons()
    elseif event == "BAG_UPDATE" then
        C_Timer.After(0.1, function()
            self:UpdateBagButtons()
            -- Check if merchant is open and items were sold
            if MerchantFrame and MerchantFrame:IsShown() then
                CheckForSoldProtectedItems()
            end
        end)
    elseif event == "MERCHANT_SHOW" then
        ScanItemsBeforeMerchant()
    elseif event == "MERCHANT_CLOSED" then
        itemsBeforeMerchant = {}
        -- Close all protection popups when merchant closes
        CloseAllProtectionPopups()
    elseif event == "UI_INFO_MESSAGE" then
        -- Handle UI info messages if needed
    end
end)

-- Hook delete confirmation
local originalDeleteCursorItem = DeleteCursorItem
DeleteCursorItem = function()
    local type, itemID = GetCursorInfo()
    if type == "item" and NoDelete:IsItemIDLocked(itemID) then
        local itemName = GetItemInfo(itemID)
        StaticPopup_Show("NODELETE_ITEM_PROTECTED_DELETE", itemName)
        return
    end
    originalDeleteCursorItem()
end



-- Static popup for protected item sale attempt
StaticPopupDialogs["NODELETE_ITEM_PROTECTED_SELL"] = {
    text = "%s is protected by NoDelete and cannot be sold.\n\nUse /nodelete to remove protection.",
    button1 = "OK",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self, data)
        -- Store the item ID for this popup so we can close it if item gets unprotected
        if data and data.itemID then
            self.nodelete_itemID = data.itemID
        end
    end,
}

-- Static popup for protected item delete attempt
StaticPopupDialogs["NODELETE_ITEM_PROTECTED_DELETE"] = {
    text = "%s is protected by NoDelete and cannot be deleted.\n\nUse /nodelete to remove protection.",
    button1 = "OK",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}


-- Static popup for clearing all locks
StaticPopupDialogs["NODELETE_CONFIRM_CLEAR_ALL"] = {
    text = "Are you sure you want to remove protection from ALL items?",
    button1 = "Yes, Clear All",
    button2 = "Cancel",
    OnAccept = function()
        wipe(NoDeleteDB.lockedItems)
        print("|cffff0000NoDelete:|r All item protections cleared.")
        NoDelete:UpdateBagButtons()
        if NoDeleteFrame and NoDeleteFrame:IsShown() then
            NoDelete:RefreshItemList()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Slash commands
SLASH_NODELETE1 = "/nodelete"
SLASH_NODELETE2 = "/nd"
SlashCmdList["NODELETE"] = function(msg)
    NoDelete:ToggleUI()
end

