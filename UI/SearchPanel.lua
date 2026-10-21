--===========================================================================
-- EzWoW - Map Finder
-- UI/SearchPanel.lua : WorldMap Docked Entity Search Panel & Animated Map Pins
--===========================================================================
local _, ns = ...
-- Text for the game's AddOns panel in the six languages without their own line: { deDE, frFR, esES, ruRU, zhCN, zhTW }
local PANEL_LANG_INDEX = { deDE = 1, frFR = 2, esES = 3, esMX = 3, ruRU = 4, zhCN = 5, zhTW = 6, de = 1, fr = 2, es = 3, ru = 4 }
local function panelText(code, ko, en, others)
    if code == "koKR" or code == "ko" then return ko end
    local index = PANEL_LANG_INDEX[code or ""]
    return (index and others and others[index]) or en
end

local EntityExplorerPanel = ns.EntityExplorerPanel or {}
ns.EntityExplorerPanel = EntityExplorerPanel

local Theme = ns.Theme
local L = ns.L
local lower = ns.ToLowerSafeString
local KIND_COLORS = ns.KIND_COLORS
local LANG_ALIASES = ns.LANG_ALIASES
local BADGE_PREFIX_POOLS = ns.BADGE_PREFIX_POOLS
local HERB_SKILL_BY_OBJECT = ns.HERB_SKILL_BY_OBJECT
local MINE_SKILL_BY_OBJECT = ns.MINE_SKILL_BY_OBJECT
local localizeZoneIdentifier = ns.FormatLocalizedZoneName
local bootstrapDB = ns.InitializeDatabase
local determineLocale = ns.SynchronizeActiveLocale
local createMapFinderButton = ns.CreateStyledButton
local resolveLocalizedEntityName = ns.GetLocalizedEntityName
local resolveLocalizedSubTitle = ns.GetLocalizedEntitySubtitle
local projectWorldSpawnToMap = ns.ProjectSpawnToWorldMapCoords
local resolveEntityZoneKey = ns.GetPrimaryEntityZoneKey
local resolveEntityZoneName = ns.GetPrimaryEntityZoneDisplayName
local buildGatheringSkillBadge = ns.FormatGatherSkillTag
local composePetRowTag = ns.FormatPetRowTag
local addPetTooltipLines = ns.AddPetTooltipLines
local parseSearchQueryTokens = ns.ParseQueryMatchers
local matchEntityZoneAgainstToken = ns.MatchEntityZoneFast
local matchEntityAgainstAllTokens = ns.MatchEntityAllTokens
local isFriendlyServiceNpc = ns.IsFriendlyNpcEntity
local acquireCategoryEntityPool = ns.GetSearchPool
local installMapFogRevealHooks = ns.SetupMapReveal
local initializeMapCoordOverlay = ns.SetupMapCoords
local installZoneLevelHeaderHook = ns.SetupZoneLevels
local installMapWheelZoomHooks = ns.SetupMapZoom
local commitMapFade = ns.ApplyMapFade
local renderWorldTransitMarkers = ns.RefreshTransitPins
local buildMapFinderSettingsFrame = ns.CreateSettingsPanel

local mapPins = {}
local activePinCount = 0
ns.selectedEntity = nil
ns.selectedSpawnIdx = 1
local pinAnimFrame = CreateFrame("Frame")
local animTime = 0
local renderActiveEntityMapPins
local refreshRows

function EntityExplorerPanel.setMapWaypointForSpawn(sp)
    if not ns.DB or ns.DB.autoWaypoint == false or not sp then return end
    local mapID2, mxVal, myVal = projectWorldSpawnToMap(sp, nil)
    if mapID2 and mxVal and myVal and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        pcall(function()
            if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID2) then return end
            local anchorPoint = UiMapPoint.CreateFromCoordinates(mapID2, mxVal, myVal)
            if anchorPoint then
                C_Map.SetUserWaypoint(anchorPoint)
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                end
            end
        end)
    end
end

function EntityExplorerPanel.removeActiveUserWaypoint()
    if C_Map and C_Map.ClearUserWaypoint then
        pcall(C_Map.ClearUserWaypoint)
    end
end

function EntityExplorerPanel.hideAllWorldMapPins()
    activePinCount = 0
    for _, pinFrame in ipairs(mapPins) do
        pinFrame:Hide()
    end
    pinAnimFrame:SetScript("OnUpdate", nil)
end

function EntityExplorerPanel.tickBouncingPinAnimation(_, elapsed)
    if activePinCount == 0 or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    animTime = animTime + (elapsed or 0.016)
    for index = 1, activePinCount do
        local pinFrame = mapPins[index]
        if pinFrame and pinFrame:IsShown() then
            if pinFrame.isPrimary then
                
                local bob = 4 + math.abs(math.sin(animTime * 5.2)) * 10
                pinFrame.arrow:ClearAllPoints()
                pinFrame.arrow:SetPoint("BOTTOM", pinFrame, "CENTER", 0, bob)

                local glow = 0.5 + 0.5 * math.sin(animTime * 6.5)
                local rowEntry = 0.294 + (1.0 - 0.294) * glow * 0.75
                local greenVal = 0.784 + (0.94 - 0.784) * glow * 0.75
                local buttonWidget = 0.910 - 0.35 * glow * 0.75
                pinFrame.headFill:SetColorTexture(rowEntry, greenVal, buttonWidget, 1.0)
                pinFrame.shaftFill:SetColorTexture(rowEntry, greenVal, buttonWidget, 1.0)

                local phase = (animTime * 1.15) % 1.0
                local ringSize = 10 + phase * 26
                local ringAlpha = (1.0 - phase) * 0.85
                pinFrame.pulseRing:SetSize(ringSize, ringSize)
                pinFrame.pulseRing:SetColorTexture(0.294, 0.784, 0.910, ringAlpha)
                pinFrame.pulseRing:Show()
            else
                local bob = 3 + math.abs(math.sin(animTime * 3.6 + index * 0.7)) * 4.5
                pinFrame.arrow:ClearAllPoints()
                pinFrame.arrow:SetPoint("BOTTOM", pinFrame, "CENTER", 0, bob)
                pinFrame.pulseRing:Hide()
            end
        end
    end
end

