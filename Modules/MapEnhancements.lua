--===========================================================================
-- EzWoW - Map Finder
-- Modules/MapEnhancements.lua : Fog-of-War Reveal, Cursor Coords, Zoom Extender & Transit Pins
--===========================================================================
local _, ns = ...

-- Click pass-through can't be changed in combat: it is set once combat ends.
local pendingPropagate = {}
local propagateFrame
local function setPropagateClicks(frame, value)
    if not frame.SetPropagateMouseClicks then return end
    if InCombatLockdown and InCombatLockdown() then
        pendingPropagate[frame] = value
        if not propagateFrame then
            propagateFrame = CreateFrame("Frame")
            propagateFrame:SetScript("OnEvent", function()
                for f, v in pairs(pendingPropagate) do
                    pendingPropagate[f] = nil
                    f:SetPropagateMouseClicks(v)
                end
            end)
            pcall(propagateFrame.RegisterEvent, propagateFrame, "PLAYER_REGEN_ENABLED")
        end
        return
    end
    pendingPropagate[frame] = nil
    frame:SetPropagateMouseClicks(value)
end
-- Text for the game's AddOns panel in the six languages without their own line: { deDE, frFR, esES, ruRU, zhCN, zhTW }
local PANEL_LANG_INDEX = { deDE = 1, frFR = 2, esES = 3, esMX = 3, ruRU = 4, zhCN = 5, zhTW = 6, de = 1, fr = 2, es = 3, ru = 4 }
local function panelText(code, ko, en, others)
    if code == "koKR" or code == "ko" then return ko end
    local index = PANEL_LANG_INDEX[code or ""]
    return (index and others and others[index]) or en
end
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

-- Our map layer runs from post-hooks on the map instead of being registered
-- as a map data provider: a provider runs inside the map's own update loop,
-- and the game's pins made after it in that loop are then blocked in combat
-- (SetPassThroughButtons). The layer keeps the provider method names.
local function attachMapLayer(map, layer)
    layer.owningMap = map
    layer.GetMap = function() return map end
    local function run(method, ...)
        local fn = layer[method]
        if type(fn) == "function" then fn(layer, ...) end
    end
    hooksecurefunc(map, "OnMapChanged", function() run("OnMapChanged") end)
    for _, method in ipairs({ "OnCanvasScaleChanged", "OnCanvasSizeChanged", "SetGlobalAlpha" }) do
        if type(map[method]) == "function" then
            local target = method == "SetGlobalAlpha" and "OnGlobalAlphaChanged" or method
            hooksecurefunc(map, method, function() run(target) end)
        end
    end
    map:HookScript("OnShow", function() run("OnShow"); run("RefreshAllData", true) end)
    map:HookScript("OnHide", function() run("OnHide") end)
end

function WorldMapCanvasEnhancer.bindMapExplorationPins(mapFrame)
    if not (mapFrame and mapFrame.OnMapChanged and mapFrame.HookScript and mapFrame.ScrollContainer and mapFrame.ScrollContainer.Child) then return end
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
    attachMapLayer(mapFrame, provider)
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
                local isSecret = issecretvalue and (issecretvalue(pxVal) or issecretvalue(pyVal))
                if pxVal and pyVal and not isSecret and (pxVal > 0 or pyVal > 0) then
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

-- Zone level under the World Map's area label. The label writes the hovered
-- area's name into its Name text; a hook on that SetText looks the name up in
-- our zone table and shows the level range (and fishing skill) in texts of our
-- own under it. Only names of zones we know get a level, so dungeons, cities
-- and points of interest never do. Nothing of the game's label is written.
local zoneLevelLabel, zoneLevelText, zoneFishText, zoneLevelByName

function WorldMapCanvasEnhancer.buildZoneLevelNames()
    zoneLevelByName = {}
    if not (C_Map and C_Map.GetMapInfo) then return end
    for mapID in pairs(ZONE_LEVEL_DATA) do
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        local name = ok and type(info) == "table" and info.name
        if type(name) == "string" and name ~= "" and not zoneLevelByName[name] then
            zoneLevelByName[name] = mapID
        end
    end
