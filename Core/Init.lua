--===========================================================================
-- EzWoW - Map Finder
-- Core/Init.lua : Namespace, SavedVariables Bootstrap & Styled Button Factory
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local CoreBootstrap = ns.CoreBootstrap or {}
ns.CoreBootstrap = CoreBootstrap

_G.EzWoW_MapFinder = ns
_G.EzWoW_MapFinder = ns
_G.EzWoWMapFinderData = _G.EzWoWMapFinderData or {}
ns.Data = _G.EzWoWMapFinderData

ns.ADDON_NAME = ADDON_NAME or "EzWoW-MapFinder"
ns.DONATE_URL = "https://buymeacoffee.com/qqhrqqhr2"

local Theme = {
    bg     = { 0.071, 0.094, 0.122, 0.96 }, 
    bgSub  = { 0.114, 0.157, 0.192, 0.94 }, 
    border = { 0.204, 0.298, 0.357, 1.00 }, 
    accent = { 0.294, 0.784, 0.910, 1.00 }, 
    text   = { 0.929, 0.957, 0.969, 1.00 }, 
    muted  = { 0.655, 0.725, 0.773, 1.00 }, 
    warn   = { 0.906, 0.486, 0.439, 1.00 }, 
}
ns.Theme = Theme

ns.KIND_COLORS = {
    rare    = "|cffcc66ff",
    pet     = "|cff60cea3",
    monster = "|cffff6b6b",
    npc     = "|cff4bc8e8",
    object  = "|cffeba86a",
    quest   = "|cfff1bd57",
    item    = "|cffc9a4ef",
}

ns.activeLocale = "enUS"
ns.activeCategory = "all"

function ns.ToLowerSafeString(s)
    if not s or s == "" then return "" end
    return (string.gsub(s, "[A-Z]", string.lower))
end

function ns.InitializeDatabase()
    if type(_G.EzWoW_MapFinderDB) ~= "table" and type(_G.EzWoW_MapFinderDB) == "table" then
        _G.EzWoW_MapFinderDB = _G.EzWoW_MapFinderDB
    end
    _G.EzWoW_MapFinderDB = _G.EzWoW_MapFinderDB or {}
    _G.EzWoW_MapFinderDB = _G.EzWoW_MapFinderDB
    local CONST_DB = _G.EzWoW_MapFinderDB
    ns.DB = CONST_DB

    if CONST_DB.lang == nil then CONST_DB.lang = "auto" end
    if CONST_DB.autoAlign == nil then CONST_DB.autoAlign = true end
    if CONST_DB.autoWaypoint == nil then CONST_DB.autoWaypoint = true end
    if CONST_DB.revealMap == nil then CONST_DB.revealMap = true end
    if CONST_DB.revealTint == nil then CONST_DB.revealTint = true end
    if CONST_DB.showCoords == nil then CONST_DB.showCoords = true end
    if CONST_DB.showZoneLevels == nil then CONST_DB.showZoneLevels = true end
    if CONST_DB.noMapFade == nil then CONST_DB.noMapFade = true end
    -- map backdrop darkness: nil = leave the game's own look alone (0-1 otherwise)
    if type(CONST_DB.mapBackdropAlpha) ~= "number" then CONST_DB.mapBackdropAlpha = nil end
    if CONST_DB.enableMapZoom == nil then CONST_DB.enableMapZoom = false end
    if CONST_DB.showTransit == nil then CONST_DB.showTransit = true end
    if CONST_DB.rareAlert == nil then CONST_DB.rareAlert = true end
    if CONST_DB.rareAlertSound == nil then CONST_DB.rareAlertSound = true end
    if CONST_DB.questLogPins == nil then CONST_DB.questLogPins = true end
    if CONST_DB.questLogPinsAll == nil then CONST_DB.questLogPinsAll = false end
    if CONST_DB.questObjectivePins == nil then CONST_DB.questObjectivePins = true end
    if CONST_DB.serviceNpcPins == nil then CONST_DB.serviceNpcPins = true end
    if CONST_DB.serviceNpcPinsZones == nil then CONST_DB.serviceNpcPinsZones = false end
    if type(CONST_DB.serviceNpcTypes) ~= "table" then CONST_DB.serviceNpcTypes = {} end
    if type(CONST_DB.buttonPos) ~= "table" then
        CONST_DB.buttonPos = { x = 0.04, y = 0.12 }
    end
    if ns.SynchronizeActiveLocale then
        ns.SynchronizeActiveLocale()
    end
    return CONST_DB
