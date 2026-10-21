--===========================================================================
-- EzWoW - Map Finder
-- Modules/MapEnhancements.lua : Fog-of-War Reveal, Cursor Coords, Zoom Extender & Transit Pins
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local WorldMapCanvasEnhancer = ns.WorldMapCanvasEnhancer or {}
ns.WorldMapCanvasEnhancer = WorldMapCanvasEnhancer

local Theme = ns.Theme
local L = ns.L
local ZONE_LEVEL_DATA = ns.ZONE_LEVEL_DATA
local TRANSIT_DATA = ns.TRANSIT_DATA
local FACTION_COLORS = ns.FACTION_COLORS

-- Each map frame (World Map, Battlefield Map) gets a data provider and a texture layer of our own
-- under its canvas. Nothing of the game's exploration pin is hooked, so the reveal does not depend on
-- how a client builds that pin.
local revealStates = {}

function WorldMapCanvasEnhancer.resolvePartialTileFileSize(pixels)
    local size = 16
    while size < pixels do size = size * 2 end
    return size
end

function WorldMapCanvasEnhancer.revealUnexploredMapTiles(state)
    if not state then return end
    for index = 1, state.used do state.textures[index]:Hide() end
    state.used = 0
    if not (ns.DB and ns.DB.revealMap ~= false) or not EzWoWMapFinderRevealData then return end
    local mapFrame = state.mapFrame
    if not mapFrame:IsShown() then return end
    local uiMapID = mapFrame.GetMapID and mapFrame:GetMapID()
    local artID = uiMapID and C_Map and C_Map.GetMapArtID and C_Map.GetMapArtID(uiMapID)
    local artData = artID and EzWoWMapFinderRevealData[artID]
    if not artData then return end

    local tileW, tileH = 256, 256
    local artLayers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(uiMapID)
    if artLayers and artLayers[1] and artLayers[1].tileWidth and artLayers[1].tileHeight then
        tileW, tileH = artLayers[1].tileWidth, artLayers[1].tileHeight
    end

    local mapInfo = C_Map.GetMapInfo and C_Map.GetMapInfo(uiMapID)
    local useTint = (ns.DB.revealTint ~= false) and mapInfo and mapInfo.mapType == 3

    local exploredKeys, exploredFiles = {}, {}
    local exList = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures and C_MapExplorationInfo.GetExploredMapTextures(uiMapID)
    for _, apiInfo in ipairs(exList or {}) do
        if apiInfo.textureWidth and apiInfo.textureHeight and apiInfo.offsetX and apiInfo.offsetY then
            exploredKeys[string.format("%d:%d:%d:%d", apiInfo.textureWidth, apiInfo.textureHeight, apiInfo.offsetX, apiInfo.offsetY)] = true
        end
        if apiInfo.fileDataIDs and apiInfo.fileDataIDs[1] then
            exploredFiles[apiInfo.fileDataIDs[1]] = true
        end
    end

    for lookupKey, filesStr in pairs(artData) do
        local files = { strsplit(",", filesStr) }
        local firstFile = tonumber(files[1])
        if not exploredKeys[lookupKey] and not (firstFile and exploredFiles[firstFile]) then
            local boxWidth, boxHeight, oxVal, oyVal = lookupKey:match("^(%d+):(%d+):(%d+):(%d+)$")
            boxWidth, boxHeight, oxVal, oyVal = tonumber(boxWidth), tonumber(boxHeight), tonumber(oxVal), tonumber(oyVal)
            if boxWidth and boxHeight and oxVal and oyVal then
                local numX = math.ceil(boxWidth / tileW)
                local numY = math.ceil(boxHeight / tileH)
                for rowIndex = 1, numY do
                    local pixH = (rowIndex < numY) and tileH or (boxHeight - tileH * (numY - 1))
                    local texH = (rowIndex < numY) and tileH or WorldMapCanvasEnhancer.resolvePartialTileFileSize(pixH)
                    for colIndex = 1, numX do
                        local pixW = (colIndex < numX) and tileW or (boxWidth - tileW * (numX - 1))
                        local texW = (colIndex < numX) and tileW or WorldMapCanvasEnhancer.resolvePartialTileFileSize(pixW)
                        local fileDataID = tonumber(files[(rowIndex - 1) * numX + colIndex])
                        if fileDataID and fileDataID > 0 then
                            state.used = state.used + 1
                            local textureRegion = state.textures[state.used]
                            if not textureRegion then
                                textureRegion = state.layer:CreateTexture(nil, "ARTWORK")
                                state.textures[state.used] = textureRegion
                            end
                            textureRegion:SetSize(pixW, pixH)
                            textureRegion:SetTexCoord(0, pixW / texW, 0, pixH / texH)
                            textureRegion:ClearAllPoints()
                            textureRegion:SetPoint("TOPLEFT", state.layer, "TOPLEFT", oxVal + tileW * (colIndex - 1), -(oyVal + tileH * (rowIndex - 1)))
                            textureRegion:SetTexture(fileDataID, nil, nil, "TRILINEAR")
                            if useTint then
                                textureRegion:SetVertexColor(0.62, 0.76, 0.92, 1.0)
                            else
                                textureRegion:SetVertexColor(1, 1, 1, 1)
                            end
                            textureRegion:Show()
                        end
                    end
                end
            end
        end
    end
