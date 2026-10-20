--===========================================================================
-- EzWoW - Map Finder
-- Modules/RareAlert.lua : Nearby Rare Monster Detection & Alert Card
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local RareAlertNotifier = ns.RareAlertNotifier or {}
ns.RareAlertNotifier = RareAlertNotifier

local Theme = ns.Theme
local L = ns.L

local REPEAT_COOLDOWN = 300   -- alert the same monster at most once per 5 minutes
local CARD_LIFETIME = 15      -- seconds the alert card stays on screen
local CARD_FADE = 1.2         -- fade-out duration at the end
local RARE_CLASSIFICATIONS = { rare = true, rareelite = true }

local rareEntityById
local lastAlertAt = {}
local alertCard

-----------------------------------------------------------------------------
-- Rare Entity Index (isRare entries of the search database)
-----------------------------------------------------------------------------
function RareAlertNotifier.buildRareEntityIndex()
    rareEntityById = {}
    for _, e in ipairs(_G.EzWoWMapFinderData or {}) do
        if e and e.kind == "npc" and e.isRare and e.id then
            rareEntityById[e.id] = e
        end
    end
    return rareEntityById
end

function RareAlertNotifier.extractCreatureId(unit)
    local guid = UnitGUID and UnitGUID(unit)
    if not guid then return nil end
    local unitType, _, _, _, _, npcId = strsplit("-", guid)
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return nil end
    return tonumber(npcId)
end

function RareAlertNotifier.resolvePlayerLocation()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    local px, py
    if pos and pos.GetXY then px, py = pos:GetXY() end
    local mapInfo = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return mapID, px, py, mapInfo and mapInfo.name or ""
end

-- Closest known spawn on the player's current map
function RareAlertNotifier.findNearestSpawnIndex(entity, mapID, px, py)
    local spawns = entity and entity.spawns
    if not spawns or #spawns == 0 then return nil end
    local bestIdx, bestDist = 1, nil
    for index, sp in ipairs(spawns) do
        if sp[2] == mapID and px and py and sp[3] and sp[4] then
            local dx, dy = sp[3] - px, sp[4] - py
            local dist = dx * dx + dy * dy
            if not bestDist or dist < bestDist then
                bestIdx, bestDist = index, dist
            end
        end
    end
    return bestIdx
end

-----------------------------------------------------------------------------
-- Alert Card
-----------------------------------------------------------------------------
function RareAlertNotifier.buildAlertCard()
    if alertCard then return alertCard end
    local rareColor = { 0.80, 0.40, 1.00, 1.00 }

    local card = CreateFrame("Frame", "EzWoWMapFinderRareCard", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    card:SetSize(320, 74)
    card:SetFrameStrata("HIGH")
    card:SetClampedToScreen(true)
    card:SetMovable(true)
    card:EnableMouse(true)
    card:RegisterForDrag("LeftButton")
    card:SetScript("OnDragStart", card.StartMoving)
    card:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        ns.DB.rareCardPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    local pos = ns.DB and ns.DB.rareCardPos
    if type(pos) == "table" and pos.point then
        card:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        card:SetPoint("TOP", UIParent, "TOP", 0, -150)
    end
    if card.SetBackdrop then
        ns.UIKit:ApplyBackdrop(card, 1, 1)
        card:SetBackdropColor(unpack(Theme.bg))
        card:SetBackdropBorderColor(unpack(Theme.border))
    end

    local stripe = card:CreateTexture(nil, "ARTWORK")
    stripe:SetColorTexture(unpack(rareColor))
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("BOTTOMLEFT", 1, 1)
    stripe:SetWidth(4)

    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30)
    icon:SetPoint("LEFT", 14, 0)
    icon:SetTexture("Interface\\AddOns\\EzWoW-MapFinder\\Media\\Icon")
    if not icon:GetTexture() then
        icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    end

    card.heading = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.heading:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 4)
    card.heading:SetTextColor(unpack(rareColor))

    card.nameText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.nameText:SetPoint("TOPLEFT", card.heading, "BOTTOMLEFT", 0, -3)
    card.nameText:SetWidth(170)
    card.nameText:SetJustifyH("LEFT")
    if card.nameText.SetWordWrap then card.nameText:SetWordWrap(false) end
    card.nameText:SetTextColor(unpack(Theme.text))

    card.placeText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.placeText:SetPoint("TOPLEFT", card.nameText, "BOTTOMLEFT", 0, -3)
    card.placeText:SetWidth(170)
    card.placeText:SetJustifyH("LEFT")
    if card.placeText.SetWordWrap then card.placeText:SetWordWrap(false) end
    card.placeText:SetTextColor(unpack(Theme.muted))

    card.mapBtn = ns.CreateStyledButton(card, 86, 22, true, function()
        RareAlertNotifier.focusCardEntityOnMap()
    end)
    card.mapBtn:SetPoint("RIGHT", -12, -4)
    card.mapBtn.label:SetFontObject("GameFontHighlightSmall")
    card.mapBtn.label:SetTextColor(unpack(Theme.accent))

    card.closeBtn = ns.CreateStyledButton(card, 18, 18, false, function() card:Hide() end)
    card.closeBtn:SetPoint("TOPRIGHT", -6, -6)
    card.closeBtn:SetText("x")

    card:SetScript("OnUpdate", function(self)
        if not self.shownAt then return end
        local age = GetTime() - self.shownAt
        if self:IsMouseOver() then
            self.shownAt = GetTime() - math.min(age, CARD_LIFETIME - CARD_FADE - 1)
            self:SetAlpha(1)
            return
        end
        if age >= CARD_LIFETIME then
            self:Hide()
        elseif age >= CARD_LIFETIME - CARD_FADE then
            self:SetAlpha((CARD_LIFETIME - age) / CARD_FADE)
        end
    end)
    card:Hide()
    alertCard = card
    return card