end

function ns.CreateStyledButton(parent, w, h, isAccent, onClick)
    local buttonWidget = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    buttonWidget:SetSize(w, h)
    if buttonWidget.SetBackdrop then
        ns.UIKit:ApplyBackdrop(buttonWidget)
    end
    local formatLocalizedLabel = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    formatLocalizedLabel:SetPoint("CENTER", 0, 0)
    buttonWidget.label = formatLocalizedLabel
    local function applyNormalButtonLook()
        if not buttonWidget.SetBackdropColor then return end
        if isAccent then
            buttonWidget:SetBackdropColor(0.14, 0.24, 0.30, 0.96)
            buttonWidget:SetBackdropBorderColor(unpack(Theme.accent))
            formatLocalizedLabel:SetTextColor(unpack(Theme.accent))
        else
            buttonWidget:SetBackdropColor(unpack(Theme.bgSub))
            buttonWidget:SetBackdropBorderColor(unpack(Theme.border))
            formatLocalizedLabel:SetTextColor(unpack(Theme.text))
        end
    end
    applyNormalButtonLook()
    buttonWidget:SetScript("OnEnter", function(self)
        if not self.SetBackdropColor then return end
        self:SetBackdropColor(0.18, 0.28, 0.35, 1)
        self:SetBackdropBorderColor(unpack(Theme.accent))
    end)
    buttonWidget:SetScript("OnLeave", applyNormalButtonLook)
    -- long translations shrink to the button width (tiny x buttons excluded)
    function buttonWidget:SetText(txt)
        self.label:SetText(txt or "")
        if w >= 40 then ns.UIKit:FitFontString(self.label, w - 8, 1) end
    end
    function buttonWidget:GetText() return self.label:GetText() end
    buttonWidget:SetScript("OnMouseDown", function() formatLocalizedLabel:SetPoint("CENTER", 1, -1) end)
    buttonWidget:SetScript("OnMouseUp", function() formatLocalizedLabel:SetPoint("CENTER", 0, 0) end)
    if onClick then buttonWidget:SetScript("OnClick", onClick) end
    return buttonWidget
end

-----------------------------------------------------------------------------
-- Our own World Map marks let right clicks through to the map (zoom out).
-- SetPassThroughButtons is blocked in combat: marks made then wait for its end.
-----------------------------------------------------------------------------
local passApplied = setmetatable({}, { __mode = "k" })
local passWaiting = {}
local passEvents

local function applyRightClickPass(frame)
    if passApplied[frame] or type(frame.SetPassThroughButtons) ~= "function" then return end
    if pcall(frame.SetPassThroughButtons, frame, "RightButton") then passApplied[frame] = true end
end

