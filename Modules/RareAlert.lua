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
    -- the GUID can be a secret value (combat, some places): no string work on it then
    if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
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
    if issecretvalue and (issecretvalue(px) or issecretvalue(py)) then px, py = nil, nil end
    local mapInfo = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return mapID, px, py, mapInfo and mapInfo.name or ""
end

-- Closest known spawn on the player's current map
function RareAlertNotifier.findNearestSpawnIndex(entity, mapID, px, py)
    local spawns = entity and entity.spawns
    if not spawns or #spawns == 0 then return nil end
    local bestIdx, bestDist = 1, nil
    if not (mapID and px and py) then return bestIdx end
    local project = ns.ProjectSpawnToWorldMapCoords
    for index, sp in ipairs(spawns) do
        -- handles both {-1, uiMapID, x, y} and world-coordinate {instanceID, wx, wy, wz} spawns
        local sx, sy
        if sp[1] == -1 then
            if sp[2] == mapID then sx, sy = sp[3], sp[4] end
        elseif project then
            local okProj, projMap, mx, my = pcall(project, sp, mapID)
            if okProj and projMap == mapID then sx, sy = mx, my end
        end
        if sx and sy then
            local dx, dy = sx - px, sy - py
            local dist = dx * dx + dy * dy
            if not bestDist or dist < bestDist then
                bestIdx, bestDist = index, dist
            end
        end
    end
    return bestIdx
end

-----------------------------------------------------------------------------
-- Alert Card Effects
-- A glowing halo that pulses around the card, a light sweep across it, a
-- fade-in when it appears. Plain textures only.
-----------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8X8"
local HALO = 14   -- width of the soft glow outside the card edges

-- a texture fading from colour a (alpha a1) to alpha a2
local function gradientTexture(parent, layer, orientation, color, a1, a2)
    local tex = parent:CreateTexture(nil, layer)
    tex:SetTexture(WHITE)
    tex:SetBlendMode("ADD")
    local r, g, b = color[1], color[2], color[3]
    local ok = CreateColor and pcall(tex.SetGradient, tex, orientation, CreateColor(r, g, b, a1), CreateColor(r, g, b, a2))
    if not ok then tex:SetVertexColor(r, g, b, (a1 + a2) / 2) end
    return tex
end