function EntityExplorerPanel.acquireBouncingPinButton(idx)
    local pinFrame = mapPins[idx]
    if pinFrame then return pinFrame end
    local canvasFrame = (WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas())
        or (_G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock:GetCanvas())
        or WorldMapFrame
    pinFrame = CreateFrame("Button", nil, canvasFrame)
    pinFrame:SetSize(32, 46)
    pinFrame:SetFrameStrata("HIGH")
    pinFrame:SetFrameLevel((canvasFrame:GetFrameLevel() or 10) + 420)

    local pulseRing = pinFrame:CreateTexture(nil, "BACKGROUND")
    pulseRing:SetPoint("CENTER", pinFrame, "CENTER", 0, 0)
    pulseRing:SetSize(16, 16)
    pulseRing:SetTexture("Interface\\Buttons\\WHITE8X8")
    if pulseRing.SetRotation then
        pulseRing:SetRotation(math.rad(45))
    end
    pulseRing:SetColorTexture(0.294, 0.784, 0.910, 0.75)
    pinFrame.pulseRing = pulseRing

    local targetBorder = pinFrame:CreateTexture(nil, "BORDER")
    targetBorder:SetPoint("CENTER", pinFrame, "CENTER", 0, 0)
    targetBorder:SetSize(9, 9)
    targetBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    if targetBorder.SetRotation then
        targetBorder:SetRotation(math.rad(45))
    end
    targetBorder:SetColorTexture(0.05, 0.07, 0.09, 0.95)
    pinFrame.targetBorder = targetBorder

    local targetDot = pinFrame:CreateTexture(nil, "ARTWORK")
    targetDot:SetPoint("CENTER", pinFrame, "CENTER", 0, 0)
    targetDot:SetSize(5, 5)
    targetDot:SetTexture("Interface\\Buttons\\WHITE8X8")
    if targetDot.SetRotation then
        targetDot:SetRotation(math.rad(45))
    end
    targetDot:SetColorTexture(1.0, 0.88, 0.30, 1.0)
    pinFrame.targetDot = targetDot

    local arrow = CreateFrame("Frame", nil, pinFrame)
    arrow:SetSize(24, 28)
    arrow:SetPoint("BOTTOM", pinFrame, "CENTER", 0, 6)
    pinFrame.arrow = arrow

    local headBorder = arrow:CreateTexture(nil, "BACKGROUND")
    headBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    headBorder:SetSize(16, 16)
    headBorder:SetPoint("CENTER", arrow, "BOTTOM", 0, 11)
    if headBorder.SetRotation then
        headBorder:SetRotation(math.rad(45))
    end
    headBorder:SetColorTexture(0.05, 0.07, 0.09, 0.96)
    pinFrame.headBorder = headBorder

    local shaftBorder = arrow:CreateTexture(nil, "BACKGROUND")
    shaftBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    shaftBorder:SetSize(10, 14)
    shaftBorder:SetPoint("BOTTOM", arrow, "BOTTOM", 0, 11)
    shaftBorder:SetColorTexture(0.05, 0.07, 0.09, 0.96)
    pinFrame.shaftBorder = shaftBorder

    local headFill = arrow:CreateTexture(nil, "ARTWORK")
    headFill:SetTexture("Interface\\Buttons\\WHITE8X8")
    headFill:SetSize(12, 12)
    headFill:SetPoint("CENTER", arrow, "BOTTOM", 0, 11.2)
    if headFill.SetRotation then
        headFill:SetRotation(math.rad(45))
    end
    headFill:SetColorTexture(0.294, 0.784, 0.910, 1.0)
    pinFrame.headFill = headFill

    local shaftFill = arrow:CreateTexture(nil, "OVERLAY")
    shaftFill:SetTexture("Interface\\Buttons\\WHITE8X8")
    shaftFill:SetSize(6, 13)
    shaftFill:SetPoint("BOTTOM", arrow, "BOTTOM", 0, 10)
    shaftFill:SetColorTexture(0.294, 0.784, 0.910, 1.0)
    pinFrame.shaftFill = shaftFill

    pinFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.title or L.title, 0.294, 0.784, 0.910)
        if self.sub then
            GameTooltip:AddLine(self.sub, 0.929, 0.957, 0.969, true)
        end
        GameTooltip:Show()
    end)
    pinFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    pinFrame:SetScript("OnClick", function(self)
        if self.spawnIndex and ns.selectedEntity then
            ns.selectedSpawnIdx = self.spawnIndex
            if ns.selectedEntity.spawns and ns.selectedEntity.spawns[ns.selectedSpawnIdx] then
                EntityExplorerPanel.setMapWaypointForSpawn(ns.selectedEntity.spawns[ns.selectedSpawnIdx])
            end
            renderActiveEntityMapPins()
        end
    end)
    mapPins[idx] = pinFrame
    return pinFrame
end