end

function WorldMapCanvasEnhancer.formatZoneLevel(minL, maxL)
    local pLvl = UnitLevel("player") or 1
    local color
    if pLvl < minL - 3 then
        color = "|cffff5050"
    elseif pLvl < minL then
        color = "|cffff9933"
    elseif pLvl <= maxL + 2 then
        color = "|cff55e673"
    else
        color = "|cff99aabb"
    end
    if minL == maxL then return string.format("%s(%d)|r", color, minL) end
    return string.format("%s(%d-%d)|r", color, minL, maxL)
end

function WorldMapCanvasEnhancer.refreshZoneLevelLabel()
    if not (zoneLevelText and zoneLevelLabel) then return end
    zoneLevelText:Hide()
    zoneFishText:Hide()
    if not (ns.DB and ns.DB.showZoneLevels ~= false) then return end
    if zoneLevelLabel.IsShown and not zoneLevelLabel:IsShown() then return end
    local nameFS = zoneLevelLabel.Name
    local name = nameFS and nameFS:GetText()
    if type(name) ~= "string" or name == "" or (issecretvalue and issecretvalue(name)) then return end
    if not zoneLevelByName then WorldMapCanvasEnhancer.buildZoneLevelNames() end
    local mapID = zoneLevelByName[name]
    local zInfo = mapID and ZONE_LEVEL_DATA[mapID]
    if not zInfo then return end

    -- below the description when the label shows one, else below the name
    local anchor = nameFS
    local descFS = zoneLevelLabel.Description
    local desc = descFS and descFS.GetText and descFS:GetText()
    if type(desc) == "string" and desc ~= "" and not (issecretvalue and issecretvalue(desc)) then anchor = descFS end
    zoneLevelText:ClearAllPoints()
    zoneLevelText:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
    zoneLevelText:SetText(WorldMapCanvasEnhancer.formatZoneLevel(zInfo[1], zInfo[2]))
    zoneLevelText:Show()

    local fishReq = zInfo[3]
    if fishReq and fishReq > 0 then
        zoneFishText:SetText(string.format("|cff7ecbe0%s %d|r", L.fishingSkill or "Fishing", fishReq))
        zoneFishText:Show()
    end
end

function WorldMapCanvasEnhancer.installZoneLevelHeaderHook()
    if zoneLevelLabel or not (WorldMapFrame and WorldMapFrame.dataProviders) then return end
    local labelFrame
    for provider in pairs(WorldMapFrame.dataProviders) do
        local label = type(provider) == "table" and provider.Label
        if label and label.Name and type(label.Name.SetText) == "function" then
            labelFrame = label
            break
        end
    end
    if not labelFrame then return end
    zoneLevelLabel = labelFrame

    local holder = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer or WorldMapFrame)
    holder:SetAllPoints()
    holder:SetFrameStrata("HIGH")
    holder:EnableMouse(false)
    zoneLevelText = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    zoneFishText = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local font, size, flags = labelFrame.Name:GetFont()
    if font and size then
        zoneLevelText:SetFont(font, math.max(10, math.floor(size * 0.65 + 0.5)), flags)
        zoneFishText:SetFont(font, math.max(9, math.floor(size * 0.45 + 0.5)), flags)
    end
    zoneLevelText:SetShadowOffset(1, -1)
    zoneLevelText:SetShadowColor(0, 0, 0, 1)
    zoneFishText:SetShadowOffset(1, -1)
    zoneFishText:SetShadowColor(0, 0, 0, 1)
    zoneFishText:SetPoint("TOP", zoneLevelText, "BOTTOM", 0, -2)
    zoneLevelText:Hide()
    zoneFishText:Hide()

    local refresh = WorldMapCanvasEnhancer.refreshZoneLevelLabel
    hooksecurefunc(labelFrame.Name, "SetText", refresh)
    if labelFrame.Description and type(labelFrame.Description.SetText) == "function" then
        hooksecurefunc(labelFrame.Description, "SetText", refresh)
    end
    if labelFrame.HookScript then
        labelFrame:HookScript("OnShow", refresh)
        labelFrame:HookScript("OnHide", refresh)
    end
    refresh()