function RareAlertNotifier.buildCardEffects(card, icon, color)
    local fx = {}
    card.fx = fx

    -- halo: four soft gradients just outside the edges, pulsing
    local halo = CreateFrame("Frame", nil, card)
    halo:SetPoint("TOPLEFT", -HALO, HALO)
    halo:SetPoint("BOTTOMRIGHT", HALO, -HALO)
    halo:SetFrameLevel(math.max(0, card:GetFrameLevel() - 1))
    local top = gradientTexture(halo, "BACKGROUND", "VERTICAL", color, 0.75, 0)
    top:SetPoint("BOTTOMLEFT", card, "TOPLEFT", 0, 0); top:SetPoint("BOTTOMRIGHT", card, "TOPRIGHT", 0, 0); top:SetHeight(HALO)
    local bottom = gradientTexture(halo, "BACKGROUND", "VERTICAL", color, 0, 0.75)
    bottom:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, 0); bottom:SetPoint("TOPRIGHT", card, "BOTTOMRIGHT", 0, 0); bottom:SetHeight(HALO)
    local left = gradientTexture(halo, "BACKGROUND", "HORIZONTAL", color, 0, 0.75)
    left:SetPoint("TOPRIGHT", card, "TOPLEFT", 0, 0); left:SetPoint("BOTTOMRIGHT", card, "BOTTOMLEFT", 0, 0); left:SetWidth(HALO)
    local right = gradientTexture(halo, "BACKGROUND", "HORIZONTAL", color, 0.75, 0)
    right:SetPoint("TOPLEFT", card, "TOPRIGHT", 0, 0); right:SetPoint("BOTTOMLEFT", card, "BOTTOMRIGHT", 0, 0); right:SetWidth(HALO)
    -- a bright rim on the card edge
    local rim = CreateFrame("Frame", nil, card, BackdropTemplateMixin and "BackdropTemplate" or nil)
    rim:SetAllPoints()
    rim:SetFrameLevel(card:GetFrameLevel() + 2)
    if rim.SetBackdrop then
        rim:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
        rim:SetBackdropBorderColor(color[1], color[2], color[3], 1)
    end
    local pulse = halo:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0.25); fade:SetDuration(0.6); fade:SetSmoothing("IN_OUT")
    local rimPulse = rim:CreateAnimationGroup()
    rimPulse:SetLooping("BOUNCE")
    local rimFade = rimPulse:CreateAnimation("Alpha")
    rimFade:SetFromAlpha(1); rimFade:SetToAlpha(0.35); rimFade:SetDuration(0.6); rimFade:SetSmoothing("IN_OUT")
    fx.pulse, fx.rimPulse = pulse, rimPulse

    -- light sweep: a soft white band moving across the card, clipped to it
    local clip = CreateFrame("Frame", nil, card)
    clip:SetAllPoints()
    clip:SetFrameLevel(card:GetFrameLevel() + 1)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    local band = CreateFrame("Frame", nil, clip)
    band:SetSize(90, 200)
    band:SetPoint("CENTER", clip, "LEFT", -60, 0)
    local bandL = gradientTexture(band, "ARTWORK", "HORIZONTAL", { 1, 1, 1 }, 0, 0.45)
    bandL:SetPoint("TOPLEFT"); bandL:SetPoint("BOTTOMRIGHT", band, "BOTTOM", 0, 0)
    local bandR = gradientTexture(band, "ARTWORK", "HORIZONTAL", { 1, 1, 1 }, 0.45, 0)
    bandR:SetPoint("TOPRIGHT"); bandR:SetPoint("BOTTOMLEFT", band, "BOTTOM", 0, 0)
    band:Hide()
    local sweep = band:CreateAnimationGroup()
    local move = sweep:CreateAnimation("Translation")
    move:SetOffset(card:GetWidth() + 120, 0); move:SetDuration(0.9); move:SetSmoothing("IN_OUT")
    sweep:SetLooping("REPEAT")
    sweep:SetScript("OnLoop", function(self)
        self.loops = (self.loops or 0) + 1
        if self.loops >= 3 then self:Stop(); band:Hide() end
    end)
    fx.sweep, fx.band = sweep, band

    -- fade-in of the whole card (no scale animations: they misbehave on this client)
    local enter = card:CreateAnimationGroup()
    local show = enter:CreateAnimation("Alpha")
    show:SetFromAlpha(0); show:SetToAlpha(1); show:SetDuration(0.25)
    fx.enter = enter

    card:HookScript("OnHide", function()
        pulse:Stop(); rimPulse:Stop(); sweep:Stop(); band:Hide()
    end)
end

function RareAlertNotifier.playCardEffects(card)
    local fx = card.fx
    if not fx then return end
    fx.enter:Stop(); fx.enter:Play()
    fx.pulse:Play(); fx.rimPulse:Play()
    fx.sweep.loops = 0
    fx.band:Show(); fx.sweep:Stop(); fx.sweep:Play()
end