function ns.PassMapRightClicks(frame)
    if not frame or passApplied[frame] then return end
    if InCombatLockdown and InCombatLockdown() then
        passWaiting[#passWaiting + 1] = frame
        if not passEvents then
            passEvents = CreateFrame("Frame")
            pcall(passEvents.RegisterEvent, passEvents, "PLAYER_REGEN_ENABLED")
            passEvents:SetScript("OnEvent", function()
                if InCombatLockdown and InCombatLockdown() then return end
                local list = passWaiting
                passWaiting = {}
                for _, waiting in ipairs(list) do applyRightClickPass(waiting) end
            end)
        end
        return
    end
    applyRightClickPass(frame)
end

-----------------------------------------------------------------------------
-- Gamepad UI: a World Map opened or moved by addon code taints the game's
-- gamepad navigation (Libs/EzWoWGamePad). With the gamepad on, the map is
-- left for the player to open and move.
-----------------------------------------------------------------------------
function ns.IsGamePadUI()
    return ns.GamePad and ns.GamePad.IsActive() or false
end

-----------------------------------------------------------------------------
-- Quest map marks moved to EzWoW - Quest. While that addon is loaded (or,
-- before login, is about to load) the copies here stay off.
-----------------------------------------------------------------------------
local QUEST_ADDON = "EzWoW-Quest"
local questAddonActive

function ns.IsQuestAddonActive()
    if questAddonActive ~= nil then return questAddonActive end
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    if type(isLoaded) == "function" then
        local ok, loaded = pcall(isLoaded, QUEST_ADDON)
        if ok and loaded then
            questAddonActive = true
            return true
        end
    end
    if IsLoggedIn and IsLoggedIn() then
        questAddonActive = false
        return false
    end
    local getState = C_AddOns and C_AddOns.GetAddOnEnableState
    local isLoadable = C_AddOns and C_AddOns.IsAddOnLoadable
    if type(getState) == "function" then
        local okName, character = pcall(UnitName, "player")
        local okState, state = pcall(getState, QUEST_ADDON, okName and character or nil)
        if okState and type(state) == "number" and state > 0 then
            if type(isLoadable) ~= "function" then return true end
            local okLoad, loadable = pcall(isLoadable, QUEST_ADDON)
            return (not okLoad) or (loadable and true or false)
        end
    end
    return false
end

-----------------------------------------------------------------------------
-- Public table for other EzWoW addons (EzWoW - Quest draws its map marks
-- with this). Every call looks the helper up when it runs, so load order
-- inside this addon does not matter.
-----------------------------------------------------------------------------
-- names the waypoint just set for the on-screen arrow (Libs/EzWoWWaypointArrow)
function ns.SetWaypointArrowLabel(text, source)
    local arrow = _G.EzWoW_WaypointArrow
    if type(arrow) == "table" and type(arrow.SetLabel) == "function" then
        pcall(arrow.SetLabel, text, source or "EzWoW - Map Finder")
    end
end

_G.EzWoWMapFinderAPI = {
    version = 1,
    -- (spawn, mapID) -> mapID, x, y on that map (nil when the spawn is not on it)
    ProjectSpawn = function(spawn, mapID)
        local fn = ns.ProjectSpawnToWorldMapCoords
        if type(fn) == "function" then return fn(spawn, mapID) end
        return nil
    end,
    -- labelText / source: what the on-screen arrow shows (optional)
    ApplyWaypoint = function(spawn, labelText, source)
        local fn = ns.ApplyWaypointForSpawn
        if type(fn) == "function" then fn(spawn, labelText, source) end
    end,
    -- (entry, spawn index) -> true when the moving arrow pin and waypoint were set
    PointAtSpawn = function(entry, spawnIdx)
        local fn = ns.PointAtSpawn
        if type(fn) == "function" then return fn(entry, spawnIdx) == true end
        return false
    end,
    PassMapRightClicks = function(frame)
        ns.PassMapRightClicks(frame)
    end,
    LocalizedName = function(entry)
        local fn = ns.GetLocalizedEntityName
        if type(fn) == "function" then return fn(entry) end
        return nil
    end,
    -- ("npc" | "object", ID) -> name in the chosen language (shared records'
    -- tooltips use it); the lookup table is made on the first call
    NameByID = function(kind, id)
        if not ns.entityByKindID then
            local index = {}
            local data = _G.EzWoWMapFinderData
            if type(data) == "table" then
                for _, e in ipairs(data) do
                    if type(e) == "table" and e.id and (e.kind == "npc" or e.kind == "object") then
                        local key = e.kind .. ":" .. e.id
                        index[key] = index[key] or e
                    end
                end
            end
            ns.entityByKindID = index
        end
        local e = ns.entityByKindID[tostring(kind) .. ":" .. tostring(id)]
        local fn = ns.GetLocalizedEntityName
        if e and type(fn) == "function" then
            local ok, name = pcall(fn, e)
            if ok and type(name) == "string" and name ~= "" then return name end
        end
        local names = e and e.names
        if type(names) ~= "table" then return nil end
        return names[(GetLocale and GetLocale()) or "enUS"] or names.enUS
    end,
    IsAutoWaypoint = function()
        return not (ns.DB and ns.DB.autoWaypoint == false)
    end,
    GetData = function() return _G.EzWoWMapFinderData end,
    GetTranslations = function() return _G.EzWoWMapFinderTranslations end,
    GetQuestData = function() return _G.EzWoWMapFinderQuestData end,
    -- [questID] = { races, classes, skill, skill rank } (Database/QuestRequirements.lua)
    GetQuestRequirements = function() return _G.EzWoWMapFinderQuestRequirements end,
}

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
CoreBootstrap.InitializeDatabase = ns.InitializeDatabase
CoreBootstrap.CreateStyledButton = ns.CreateStyledButton
CoreBootstrap.ToLowerSafeString = ns.ToLowerSafeString