end

-- The player's own mapFade value is saved the first time the option takes effect
-- and put back when the option is turned off; with the option off nothing is touched.
function WorldMapCanvasEnhancer.readCVar(name)
    if C_CVar and C_CVar.GetCVar then
        local ok, value = pcall(C_CVar.GetCVar, name)
        if ok then return value end
    end
    if type(GetCVar) == "function" then
        local ok, value = pcall(GetCVar, name)
        if ok then return value end
    end
end

function WorldMapCanvasEnhancer.writeCVar(name, value)
    if C_CVar and C_CVar.SetCVar then
        if pcall(C_CVar.SetCVar, name, value) then return end
    end
    if type(SetCVar) == "function" then pcall(SetCVar, name, value) end
end

function WorldMapCanvasEnhancer.commitMapFade()
    if not ns.DB then return end
    if ns.DB.noMapFade ~= false then
        if ns.DB.mapFadeOriginal == nil then
            local current = WorldMapCanvasEnhancer.readCVar("mapFade")
            if type(current) ~= "string" or current == "" then current = nil end
            -- earlier versions set 0 on every login without keeping the old value;
            -- a 0 found then is most likely ours, so the game default is kept instead
            if current == "0" and not ns.DB.mapFadeSaveV1 then
                local ok, default
                if C_CVar and C_CVar.GetCVarDefault then ok, default = pcall(C_CVar.GetCVarDefault, "mapFade") end
                current = (ok and type(default) == "string" and default ~= "") and default or "1"
            end
            ns.DB.mapFadeOriginal = current or "1"
        end
        ns.DB.mapFadeSaveV1 = true
        if WorldMapCanvasEnhancer.readCVar("mapFade") ~= "0" then
            WorldMapCanvasEnhancer.writeCVar("mapFade", "0")
        end
    elseif ns.DB.mapFadeOriginal ~= nil then
        WorldMapCanvasEnhancer.writeCVar("mapFade", tostring(ns.DB.mapFadeOriginal))
        ns.DB.mapFadeOriginal = nil
    end
end

