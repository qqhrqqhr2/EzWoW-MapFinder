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
    if CONST_DB.enableMapZoom == nil then CONST_DB.enableMapZoom = true end
    if CONST_DB.showTransit == nil then CONST_DB.showTransit = true end
    if CONST_DB.rareAlert == nil then CONST_DB.rareAlert = true end
    if CONST_DB.rareAlertSound == nil then CONST_DB.rareAlertSound = true end
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
    function buttonWidget:SetText(txt) self.label:SetText(txt or "") end
    function buttonWidget:GetText() return self.label:GetText() end
    buttonWidget:SetScript("OnMouseDown", function() formatLocalizedLabel:SetPoint("CENTER", 1, -1) end)
    buttonWidget:SetScript("OnMouseUp", function() formatLocalizedLabel:SetPoint("CENTER", 0, 0) end)
    if onClick then buttonWidget:SetScript("OnClick", onClick) end
    return buttonWidget
end

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
CoreBootstrap.InitializeDatabase = ns.InitializeDatabase
CoreBootstrap.CreateStyledButton = ns.CreateStyledButton
CoreBootstrap.ToLowerSafeString = ns.ToLowerSafeString
