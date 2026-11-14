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
local commitMapBackdrop = ns.ApplyMapBackdrop
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

-- Settings window position, kept like the rare alert card's (falls back to the screen centre).
function SettingsDialog.saveSettingsPosition(windowFrame)
    if not ns.DB then return end
    local isCallOk, point, _, relPoint, x, y = pcall(windowFrame.GetPoint, windowFrame, 1)
    if isCallOk and type(point) == "string" and type(x) == "number" and type(y) == "number" then
        ns.DB.settingsPos = { point = point, relPoint = relPoint or point, x = x, y = y }
    end
end

function SettingsDialog.restoreSettingsPosition(windowFrame)
    windowFrame:ClearAllPoints()
    local pos = ns.DB and ns.DB.settingsPos
    if type(pos) == "table" and type(pos.point) == "string" and type(pos.x) == "number" and type(pos.y) == "number" then
        local isPlaced = pcall(windowFrame.SetPoint, windowFrame, pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
        if isPlaced then return end
        windowFrame:ClearAllPoints()
        ns.DB.settingsPos = nil
    end
    windowFrame:SetPoint("CENTER")
end

function SettingsDialog.buildMapFinderSettingsFrame()
    if ns.settingsPanel then return ns.settingsPanel end
    local windowFrame = CreateFrame("Frame", "EzWoWMapFinderSettings", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    windowFrame:SetSize(440, 762)
    SettingsDialog.restoreSettingsPosition(windowFrame)
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
    top:SetScript("OnDragStop", function()
        windowFrame:StopMovingOrSizing()
        SettingsDialog.saveSettingsPosition(windowFrame)
    end)

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

    -- language: click the box, then pick a language from the list
    local langBtn = createMapFinderButton(windowFrame, 220, 24, false, nil)
    langBtn:SetPoint("TOPLEFT", 20, -110)
    windowFrame.langBtn = langBtn
    local langItems = {}
    for index, optionEntry in ipairs(LANG_OPTIONS) do
        langItems[index] = { value = optionEntry.code,
            text = optionEntry.code == "auto" and function() return L.langAuto end or optionEntry.label }
    end
    ns.LanguageDropdown.Attach(langBtn, {
        items = langItems,
        colors = { bg = Theme.bg, border = Theme.border, accent = Theme.accent, text = Theme.text },
        get = function() return ns.DB.lang or "auto" end,
        set = function(code)
            ns.DB.lang = code
            determineLocale()
            if ns.RefreshUITexts then ns.RefreshUITexts() end
        end,
    })
    -- the single box takes 50px less than the old three rows of language buttons
    local LANG_ROWS_SAVED = 50

    local function showOptionTip(owner, dbKey, title)
        local hasKo = (ns.activeLocale == "koKR")
        local otherTips = ns.OPTION_TIPS_OTHER and ns.OPTION_TIPS_OTHER[ns.activeLocale]
        local tipWidget = (hasKo and OPTION_TIPS_KO[dbKey]) or (otherTips and otherTips[dbKey]) or OPTION_TIPS_EN[dbKey]
        if tipWidget and GameTooltip then
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(title or "", unpack(Theme.accent))
            GameTooltip:AddLine(tipWidget, 0.92, 0.95, 0.97, true)
            GameTooltip:Show()
        end
    end

    local function createCheckOptionRow(yOffset, dbKey, onToggle)
        local checkWidget = CreateFrame("CheckButton", nil, windowFrame, "UICheckButtonTemplate")
        checkWidget:SetSize(22, 22)
        checkWidget:SetPoint("TOPLEFT", 18, yOffset + LANG_ROWS_SAVED)
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
            showOptionTip(self, dbKey, self.label:GetText())
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

    windowFrame.zoneLevelCheck = createCheckOptionRow(-322, "showZoneLevels", function()
        if ns.RefreshZoneLevelLabel then ns.RefreshZoneLevelLabel() end
    end)

    windowFrame.noFadeCheck = createCheckOptionRow(-348, "noMapFade", function()
        commitMapFade()
    end)

    -- map backdrop darkness: 0-100% in steps of 5; "Default" leaves the game's look alone
    do
        local rowY = -374 + LANG_ROWS_SAVED
        local backdropLabel = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        backdropLabel:SetPoint("TOPLEFT", 22, rowY - 4)
        backdropLabel:SetWidth(300)
        backdropLabel:SetJustifyH("LEFT")
        if backdropLabel.SetWordWrap then backdropLabel:SetWordWrap(false) end
        backdropLabel:SetTextColor(unpack(Theme.text))
        windowFrame.backdropLabel = backdropLabel

        local backdropValue = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        backdropValue:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -20, rowY - 4)
        backdropValue:SetJustifyH("RIGHT")
        backdropValue:SetTextColor(unpack(Theme.accent))
        windowFrame.backdropValue = backdropValue

        local slider = CreateFrame("Slider", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        slider:SetOrientation("HORIZONTAL")
        slider:SetSize(310, 14)
        slider:SetPoint("TOPLEFT", 24, rowY - 24)
        if slider.SetBackdrop then
            slider:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
            slider:SetBackdropColor(0.071, 0.094, 0.122, 0.9)
        end
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        slider:SetMinMaxValues(0, 100)
        slider:SetValueStep(5)
        slider:SetObeyStepOnDrag(true)
        slider:EnableMouseWheel(false)
        windowFrame.backdropSlider = slider

        local function refreshBackdropControls()
            local stored = ns.DB and ns.DB.mapBackdropAlpha
            local percent
            if type(stored) == "number" then
                percent = math.floor(stored * 100 + 0.5)
                backdropValue:SetText(percent .. "%")
            else
                -- show where the game's own darkness sits, without saving it
                local tex = ns.GetMapBackdropTexture and ns.GetMapBackdropTexture()
                local current = tex and type(tex.GetAlpha) == "function" and tex:GetAlpha() or nil
                if type(current) ~= "number" or (issecretvalue and issecretvalue(current)) then current = 1 end
                percent = math.floor(current * 20 + 0.5) * 5
                backdropValue:SetText(L.mapBackdropDefault or "Default")
            end
            slider.refreshing = true
            slider:SetValue(percent)
            slider.refreshing = false
        end
        windowFrame.RefreshBackdropControls = refreshBackdropControls

        slider:SetScript("OnValueChanged", function(self, value)
            if self.refreshing or not ns.DB then return end
            local percent = math.floor((value or 0) / 5 + 0.5) * 5
            if percent < 0 then percent = 0 elseif percent > 100 then percent = 100 end
            ns.DB.mapBackdropAlpha = percent / 100
            backdropValue:SetText(percent .. "%")
            if commitMapBackdrop then commitMapBackdrop() end
        end)
        slider:SetScript("OnEnter", function(self)
            showOptionTip(self, "mapBackdrop", backdropLabel:GetText())
        end)
        slider:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        local defaultBtn = createStyledActionBtn(70, 20, false, function()
            if not ns.DB then return end
            ns.DB.mapBackdropAlpha = nil
            if commitMapBackdrop then commitMapBackdrop() end
            refreshBackdropControls()
        end)
        defaultBtn:SetPoint("LEFT", slider, "RIGHT", 16, 0)
        windowFrame.backdropDefaultBtn = defaultBtn
    end

    windowFrame.transitCheck = createCheckOptionRow(-422, "showTransit", function()
        renderWorldTransitMarkers()
    end)

    windowFrame.rareAlertCheck = createCheckOptionRow(-448, "rareAlert", nil)

    windowFrame.rareSoundCheck = createCheckOptionRow(-474, "rareAlertSound", nil)

    windowFrame.questPinsCheck = createCheckOptionRow(-500, "questLogPins", function()
        if ns.RefreshQuestLogPins then ns.RefreshQuestLogPins() end
    end)

    windowFrame.questPinsAllCheck = createCheckOptionRow(-526, "questLogPinsAll", function()
        if ns.RefreshQuestLogPins then ns.RefreshQuestLogPins() end
    end)

    windowFrame.questObjCheck = createCheckOptionRow(-552, "questObjectivePins", function()
        if ns.RefreshQuestObjectivePins then ns.RefreshQuestObjectivePins() end
    end)

    -- service NPC icons on town maps; the rows move up when the quest rows are hidden
    local SERVICE_ROW_Y = -578
    windowFrame.serviceCheck = createCheckOptionRow(-578, "serviceNpcPins", function()
        if ns.RefreshServiceNpcPins then ns.RefreshServiceNpcPins() end
    end)
    windowFrame.serviceZonesCheck = createCheckOptionRow(-604, "serviceNpcPinsZones", function()
        if ns.RefreshServiceNpcPins then ns.RefreshServiceNpcPins() end
    end)

    -- gathering helpers (herb / ore spots, interact icons, auto tracking)
    windowFrame.gatherCheck = createCheckOptionRow(-630, "gatherPins", function()
        if ns.RefreshServiceNpcPins then ns.RefreshServiceNpcPins() end
        if ns.GatherPins and ns.GatherPins.updateMinimap then pcall(ns.GatherPins.updateMinimap) end
    end)
    windowFrame.gatherIconsCheck = createCheckOptionRow(-656, "gatherInteractIcons", function()
        if ns.GatherPins and ns.GatherPins.applyInteractIcons then pcall(ns.GatherPins.applyInteractIcons) end
    end)
    windowFrame.gatherTrackCheck = createCheckOptionRow(-682, "gatherAutoTrack", function(enabled)
        if enabled and ns.GatherPins and ns.GatherPins.autoTrack then pcall(ns.GatherPins.autoTrack) end
    end)

    -- per-type toggles: a small checklist under the "Types" button
    local typesBtn = createStyledActionBtn(96, 20, false, nil)
    windowFrame.serviceTypesBtn = typesBtn
    local typesPopup
    local function placeServiceRows(shift)
        local y = SERVICE_ROW_Y + LANG_ROWS_SAVED + shift
        windowFrame.serviceCheck:ClearAllPoints()
        windowFrame.serviceCheck:SetPoint("TOPLEFT", 18, y)
        windowFrame.serviceZonesCheck:ClearAllPoints()
        windowFrame.serviceZonesCheck:SetPoint("TOPLEFT", 18, y - 26)
        windowFrame.gatherCheck:ClearAllPoints()
        windowFrame.gatherCheck:SetPoint("TOPLEFT", 18, y - 52)
        windowFrame.gatherIconsCheck:ClearAllPoints()
        windowFrame.gatherIconsCheck:SetPoint("TOPLEFT", 18, y - 78)
        windowFrame.gatherTrackCheck:ClearAllPoints()
        windowFrame.gatherTrackCheck:SetPoint("TOPLEFT", 18, y - 104)
        typesBtn:ClearAllPoints()
        typesBtn:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -20, y - 1)
    end
    windowFrame.PlaceServiceRows = placeServiceRows
    placeServiceRows(0)

    local function buildTypesPopup()
        local popup = CreateFrame("Frame", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        local types = ns.SERVICE_NPC_TYPES or {}
        local rowsPerCol = math.ceil(#types / 2)
        popup:SetSize(372, rowsPerCol * 22 + 46)
        popup:SetFrameLevel(windowFrame:GetFrameLevel() + 30)
        popup:EnableMouse(true)
        if popup.SetBackdrop then
            ns.UIKit:ApplyBackdrop(popup)
            popup:SetBackdropColor(unpack(Theme.bg))
            popup:SetBackdropBorderColor(unpack(Theme.accent))
        end
        popup.rows = {}
        for index, t in ipairs(types) do
            local col = (index - 1) >= rowsPerCol and 1 or 0
            local row = (index - 1) % rowsPerCol
            local check = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
            check:SetSize(20, 20)
            check:SetPoint("TOPLEFT", 8 + col * 182, -8 - row * 22)
            local icon = check:CreateTexture(nil, "ARTWORK")
            icon:SetSize(14, 14)
            icon:SetPoint("LEFT", check, "RIGHT", 2, 0)
            icon:SetTexture(t.tex)
            if t.round then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
            check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            check.label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
            check.label:SetJustifyH("LEFT")
            if check.label.SetWordWrap then check.label:SetWordWrap(false) end
            check.label:SetTextColor(unpack(Theme.text))
            check.typeKey = t.key
            check:SetScript("OnClick", function(self)
                if type(ns.DB.serviceNpcTypes) ~= "table" then ns.DB.serviceNpcTypes = {} end
                ns.DB.serviceNpcTypes[self.typeKey] = (not self:GetChecked()) and false or nil
                if ns.RefreshServiceNpcPins then ns.RefreshServiceNpcPins() end
            end)
            popup.rows[#popup.rows + 1] = check
        end
        local function setAll(on)
            ns.DB.serviceNpcTypes = {}
            if not on then
                for _, t in ipairs(types) do ns.DB.serviceNpcTypes[t.key] = false end
            end
            popup:RefreshTexts()
            if ns.RefreshServiceNpcPins then ns.RefreshServiceNpcPins() end
        end
        local allBtn = createMapFinderButton(popup, 80, 20, false, function() setAll(true) end)
        allBtn:SetPoint("BOTTOMLEFT", 10, 10)
        allBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        local noneBtn = createMapFinderButton(popup, 80, 20, false, function() setAll(false) end)
        noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 8, 0)
        noneBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        local closeBtn = createMapFinderButton(popup, 22, 20, false, function() popup:Hide() end)
        closeBtn:SetPoint("BOTTOMRIGHT", -10, 10)
        closeBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        closeBtn:SetText("X")
        function popup:RefreshTexts()
            local disabled = type(ns.DB.serviceNpcTypes) == "table" and ns.DB.serviceNpcTypes or {}
            for _, check in ipairs(self.rows) do
                check.label:SetText(L["serviceType_" .. check.typeKey] or check.typeKey)
                ns.UIKit:FitFontString(check.label, 140, 1)
                check:SetChecked(disabled[check.typeKey] ~= false)
            end
            allBtn:SetText(L.serviceNpcAll)
            noneBtn:SetText(L.serviceNpcNone)
        end
        popup:Hide()
        return popup
    end

    typesBtn:SetScript("OnClick", function()
        if not typesPopup then typesPopup = buildTypesPopup() end
        if typesPopup:IsShown() then
            typesPopup:Hide()
            return
        end
        typesPopup:ClearAllPoints()
        typesPopup:SetPoint("BOTTOMRIGHT", typesBtn, "TOPRIGHT", 0, 4)
        typesPopup:RefreshTexts()
        typesPopup:Show()
    end)
    windowFrame:HookScript("OnHide", function()
        if typesPopup then typesPopup:Hide() end
    end)
    windowFrame.RefreshServiceTypesPopup = function()
        if typesPopup and typesPopup:IsShown() then typesPopup:RefreshTexts() end
    end

    -- shown instead of the three quest rows while EzWoW - Quest is loaded
    local questManagedNote = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    questManagedNote:SetPoint("TOPLEFT", 22, -500 + LANG_ROWS_SAVED - 4)
    questManagedNote:SetWidth(396)
    questManagedNote:SetJustifyH("LEFT")
    if questManagedNote.SetWordWrap then questManagedNote:SetWordWrap(false) end
    questManagedNote:SetTextColor(unpack(Theme.muted))
    questManagedNote:Hide()
    windowFrame.questManagedNote = questManagedNote

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
        ns.UIKit:FitFontString(self.autoCheck.label, 380, 1)
        self.autoCheck:SetChecked(ns.DB.autoAlign ~= false)
        self.waypointCheck.label:SetText(L.autoWaypoint)
        ns.UIKit:FitFontString(self.waypointCheck.label, 380, 1)
        self.waypointCheck:SetChecked(ns.DB.autoWaypoint ~= false)
        self.revealCheck.label:SetText(L.revealMap)
        ns.UIKit:FitFontString(self.revealCheck.label, 380, 1)
        self.revealCheck:SetChecked(ns.DB.revealMap ~= false)
        self.tintCheck.label:SetText(L.revealTint)
        ns.UIKit:FitFontString(self.tintCheck.label, 380, 1)
        self.tintCheck:SetChecked(ns.DB.revealTint ~= false)
        self.coordsCheck.label:SetText(L.showCoords)
        ns.UIKit:FitFontString(self.coordsCheck.label, 380, 1)
        self.coordsCheck:SetChecked(ns.DB.showCoords ~= false)
        self.zoneLevelCheck.label:SetText(L.showZoneLevels)
        ns.UIKit:FitFontString(self.zoneLevelCheck.label, 380, 1)
        self.zoneLevelCheck:SetChecked(ns.DB.showZoneLevels ~= false)
        self.noFadeCheck.label:SetText(L.noMapFade)
        ns.UIKit:FitFontString(self.noFadeCheck.label, 380, 1)
        self.noFadeCheck:SetChecked(ns.DB.noMapFade ~= false)
        self.backdropLabel:SetText(L.mapBackdrop)
        ns.UIKit:FitFontString(self.backdropLabel, 300, 1)
        self.backdropDefaultBtn:SetText(L.mapBackdropDefault)
        self:RefreshBackdropControls()
        self.transitCheck.label:SetText(L.showTransit)
        ns.UIKit:FitFontString(self.transitCheck.label, 380, 1)
        self.transitCheck:SetChecked(ns.DB.showTransit ~= false)
        self.rareAlertCheck.label:SetText(L.rareAlert)
        ns.UIKit:FitFontString(self.rareAlertCheck.label, 380, 1)
        self.rareAlertCheck:SetChecked(ns.DB.rareAlert ~= false)
        self.rareSoundCheck.label:SetText(L.rareAlertSound)
        ns.UIKit:FitFontString(self.rareSoundCheck.label, 380, 1)
        self.rareSoundCheck:SetChecked(ns.DB.rareAlertSound ~= false)
        self.questPinsCheck.label:SetText(L.questLogPins)
        ns.UIKit:FitFontString(self.questPinsCheck.label, 380, 1)
        self.questPinsCheck:SetChecked(ns.DB.questLogPins ~= false)
        self.questPinsAllCheck.label:SetText(L.questLogPinsAll)
        ns.UIKit:FitFontString(self.questPinsAllCheck.label, 380, 1)
        self.questPinsAllCheck:SetChecked(ns.DB.questLogPinsAll == true)
        self.questObjCheck.label:SetText(L.questObjectivePins)
        ns.UIKit:FitFontString(self.questObjCheck.label, 380, 1)
        self.questObjCheck:SetChecked(ns.DB.questObjectivePins ~= false)
        local questElsewhere = ns.IsQuestAddonActive and ns.IsQuestAddonActive() or false
        self.questPinsCheck:SetShown(not questElsewhere)
        self.questPinsAllCheck:SetShown(not questElsewhere)
        self.questObjCheck:SetShown(not questElsewhere)
        self.questManagedNote:SetText(L.questManagedByQuest or "")
        ns.UIKit:FitFontString(self.questManagedNote, 396, 1)
        self.questManagedNote:SetShown(questElsewhere)
        self.serviceCheck.label:SetText(L.serviceNpcPins)
        ns.UIKit:FitFontString(self.serviceCheck.label, 290, 1)
        self.serviceCheck:SetChecked(ns.DB.serviceNpcPins ~= false)
        self.serviceZonesCheck.label:SetText(L.serviceNpcPinsZones)
        ns.UIKit:FitFontString(self.serviceZonesCheck.label, 380, 1)
        self.serviceZonesCheck:SetChecked(ns.DB.serviceNpcPinsZones == true)
        self.gatherCheck.label:SetText(L.gatherPins)
        ns.UIKit:FitFontString(self.gatherCheck.label, 380, 1)
        self.gatherCheck:SetChecked(ns.DB.gatherPins ~= false)
        self.gatherIconsCheck.label:SetText(L.gatherInteractIcons)
        ns.UIKit:FitFontString(self.gatherIconsCheck.label, 380, 1)
        self.gatherIconsCheck:SetChecked(ns.DB.gatherInteractIcons ~= false)
        self.gatherTrackCheck.label:SetText(L.gatherAutoTrack)
        ns.UIKit:FitFontString(self.gatherTrackCheck.label, 380, 1)
        self.gatherTrackCheck:SetChecked(ns.DB.gatherAutoTrack ~= false)
        self.serviceTypesBtn:SetText((L.serviceNpcTypes or "Types") .. " ▼")
        self.PlaceServiceRows(questElsewhere and 52 or 0)
        self.RefreshServiceTypesPopup()
        self:SetHeight(questElsewhere and 684 or 736)
        self.resetBtn:SetText(L.resetPos)
        self.donateBtn:SetText(L.donate)
        local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
        local isMetaOk, addonVersion = false, nil
        if type(getMeta) == "function" then
            isMetaOk, addonVersion = pcall(getMeta, ns.ADDON_NAME or "EzWoW-MapFinder", "Version")
        end
        local versionStr = (isMetaOk and type(addonVersion) == "string" and addonVersion ~= "") and (" v" .. addonVersion) or ""
        self.hintText:SetText("EzWoW - Map Finder" .. versionStr .. "  ·  " .. (L.help or "/ezmf"))
        local langName = L.langAuto
        for _, optionEntry in ipairs(LANG_OPTIONS) do
            if optionEntry.code ~= "auto" and optionEntry.code == (ns.DB.lang or "auto") then langName = optionEntry.label end
        end
        self.langBtn:SetText(langName .. " ▼")
        ns.LanguageDropdown.Refresh(self.langBtn)
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
