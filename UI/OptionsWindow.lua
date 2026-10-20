--===========================================================================
-- EzWoW - Map Finder
-- UI/OptionsWindow.lua : EzWoW Style Map Finder Settings Window & Donate Dialog
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local SettingsDialog = ns.SettingsDialog or {}
ns.SettingsDialog = SettingsDialog

local Theme = ns.Theme
local L = ns.L
local DONATE_URL = ns.DONATE_URL
local LANG_OPTIONS = ns.LANG_OPTIONS
local OPTION_TIPS_KO = ns.OPTION_TIPS_KO
local OPTION_TIPS_EN = ns.OPTION_TIPS_EN
local createMapFinderButton = ns.CreateStyledButton
local determineLocale = ns.SynchronizeActiveLocale
local syncMapExplorations = ns.RefreshMapExplorations
local refreshMapCoordsVisibility = ns.UpdateMapCoordsVisibility
local commitMapFade = ns.ApplyMapFade
local commitMapZoom = ns.ApplyMapZoom
local renderWorldTransitMarkers = ns.RefreshTransitPins

local donateFrame
function SettingsDialog.openDonateDialog()
    if not donateFrame then
        local windowFrame = CreateFrame("Frame", "EzWoWMapFinderDonate", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        windowFrame:SetSize(380, 132)
        windowFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        ns.UIKit:ElevateModal(windowFrame, 260)
        windowFrame:EnableMouse(true)
        windowFrame:SetMovable(true)
        windowFrame:RegisterForDrag("LeftButton")
        windowFrame:SetScript("OnDragStart", windowFrame.StartMoving)
        windowFrame:SetScript("OnDragStop", windowFrame.StopMovingOrSizing)
        if windowFrame.SetBackdrop then
            ns.UIKit:ApplyBackdrop(windowFrame)
            windowFrame:SetBackdropColor(unpack(Theme.bg))
            windowFrame:SetBackdropBorderColor(unpack(Theme.accent))
        end
        if UISpecialFrames then tinsert(UISpecialFrames, "EzWoWMapFinderDonate") end
        local titleStr = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleStr:SetPoint("TOP", windowFrame, "TOP", 0, -12)
        titleStr:SetTextColor(unpack(Theme.accent))
        windowFrame.title = titleStr
        local desc = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOP", titleStr, "BOTTOM", 0, -6)
        desc:SetWidth(346)
        desc:SetTextColor(unpack(Theme.muted))
        windowFrame.desc = desc
        local inputBox = CreateFrame("EditBox", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        inputBox:SetSize(344, 24)
        inputBox:SetFrameLevel(windowFrame:GetFrameLevel() + 5)
        inputBox:SetPoint("BOTTOM", windowFrame, "BOTTOM", 0, 14)
        if inputBox.SetBackdrop then
            ns.UIKit:ApplyBackdrop(inputBox)
            inputBox:SetBackdropColor(0.047, 0.067, 0.086, 0.96)
            inputBox:SetBackdropBorderColor(unpack(Theme.border))
        end
        inputBox:SetFontObject(ChatFontNormal)
        inputBox:SetTextColor(unpack(Theme.text))
        inputBox:SetTextInsets(8, 8, 0, 0)
        inputBox:SetAutoFocus(false)
        inputBox:SetText(DONATE_URL)
        inputBox:SetScript("OnTextChanged", function(self, userInput)
            if userInput then self:SetText(DONATE_URL); self:HighlightText() end
        end)
        inputBox:SetScript("OnEditFocusGained", function(self)
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(unpack(Theme.accent)) end
            self:HighlightText()
        end)
        inputBox:SetScript("OnEditFocusLost", function(self)
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(unpack(Theme.border)) end
        end)
        inputBox:SetScript("OnEscapePressed", function() windowFrame:Hide() end)
        inputBox:SetScript("OnEnterPressed", function() windowFrame:Hide() end)
        windowFrame.eb = inputBox
        local close = createMapFinderButton(windowFrame, 22, 22, false, function() windowFrame:Hide() end)
        close:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -8, -8)
        close:SetFrameLevel(windowFrame:GetFrameLevel() + 5)
        close:SetText("X")
        donateFrame = windowFrame
    end
    donateFrame.title:SetText(L.donate)
    donateFrame.desc:SetText(L.donateText)
    ns.UIKit:ElevateModal(donateFrame, 260)
    donateFrame:Show()
    if donateFrame.Raise then donateFrame:Raise() end
    donateFrame.eb:SetText(DONATE_URL)
    donateFrame.eb:SetFocus()
    donateFrame.eb:HighlightText()
end

local optionsCanvas

function SettingsDialog.buildMapFinderSettingsFrame()
    if ns.settingsPanel then return ns.settingsPanel end
    local windowFrame = CreateFrame("Frame", "EzWoWMapFinderSettings", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    windowFrame:SetSize(440, 556)
    windowFrame:SetPoint("CENTER")
    windowFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    windowFrame:SetToplevel(true)
    windowFrame:SetClampedToScreen(true)
    windowFrame:SetMovable(true)
    windowFrame:EnableMouse(true)
    if windowFrame.SetBackdrop then
        ns.UIKit:ApplyBackdrop(windowFrame, 1, 1)
        windowFrame:SetBackdropColor(unpack(Theme.bg))
        windowFrame:SetBackdropBorderColor(unpack(Theme.border))
    end
    if UISpecialFrames then tinsert(UISpecialFrames, "EzWoWMapFinderSettings") end

    local top = CreateFrame("Frame", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    top:SetPoint("TOPLEFT", windowFrame, "TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -1, -1)
    top:SetHeight(56)
    if top.SetBackdrop then
        top:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        top:SetBackdropColor(unpack(Theme.bgSub))
    end
    top:EnableMouse(true)
    top:RegisterForDrag("LeftButton")
    top:SetScript("OnDragStart", function() windowFrame:StartMoving() end)
    top:SetScript("OnDragStop", function() windowFrame:StopMovingOrSizing() end)

    local accentLine = top:CreateTexture(nil, "ARTWORK")
    accentLine:SetColorTexture(unpack(Theme.accent))
    accentLine:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", 0, 0)
    accentLine:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 0, 0)
    accentLine:SetHeight(2)

    local titleIcon = top:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(28, 28)
    titleIcon:SetPoint("TOPLEFT", 14, -14)
    titleIcon:SetTexture("Interface\\AddOns\\EzWoW-MapFinder\\Media\\Icon")
    if not titleIcon:GetTexture() then
        titleIcon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    end

    local headingRegion = top:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headingRegion:SetPoint("TOPLEFT", 48, -11)
    headingRegion:SetText("EzWoW - Map Finder")
    headingRegion:SetTextColor(unpack(Theme.accent))
    windowFrame.title = headingRegion

    local subtitleRegion = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitleRegion:SetPoint("TOPLEFT", headingRegion, "BOTTOMLEFT", 0, -3)
    subtitleRegion:SetWidth(350)
    subtitleRegion:SetJustifyH("LEFT")
    subtitleRegion:SetTextColor(unpack(Theme.muted))
    windowFrame.subtitle = subtitleRegion

    local close = createMapFinderButton(windowFrame, 24, 24, false, function() windowFrame:Hide() end)
    close:SetPoint("TOPRIGHT", -12, -14)
    close:SetFrameLevel(top:GetFrameLevel() + 3)
    close:SetText("X")

    local secTitle = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    secTitle:SetPoint("TOPLEFT", 20, -68)
    secTitle:SetTextColor(unpack(Theme.accent))
    windowFrame.secTitle = secTitle

    local secLine = windowFrame:CreateTexture(nil, "ARTWORK")
    secLine:SetColorTexture(0.204, 0.298, 0.357, 0.85)
    secLine:SetPoint("TOPLEFT", windowFrame, "TOPLEFT", 20, -85)
    secLine:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -20, -85)
    secLine:SetHeight(1)

    windowFrame.langLabel = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    windowFrame.langLabel:SetPoint("TOPLEFT", 20, -93)
    windowFrame.langLabel:SetTextColor(unpack(Theme.muted))

    local function createStyledActionBtn(w, h, isAccent, onClick)
        local buttonWidget = createMapFinderButton(windowFrame, w, h, isAccent, onClick)
        buttonWidget.label:SetFontObject("GameFontHighlightSmall")
        buttonWidget.label:SetTextColor(unpack(isAccent and Theme.accent or Theme.text))
        return buttonWidget
    end

    windowFrame.langBtns = {}
    for index, optionEntry in ipairs(LANG_OPTIONS) do
        local buttonWidget = CreateFrame("Button", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        buttonWidget:SetSize(128, 22)
        local columnIndex = (index - 1) % 3
        local rowWidget = math.floor((index - 1) / 3)
        buttonWidget:SetPoint("TOPLEFT", 20 + columnIndex * 136, -110 - rowWidget * 25)
        if buttonWidget.SetBackdrop then
            ns.UIKit:ApplyBackdrop(buttonWidget)
        end
        buttonWidget.label = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        buttonWidget.label:SetPoint("CENTER")
        buttonWidget.code = optionEntry.code
        buttonWidget.rawLabel = optionEntry.label
        buttonWidget:SetScript("OnClick", function(self)
            ns.DB.lang = self.code
            determineLocale()
            if ns.RefreshUITexts then ns.RefreshUITexts() end
        end)
        windowFrame.langBtns[index] = buttonWidget
    end

    local function createCheckOptionRow(yOffset, dbKey, onToggle)
        local checkWidget = CreateFrame("CheckButton", nil, windowFrame, "UICheckButtonTemplate")
        checkWidget:SetSize(22, 22)
        checkWidget:SetPoint("TOPLEFT", 18, yOffset)
        checkWidget.label = checkWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        checkWidget.label:SetPoint("LEFT", checkWidget, "RIGHT", 4, 0)
        checkWidget.label:SetWidth(380)
        checkWidget.label:SetJustifyH("LEFT")
        if checkWidget.label.SetWordWrap then checkWidget.label:SetWordWrap(false) end
        checkWidget.label:SetTextColor(unpack(Theme.text))
        checkWidget.dbKey = dbKey
        checkWidget:SetScript("OnClick", function(self)
            ns.DB[dbKey] = self:GetChecked() and true or false
            if onToggle then onToggle(ns.DB[dbKey]) end
        end)
        checkWidget:SetScript("OnEnter", function(self)
            local hasKo = (ns.activeLocale == "koKR")
            local tipWidget = (hasKo and OPTION_TIPS_KO[dbKey]) or OPTION_TIPS_EN[dbKey]
            if tipWidget and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.label:GetText() or "", unpack(Theme.accent))
                GameTooltip:AddLine(tipWidget, 0.92, 0.95, 0.97, true)
                GameTooltip:Show()
            end
        end)
        checkWidget:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        return checkWidget
    end

    windowFrame.autoCheck = createCheckOptionRow(-192, "autoAlign", function()
        _G.EzWoWWorldMapDock:Layout()
        if ns.PositionPanel then ns.PositionPanel() end
    end)

    windowFrame.waypointCheck = createCheckOptionRow(-218, "autoWaypoint", function(enabled)
        if not enabled then
            if ns.ClearUserWaypointPin then ns.ClearUserWaypointPin() end
        elseif ns.selectedEntity and ns.selectedEntity.spawns and ns.selectedEntity.spawns[ns.selectedSpawnIdx or 1] then
            if ns.ApplyWaypointForSpawn then ns.ApplyWaypointForSpawn(ns.selectedEntity.spawns[ns.selectedSpawnIdx or 1]) end
        end
    end)

    windowFrame.revealCheck = createCheckOptionRow(-244, "revealMap", function()
        syncMapExplorations()
    end)

    windowFrame.tintCheck = createCheckOptionRow(-270, "revealTint", function()
        syncMapExplorations()
    end)

    windowFrame.coordsCheck = createCheckOptionRow(-296, "showCoords", function()
        refreshMapCoordsVisibility()
    end)

    windowFrame.zoneLevelCheck = createCheckOptionRow(-322, "showZoneLevels", nil)

    windowFrame.noFadeCheck = createCheckOptionRow(-348, "noMapFade", function()
        commitMapFade()
    end)

    windowFrame.zoomCheck = createCheckOptionRow(-374, "enableMapZoom", function(enabled)
        commitMapZoom(not enabled)
    end)

    windowFrame.transitCheck = createCheckOptionRow(-400, "showTransit", function()
        renderWorldTransitMarkers()
    end)

    windowFrame.rareAlertCheck = createCheckOptionRow(-426, "rareAlert", nil)

    windowFrame.rareSoundCheck = createCheckOptionRow(-452, "rareAlertSound", nil)

    local resetBtn = createStyledActionBtn(194, 26, false, function()
        ns.DB.autoAlign = true
        ns.DB.buttonPos = { x = 0.04, y = 0.12 }
        if windowFrame.autoCheck then windowFrame.autoCheck:SetChecked(true) end
        _G.EzWoWWorldMapDock:Layout()
        if ns.PositionPanel then ns.PositionPanel() end
    end)
    resetBtn:SetPoint("BOTTOMLEFT", 20, 32)
    windowFrame.resetBtn = resetBtn

    local donateBtn = createStyledActionBtn(194, 26, true, SettingsDialog.openDonateDialog)
    donateBtn:SetPoint("BOTTOMRIGHT", -20, 32)
    windowFrame.donateBtn = donateBtn

    local hintText = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hintText:SetPoint("BOTTOM", 0, 10)
    hintText:SetTextColor(unpack(Theme.muted))
    windowFrame.hintText = hintText

    function windowFrame:RefreshTexts()
        self.title:SetText("EzWoW - Map Finder")
        self.subtitle:SetText(L.subtitle)
        self.secTitle:SetText(L.settings)
        self.langLabel:SetText(L.language)
        self.autoCheck.label:SetText(L.autoAlign)
        self.autoCheck:SetChecked(ns.DB.autoAlign ~= false)
        self.waypointCheck.label:SetText(L.autoWaypoint)
        self.waypointCheck:SetChecked(ns.DB.autoWaypoint ~= false)
        self.revealCheck.label:SetText(L.revealMap)
        self.revealCheck:SetChecked(ns.DB.revealMap ~= false)
        self.tintCheck.label:SetText(L.revealTint)
        self.tintCheck:SetChecked(ns.DB.revealTint ~= false)
        self.coordsCheck.label:SetText(L.showCoords)
        self.coordsCheck:SetChecked(ns.DB.showCoords ~= false)
        self.zoneLevelCheck.label:SetText(L.showZoneLevels)
        self.zoneLevelCheck:SetChecked(ns.DB.showZoneLevels ~= false)
        self.noFadeCheck.label:SetText(L.noMapFade)
        self.noFadeCheck:SetChecked(ns.DB.noMapFade ~= false)
        self.zoomCheck.label:SetText(L.enableMapZoom)
        self.zoomCheck:SetChecked(ns.DB.enableMapZoom ~= false)
        self.transitCheck.label:SetText(L.showTransit)
        self.transitCheck:SetChecked(ns.DB.showTransit ~= false)
        self.rareAlertCheck.label:SetText(L.rareAlert)
        self.rareAlertCheck:SetChecked(ns.DB.rareAlert ~= false)
        self.rareSoundCheck.label:SetText(L.rareAlertSound)
        self.rareSoundCheck:SetChecked(ns.DB.rareAlertSound ~= false)
        self.resetBtn.label:SetText(L.resetPos)
        self.donateBtn.label:SetText(L.donate)
        self.hintText:SetText("EzWoW - Map Finder v0.3.0  ·  " .. (L.help or "/ezmf"))
        for _, lbVal in ipairs(self.langBtns) do
            lbVal.label:SetText(lbVal.code == "auto" and L.langAuto or lbVal.rawLabel)
            local active = (ns.DB.lang or "auto") == lbVal.code
            if lbVal.SetBackdropColor then
                if active then
                    lbVal:SetBackdropColor(0.14, 0.24, 0.30, 0.96)
                    lbVal:SetBackdropBorderColor(unpack(Theme.accent))
                    lbVal.label:SetTextColor(unpack(Theme.accent))
                else
                    lbVal:SetBackdropColor(unpack(Theme.bgSub))
                    lbVal:SetBackdropBorderColor(unpack(Theme.border))
                    lbVal.label:SetTextColor(unpack(Theme.text))
                end
            end
        end
        if optionsCanvas and optionsCanvas.RefreshTexts then
            optionsCanvas:RefreshTexts()
        end
    end

    windowFrame:SetScript("OnShow", function(self) self:RefreshTexts() end)
    windowFrame:RefreshTexts()
    windowFrame:Hide()
    ns.settingsPanel = windowFrame
    return windowFrame
end

ns.ShowDonate = SettingsDialog.openDonateDialog
ns.CreateSettingsPanel = SettingsDialog.buildMapFinderSettingsFrame
ns.SetOptionsCanvas = function(c) optionsCanvas = c end