renderActiveEntityMapPins = function()
    EntityExplorerPanel.hideAllWorldMapPins()
    if not ns.selectedEntity or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local canvasFrame = (WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas())
        or (_G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock:GetCanvas())
        or WorldMapFrame
    local cwVal, chVal = canvasFrame:GetWidth(), canvasFrame:GetHeight()
    if not cwVal or not chVal or cwVal <= 0 or chVal <= 0 then return end

    local cScale = (WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()) or 1
    if not cScale or cScale <= 0 then cScale = 1 end

    local pinCount = 0
    local zName = resolveEntityZoneName(ns.selectedEntity, ns.selectedSpawnIdx)
    local eName = resolveLocalizedEntityName(ns.selectedEntity)
    local headerTitle = (zName ~= "" and (zName .. " > " .. eName)) or eName

    for index, sp in ipairs(ns.selectedEntity.spawns or {}) do
        local mapID2, mxVal, myVal = projectWorldSpawnToMap(sp, mapID)
        if mxVal and myVal and (not mapID or mapID2 == mapID) then
            pinCount = pinCount + 1
            local pinFrame = EntityExplorerPanel.acquireBouncingPinButton(pinCount)
            pinFrame:SetParent(canvasFrame)
            local hasPrimary = (index == ns.selectedSpawnIdx)
            pinFrame.isPrimary = hasPrimary
            pinFrame.spawnIndex = index
            pinFrame:SetFrameLevel((canvasFrame:GetFrameLevel() or 10) + (hasPrimary and 440 or 415))
            pinFrame.arrow:SetScale((hasPrimary and 1.0 or 0.72) / cScale)
            if hasPrimary then
                pinFrame.headFill:SetColorTexture(0.294, 0.784, 0.910, 1.0)
                pinFrame.shaftFill:SetColorTexture(0.294, 0.784, 0.910, 1.0)
                pinFrame.targetDot:SetColorTexture(1.0, 0.88, 0.30, 1.0)
            else
                pinFrame.headFill:SetColorTexture(0.95, 0.66, 0.36, 0.92)
                pinFrame.shaftFill:SetColorTexture(0.95, 0.66, 0.36, 0.92)
                pinFrame.targetDot:SetColorTexture(0.95, 0.66, 0.36, 0.92)
            end
            pinFrame.title = headerTitle
            pinFrame.sub = string.format("(%.1f, %.1f) [%d/%d]", mxVal * 100, myVal * 100, index, #ns.selectedEntity.spawns)
            pinFrame:ClearAllPoints()
            pinFrame:SetPoint("CENTER", canvasFrame, "TOPLEFT", mxVal * cwVal, -myVal * chVal)
            pinFrame:Show()
        end
    end
    activePinCount = pinCount
    if pinCount > 0 then
        pinAnimFrame:SetScript("OnUpdate", EntityExplorerPanel.tickBouncingPinAnimation)
    end
end

local switchBtn, uiPanel, edit, statusRegion, sliderWidget
local rowButtons = {}
local catButtons = {}
local filteredResults = {}
local scrollOffset = 0
local VISIBLE_ROWS = 10
local MAX_MATCHES = 300

local searchWorker = CreateFrame("Frame")
local hasSearching = false
local searchPool = nil
local searchCursor = 1
local searchTotal = 0
local activeMatchers = nil
local matchedSpawnByEntity = {}

refreshRows = function()
    if not uiPanel then return end
    local grandTotal = #filteredResults
    local extraRows = hasSearching and 1 or 0
    local displayTotal = grandTotal + extraRows
    local maxOffset = math.max(0, displayTotal - VISIBLE_ROWS)
    if scrollOffset > maxOffset then scrollOffset = maxOffset end
    if scrollOffset < 0 then scrollOffset = 0 end
    if sliderWidget then
        sliderWidget:SetMinMaxValues(0, maxOffset)
        sliderWidget:SetValue(scrollOffset)
        sliderWidget:SetShown(maxOffset > 0)
    end
    local pct = (searchTotal > 0) and math.min(99, math.floor(((searchCursor - 1) / searchTotal) * 100)) or 0
    for index = 1, VISIBLE_ROWS do
        local buttonWidget = rowButtons[index]
        local rowIdx = scrollOffset + index
        local hasSearchingIndicator = hasSearching and (
            rowIdx == grandTotal + 1
            or (index == VISIBLE_ROWS and grandTotal >= VISIBLE_ROWS and scrollOffset == 0)
        )
        if hasSearchingIndicator then
            buttonWidget.label:SetText("|cff4bc8e8" .. string.format(L.searchingRow, pct) .. "|r")
            buttonWidget.entry = nil
            buttonWidget.bg:SetColorTexture(0.114, 0.220, 0.280, 0.55)
            buttonWidget:Show()
        else
            local entry = filteredResults[rowIdx]
            if entry then
                local badge
                if entry.isPet then
                    if entry.isRare then
                        badge = KIND_COLORS.rare .. "[R]|r" .. KIND_COLORS.pet .. "[P]|r "
                    else
                        badge = KIND_COLORS.pet .. "[P]|r "
                    end
                elseif entry.isRare then
                    badge = KIND_COLORS.rare .. "[R]|r "
                elseif entry.isMonster then
                    badge = KIND_COLORS.monster .. "[M]|r "
                else
                    local columnIndex = KIND_COLORS[entry.kind] or "|cffedf4f7"
                    badge = columnIndex .. "[" .. string.upper(string.sub(entry.kind, 1, 1)) .. "]|r "
                end
                local spIdx = (ns.selectedEntity == entry) and ns.selectedSpawnIdx or (matchedSpawnByEntity[entry] or 1)
                local zName = resolveEntityZoneName(entry, spIdx)
                local zonePrefix = (zName and zName ~= "") and ("|cff7ecbe0" .. zName .. "|r |cffa7b9c5>|r ") or ""
                local eName = resolveLocalizedEntityName(entry)
                local sub = resolveLocalizedSubTitle(entry)
                local subStr = (sub and sub ~= "" and not string.find(eName, sub, 1, true)) and (" |cffa7b9c5<" .. sub .. ">|r") or ""
                if subStr == "" and entry.isPet then
                    subStr = composePetRowTag(entry) or ""
                elseif subStr == "" and entry.kind == "object" then
                    subStr = buildGatheringSkillBadge(entry) or ""
                end
                local countStr = entry.spawns and #entry.spawns > 1 and (" |cffa7b9c5(" .. #entry.spawns .. ")|r") or ""
                buttonWidget.label:SetText(badge .. zonePrefix .. eName .. subStr .. countStr)
                buttonWidget.entry = entry
                if ns.selectedEntity == entry then
                    buttonWidget.bg:SetColorTexture(0.294, 0.784, 0.910, 0.24)
                else
                    buttonWidget.bg:SetColorTexture(0.114, 0.157, 0.192, (index % 2 == 0) and 0.75 or 0.45)
                end
                buttonWidget:Show()
            else
                buttonWidget.entry = nil
                buttonWidget:Hide()
            end
        end
    end
    if hasSearching then
        statusRegion:SetText("|cff4bc8e8" .. string.format(L.searchingStatus, pct, grandTotal) .. "|r")
    elseif grandTotal == 0 then
        statusRegion:SetText(L.noResults)
    else
        local firstIdx = scrollOffset + 1
        local lastIdx = math.min(grandTotal, scrollOffset + VISIBLE_ROWS)
        statusRegion:SetText(string.format(L.resultsFmt, grandTotal, firstIdx, lastIdx))
    end
end

function EntityExplorerPanel.executeAsyncSearchBatch()
    if not hasSearching or not searchPool or searchCursor > searchTotal then
        hasSearching = false
        searchWorker:SetScript("OnUpdate", nil)
        refreshRows()
        return
    end
    local t0Val = debugprofilestop and debugprofilestop() or 0
    local budgetMs = 1.5
    local maxSteps = 550
    local steps = 0
    local foundInFrame = 0

    while searchCursor <= searchTotal do
        local recordEntry = searchPool[searchCursor]
        searchCursor = searchCursor + 1
        steps = steps + 1

        local isCallOk, spIdx = matchEntityAgainstAllTokens(recordEntry, activeMatchers)
        if isCallOk then
            filteredResults[#filteredResults + 1] = recordEntry
            if spIdx then
                matchedSpawnByEntity[recordEntry] = spIdx
            end
            foundInFrame = foundInFrame + 1
            if #filteredResults >= MAX_MATCHES then
                hasSearching = false
                searchWorker:SetScript("OnUpdate", nil)
                break
            end
            
            if #filteredResults < VISIBLE_ROWS and foundInFrame >= 1 then
                break
            end
        end

        if steps >= maxSteps then
            break
        end
        if t0Val > 0 and (steps % 16 == 0) and (debugprofilestop() - t0Val) >= budgetMs then
            break
        end
    end

    if searchCursor > searchTotal then
        hasSearching = false
        searchWorker:SetScript("OnUpdate", nil)
    end
    refreshRows()
end

function EntityExplorerPanel.restartAsyncEntitySearch()
    if not edit then return end
    acquireCategoryEntityPool(ns.activeCategory)
    local rawText = edit:GetText() or ""
    local leadTrimmed = lower(rawText:gsub("^[ \t\r\n>]+", ""))
    local prefixChar, afterPrefix = leadTrimmed:match("^([mrnoqip])[ \t]+(.*)$")
    if not prefixChar then
        prefixChar, afterPrefix = leadTrimmed:match("^%[([mrnoqip])%]%s*(.*)$")
    end

    local poolKey = prefixChar and BADGE_PREFIX_POOLS[prefixChar]
    if poolKey then
        searchPool = acquireCategoryEntityPool(poolKey)
    else
        searchPool = acquireCategoryEntityPool(ns.activeCategory)
    end

    local priorityQueue = (afterPrefix or leadTrimmed):gsub("^[ \t\r\n>]+", ""):gsub("[ \t\r\n>]+$", "")
    searchTotal = #searchPool
    filteredResults = {}
    matchedSpawnByEntity = {}
    scrollOffset = 0
    activeMatchers = parseSearchQueryTokens(priorityQueue)

    if #activeMatchers == 0 then
        hasSearching = false
        searchWorker:SetScript("OnUpdate", nil)
        for index = 1, searchTotal do
            filteredResults[index] = searchPool[index]
        end
        refreshRows()
        return
    end

    searchCursor = 1
    hasSearching = (searchTotal > 0)
    refreshRows()
    if hasSearching then
        searchWorker:SetScript("OnUpdate", EntityExplorerPanel.executeAsyncSearchBatch)
    else
        searchWorker:SetScript("OnUpdate", nil)
    end
end

function EntityExplorerPanel.handleSearchResultSelection(entry, forcedSpawnIdx)
    if not entry then return end
    if forcedSpawnIdx then
        ns.selectedEntity = entry
        ns.selectedSpawnIdx = forcedSpawnIdx
    elseif ns.selectedEntity == entry and entry.spawns and #entry.spawns > 1 then
        ns.selectedSpawnIdx = (ns.selectedSpawnIdx % #entry.spawns) + 1
    else
        ns.selectedEntity = entry
        ns.selectedSpawnIdx = matchedSpawnByEntity[entry] or 1
    end
    refreshRows()
    local spawns = entry.spawns
    local anchorTarget = spawns and spawns[ns.selectedSpawnIdx]
    if not anchorTarget then
        local _, fallbackUiMapID = resolveEntityZoneKey(entry, 1)
        if fallbackUiMapID and WorldMapFrame and WorldMapFrame.SetMapID and not (InCombatLockdown and InCombatLockdown()) then
            pcall(WorldMapFrame.SetMapID, WorldMapFrame, fallbackUiMapID)
        end
        statusRegion:SetText(L.noCoords)
        renderActiveEntityMapPins()
        return
    end
    local uiMapID, mxVal, myVal, zKey = projectWorldSpawnToMap(anchorTarget, nil)
    if uiMapID and WorldMapFrame and WorldMapFrame.SetMapID then
        if InCombatLockdown and InCombatLockdown() then
            statusRegion:SetText(L.combatNote)
        else
            pcall(WorldMapFrame.SetMapID, WorldMapFrame, uiMapID)
        end
    end
    local mapID = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID() or uiMapID
    local _, cxVal, cyVal, lookupKey = projectWorldSpawnToMap(anchorTarget, mapID)
    mxVal, myVal = cxVal or mxVal, cyVal or myVal
    local mapName = localizeZoneIdentifier(lookupKey or zKey)
    if not mapName or mapName == "" then
        local mapInfo = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        mapName = (mapInfo and mapInfo.name) or ("Map " .. tostring(mapID or anchorTarget[1]))
    end
    if mxVal and myVal then
        statusRegion:SetText(string.format(L.coordFmt, mapName, mxVal * 100, myVal * 100, ns.selectedSpawnIdx, #spawns))
    else
        statusRegion:SetText(string.format(L.worldCoordFmt, anchorTarget[1], anchorTarget[2], anchorTarget[3], ns.selectedSpawnIdx, #spawns))
    end
    EntityExplorerPanel.setMapWaypointForSpawn(anchorTarget)
    renderActiveEntityMapPins()
end

function EntityExplorerPanel.positionPanel()
    if not uiPanel or not switchBtn then return end
    local canvasFrame = _G.EzWoWWorldMapDock:GetCanvas()
    local cwVal, chVal = canvasFrame:GetWidth(), canvasFrame:GetHeight()
    uiPanel:ClearAllPoints()
    if not cwVal or not chVal or cwVal <= 0 or chVal <= 0 then
        uiPanel:SetPoint("BOTTOMLEFT", switchBtn, "BOTTOMRIGHT", 6, 0)
        return
    end
    local bLeft, bBottom = switchBtn:GetLeft(), switchBtn:GetBottom()
    local cLeft, cBottom = canvasFrame:GetLeft(), canvasFrame:GetBottom()
    local bsVal, csVal = switchBtn:GetEffectiveScale(), canvasFrame:GetEffectiveScale()
    if bLeft and bBottom and cLeft and cBottom and csVal > 0 then
        local rxVal = (bLeft * bsVal / csVal) - cLeft
        local ryVal = (bBottom * bsVal / csVal) - cBottom
        local pxVal = rxVal + 28 + 6
        if pxVal + uiPanel:GetWidth() > cwVal - 8 then
            pxVal = math.max(8, rxVal - uiPanel:GetWidth() - 6)
        end
        local pyVal = math.max(35, math.min(chVal - uiPanel:GetHeight() - 8, ryVal))
        uiPanel:SetPoint("BOTTOMLEFT", canvasFrame, "BOTTOMLEFT", pxVal, pyVal)
    else
        uiPanel:SetPoint("BOTTOMLEFT", switchBtn, "BOTTOMRIGHT", 6, 0)
    end
end

function EntityExplorerPanel.anchorFreeButton(btn, canvasFrame)
    if _G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock.NormalizeButtonParent then _G.EzWoWWorldMapDock:NormalizeButtonParent(btn, canvasFrame) end
    local cwVal, chVal = canvasFrame:GetWidth(), canvasFrame:GetHeight()
    if not cwVal or not chVal or cwVal <= 0 or chVal <= 0 then return end
    local coordPos = (ns.DB and ns.DB.buttonPos) or { x = 0.04, y = 0.12 }
    local coordX = math.max(4, math.min(cwVal - 32, (coordPos.x or 0.04) * cwVal))
    local coordY = math.max(4, math.min(chVal - 32, (coordPos.y or 0.12) * chVal))
    btn:SetSize(28, 28)
    btn:ClearAllPoints()
    btn:SetPoint("BOTTOMLEFT", canvasFrame, "BOTTOMLEFT", coordX, coordY)
    EntityExplorerPanel.positionPanel()
end

function EntityExplorerPanel.syncUITexts(skipSearch)
    if not uiPanel then return end
    uiPanel.head:SetText(L.title)
    if uiPanel.sub then uiPanel.sub:SetText(L.subtitle) end
    if uiPanel.cfgBtn and uiPanel.cfgBtn.label then
        uiPanel.cfgBtn.label:SetText(L.settings or "설정")
        -- header button follows its text (German / Russian are long) so the title keeps room
        ns.UIKit:SizeButtonToText(uiPanel.cfgBtn, uiPanel.cfgBtn.label, 40, 90, 10)
    end
    uiPanel.clearBtn:SetText(L.clearPins)
    local catLabels = {
        all     = L.catAll,
        monster = L.catMonster,
        npc     = L.catNpc,
        object  = L.catObj,
        quest   = L.catQuest,
        item    = L.catItem,
    }
    for _, checkWidget in ipairs(catButtons) do
        checkWidget.label:SetText(catLabels[checkWidget.cat] or checkWidget.cat)
        ns.UIKit:FitFontString(checkWidget.label, 46, 1)
    end
    if ns.settingsPanel and ns.settingsPanel.RefreshTexts then
        ns.settingsPanel:RefreshTexts()
    end
    if not skipSearch then
        EntityExplorerPanel.restartAsyncEntitySearch()
    else
        refreshRows()
    end
    renderActiveEntityMapPins()
end

function EntityExplorerPanel.init()
    if uiPanel then return end
    bootstrapDB()
    local canvasFrame = _G.EzWoWWorldMapDock:GetCanvas()

    switchBtn = CreateFrame("Button", "EzWoWMapFinderToggle", canvasFrame)
    switchBtn:SetSize(28, 28)
    switchBtn:SetFrameStrata("HIGH")
    switchBtn:SetFrameLevel((canvasFrame:GetFrameLevel() or 10) + 450)
    local iconTex = switchBtn:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexture("Interface\\AddOns\\EzWoW-MapFinder\\Media\\Icon")
    if not iconTex:GetTexture() then
        iconTex:SetTexture("Interface\\AddOns\\EzWoW-MapFinder\\Textures\\EzWoWMapFinderIcon")
    end
    if not iconTex:GetTexture() then
        iconTex:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    end
    iconTex:SetTexCoord(0, 1, 0, 1)
    switchBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    switchBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    switchBtn:RegisterForDrag("LeftButton")

    switchBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.title, unpack(Theme.accent))
        GameTooltip:AddLine(L.tipLeft, unpack(Theme.text))
        GameTooltip:AddLine(L.tipRight, unpack(Theme.muted))
        GameTooltip:AddLine(L.tipDrag, unpack(Theme.muted))
        GameTooltip:Show()
    end)
    switchBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    switchBtn:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self.isDragging = true
        local dock = _G.EzWoWWorldMapDock
        local curX, curY, maxW, maxH = dock:GetCursorCanvasXY(self)
        local btnCX, btnCY = dock:GetButtonCanvasCenter(self)
        local grabDX = (btnCX and curX) and (btnCX - curX) or 0
        local grabDY = (btnCY and curY) and (btnCY - curY) or 0
        if btnCX and btnCY and maxW and maxH and maxW > 0 and maxH > 0 then
            ns.DB.buttonPos = {
                x = math.max(0.005, math.min(0.96, (btnCX - 14) / maxW)),
                y = math.max(0.005, math.min(0.95, (btnCY - 14) / maxH)),
            }
        end
        ns.DB.autoAlign = false
        if ns.settingsPanel and ns.settingsPanel.autoCheck then ns.settingsPanel.autoCheck:SetChecked(false) end
        dock:Layout()
        self:SetScript("OnUpdate", function(btn)
            local cx, cy, cw, ch = dock:GetCursorCanvasXY(btn)
            if not (cx and cy and cw and ch and cw > 0 and ch > 0) then return end
            local leftX = math.max(4, math.min(cw - 32, cx + grabDX - 14))
            local bottomY = math.max(4, math.min(ch - 32, cy + grabDY - 14))
            ns.DB.buttonPos = {
                x = leftX / cw,
                y = bottomY / ch,
            }
            EntityExplorerPanel.anchorFreeButton(btn, dock:GetCanvas())
        end)
    end)
    switchBtn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self.isDragging = false
        EntityExplorerPanel.anchorFreeButton(self, _G.EzWoWWorldMapDock:GetCanvas())
    end)

    uiPanel = CreateFrame("Frame", "EzWoWMapFinderPanel", canvasFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    uiPanel:SetSize(368, 390)
    uiPanel:SetFrameStrata("DIALOG")
    uiPanel:SetFrameLevel(switchBtn:GetFrameLevel() + 10)
    uiPanel:EnableMouse(true)
    if uiPanel.SetBackdrop then
        ns.UIKit:ApplyBackdrop(uiPanel)
        uiPanel:SetBackdropColor(unpack(Theme.bg))
        uiPanel:SetBackdropBorderColor(unpack(Theme.border))
    else
        local backdropTex = uiPanel:CreateTexture(nil, "BACKGROUND")
        backdropTex:SetAllPoints(uiPanel)
        backdropTex:SetColorTexture(unpack(Theme.bg))
    end
    local headerBg = uiPanel:CreateTexture(nil, "BACKGROUND")
    headerBg:SetPoint("TOPLEFT", 1, -1)
    headerBg:SetPoint("TOPRIGHT", -1, -1)
    headerBg:SetHeight(30)
    headerBg:SetColorTexture(unpack(Theme.bgSub))
    local headerLine = uiPanel:CreateTexture(nil, "OVERLAY")
    headerLine:SetPoint("TOPLEFT", headerBg, "BOTTOMLEFT", 0, 0)
    headerLine:SetPoint("TOPRIGHT", headerBg, "BOTTOMRIGHT", 0, 0)
    headerLine:SetHeight(1)
    headerLine:SetColorTexture(unpack(Theme.accent))

    uiPanel.head = uiPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    uiPanel.head:SetPoint("LEFT", headerBg, "LEFT", 10, 0)
    uiPanel.head:SetTextColor(unpack(Theme.accent))

    uiPanel.sub = uiPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    uiPanel.sub:Hide()

    local close = CreateFrame("Button", nil, uiPanel, BackdropTemplateMixin and "BackdropTemplate" or nil)
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", headerBg, "RIGHT", -5, 0)
    if close.SetBackdrop then
        ns.UIKit:ApplyBackdrop(close)
        close:SetBackdropColor(0.071, 0.094, 0.122, 0.90)
        close:SetBackdropBorderColor(unpack(Theme.border))
    end
    local dismissTxt = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dismissTxt:SetPoint("CENTER", 0, 0)
    dismissTxt:SetText("X")
    dismissTxt:SetTextColor(unpack(Theme.muted))
    close:SetScript("OnEnter", function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(unpack(Theme.accent)) end
        dismissTxt:SetTextColor(unpack(Theme.text))
    end)
    close:SetScript("OnLeave", function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(unpack(Theme.border)) end
        dismissTxt:SetTextColor(unpack(Theme.muted))
    end)
    close:SetScript("OnClick", function() uiPanel:Hide() end)

    local gearBtn = CreateFrame("Button", nil, uiPanel, BackdropTemplateMixin and "BackdropTemplate" or nil)
    gearBtn:SetSize(40, 20)
    gearBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)
        uiPanel.head:SetPoint("RIGHT", gearBtn, "LEFT", -6, 0)
        uiPanel.head:SetJustifyH("LEFT")
        if uiPanel.head.SetWordWrap then uiPanel.head:SetWordWrap(false) end
    if gearBtn.SetBackdrop then
        ns.UIKit:ApplyBackdrop(gearBtn)
        gearBtn:SetBackdropColor(0.071, 0.094, 0.122, 0.90)
        gearBtn:SetBackdropBorderColor(unpack(Theme.border))
    end
    gearBtn.label = gearBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    gearBtn.label:SetPoint("CENTER", 0, 0)
    gearBtn.label:SetText(L.settings or "설정")
    gearBtn.label:SetTextColor(unpack(Theme.text))
    ns.UIKit:SizeButtonToText(gearBtn, gearBtn.label, 40, 90, 10)
    gearBtn:SetScript("OnEnter", function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(unpack(Theme.accent)) end
        self.label:SetTextColor(unpack(Theme.accent))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("EzWoW - Map Finder", unpack(Theme.accent))
        GameTooltip:AddLine((L.settings or "설정") .. " (/ezmf)", unpack(Theme.text))
        GameTooltip:Show()
    end)
    gearBtn:SetScript("OnLeave", function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(unpack(Theme.border)) end
        self.label:SetTextColor(unpack(Theme.text))
        GameTooltip:Hide()
    end)
    gearBtn:SetScript("OnClick", function()
        local sp = buildMapFinderSettingsFrame()
        EntityExplorerPanel.syncUITexts(true)
        sp:SetShown(not sp:IsShown())
        if sp:IsShown() then sp:Raise() end
    end)
    uiPanel.cfgBtn = gearBtn

    local cats = { "all", "monster", "npc", "object", "quest", "item" }
    local function styleCatButton(checkWidget, isActive)
        if checkWidget.SetBackdropColor then
            if isActive then
                checkWidget:SetBackdropColor(0.14, 0.24, 0.30, 0.96)
                checkWidget:SetBackdropBorderColor(unpack(Theme.accent))
            else
                checkWidget:SetBackdropColor(unpack(Theme.bgSub))
                checkWidget:SetBackdropBorderColor(unpack(Theme.border))
            end
        end
        checkWidget.label:SetTextColor(unpack(isActive and Theme.accent or Theme.muted))
    end
    for index, categoryKey in ipairs(cats) do
        local checkWidget = CreateFrame("Button", nil, uiPanel, BackdropTemplateMixin and "BackdropTemplate" or nil)
        checkWidget:SetSize(54, 20)
        checkWidget:SetPoint("TOPLEFT", uiPanel, "TOPLEFT", 12 + (index - 1) * 58, -36)
        if checkWidget.SetBackdrop then
            ns.UIKit:ApplyBackdrop(checkWidget)
        end
        checkWidget.label = checkWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        checkWidget.label:SetPoint("CENTER")
        checkWidget.cat = categoryKey
        checkWidget:SetScript("OnEnter", function(self)
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(unpack(Theme.accent)) end
            self.label:SetTextColor(unpack(self.cat == ns.activeCategory and Theme.accent or Theme.text))
        end)
        checkWidget:SetScript("OnLeave", function(self)
            styleCatButton(self, self.cat == ns.activeCategory)
        end)
        checkWidget:SetScript("OnClick", function(self)
            ns.activeCategory = self.cat
            for _, other in ipairs(catButtons) do
                styleCatButton(other, other.cat == ns.activeCategory)
            end
            EntityExplorerPanel.restartAsyncEntitySearch()
        end)
        styleCatButton(checkWidget, categoryKey == ns.activeCategory)
        catButtons[index] = checkWidget
    end

    edit = CreateFrame("EditBox", nil, uiPanel, BackdropTemplateMixin and "BackdropTemplate" or nil)
    edit:SetSize(264, 22)
    edit:SetPoint("TOPLEFT", uiPanel, "TOPLEFT", 12, -62)
    if edit.SetBackdrop then
        ns.UIKit:ApplyBackdrop(edit)
        edit:SetBackdropColor(0.047, 0.067, 0.086, 0.96)
        edit:SetBackdropBorderColor(unpack(Theme.border))
    end
    edit:SetFontObject(ChatFontNormal)
    edit:SetTextColor(unpack(Theme.text))
    edit:SetTextInsets(6, 6, 0, 0)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEditFocusGained", function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(unpack(Theme.accent)) end
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(unpack(Theme.border)) end
    end)
    edit:SetScript("OnTextChanged", function()
        if uiPanel and uiPanel:IsShown() then
            EntityExplorerPanel.restartAsyncEntitySearch()
        end
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local resetPinsBtn = createMapFinderButton(uiPanel, 74, 22, false, function()
        ns.selectedEntity = nil
        EntityExplorerPanel.hideAllWorldMapPins()
        EntityExplorerPanel.removeActiveUserWaypoint()
        renderActiveEntityMapPins()
        refreshRows()
    end)
    resetPinsBtn:SetPoint("LEFT", edit, "RIGHT", 6, 0)
    uiPanel.clearBtn = resetPinsBtn

    local listFrame = CreateFrame("Frame", nil, uiPanel)
    listFrame:SetPoint("TOPLEFT", uiPanel, "TOPLEFT", 12, -90)
    listFrame:SetPoint("BOTTOMRIGHT", uiPanel, "BOTTOMRIGHT", -12, 28)
    listFrame:EnableMouseWheel(true)
    listFrame:SetScript("OnMouseWheel", function(_, delta)
        scrollOffset = scrollOffset - delta * 3
        refreshRows()
    end)

    for index = 1, VISIBLE_ROWS do
        local buttonWidget = CreateFrame("Button", nil, listFrame)
        buttonWidget:SetSize(324, 25)
        buttonWidget:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -(index - 1) * 27)
        buttonWidget.bg = buttonWidget:CreateTexture(nil, "BACKGROUND")
        buttonWidget.bg:SetAllPoints()
        buttonWidget.bg:SetColorTexture(0.114, 0.157, 0.192, 0.6)
        buttonWidget:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        buttonWidget.label = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        buttonWidget.label:SetPoint("LEFT", 8, 0)
        buttonWidget.label:SetPoint("RIGHT", -8, 0)
        buttonWidget.label:SetJustifyH("LEFT")
        buttonWidget.label:SetWordWrap(false)
        buttonWidget.label:SetTextColor(unpack(Theme.text))

        buttonWidget:SetScript("OnEnter", function(self)
            local recordEntry = self.entry
            if not recordEntry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local eName = resolveLocalizedEntityName(recordEntry)
            local sub = resolveLocalizedSubTitle(recordEntry)
            local columnIndex = (recordEntry.isRare and KIND_COLORS.rare) or (recordEntry.isPet and KIND_COLORS.pet) or (recordEntry.isMonster and KIND_COLORS.monster) or (KIND_COLORS[recordEntry.kind] or "|cff4bc8e8")
            GameTooltip:SetText(columnIndex .. eName .. "|r", 1, 1, 1)
            if sub and sub ~= "" then
                GameTooltip:AddLine("<" .. sub .. ">", 0.655, 0.725, 0.773)
            end
            local spIdx = (ns.selectedEntity == recordEntry) and ns.selectedSpawnIdx or (matchedSpawnByEntity[recordEntry] or 1)
            local zName = resolveEntityZoneName(recordEntry, spIdx)
            local spCount = recordEntry.spawns and #recordEntry.spawns or 0
            if zName and zName ~= "" then
                if spCount > 1 then
                    GameTooltip:AddLine(string.format(L.locCountFmt, zName, spCount), 0.929, 0.957, 0.969)
                elseif spCount == 1 and recordEntry.spawns[1] then
                    local _, mxVal, myVal = projectWorldSpawnToMap(recordEntry.spawns[1], nil)
                    if mxVal and myVal then
                        GameTooltip:AddLine(string.format("%s (%.1f, %.1f)", zName, mxVal * 100, myVal * 100), 0.929, 0.957, 0.969)
                    else
                        GameTooltip:AddLine(zName, 0.929, 0.957, 0.969)
                    end
                else
                    GameTooltip:AddLine(zName, 0.929, 0.957, 0.969)
                end
            end
            if recordEntry.kind == "object" and recordEntry.id then
                local hReq = HERB_SKILL_BY_OBJECT[recordEntry.id]
                local mReq = MINE_SKILL_BY_OBJECT[recordEntry.id]
                if hReq then
                    GameTooltip:AddLine(string.format("%s: %d", L.herbSkill or "Herbalism", hReq), 0.376, 0.808, 0.639)
                elseif mReq then
                    GameTooltip:AddLine(string.format("%s: %d", L.mineSkill or "Mining", mReq), 0.945, 0.741, 0.341)
                end
            end
            addPetTooltipLines(recordEntry)
            GameTooltip:AddLine(L.rowTipClick, 0.655, 0.725, 0.773)
            GameTooltip:Show()
        end)
        buttonWidget:SetScript("OnLeave", function() GameTooltip:Hide() end)

        buttonWidget:SetScript("OnClick", function(self)
            EntityExplorerPanel.handleSearchResultSelection(self.entry)
        end)
        buttonWidget:Hide()
        rowButtons[index] = buttonWidget
    end

    sliderWidget = CreateFrame("Slider", nil, listFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    sliderWidget:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", 0, -2)
    sliderWidget:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", 0, 2)
    sliderWidget:SetWidth(12)
    sliderWidget:SetOrientation("VERTICAL")
    if sliderWidget.SetBackdrop then
        sliderWidget:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        sliderWidget:SetBackdropColor(0.071, 0.094, 0.122, 0.8)
    end
    sliderWidget:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    sliderWidget:SetValueStep(1)
    sliderWidget:SetObeyStepOnDrag(true)
    sliderWidget:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        if v ~= scrollOffset then
            scrollOffset = v
            refreshRows()
        end
    end)

    statusRegion = uiPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusRegion:SetPoint("BOTTOMLEFT", uiPanel, "BOTTOMLEFT", 12, 8)
    statusRegion:SetPoint("RIGHT", uiPanel, "RIGHT", -12, 0)
    statusRegion:SetJustifyH("LEFT")
    statusRegion:SetTextColor(unpack(Theme.muted))

    uiPanel:SetScript("OnShow", function()
        if _G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock.CloseOthers then
            _G.EzWoWWorldMapDock:CloseOthers("EzWoW_MapFinder")
        end
        EntityExplorerPanel.positionPanel()
        EntityExplorerPanel.syncUITexts()
    end)
    uiPanel:SetScript("OnHide", function()
        hasSearching = false
        searchWorker:SetScript("OnUpdate", nil)
    end)
    uiPanel:Hide()

    switchBtn:SetScript("OnClick", function(_, button)
        if switchBtn.isDragging then return end
        if button == "RightButton" then
            ns.DB.autoAlign = true
            ns.DB.buttonPos = nil
            if ns.settingsPanel and ns.settingsPanel.autoCheck then ns.settingsPanel.autoCheck:SetChecked(true) end
            _G.EzWoWWorldMapDock:Layout()
            return
        end
        if uiPanel:IsShown() then
            uiPanel:Hide()
        else
            if _G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock.CloseOthers then
                _G.EzWoWWorldMapDock:CloseOthers("EzWoW_MapFinder")
            end
            uiPanel:Show()
        end
    end)

    _G.EzWoWWorldMapDock:Register("EzWoW_MapFinder", {
        order = 1,
        button = switchBtn,
        isAuto = function() return ns.DB and ns.DB.autoAlign ~= false end,
        onDockedLayout = function() EntityExplorerPanel.positionPanel() end,
        onFreeLayout = function(btn, themeColor) EntityExplorerPanel.anchorFreeButton(btn, themeColor) end,
        closePanel = function()
            if uiPanel and uiPanel:IsShown() then
                uiPanel:Hide()
            end
        end,
    })

    if WorldMapFrame then
        if WorldMapFrame.OnMapChanged then
            hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
                renderActiveEntityMapPins()
                renderWorldTransitMarkers()
            end)
        end
        if WorldMapFrame.OnCanvasScaleChanged then
            hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", function()
                renderActiveEntityMapPins()
                renderWorldTransitMarkers()
            end)
        end
        WorldMapFrame:HookScript("OnShow", function()
            renderActiveEntityMapPins()
            renderWorldTransitMarkers()
        end)
        WorldMapFrame:HookScript("OnSizeChanged", function()
            renderActiveEntityMapPins()
            renderWorldTransitMarkers()
        end)
    end

    installMapFogRevealHooks()
    initializeMapCoordOverlay()
    installZoneLevelHeaderHook()
    installMapWheelZoomHooks()
    commitMapFade()
    renderWorldTransitMarkers()

    SLASH_EZWOWMAPFINDER1 = "/ezmf"
    SLASH_EZWOWMAPFINDER2 = "/emf"
    SLASH_EZWOWMAPFINDER3 = "/맵파인더"
    SlashCmdList.EZWOWMAPFINDER = function(msg)
        local raw = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local cmd, rest = raw:match("^(%S+)%s*(.*)$")
        cmd = lower(cmd or "")
        if cmd == "config" or cmd == "settings" or cmd == "설정" then
            local sp = buildMapFinderSettingsFrame()
            sp:SetShown(not sp:IsShown())
            if sp:IsShown() then sp:Raise() end
            return
        elseif cmd == "clear" then
            ns.selectedEntity = nil
            EntityExplorerPanel.hideAllWorldMapPins()
            EntityExplorerPanel.removeActiveUserWaypoint()
            renderActiveEntityMapPins()
            refreshRows()
            return
        elseif cmd == "lang" then
            local targetKey = LANG_ALIASES[lower(rest or "")]
            if targetKey then
                ns.DB.lang = targetKey
                determineLocale()
                EntityExplorerPanel.syncUITexts()
                print("|cff4bc8e8EzWoW - Map Finder|r: " .. L.language .. " = " .. targetKey)
            end
            return
        elseif cmd == "help" or cmd == "?" then
            print("|cff4bc8e8EzWoW - Map Finder|r: " .. L.help)
            return
        end
        if WorldMapFrame and not WorldMapFrame:IsShown() and not (InCombatLockdown and InCombatLockdown()) then
            WorldMapFrame:Show()
        end
        uiPanel:Show()
        if raw ~= "" then
            edit:SetText(raw)
        else
            EntityExplorerPanel.restartAsyncEntitySearch()
        end
    end
    

    do
        local canvasFrame = CreateFrame("Frame", "EzWoWMapFinderOptionsPanel", UIParent)
        canvasFrame.name = "EzWoW - Map Finder"
        ns.SetOptionsCanvas(canvasFrame)

        local icVal = canvasFrame:CreateTexture(nil, "ARTWORK")
        icVal:SetSize(32, 32)
        icVal:SetPoint("TOPLEFT", 18, -18)
        icVal:SetTexture("Interface\\AddOns\\EzWoW-MapFinder\\Media\\Icon")

        local resolvedValue = canvasFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        resolvedValue:SetPoint("LEFT", icVal, "RIGHT", 10, 0)
        resolvedValue:SetTextColor(unpack(Theme.accent))
        resolvedValue:SetText("EzWoW - Map Finder")

        local desc = canvasFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", icVal, "BOTTOMLEFT", 0, -14)
        desc:SetWidth(520)
        desc:SetJustifyH("LEFT")

        local buttonWidget = createMapFinderButton(canvasFrame, 220, 28, true, function()
            local sp = buildMapFinderSettingsFrame()
            sp:SetShown(not sp:IsShown())
            if sp:IsShown() then sp:Raise() end
        end)
        buttonWidget.label:SetFontObject("GameFontHighlight")
        buttonWidget.label:SetTextColor(unpack(Theme.accent))
        buttonWidget:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)

        local hint = canvasFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", buttonWidget, "BOTTOMLEFT", 0, -14)
        hint:SetTextColor(unpack(Theme.muted))

        function canvasFrame:RefreshTexts()
            local hasKo = (L.settings == "설정")
            desc:SetText(panelText(ns.activeLocale, "세계지도에서 몬스터, NPC, 오브젝트, 퀘스트, 아이템 위치를 빠르게 검색하고 화살표 마커 및 지도 추적 핀(웨이포인트)으로 안내합니다.", "Quickly searches and marks monster, NPC, object, quest, and item locations on the world map with arrow pins and map waypoints.", { "Sucht Monster, NSC, Objekte, Quests und Gegenstände auf der Weltkarte und markiert sie mit Pfeilen und Wegpunkten.", "Recherche monstres, PNJ, objets interactifs, quêtes et objets sur la carte du monde et les marque avec des flèches et des points de passage.", "Busca monstruos, PNJ, objetos interactivos, misiones y objetos en el mapa del mundo y los marca con flechas y puntos de ruta.", "Быстро находит монстров, НИП, объекты, задания и предметы на карте мира и отмечает их стрелками и путевыми точками.", "在世界地图上快速搜索怪物、NPC、物体、任务和物品，并用箭头和路径点标记。", "在世界地圖上快速搜尋怪物、NPC、物件、任務和物品，並以箭頭和路徑點標記。" }))
            buttonWidget:SetText((L.settings or "설정") .. " (/ezmf)")
            hint:SetText(panelText(ns.activeLocale, "채팅창에 /ezmf 또는 /ezmf config를 입력해도 설정창을 열 수 있습니다.", "Type /ezmf or /ezmf config in chat to open settings.", { "Du kannst die Einstellungen auch mit /ezmf oder /ezmf config im Chat öffnen.", "Vous pouvez aussi ouvrir les options en tapant /ezmf ou /ezmf config dans le chat.", "También puedes abrir las opciones escribiendo /ezmf o /ezmf config en el chat.", "Настройки также открываются командой /ezmf или /ezmf config в чате.", "也可以在聊天框输入 /ezmf 或 /ezmf config 打开设置。", "也可以在聊天框輸入 /ezmf 或 /ezmf config 開啟設定。" }))
        end
        canvasFrame:SetScript("OnShow", function(self) self:RefreshTexts() end)
        canvasFrame:RefreshTexts()

        if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
            local isCallOk, categoryKey = pcall(Settings.RegisterCanvasLayoutCategory, canvasFrame, "EzWoW - Map Finder")
            if isCallOk and categoryKey then pcall(Settings.RegisterAddOnCategory, categoryKey) end
        elseif InterfaceOptions_AddCategory then
            pcall(InterfaceOptions_AddCategory, canvasFrame)
        end
    end
end

local parentFrame = CreateFrame("Frame")
parentFrame:RegisterEvent("PLAYER_LOGIN")
parentFrame:SetScript("OnEvent", EntityExplorerPanel.init)

ns.ApplyWaypointForSpawn = EntityExplorerPanel.setMapWaypointForSpawn
ns.ClearUserWaypointPin = EntityExplorerPanel.removeActiveUserWaypoint
ns.ClearMapPins = EntityExplorerPanel.hideAllWorldMapPins
ns.RefreshMapPins = renderActiveEntityMapPins
ns.PositionPanel = EntityExplorerPanel.positionPanel
ns.RefreshUITexts = EntityExplorerPanel.syncUITexts
ns.RunSearch = EntityExplorerPanel.restartAsyncEntitySearch
ns.SelectEntityOnMap = EntityExplorerPanel.handleSearchResultSelection