-- Darkness of the screen behind the full-screen map (the map's own blackout texture).
-- mapBackdropAlpha nil = the game's own look is left alone; a number 0-1 is applied.
-- Only that texture's alpha changes (not a protected call); the frame still keeps
-- clicks off the world. This is separate from mapFade, which fades the whole map
-- window while moving, so the two settings do not overlap.
local backdropOriginalAlpha
local backdropTouched = false
local backdropHooked = false

function WorldMapCanvasEnhancer.getMapBackdropTexture()
    local mapFrame = _G.WorldMapFrame
    local holder = mapFrame and mapFrame.BlackoutFrame
    local tex = holder and holder.Blackout
    if tex and type(tex.SetAlpha) == "function" then return tex end
    return nil
end

function WorldMapCanvasEnhancer.commitMapBackdrop()
    local tex = WorldMapCanvasEnhancer.getMapBackdropTexture()
    if not tex then return end
    local value = ns.DB and ns.DB.mapBackdropAlpha
    if type(value) == "number" then
        if value < 0 then value = 0 elseif value > 1 then value = 1 end
        if not backdropTouched then
            local current = type(tex.GetAlpha) == "function" and tex:GetAlpha() or nil
            if type(current) ~= "number" or (issecretvalue and issecretvalue(current)) then current = 1 end
            backdropOriginalAlpha = current
            backdropTouched = true
        end
        tex:SetAlpha(value)
    elseif backdropTouched then
        tex:SetAlpha(backdropOriginalAlpha or 1)
        backdropTouched = false
    end
end

function WorldMapCanvasEnhancer.installMapBackdropHooks()
    if backdropHooked then return end
    local mapFrame = _G.WorldMapFrame
    if not mapFrame then return end
    backdropHooked = true
    local apply = WorldMapCanvasEnhancer.commitMapBackdrop
    mapFrame:HookScript("OnShow", apply)
    mapFrame:HookScript("OnSizeChanged", apply)
    for _, method in ipairs({ "Maximize", "Minimize", "SynchronizeDisplayState" }) do
        if type(mapFrame[method]) == "function" then
            hooksecurefunc(mapFrame, method, apply)
        end
    end
    local holder = mapFrame.BlackoutFrame
    if holder and holder.HookScript then holder:HookScript("OnShow", apply) end
    apply()
end

function WorldMapCanvasEnhancer.expandCanvasZoomRange(scVal)
    if not (ns.DB and ns.DB.enableMapZoom ~= false) then return end
    -- the zoom table belongs to the game's map; leave it alone during combat
    if InCombatLockdown and InCombatLockdown() then return end
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
    if InCombatLockdown and InCombatLockdown() then return end
    local scVal = WorldMapFrame.ScrollContainer
    if scVal.CreateZoomLevels then
        pcall(scVal.CreateZoomLevels, scVal)
    end
    if resetZoom and scVal.ResetZoom then
        pcall(scVal.ResetZoom, scVal)
    end
end

local zoomLevelsHooked = false
function WorldMapCanvasEnhancer.installMapWheelZoomHooks()
    if not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return end
    local scVal = WorldMapFrame.ScrollContainer
    if not zoomLevelsHooked and scVal.CreateZoomLevels then
        zoomLevelsHooked = true
        hooksecurefunc(scVal, "CreateZoomLevels", WorldMapCanvasEnhancer.expandCanvasZoomRange)
        WorldMapCanvasEnhancer.expandCanvasZoomRange(scVal)
    end
end

local transitPins = {}
local activeTransitCount = 0
local TRANSIT_ICONS = {
    boat = "Interface\\AddOns\\EzWoW-MapFinder\\Media\\Transit-Boat",
    zepp = "Interface\\AddOns\\EzWoW-MapFinder\\Media\\Transit-Zeppelin",
    tram = "Interface\\AddOns\\EzWoW-MapFinder\\Media\\Transit-Tram",
    portal = "Interface\\AddOns\\EzWoW-MapFinder\\Media\\Transit-Portal",
}
local pendingTransitMapID, transitNavigationFrame

-- Chat lines added in combat taint the chat history, so in combat the note goes
-- on the open tooltip; a chat line is only printed out of combat.
function WorldMapCanvasEnhancer.reportTransitNavigation(key, target)
    local message = L[key]
    if not message then return end
    if target then message = message:format(target) end
    if InCombatLockdown and InCombatLockdown() then
        if GameTooltip and GameTooltip:IsShown() then
            GameTooltip:AddLine(message, unpack(Theme.warn))
            GameTooltip:Show()
        end
        return
    end
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff4bc8e8EzWoW - Map Finder:|r " .. message) end
end

function WorldMapCanvasEnhancer.openTransitMap(target)
    target = tonumber(target)
    if not target or not WorldMapFrame or not WorldMapFrame.SetMapID then return end
    if InCombatLockdown and InCombatLockdown() then
        pendingTransitMapID = target
        if not transitNavigationFrame then
            transitNavigationFrame = CreateFrame("Frame")
            transitNavigationFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            transitNavigationFrame:SetScript("OnEvent", function()
                local mapID = pendingTransitMapID
                pendingTransitMapID = nil
                if mapID then WorldMapCanvasEnhancer.openTransitMap(mapID) end
            end)
        end
        WorldMapCanvasEnhancer.reportTransitNavigation("transitQueued")
        return
    end
    local function navigate()
        if InCombatLockdown and InCombatLockdown() then
            WorldMapCanvasEnhancer.openTransitMap(target)
            return
        end
        local ok, errorText = pcall(WorldMapFrame.SetMapID, WorldMapFrame, target)
        if ok and WorldMapFrame.GetMapID then
            local readable, current = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
            ok = readable and current == target
        end
        if not ok then
            ns.lastTransitNavigationError = errorText or "Map did not change"
            WorldMapCanvasEnhancer.reportTransitNavigation("transitFailed", target)
        elseif GameTooltip then
            GameTooltip:Hide()
        end
    end
    -- Capture the destination before changing maps recycles the clicked pin.
    -- Navigate after the current mouse event has finished.
    if C_Timer and C_Timer.After then C_Timer.After(0, navigate) else navigate() end
end

function WorldMapCanvasEnhancer.obtainTransitPin(entryIndex)
    local pin = transitPins[entryIndex]
    if pin then return pin end
    local canvasFrame = (WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas())
        or (_G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock:GetCanvas())
        or WorldMapFrame
    pin = CreateFrame("Button", nil, canvasFrame)
    pin:EnableMouse(true)
    pin:RegisterForClicks("LeftButtonUp")
    if pin.SetMouseClickEnabled then pin:SetMouseClickEnabled(true) end
    setPropagateClicks(pin, false)
    pin:SetSize(20, 20)
    pin:SetFrameStrata("HIGH")
    pin:SetFrameLevel((canvasFrame:GetFrameLevel() or 10) + 180)
    local iconTex = pin:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    pin.icon = iconTex
    pin:SetScript("OnEnter", function(self)
        local apiInfo = self.info
        if not apiInfo then return end
        local hasKo = (ns.activeLocale == "koKR")
        local titleStr = hasKo and apiInfo.ko or apiInfo.en
        local fcVal = FACTION_COLORS[apiInfo.fac] or FACTION_COLORS.N
        local facText = (apiInfo.fac == "A" and panelText(ns.activeLocale, "얼라이언스", "Alliance", { "Allianz", "Alliance", "Alianza", "Альянс", "联盟", "聯盟" }))
            or (apiInfo.fac == "H" and panelText(ns.activeLocale, "호드", "Horde", { "Horde", "Horde", "Horda", "Орда", "部落", "部落" }))
            or panelText(ns.activeLocale, "중립", "Neutral", { "Neutral", "Neutre", "Neutral", "Нейтрально", "中立", "中立" })
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
            GameTooltip:AddDoubleLine(" ", "EzWoW - Map Finder", 0, 0, 0, 0.5, 0.5, 0.5)
            GameTooltip:Show()
            if _G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.Refit then pcall(_G.EzWoWTooltipTagSizer.Refit, GameTooltip) end
            return
        end
        GameTooltip:SetText(titleStr, unpack(Theme.accent))
        GameTooltip:AddLine(string.format("[%s] (%.1f, %.1f)", facText, apiInfo.x, apiInfo.y), fcVal[1], fcVal[2], fcVal[3])
        if apiInfo.dest then
            GameTooltip:AddLine(L.transitClick or "Click: Open destination map", unpack(Theme.muted))
        end
        GameTooltip:AddDoubleLine(" ", "EzWoW - Map Finder", 0, 0, 0, 0.5, 0.5, 0.5)
        GameTooltip:Show()
        if _G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.Refit then pcall(_G.EzWoWTooltipTagSizer.Refit, GameTooltip) end
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local apiInfo = self.info
        local target = apiInfo and (apiInfo.members and apiInfo.zone or apiInfo.dest)
        if target then WorldMapCanvasEnhancer.openTransitMap(target) end
    end)
    if ns.PassMapRightClicks then ns.PassMapRightClicks(pin) end
    transitPins[entryIndex] = pin
    return pin
end

-- Places a pin at its map position (0-1) at the current canvas zoom; pins keep
-- one size on screen, so their offsets are in their own (scaled) units.
function WorldMapCanvasEnhancer.anchorTransitPin(pin, canvasFrame, cwVal, chVal, cScale)
    local pinScale = 1 / cScale
    pin:SetScale(pinScale)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvasFrame, "TOPLEFT", (pin.nx * cwVal) / pinScale, -(pin.ny * chVal) / pinScale)