-----------------------------------------------------------------------------
-- Alert Card
-----------------------------------------------------------------------------
function RareAlertNotifier.buildAlertCard()
    if alertCard then return alertCard end
    local rareColor = { 0.80, 0.40, 1.00, 1.00 }

    local card = CreateFrame("Frame", "EzWoWMapFinderRareCard", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    card:SetSize(470, 96)
    card:SetFrameStrata("HIGH")
    card:SetClampedToScreen(true)
    card:SetMovable(true)
    card:EnableMouse(true)
    card:RegisterForDrag("LeftButton")
    card:SetScript("OnDragStart", function(self)
        self:StartMoving()
        self.dragging = true
    end)
    card:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.dragging = false
        local point, _, relPoint, x, y = self:GetPoint(1)
        ns.DB.rareCardPos = { point = point, relPoint = relPoint, x = x, y = y }
        RareAlertNotifier.updateTargetButton()
    end)
    card:HookScript("OnHide", function(self)
        self.closeAfterCombat = nil
        RareAlertNotifier.updateTargetButton()
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
    icon:SetPoint("TOPLEFT", 14, -14)
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
    card.mapBtn:SetPoint("TOPRIGHT", -12, -30)
    card.mapBtn.label:SetFontObject("GameFontHighlightSmall")
    card.mapBtn.label:SetTextColor(unpack(Theme.accent))

    card.closeBtn = ns.CreateStyledButton(card, 18, 18, false, function() RareAlertNotifier.closeCard() end)
    card.closeBtn:SetPoint("TOPRIGHT", -6, -6)
    card.closeBtn:SetText("x")

    -- effects are extras: the card still works if one of them fails to build
    pcall(RareAlertNotifier.buildCardEffects, card, icon, rareColor)

    card:SetScript("OnUpdate", function(self)
        -- the target / mark buttons follow the card while it is dragged (out of combat)
        if self.dragging and not InCombatLockdown() then RareAlertNotifier.updateTargetButton() end
        if not self.shownAt then return end
        local age = GetTime() - self.shownAt
        -- while its secure buttons are up in combat the card stays (they can't be hidden then)
        if self:IsMouseOver() or (InCombatLockdown() and RareAlertNotifier.secureButtonsShown()) then
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

-- Closes the card. While its secure buttons are up in combat they can't be
-- hidden (an invisible button still takes clicks), so it closes when combat ends.
function RareAlertNotifier.closeCard()
    local card = alertCard
    if not card then return end
    if InCombatLockdown() and RareAlertNotifier.secureButtonsShown() then
        card.closeAfterCombat = true
        return
    end
    card:Hide()
end

-----------------------------------------------------------------------------
-- Target & Mark Buttons
-- Targeting and marking need secure buttons. They are not children of the
-- card (that would make the card protected, and it could no longer be shown
-- or hidden in combat): they sit on UIParent over the card, placed by screen
-- position (not anchored to the card), and are only changed out of combat.
-----------------------------------------------------------------------------
local targetBtn
local markBtns = {}
local MARK_SIZE, MARK_GAP = 18, 4
local secureUpdatePending = false

local function createSecureButton(name, w, h)
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate,BackdropTemplate")
    b:SetSize(w, h)
    b:SetFrameStrata("HIGH")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "macro")
    b:Hide()
    return b
end

function RareAlertNotifier.buildSecureButtons()
    if targetBtn then return end
    local b = createSecureButton("EzWoWMapFinderRareTarget", 76, 22)
    ns.UIKit:ApplyBackdrop(b)
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", 0, 0)
    b.label = label
    local function normalLook()
        b:SetBackdropColor(0.14, 0.24, 0.30, 0.96)
        b:SetBackdropBorderColor(unpack(Theme.accent))
        label:SetTextColor(unpack(Theme.accent))
    end
    normalLook()
    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.18, 0.28, 0.35, 1)
        self:SetBackdropBorderColor(unpack(Theme.accent))
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L.rareTarget or "Target", 1, 1, 1)
            GameTooltip:AddLine(L.rareTargetTip or "", 0.85, 0.86, 0.90, true)
            GameTooltip:AddDoubleLine(" ", "EzWoW - Map Finder", 0, 0, 0, 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        normalLook()
        if GameTooltip then GameTooltip:Hide() end
    end)
    -- after the target click (insecure code, also in combat): the tracking pin
    b:HookScript("PostClick", function() pcall(RareAlertNotifier.pinCardMonster) end)
    targetBtn = b

    -- the eight raid marks (1 star ... 8 skull), as in the game's mark menu
    for index = 1, 8 do
        local m = createSecureButton("EzWoWMapFinderRareMark" .. index, MARK_SIZE, MARK_SIZE)
        local icon = m:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        local col, row = (index - 1) % 4, math.floor((index - 1) / 4)
        icon:SetTexCoord(col * 0.25, (col + 1) * 0.25, row * 0.25, (row + 1) * 0.25)
        local hl = m:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.25)
        m.index = index
        m:HookScript("PostClick", function() pcall(RareAlertNotifier.pinCardMonster) end)
        markBtns[index] = m
    end
end

local function setSecureAlpha(alpha)
    if not targetBtn then return end
    targetBtn:SetAlpha(alpha)
    for _, m in ipairs(markBtns) do m:SetAlpha(alpha) end
end

local function hideSecureButtons()
    if not targetBtn then return end
    targetBtn:Hide()
    for _, m in ipairs(markBtns) do m:Hide() end
    setSecureAlpha(1)
end

function RareAlertNotifier.secureButtonsShown()
    return targetBtn ~= nil and targetBtn:IsShown() and targetBtn:GetAlpha() > 0
end