end

function WorldMapCanvasEnhancer.bindMapExplorationPins(mapFrame)
    if not (mapFrame and mapFrame.AddDataProvider and mapFrame.ScrollContainer and mapFrame.ScrollContainer.Child) then return end
    if revealStates[mapFrame] then return revealStates[mapFrame] end
    if not (MapCanvasDataProviderMixin and CreateFromMixins) then return end

    local state = { mapFrame = mapFrame, textures = {}, used = 0 }
    local layerFrame = CreateFrame("Frame", nil, mapFrame.ScrollContainer.Child)
    layerFrame:SetAllPoints()
    local levelsManager = mapFrame.GetPinFrameLevelsManager and mapFrame:GetPinFrameLevelsManager()
    local isLevelOk, frameLevel = pcall(function() return levelsManager:GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_EXPLORATION") end)
    layerFrame:SetFrameLevel(isLevelOk and frameLevel or ((mapFrame.ScrollContainer.Child:GetFrameLevel() or 0) + 1))
    layerFrame:SetScript("OnEvent", function() WorldMapCanvasEnhancer.revealUnexploredMapTiles(state) end)
    state.layer = layerFrame

    local provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.OnMapChanged = function() WorldMapCanvasEnhancer.revealUnexploredMapTiles(state) end
    provider.RefreshAllData = provider.OnMapChanged
    provider.RemoveAllData = function()
        for index = 1, state.used do state.textures[index]:Hide() end
        state.used = 0
    end
    provider.OnShow = function() layerFrame:RegisterEvent("MAP_EXPLORATION_UPDATED") end
    provider.OnHide = function() layerFrame:UnregisterEvent("MAP_EXPLORATION_UPDATED") end
    provider.OnGlobalAlphaChanged = function(self)
        local map = self:GetMap()
        if map and map.GetGlobalAlpha then layerFrame:SetAlpha(map:GetGlobalAlpha()) end
    end
    mapFrame:AddDataProvider(provider)
    provider:OnGlobalAlphaChanged()
    if mapFrame:IsShown() then provider:OnShow() end
    state.provider = provider
    revealStates[mapFrame] = state
    WorldMapCanvasEnhancer.revealUnexploredMapTiles(state)
    return state
end

function WorldMapCanvasEnhancer.syncMapExplorations()
    WorldMapCanvasEnhancer.bindMapExplorationPins(WorldMapFrame)
    WorldMapCanvasEnhancer.bindMapExplorationPins(BattlefieldMapFrame)
    for _, state in pairs(revealStates) do
        WorldMapCanvasEnhancer.revealUnexploredMapTiles(state)
    end
end

function WorldMapCanvasEnhancer.installMapFogRevealHooks()
    WorldMapCanvasEnhancer.bindMapExplorationPins(WorldMapFrame)
    WorldMapCanvasEnhancer.bindMapExplorationPins(BattlefieldMapFrame)
    local mapWatcher = CreateFrame("Frame")
    mapWatcher:RegisterEvent("ADDON_LOADED")
    mapWatcher:SetScript("OnEvent", function(_, _, addonName)
        if addonName == "Blizzard_WorldMap" then
            WorldMapCanvasEnhancer.bindMapExplorationPins(WorldMapFrame)
        elseif addonName == "Blizzard_BattlefieldMap" then
            WorldMapCanvasEnhancer.bindMapExplorationPins(BattlefieldMapFrame)
        end
    end)
end

local mapCoordsFrame
function WorldMapCanvasEnhancer.refreshMapCoordsVisibility()
    if not mapCoordsFrame then return end
    if ns.DB and ns.DB.showCoords ~= false then
        mapCoordsFrame:Show()
    else
        mapCoordsFrame:Hide()
    end
end

function WorldMapCanvasEnhancer.initializeMapCoordOverlay()
    if mapCoordsFrame or not WorldMapFrame then return end
    local parentFrame = WorldMapFrame.BorderFrame or WorldMapFrame
    local windowFrame = CreateFrame("Frame", "EzWoWMapFinderCoordsFrame", parentFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    windowFrame:SetSize(250, 20)
    local scrollFrame = WorldMapFrame.ScrollContainer or WorldMapFrame
    windowFrame:SetPoint("BOTTOM", scrollFrame, "BOTTOM", 0, 8)
    windowFrame:SetFrameStrata("HIGH")
    windowFrame:SetFrameLevel((parentFrame:GetFrameLevel() or 10) + 50)
    if windowFrame.SetBackdrop then
        ns.UIKit:ApplyBackdrop(windowFrame)
        windowFrame:SetBackdropColor(0.071, 0.094, 0.122, 0.82)
        windowFrame:SetBackdropBorderColor(0.204, 0.298, 0.357, 0.90)
    end
    local displayText = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    displayText:SetPoint("CENTER", 0, 0)
    windowFrame.txt = displayText

    local elapsedAcc = 0
    windowFrame:SetScript("OnUpdate", function(self, elapsed)
        elapsedAcc = elapsedAcc + (elapsed or 0)
        if elapsedAcc < 0.05 then return end
        elapsedAcc = 0
        if not WorldMapFrame:IsShown() then return end

        local uiMapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
        local pStr = "--, --"
        if uiMapID and C_Map and C_Map.GetPlayerMapPosition then
            local coordPos = C_Map.GetPlayerMapPosition(uiMapID, "player")
            if coordPos then
                local pxVal, pyVal = coordPos:GetXY()
                if pxVal and pyVal and (pxVal > 0 or pyVal > 0) then
                    pStr = string.format("%.1f, %.1f", pxVal * 100, pyVal * 100)
                end
            end
        end

        local cStr = "--, --"
        local scVal = WorldMapFrame.ScrollContainer
        if scVal and scVal.IsMouseOver and scVal:IsMouseOver() then
            local cxVal, cyVal
            if scVal.GetNormalizedCursorPosition then
                cxVal, cyVal = scVal:GetNormalizedCursorPosition()
            end
            if cxVal and cyVal and cxVal >= 0 and cxVal <= 1 and cyVal >= 0 and cyVal <= 1 then
                cStr = string.format("%.1f, %.1f", cxVal * 100, cyVal * 100)
            end
        end

        self.txt:SetText(string.format("|cff4bc8e8%s:|r |cffedf4f7%s|r   |cff4bc8e8%s:|r |cffedf4f7%s|r",
            L.playerCoord or "Player", pStr, L.cursorCoord or "Cursor", cStr))
    end)

    mapCoordsFrame = windowFrame
    WorldMapCanvasEnhancer.refreshMapCoordsVisibility()
end

local function StripZoneLabelDecorations(rawText)
    if type(rawText) ~= "string" or rawText == "" then return "" end
    local s = rawText
    -- Strip our own colored suffixes
    s = s:gsub("%s*|cff%x%x%x%x%x%x%(%d+[^)]*%)|r.*$", "")
    s = s:gsub("%s*|cff%x%x%x%x%x%x%[[^%]]*%]|r.*$", "")
    -- Strip any native/second-line level suffix like "\n(20-30)" or " (20-30)"
    s = s:gsub("%s*[\r\n]+%s*|?c?f?f?%x*%s*%(%d+%s*%-?%s*%d*%).*$", "")
    s = s:gsub("%s*%(%d+%s*%-?%s*%d*%)$", "")
    return s
end

local function ApplyZoneLevelToMapLabel(labelFrame)
    if not labelFrame or labelFrame._ezmfUpdating then return end
    local nameFS = labelFrame.Name
    if not nameFS then return end
    local descFS = labelFrame.Description
    local rawName = nameFS:GetText()
    if not rawName or rawName == "" then return end

    if not (ns.DB and ns.DB.showZoneLevels ~= false) then
        local stripped = StripZoneLabelDecorations(rawName)
        if stripped ~= rawName and stripped ~= "" then
            labelFrame._ezmfUpdating = true
            nameFS:SetText(stripped)
            labelFrame._ezmfUpdating = false
        end
        return
    end

    -- Clear duplicate plain level range on Description if present so it never flickers on a 2nd line
    if descFS and descFS.GetText then
        local dTxt = descFS:GetText()
        if dTxt and dTxt ~= "" then
            local cleanDesc = dTxt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            if cleanDesc:match("^%s*%(?%d+%s*%-?%s*%d*%)?%s*$") then
                descFS:SetText("")
            end
        end
    end

    if rawName == labelFrame._ezmfLastName then return end

    local baseName = StripZoneLabelDecorations(rawName)
    if baseName == "" then return end

    local uiMapID = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if not uiMapID then return end
    local targetMapID = uiMapID
    local scVal = WorldMapFrame.ScrollContainer
    if scVal and scVal.GetNormalizedCursorPosition and C_Map and C_Map.GetMapInfoAtPosition then
        local cxVal, cyVal = scVal:GetNormalizedCursorPosition()
        if cxVal and cyVal and cxVal >= 0 and cxVal <= 1 and cyVal >= 0 and cyVal <= 1 then
            local qx = math.floor(cxVal * 500 + 0.5)
            local qy = math.floor(cyVal * 500 + 0.5)
            if labelFrame._ezmfLastMapID == uiMapID and labelFrame._ezmfLastQX == qx and labelFrame._ezmfLastQY == qy and labelFrame._ezmfCachedTargetMapID then
                targetMapID = labelFrame._ezmfCachedTargetMapID
            else
                local childInfo = C_Map.GetMapInfoAtPosition(uiMapID, cxVal, cyVal)
                if childInfo and childInfo.mapID then
                    targetMapID = childInfo.mapID
                end
                labelFrame._ezmfLastMapID = uiMapID
                labelFrame._ezmfLastQX = qx
                labelFrame._ezmfLastQY = qy
                labelFrame._ezmfCachedTargetMapID = targetMapID
            end
        end
    end

    local zInfo = ZONE_LEVEL_DATA[targetMapID]
    if not zInfo then
        labelFrame._ezmfLastName = rawName
        return
    end

    local minL, maxL, fishReq = zInfo[1], zInfo[2], zInfo[3]
    local pLvl = UnitLevel("player") or 1
    local fishLabel = L.fishingSkill or "Fishing"
    local cacheKey = string.format("%s:%d:%d:%s", baseName, targetMapID, pLvl, fishLabel)
    local finalHeader = (labelFrame._ezmfCacheKey == cacheKey) and labelFrame._ezmfCacheHeader or nil

    if not finalHeader then
        local columnIndex = "|cffffffff"
        if pLvl < minL - 3 then
            columnIndex = "|cffff5050"
        elseif pLvl < minL then
            columnIndex = "|cffff9933"
        elseif pLvl <= maxL + 2 then
            columnIndex = "|cff55e673"
        else
            columnIndex = "|cff99aabb"
        end
        local lvlText = (minL == maxL) and string.format("%s(%d)|r", columnIndex, minL) or string.format("%s(%d-%d)|r", columnIndex, minL, maxL)
        local fishText = (fishReq and fishReq > 0) and string.format(" |cff7ecbe0[%s %d]|r", fishLabel, fishReq) or ""
        finalHeader = baseName .. " " .. lvlText .. fishText
        labelFrame._ezmfCacheKey = cacheKey
        labelFrame._ezmfCacheHeader = finalHeader
    end

    labelFrame._ezmfLastName = finalHeader
    if rawName ~= finalHeader then
        labelFrame._ezmfUpdating = true
        nameFS:SetText(finalHeader)
        labelFrame._ezmfUpdating = false
    end
end

function WorldMapCanvasEnhancer.installZoneLevelHeaderHook()
    if not (WorldMapFrame and WorldMapFrame.dataProviders) then return end
    for WorldMapDataProvider in pairs(WorldMapFrame.dataProviders) do
        if WorldMapDataProvider and WorldMapDataProvider.Label and WorldMapDataProvider.Label.Name and not WorldMapDataProvider.Label._ezmfZoneLevelHooked then
            local labelFrame = WorldMapDataProvider.Label
            labelFrame._ezmfZoneLevelHooked = true
            labelFrame:HookScript("OnUpdate", function(self)
                ApplyZoneLevelToMapLabel(self)
            end)
            if type(WorldMapDataProvider.EvaluateLabels) == "function" then
                hooksecurefunc(WorldMapDataProvider, "EvaluateLabels", function()
                    ApplyZoneLevelToMapLabel(labelFrame)
                end)
            end
            if labelFrame.Name and type(labelFrame.Name.SetText) == "function" then
                hooksecurefunc(labelFrame.Name, "SetText", function()
                    ApplyZoneLevelToMapLabel(labelFrame)
                end)
            end
            if labelFrame.Description and type(labelFrame.Description.SetText) == "function" then
                hooksecurefunc(labelFrame.Description, "SetText", function()
                    ApplyZoneLevelToMapLabel(labelFrame)
                end)
            end
        end
    end
end

function WorldMapCanvasEnhancer.commitMapFade()
    if SetCVar then
        pcall(SetCVar, "mapFade", (ns.DB and ns.DB.noMapFade ~= false) and "0" or "1")
    end
end

function WorldMapCanvasEnhancer.expandCanvasZoomRange(scVal)
    if not (ns.DB and ns.DB.enableMapZoom ~= false) then return end
    if not (scVal and scVal.zoomLevels and #scVal.zoomLevels > 0) then return end
    local base = scVal.zoomLevels[1]
    local top = scVal.zoomLevels[#scVal.zoomLevels]
    if not (base and top and base.scale and top.width and top.height) then return end
    local mults = { 1.35, 1.75, 2.20, 2.70, 3.20 }
    for index = 1, #mults do
        local nextScale = base.scale * mults[index]
        if nextScale > (scVal.zoomLevels[#scVal.zoomLevels].scale + 0.05) then
            scVal.zoomLevels[#scVal.zoomLevels + 1] = {
                scale = nextScale,
                width = top.width,
                height = top.height,
            }
        end
    end
end

function WorldMapCanvasEnhancer.commitMapZoom(resetZoom)
    if not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return end
    local scVal = WorldMapFrame.ScrollContainer
    if scVal.CreateZoomLevels then
        pcall(scVal.CreateZoomLevels, scVal)
    end
    if resetZoom and scVal.ResetZoom then
        pcall(scVal.ResetZoom, scVal)
    end
end

function WorldMapCanvasEnhancer.installMapWheelZoomHooks()
    if not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return end
    local scVal = WorldMapFrame.ScrollContainer
    if not scVal._ezmfZoomHooked and scVal.CreateZoomLevels then
        scVal._ezmfZoomHooked = true
        hooksecurefunc(scVal, "CreateZoomLevels", WorldMapCanvasEnhancer.expandCanvasZoomRange)
        WorldMapCanvasEnhancer.expandCanvasZoomRange(scVal)
    end
end

local transitPins = {}
local activeTransitCount = 0

function WorldMapCanvasEnhancer.obtainTransitPin(entryIndex)
    local pin = transitPins[entryIndex]
    if pin then return pin end
    local canvasFrame = (WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas())
        or (_G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock:GetCanvas())
        or WorldMapFrame
    pin = CreateFrame("Button", nil, canvasFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    pin:SetSize(20, 20)
    pin:SetFrameStrata("HIGH")
    pin:SetFrameLevel((canvasFrame:GetFrameLevel() or 10) + 180)
    if pin.SetBackdrop then
        ns.UIKit:ApplyBackdrop(pin)
        pin:SetBackdropColor(0.071, 0.094, 0.122, 0.92)
    end
    local iconTex = pin:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT", 2, -2)
    iconTex:SetPoint("BOTTOMRIGHT", -2, 2)
    pin.icon = iconTex

    local tag = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tag:SetPoint("CENTER", 0, 0)
    pin.tag = tag

    pin:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    pin:SetScript("OnEnter", function(self)
        local apiInfo = self.info
        if not apiInfo then return end
        local hasKo = (ns.activeLocale == "koKR")
        local titleStr = hasKo and apiInfo.ko or apiInfo.en
        local fcVal = FACTION_COLORS[apiInfo.fac] or FACTION_COLORS.N
        local facText = (apiInfo.fac == "A" and (hasKo and "얼라이언스" or "Alliance"))
            or (apiInfo.fac == "H" and (hasKo and "호드" or "Horde"))
            or (hasKo and "중립" or "Neutral")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if apiInfo.members then
            -- continent / world map: every line at this stop, click opens the zone
            local zoneInfo = C_Map.GetMapInfo and C_Map.GetMapInfo(apiInfo.zone)
            GameTooltip:SetText(zoneInfo and zoneInfo.name or titleStr, unpack(Theme.accent))
            for _, member in ipairs(apiInfo.members) do
                local mc = FACTION_COLORS[member.fac] or FACTION_COLORS.N
                GameTooltip:AddLine(hasKo and member.ko or member.en, mc[1], mc[2], mc[3], true)
            end
            GameTooltip:AddLine(L.transitClickZone or (hasKo and "클릭: 이 지역 지도 열기" or "Click: Open this zone's map"), unpack(Theme.muted))
            GameTooltip:Show()
            return
        end
        GameTooltip:SetText(titleStr, unpack(Theme.accent))
        GameTooltip:AddLine(string.format("[%s] (%.1f, %.1f)", facText, apiInfo.x, apiInfo.y), fcVal[1], fcVal[2], fcVal[3])
        if apiInfo.dest then
            GameTooltip:AddLine(L.transitClick or "Click: Open destination map", unpack(Theme.muted))
        end
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:SetScript("OnClick", function(self)
        local apiInfo = self.info
        local target = apiInfo and (apiInfo.members and apiInfo.zone or apiInfo.dest)
        if target and WorldMapFrame and WorldMapFrame.SetMapID then
            if not (InCombatLockdown and InCombatLockdown()) then
                pcall(WorldMapFrame.SetMapID, WorldMapFrame, target)
            end
        end
    end)
    transitPins[entryIndex] = pin
    return pin
end

-- Transit data is stored per zone map. On a continent or the world map the
-- zone positions are projected with C_Map.GetMapRectOnMap; stops that land on
-- the same spot (a zeppelin tower with two lines) share one pin.
local TRANSIT_MERGE_DISTANCE = 1.2   -- percent of the map

function WorldMapCanvasEnhancer.collectTransitForMap(uiMapID)
    local direct = TRANSIT_DATA[uiMapID]
    local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(uiMapID)
    local mapType = mapInfo and mapInfo.mapType
    local isOverview = Enum and Enum.UIMapType and (mapType == Enum.UIMapType.Continent or mapType == Enum.UIMapType.World
        or mapType == Enum.UIMapType.Cosmic)
    if not isOverview or not (C_Map and C_Map.GetMapRectOnMap) then
        return direct
    end
    local groups = {}
    for zoneID, stops in pairs(TRANSIT_DATA) do
        local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, zoneID, uiMapID)
        if ok and minX and maxX and minY and maxY and maxX > minX and maxY > minY then
            for _, stop in ipairs(stops) do
                local x = (minX + (stop.x / 100) * (maxX - minX)) * 100
                local y = (minY + (stop.y / 100) * (maxY - minY)) * 100
                local group
                for _, existing in ipairs(groups) do
                    if math.abs(existing.x - x) < TRANSIT_MERGE_DISTANCE and math.abs(existing.y - y) < TRANSIT_MERGE_DISTANCE then
                        group = existing
                        break
                    end
                end
                if group then
                    local duplicate = false
                    for _, member in ipairs(group.members) do
                        if member.en == stop.en then duplicate = true break end
                    end
                    if not duplicate then group.members[#group.members + 1] = stop end
                else
                    groups[#groups + 1] = { kind = stop.kind, fac = stop.fac, x = x, y = y, ko = stop.ko, en = stop.en,
                        zone = zoneID, members = { stop } }
                end
            end
        end
    end
    return groups
end

function WorldMapCanvasEnhancer.renderWorldTransitMarkers()
    for index = 1, #transitPins do
        transitPins[index]:Hide()
    end
    activeTransitCount = 0
    if not (ns.DB and ns.DB.showTransit ~= false) then return end
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    local uiMapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local itemList = uiMapID and WorldMapCanvasEnhancer.collectTransitForMap(uiMapID)
    if not itemList or #itemList == 0 then return end

    local canvasFrame = (WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas())
        or (_G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock:GetCanvas())
        or WorldMapFrame
    local cwVal, chVal = canvasFrame:GetWidth(), canvasFrame:GetHeight()
    if not cwVal or not chVal or cwVal <= 0 or chVal <= 0 then return end
    local cScale = (WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()) or 1
    if not cScale or cScale <= 0 then cScale = 1 end
    local pinScale = 1 / cScale

    local hasKo = (ns.activeLocale == "koKR")
    for index = 1, #itemList do
        local apiInfo = itemList[index]
        local pin = WorldMapCanvasEnhancer.obtainTransitPin(index)
        pin:SetParent(canvasFrame)
        pin.info = apiInfo
        local fcVal = FACTION_COLORS[apiInfo.fac] or FACTION_COLORS.N
        if pin.SetBackdropBorderColor then
            if apiInfo.kind == "portal" then
                pin:SetBackdropBorderColor(0.788, 0.643, 0.937, 1.0)
            else
                pin:SetBackdropBorderColor(fcVal[1], fcVal[2], fcVal[3], 1.0)
            end
        end
        pin.icon:SetTexture(nil)
        pin.tag:SetText("")
        local usedAtlas = false
        if apiInfo.kind == "portal" and pin.icon.SetAtlas and C_Texture and C_Texture.GetAtlasInfo then
            local atlasName = (apiInfo.fac == "H") and "MagePortalHorde" or "MagePortalAlliance"
            if C_Texture.GetAtlasInfo(atlasName) then
                pin.icon:SetAtlas(atlasName)
                usedAtlas = true
            end
        elseif (apiInfo.kind == "boat" or apiInfo.kind == "zepp" or apiInfo.kind == "tram") and pin.icon.SetAtlas and C_Texture and C_Texture.GetAtlasInfo then
            local atlasName = (apiInfo.fac == "A" and "TaxiNode_Continent_Alliance")
                or (apiInfo.fac == "H" and "TaxiNode_Continent_Horde")
                or "TaxiNode_Continent_Neutral"
            if C_Texture.GetAtlasInfo(atlasName) then
                pin.icon:SetAtlas(atlasName)
                usedAtlas = true
            end
        end
        if not usedAtlas then
            local lbl = (apiInfo.kind == "portal" and (hasKo and "문" or "P"))
                or (apiInfo.kind == "tram" and (hasKo and "철" or "T"))
                or (apiInfo.kind == "zepp" and (hasKo and "비" or "Z"))
                or (hasKo and "배" or "B")
            pin.tag:SetText(lbl)
            pin.tag:SetTextColor(fcVal[1], fcVal[2], fcVal[3])
        end
        pin:SetScale(pinScale)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvasFrame, "TOPLEFT", ((apiInfo.x / 100) * cwVal) / pinScale, -((apiInfo.y / 100) * chVal) / pinScale)
        pin:Show()
        activeTransitCount = index
    end
end

ns.RevealPinOverlays = WorldMapCanvasEnhancer.revealUnexploredMapTiles
ns.HookMapExplorationPins = WorldMapCanvasEnhancer.bindMapExplorationPins
ns.RefreshMapExplorations = WorldMapCanvasEnhancer.syncMapExplorations
ns.SetupMapReveal = WorldMapCanvasEnhancer.installMapFogRevealHooks
ns.UpdateMapCoordsVisibility = WorldMapCanvasEnhancer.refreshMapCoordsVisibility
ns.SetupMapCoords = WorldMapCanvasEnhancer.initializeMapCoordOverlay
ns.SetupZoneLevels = WorldMapCanvasEnhancer.installZoneLevelHeaderHook
ns.ApplyMapFade = WorldMapCanvasEnhancer.commitMapFade
ns.ExtendMapZoomLevels = WorldMapCanvasEnhancer.expandCanvasZoomRange
ns.ApplyMapZoom = WorldMapCanvasEnhancer.commitMapZoom
ns.SetupMapZoom = WorldMapCanvasEnhancer.installMapWheelZoomHooks
ns.AcquireTransitPin = WorldMapCanvasEnhancer.obtainTransitPin
ns.RefreshTransitPins = WorldMapCanvasEnhancer.renderWorldTransitMarkers