end

function WorldMapCanvasEnhancer.canvasMetrics()
    local canvasFrame = (WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas())
        or (_G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock:GetCanvas())
        or WorldMapFrame
    if not canvasFrame then return nil end
    local cwVal, chVal = canvasFrame:GetWidth(), canvasFrame:GetHeight()
    if not cwVal or not chVal or cwVal <= 0 or chVal <= 0 then return nil end
    local cScale = (WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()) or 1
    if not cScale or cScale <= 0 then cScale = 1 end
    return canvasFrame, cwVal, chVal, cScale
end

-- Zoom changes only move and resize the pins already shown.
function WorldMapCanvasEnhancer.rescaleTransitPins()
    if activeTransitCount == 0 then return end
    local canvasFrame, cwVal, chVal, cScale = WorldMapCanvasEnhancer.canvasMetrics()
    if not canvasFrame then return end
    for index = 1, activeTransitCount do
        local pin = transitPins[index]
        if pin and pin:IsShown() and pin.nx then
            WorldMapCanvasEnhancer.anchorTransitPin(pin, canvasFrame, cwVal, chVal, cScale)
        end
    end
end

-- Transit data is stored per zone map. On a continent or the world map the
-- zone positions are projected with C_Map.GetMapRectOnMap; stops that land on
-- the same spot (a zeppelin tower with two lines) share one pin.
local TRANSIT_MERGE_DISTANCE = 1.2   -- percent of the map