-- Shows the buttons for the monster on the card, or hides them with the card.
function RareAlertNotifier.updateTargetButton()
    if InCombatLockdown() then
        secureUpdatePending = true
        -- a card closed in combat: its buttons can't be hidden until combat
        -- ends, so they are made invisible for now
        if not (alertCard and alertCard:IsShown()) then setSecureAlpha(0) end
        return
    end
    secureUpdatePending = false
    local card = alertCard
    local name = card and card:IsShown() and card.targetName
    if not name then
        hideSecureButtons()
        return
    end
    RareAlertNotifier.buildSecureButtons()
    local level = card:GetFrameLevel() + 10

    -- target button: left of the map button (or at the right edge without it)
    -- (the map button keeps its place while hidden, so its height is used either way)
    local middle = select(2, card.mapBtn:GetCenter())
    local right
    if card.mapBtn:IsShown() then
        right = card.mapBtn:GetLeft()
        right = right and right - 6
    else
        right = card:GetRight()
        right = right and right - 12
    end
    local left, bottom = card.nameText:GetLeft(), card:GetBottom()
    if not (right and middle and left and bottom) then
        hideSecureButtons()
        return
    end
    targetBtn:SetAttribute("macrotext", "/targetexact " .. name)
    targetBtn.label:SetText(L.rareTarget or "Target")
    targetBtn:SetFrameLevel(level)
    targetBtn:ClearAllPoints()
    targetBtn:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", right, middle)
    setSecureAlpha(1)
    targetBtn:Show()

    -- mark row along the bottom of the card, under the name
    for index, m in ipairs(markBtns) do
        m:SetAttribute("macrotext", "/targetexact " .. name .. "\n/tm " .. index)
        m:SetFrameLevel(level)
        m:ClearAllPoints()
        m:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left + (index - 1) * (MARK_SIZE + MARK_GAP), bottom + 7)
        m:Show()
    end
end

local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:SetScript("OnEvent", function()
    if alertCard and alertCard.closeAfterCombat then
        alertCard.closeAfterCombat = nil
        alertCard:Hide() -- OnHide then hides the secure buttons (out of combat now)
    end
    if secureUpdatePending then pcall(RareAlertNotifier.updateTargetButton) end
end)

-- Target (or mark) on the card: a tracking pin with the on-screen arrow at the
-- monster's spot, without opening the map. The button fires on press and on
-- release, so a second call right after is skipped.
local lastPinAt = 0
function RareAlertNotifier.pinCardMonster()
    local card = alertCard
    if not (card and card:IsShown() and card.pinSpot) then return end
    local now = GetTime()
    if now - lastPinAt < 0.5 then return end
    lastPinAt = now
    if card.entity then
        ns.selectedEntity = card.entity
        ns.selectedSpawnIdx = card.spawnIdx or 1
    end
    if ns.ApplyWaypointForSpawn then ns.ApplyWaypointForSpawn(card.pinSpot, card.pinName, nil, true) end
    if ns.RefreshMapPins and not (InCombatLockdown and InCombatLockdown()) then pcall(ns.RefreshMapPins) end
end

function RareAlertNotifier.openEntityOnMap(entity, spawnIdx)
    -- with the gamepad on, only the waypoint and pins are set: see ns.IsGamePadUI
    -- not opened in combat either: the map's pins would be blocked then
    -- (the waypoint and pins are still set, the map moves after combat)
    if WorldMapFrame and not WorldMapFrame:IsShown() and not ns.IsGamePadUI()
        and not (InCombatLockdown and InCombatLockdown()) then
        -- opened by the game itself (C_Map.OpenWorldMap), not from addon code
        if C_Map and C_Map.OpenWorldMap then pcall(C_Map.OpenWorldMap) end
    end
    if ns.SelectEntityOnMap then
        ns.SelectEntityOnMap(entity, spawnIdx)
    end
end

function RareAlertNotifier.focusCardEntityOnMap()
    local card = alertCard
    if not card or not card.entity then return end
    RareAlertNotifier.openEntityOnMap(card.entity, card.spawnIdx)
    RareAlertNotifier.closeCard()
end