end

function RareAlertNotifier.focusCardEntityOnMap()
    local card = alertCard
    if not card or not card.entity then return end
    if InCombatLockdown and InCombatLockdown() then
        print("|cff4bc8e8[Map Finder]|r " .. (L.combatNote or ""))
        return
    end
    if WorldMapFrame and not WorldMapFrame:IsShown() then
        if ToggleWorldMap then pcall(ToggleWorldMap) else pcall(ShowUIPanel, WorldMapFrame) end
    end
    if ns.SelectEntityOnMap then
        ns.SelectEntityOnMap(card.entity, card.spawnIdx)
    end
    card:Hide()
end

function RareAlertNotifier.presentAlertCard(unitName, entity, spawnIdx, mapName, px, py)
    local card = RareAlertNotifier.buildAlertCard()
    card.entity = entity
    card.spawnIdx = spawnIdx
    card.heading:SetText(L.rareTitle)
    card.nameText:SetText(unitName)
    if entity then
        if px and py then
            card.placeText:SetText(string.format("%s · %.1f, %.1f", mapName or "", px * 100, py * 100))
        else
            card.placeText:SetText(mapName or "")
        end
        card.mapBtn:SetText(L.rareShowMap)
        card.mapBtn:Show()
        card.nameText:SetWidth(170)
    else
        card.placeText:SetText(L.rareUnlisted)
        card.mapBtn:Hide()
        card.nameText:SetWidth(260)
    end
    card:SetAlpha(1)
    card.shownAt = GetTime()
    card:Show()
end

-----------------------------------------------------------------------------
-- Detection
-----------------------------------------------------------------------------
function RareAlertNotifier.inspectUnit(unit)
    local db = ns.DB
    if not db or db.rareAlert == false or not unit then return end
    if not UnitExists(unit) or UnitIsPlayer(unit) or UnitIsDeadOrGhost(unit) then return end
    if UnitIsFriend and UnitIsFriend("player", unit) then return end
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType ~= "none" then return end

    local npcId = RareAlertNotifier.extractCreatureId(unit)
    if not npcId then return end
    local entity = (rareEntityById or RareAlertNotifier.buildRareEntityIndex())[npcId]
    if not entity and not RARE_CLASSIFICATIONS[UnitClassification(unit) or ""] then return end

    local now = GetTime()
    if lastAlertAt[npcId] and now - lastAlertAt[npcId] < REPEAT_COOLDOWN then return end
    lastAlertAt[npcId] = now

    local unitName = UnitName(unit) or (entity and ns.GetLocalizedEntityName and ns.GetLocalizedEntityName(entity)) or "?"
    local mapID, px, py, mapName = RareAlertNotifier.resolvePlayerLocation()
    local spawnIdx = entity and RareAlertNotifier.findNearestSpawnIndex(entity, mapID, px, py)

    RareAlertNotifier.presentAlertCard(unitName, entity, spawnIdx, mapName, px, py)
    if db.rareAlertSound ~= false and PlaySound then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.MAP_PING) or 3175, "Master")
    end
    local place = (px and py) and string.format(" · %s %.1f, %.1f", mapName or "", px * 100, py * 100) or ""
    print(string.format("|cff4bc8e8[Map Finder]|r %s%s|r — %s%s",
        ns.KIND_COLORS.rare, L.rareTitle, unitName, place))
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
watcher:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
watcher:SetScript("OnEvent", function(_, event, unit)
    if event == "UPDATE_MOUSEOVER_UNIT" then
        unit = "mouseover"
    elseif event == "PLAYER_TARGET_CHANGED" then
        unit = "target"
    end
    pcall(RareAlertNotifier.inspectUnit, unit)
end)

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
ns.BuildRareEntityIndex = RareAlertNotifier.buildRareEntityIndex
ns.InspectRareUnit = RareAlertNotifier.inspectUnit