function WorldMapCanvasEnhancer.filterTransitByFaction(stops, playerFaction)
    local visible = {}
    for _, stop in ipairs(stops or {}) do
        local enemy = (playerFaction == "Horde" and stop.fac == "A")
            or (playerFaction == "Alliance" and stop.fac == "H")
        if not enemy then visible[#visible + 1] = stop end
    end
    return visible
end

function WorldMapCanvasEnhancer.collectTransitForMap(uiMapID)
    local playerFaction = UnitFactionGroup and UnitFactionGroup("player")
    local direct = WorldMapCanvasEnhancer.filterTransitByFaction(TRANSIT_DATA[uiMapID], playerFaction)
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
            for _, stop in ipairs(WorldMapCanvasEnhancer.filterTransitByFaction(stops, playerFaction)) do
                local x = (minX + (stop.x / 100) * (maxX - minX)) * 100
                local y = (minY + (stop.y / 100) * (maxY - minY)) * 100
                local group
                for _, existing in ipairs(groups) do
                    if existing.kind == stop.kind and math.abs(existing.x - x) < TRANSIT_MERGE_DISTANCE and math.abs(existing.y - y) < TRANSIT_MERGE_DISTANCE then
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

    local canvasFrame, cwVal, chVal, cScale = WorldMapCanvasEnhancer.canvasMetrics()
    if not canvasFrame then return end

    for index = 1, #itemList do
        local apiInfo = itemList[index]
        local pin = WorldMapCanvasEnhancer.obtainTransitPin(index)
        pin:SetParent(canvasFrame)
        pin.info = apiInfo
        local texture = TRANSIT_ICONS[apiInfo.kind] or TRANSIT_ICONS.boat
        pin.icon:SetTexture(texture)
        pin:SetHighlightTexture(texture, "ADD")
        local highlight = pin:GetHighlightTexture()
        if highlight then highlight:SetAlpha(0.3) end
        pin.nx, pin.ny = apiInfo.x / 100, apiInfo.y / 100
        WorldMapCanvasEnhancer.anchorTransitPin(pin, canvasFrame, cwVal, chVal, cScale)
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
ns.RefreshZoneLevelLabel = WorldMapCanvasEnhancer.refreshZoneLevelLabel
ns.ApplyMapFade = WorldMapCanvasEnhancer.commitMapFade
ns.ApplyMapBackdrop = WorldMapCanvasEnhancer.commitMapBackdrop
ns.SetupMapBackdrop = WorldMapCanvasEnhancer.installMapBackdropHooks
ns.GetMapBackdropTexture = WorldMapCanvasEnhancer.getMapBackdropTexture
ns.ExtendMapZoomLevels = WorldMapCanvasEnhancer.expandCanvasZoomRange
ns.ApplyMapZoom = WorldMapCanvasEnhancer.commitMapZoom
ns.SetupMapZoom = WorldMapCanvasEnhancer.installMapWheelZoomHooks
ns.AcquireTransitPin = WorldMapCanvasEnhancer.obtainTransitPin
ns.RefreshTransitPins = WorldMapCanvasEnhancer.renderWorldTransitMarkers
ns.RescaleTransitPins = WorldMapCanvasEnhancer.rescaleTransitPins