function RareAlertNotifier.presentAlertCard(unitName, entity, spawnIdx, mapName, px, py)
    local card = RareAlertNotifier.buildAlertCard()
    card.entity = entity
    card.spawnIdx = spawnIdx
    -- a name the client hides can't be put in a macro: no target button then
    local readable = type(unitName) == "string" and not (issecretvalue and issecretvalue(unitName))
        and unitName ~= "" and unitName ~= "?"
    card.targetName = readable and unitName or nil
    -- where the target button points the tracking pin: the nearest known spawn
    -- (a sighting shared by another player sets its own spot after this)
    card.pinSpot = entity and spawnIdx and entity.spawns and entity.spawns[spawnIdx] or nil
    card.pinName = card.targetName
        or (entity and ns.GetLocalizedEntityName and ns.GetLocalizedEntityName(entity)) or L.rareTitle
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
        card.nameText:SetWidth(160)
    else
        card.placeText:SetText(L.rareUnlisted)
        card.mapBtn:Hide()
        card.nameText:SetWidth(250)
    end
    card.placeText:SetWidth(card.nameText:GetWidth())
    card:SetAlpha(1)
    card.shownAt = GetTime()
    card.closeAfterCombat = nil
    card:Show()
    pcall(RareAlertNotifier.playCardEffects, card)
    RareAlertNotifier.updateTargetButton()
end

-----------------------------------------------------------------------------
-- Rares other players of the EzWoW addons saw (Libs/EzWoWShare): a sighting
-- in the player's zone, at most 10 minutes old, shows the same card
-----------------------------------------------------------------------------
local SHARED_MAX_AGE = 600

function RareAlertNotifier.onSharedRecords(kinds)
    if type(kinds) ~= "table" or not kinds.rare then return end
    local share = ns.Share
    if not (share and share.TakeNewRares) then return end
    local list = share.TakeNewRares()
    local db = ns.DB
    if not db or db.rareAlert == false or (InCombatLockdown and InCombatLockdown()) then return end
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType ~= "none" then return end
    local mapID, _, _, mapName = RareAlertNotifier.resolvePlayerLocation()
    for _, npcId in ipairs(list) do
        local rec = share.GetRare(npcId)
        local age = rec and (time() - (rec.t or 0))
        if rec and rec.shared and rec.m == mapID and age and age <= SHARED_MAX_AGE
            and not (lastAlertAt[npcId] and GetTime() - lastAlertAt[npcId] < REPEAT_COOLDOWN) then
            lastAlertAt[npcId] = GetTime()
            local entity = (rareEntityById or RareAlertNotifier.buildRareEntityIndex())[npcId]
            local name = (entity and ns.GetLocalizedEntityName and ns.GetLocalizedEntityName(entity))
                or share.SourceName("n" .. npcId) or "?"
            local spawnIdx = entity and RareAlertNotifier.findNearestSpawnIndex(entity, mapID, rec.x, rec.y)
            RareAlertNotifier.presentAlertCard(name, entity, spawnIdx, mapName, rec.x, rec.y)
            local card = RareAlertNotifier.buildAlertCard()
            card.heading:SetText(L.rareSharedTitle .. " · " .. share.Ago(rec.t))
            -- the spot where it was seen is closer to it than the nearest spawn
            if type(rec.x) == "number" and type(rec.y) == "number" and mapID then
                card.pinSpot = { -1, mapID, rec.x, rec.y }
            end
            if db.rareAlertSound ~= false and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
                pcall(PlaySound, SOUNDKIT.RAID_WARNING)
            end
            break
        end
    end
end

if ns.Share and ns.Share.RegisterCallback then
    ns.Share.RegisterCallback("EzWoW-MapFinder", function(kinds) RareAlertNotifier.onSharedRecords(kinds) end)
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
        -- a bright fanfare: the legendary loot toast, else the level-up sound,
        -- else the raid warning (the first one this client has)
        for _, kit in ipairs({ (SOUNDKIT and SOUNDKIT.UI_LEGENDARY_LOOT_TOAST) or 63971,
                (SOUNDKIT and SOUNDKIT.LEVELUP) or 888, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959 }) do
            local ok, willPlay = pcall(PlaySound, kit, "Master")
            if ok and willPlay then break end
        end
    end
    -- a name the client hides can't go into a chat line (it may be held until combat ends)
    local shownName = unitName
    if issecretvalue and issecretvalue(shownName) then
        shownName = entity and ns.GetLocalizedEntityName and ns.GetLocalizedEntityName(entity) or nil
    end
    if shownName and ns.ChatPrint then
        local place = (px and py) and string.format(" · %s %.1f, %.1f", mapName or "", px * 100, py * 100) or ""
        ns.ChatPrint(string.format("%s%s|r — %s%s", ns.KIND_COLORS.rare, L.rareTitle, shownName, place))
    end
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
