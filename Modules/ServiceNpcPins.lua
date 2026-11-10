--===========================================================================
-- EzWoW - Map Finder
-- Modules/ServiceNpcPins.lua : service NPC icons on town maps
--===========================================================================
-- Innkeepers, bankers, flight masters, trainers, vendors, mailboxes and so
-- on get a small icon on city maps (and, as an option, on regular zone maps),
-- much like the minimap tracking icons. Clicking an icon sets a waypoint.
-- NPCs are sorted into types once from their game flags and titles; each map
-- gets its own list the first time it is opened.
local _, ns = ...
-- frames made on the World Map are made without a parent and put in after
-- (Libs/EzWoWGamePad MakeFrame: keeps the game's gamepad cursor untainted)
local CreateFrame = (ns.GamePad and ns.GamePad.MakeFrame) or CreateFrame

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

-- The hovered mark comes to the front of marks that overlap it, and goes back
-- to its own level when the mouse leaves.
local function raisePin(self)
    if self.ezBaseLevel == nil then self.ezBaseLevel = self:GetFrameLevel() end
    self:SetFrameLevel(self.ezBaseLevel + 500)
end
local function lowerPin(self)
    if self.ezBaseLevel ~= nil then
        self:SetFrameLevel(self.ezBaseLevel)
        self.ezBaseLevel = nil
    end
end

-- Marks grow a little when the map is zoomed in (less than the map itself,
-- at most 3x), so they stay readable without covering the map.
local function zoomGrow(cScale)
    local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
    local minScale
    if sc and sc.GetScaleForMinZoom then
        local ok, v = pcall(sc.GetScaleForMinZoom, sc)
        if ok and type(v) == "number" and v > 0 then minScale = v end
    end
    if not minScale or not cScale or cScale <= minScale then return 1 end
    local f = (cScale / minScale) ^ 0.6
    if f > 3 then f = 3 end
    return f
end
local type, pairs, ipairs, tostring, pcall = type, pairs, ipairs, tostring, pcall
local find, lower = string.find, string.lower

local ServiceNpcPins = ns.ServiceNpcPins or {}
ns.ServiceNpcPins = ServiceNpcPins

local L = ns.L
local Theme = ns.Theme

local PIN_SIZE = 14
local MERGE_PIXELS = 12
local TOOLTIP_MAX_NAMES = 8

local function isSecret(v) return issecretvalue and issecretvalue(v) end

-----------------------------------------------------------------------------
-- Types (order = option order). tex: the game's own tracking texture;
-- color: rim colour (and the dot shown when the texture can't be loaded).
-----------------------------------------------------------------------------
local TYPES = {
    { key = "innkeeper",    tex = "Interface\\Minimap\\Tracking\\Innkeeper",    color = { 0.98, 0.78, 0.35 } },
    { key = "banker",       tex = "Interface\\Minimap\\Tracking\\Banker",       color = { 0.95, 0.85, 0.30 } },
    { key = "auctioneer",   tex = "Interface\\Minimap\\Tracking\\Auctioneer",   color = { 0.90, 0.70, 0.30 } },
    { key = "flight",       tex = "Interface\\Minimap\\Tracking\\FlightMaster", color = { 0.45, 0.85, 0.45 } },
    { key = "stable",       tex = "Interface\\Minimap\\Tracking\\StableMaster", color = { 0.75, 0.55, 0.35 } },
    { key = "classTrainer", tex = "Interface\\Minimap\\Tracking\\Class",        color = { 0.55, 0.75, 1.00 } },
    { key = "profTrainer",  tex = "Interface\\Minimap\\Tracking\\Profession",   color = { 0.85, 0.65, 1.00 } },
    { key = "repair",       tex = "Interface\\Minimap\\Tracking\\Repair",       color = { 0.70, 0.70, 0.75 } },
    { key = "general",      tex = "Interface\\GossipFrame\\VendorGossipIcon",   color = { 0.95, 0.95, 0.80 } },
    { key = "food",         tex = "Interface\\Minimap\\Tracking\\Food",         color = { 0.95, 0.55, 0.35 } },
    { key = "reagent",      tex = "Interface\\Minimap\\Tracking\\Reagents",     color = { 0.70, 0.45, 0.95 } },
    { key = "trade",        tex = "Interface\\Icons\\INV_Misc_Bag_10",          color = { 0.80, 0.80, 0.55 }, round = true },
    { key = "guild",        tex = "Interface\\GossipFrame\\TabardGossipIcon",   color = { 0.40, 0.80, 0.90 } },
    { key = "battlemaster", tex = "Interface\\Minimap\\Tracking\\BattleMaster", color = { 0.95, 0.35, 0.35 } },
    { key = "spirit",       tex = "Interface\\Icons\\Spell_Holy_Resurrection",  color = { 0.75, 0.90, 1.00 }, round = true },
    { key = "mailbox",      tex = "Interface\\Minimap\\Tracking\\Mailbox",      color = { 0.90, 0.90, 0.95 } },
}
local TYPE_BY_KEY = {}
for index, t in ipairs(TYPES) do
    t.order = index
    TYPE_BY_KEY[t.key] = t
end
ServiceNpcPins.TYPES = TYPES
ns.SERVICE_NPC_TYPES = TYPES

-- Profession trainers: the profession's own icon, read from its base spell
-- when the client knows it, a fixed icon otherwise.
local PROFESSIONS = {
    alchemy        = { spell = 2259, icon = "Interface\\Icons\\Trade_Alchemy" },
    blacksmithing  = { spell = 2018, icon = "Interface\\Icons\\Trade_BlackSmithing" },
    enchanting     = { spell = 7411, icon = "Interface\\Icons\\Trade_Engraving" },
    engineering    = { spell = 4036, icon = "Interface\\Icons\\Trade_Engineering" },
    herbalism      = { spell = 2366, icon = "Interface\\Icons\\Spell_Nature_NatureTouchGrow" },
    leatherworking = { spell = 2108, icon = "Interface\\Icons\\Trade_LeatherWorking" },
    mining         = { spell = 2575, icon = "Interface\\Icons\\Trade_Mining" },
    skinning       = { spell = 8613, icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" },
    tailoring      = { spell = 3908, icon = "Interface\\Icons\\Trade_Tailoring" },
    cooking        = { spell = 2550, icon = "Interface\\Icons\\INV_Misc_Food_15" },
    fishing        = { spell = 7620, icon = "Interface\\Icons\\Trade_Fishing" },
    firstAid       = { spell = 3273, icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
}

-- Title words -> profession (English titles first, Korean as a fallback)
local PROFESSION_WORDS = {
    { "first aid", "firstAid" }, { "physician", "firstAid" }, { "surgeon", "firstAid" },
    { "alchem", "alchemy" }, { "blacksmith", "blacksmithing" }, { "armorsmith", "blacksmithing" },
    { "weaponsmith", "blacksmithing" }, { "armor crafter", "blacksmithing" }, { "weapon crafter", "blacksmithing" },
    { "enchant", "enchanting" }, { "engineer", "engineering" }, { "herbal", "herbalism" },
    { "leather", "leatherworking" }, { "mining", "mining" }, { "miner", "mining" },
    { "skinn", "skinning" }, { "tailor", "tailoring" }, { "shadoweave", "tailoring" },
    { "cook", "cooking" }, { "chef", "cooking" }, { "fish", "fishing" },
    { "응급치료", "firstAid" }, { "연금술", "alchemy" }, { "대장장이", "blacksmithing" },
    { "마법부여", "enchanting" }, { "기술자", "engineering" }, { "약초", "herbalism" },
    { "가죽세공", "leatherworking" }, { "광부", "mining" }, { "채광", "mining" },
    { "무두", "skinning" }, { "재봉", "tailoring" }, { "요리", "cooking" }, { "낚시", "fishing" },
}

-- Class trainers: the round class crest
local CLASS_WORDS = {
    { "warrior", "WARRIOR" }, { "paladin", "PALADIN" }, { "hunter", "HUNTER" }, { "rogue", "ROGUE" },
    { "priest", "PRIEST" }, { "shaman", "SHAMAN" }, { "warlock", "WARLOCK" }, { "mage", "MAGE" },
    { "druid", "DRUID" },
    { "pet trainer", "HUNTER" }, { "demon trainer", "WARLOCK" }, { "portal trainer", "MAGE" },
    { "전사", "WARRIOR" }, { "성기사", "PALADIN" }, { "사냥꾼", "HUNTER" }, { "도적", "ROGUE" },
    { "사제", "PRIEST" }, { "주술사", "SHAMAN" }, { "흑마법사", "WARLOCK" }, { "마법사", "MAGE" },
    { "드루이드", "DRUID" }, { "악마 훈련사", "WARLOCK" },
}
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local CLASS_COORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 },             MAGE = { 0.25, 0.49609375, 0, 0.25 },
    ROGUE = { 0.49609375, 0.7421875, 0, 0.25 }, DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
    HUNTER = { 0, 0.25, 0.25, 0.5 },            SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
    PALADIN = { 0, 0.25, 0.5, 0.75 },
}

-----------------------------------------------------------------------------
-- Classification
-----------------------------------------------------------------------------
-- game NPC flags carried in the data
local F_FLIGHT, F_TRAINER, F_SPIRIT = 8, 16, 32
local F_INN, F_BANK, F_PETITION, F_TABARD = 128, 256, 512, 1024
local F_BATTLE, F_AUCTION, F_STABLE, F_REPAIR = 2048, 4096, 8192, 16384

local function hasFlag(flags, bit)
    return flags % (bit * 2) >= bit
end

local function has(text, ...)
    if not text or text == "" then return false end
    for i = 1, select("#", ...) do
        if find(text, (select(i, ...)), 1, true) then return true end
    end
    return false
end

local function wordIn(list, text)
    if not text or text == "" then return nil end
    for _, pair in ipairs(list) do
        if find(text, pair[1], 1, true) then return pair[2] end
    end
    return nil
end

local function classWord(text)
    if not text or text == "" then return nil end
    -- whole words, so "Mage" does not match "Image" or "Damage"
    local padded = " " .. text .. " "
    for _, pair in ipairs(CLASS_WORDS) do
        local w = pair[1]
        if w:byte(1) and w:byte(1) < 128 then
            if find(padded, "[^%a]" .. w .. "[^%a]") then return pair[2] end
        elseif find(text, w, 1, true) then
            return pair[2]
        end
    end
    return nil
end

local function localSubTitle(id)
    local tr = _G.EzWoWMapFinderTranslations
    local loc = ns.activeLocale
    local t = tr and loc and tr[loc] and tr[loc].subname
    local s = t and t[id]
    if (not s or s == "") and tr and tr.koKR and tr.koKR.subname then s = tr.koKR.subname[id] end
    return s
end

-- entry -> typeKey, detail (class token / profession key) or nil
function ServiceNpcPins.classify(e)
    if type(e) ~= "table" or not e.id then return nil end
    local name = e.names and e.names.enUS or ""
    if e.kind == "object" then
        if name == "Mailbox" then return "mailbox" end
        local tr = _G.EzWoWMapFinderTranslations
        local ko = tr and tr.koKR and tr.koKR.object and tr.koKR.object[e.id]
        if ko == "우체통" then return "mailbox" end
        return nil
    end
    if e.kind ~= "npc" then return nil end
    local flags = type(e.flags) == "number" and e.flags or 0
    local subRaw = _G.EzWoWMapFinderSubNames and _G.EzWoWMapFinderSubNames[e.id]
    local sub = subRaw and lower(subRaw) or ""
    local ko = (sub == "") and localSubTitle(e.id) or nil
    local lname = lower(name)

    if hasFlag(flags, F_AUCTION) or find(lname, "^auctioneer ") or has(sub, "auctioneer") or has(ko, "경매인") then
        return "auctioneer"
    end
    if hasFlag(flags, F_BANK) or has(sub, "banker") or has(ko, "은행원") then return "banker" end
    if (has(sub, "innkeeper") and not has(sub, "assistant")) or has(ko, "여관주인")
        or (hasFlag(flags, F_INN) and sub == "") then
        return "innkeeper"
    end
    if not has(sub, "spectral") and (hasFlag(flags, F_FLIGHT)
        or has(sub, "gryphon master", "wind rider master", "hippogryph master", "bat handler", "flight master")
        or has(ko, "그리핀 조련사", "와이번 조련사", "히포그리프 조련사", "박쥐 조련사", "비행 조련사")) then
        return "flight"
    end
    if hasFlag(flags, F_STABLE) or has(sub, "stable master") or has(ko, "야수 관리인") then return "stable" end
    if hasFlag(flags, F_BATTLE) or has(sub, "battlemaster", "battle master") or has(ko, "전투모병관") then
        return "battlemaster"
    end
    if hasFlag(flags, F_PETITION) or hasFlag(flags, F_TABARD) or has(sub, "guild master", "tabard")
        or has(ko, "길드 사무관", "길드 휘장") then
        return "guild"
    end
    if hasFlag(flags, F_SPIRIT) or lname == "spirit healer" or has(sub, "spirit healer") then return "spirit" end

    -- trainers: the flag when the data has flags, the title otherwise
    local trainerTitle = has(sub, "trainer") or find(sub, "^journeyman ") or find(sub, "^expert ")
        or find(sub, "^artisan ") or find(sub, "^master ") or has(ko, "상급 ", "수습 ", "숙련 ", "전문 ", "의 대가", "훈련사", "조련사")
    local isTrainer = hasFlag(flags, F_TRAINER) or (flags == 0 and trainerTitle)
        or has(sub, "demon trainer") or has(ko, "악마 훈련사")
    if isTrainer and not has(sub, "riding", "instructor", "*temp*") then
        local class = classWord(sub) or classWord(ko)
        if class then return "classTrainer", class end
        if has(sub, "weapon master") or has(ko, "무기 전문가") then return "classTrainer" end
        local prof = wordIn(PROFESSION_WORDS, sub) or wordIn(PROFESSION_WORDS, ko)
        if prof then return "profTrainer", prof end
    end

    -- vendors
    if has(sub, "general goods", "general supplies", "general goods vendor", "general & trade")
        or has(ko, "일용품") then
        return "general"
    end
    if has(sub, "food", "drink", "baker", "bread", "butcher", "meat vendor", "fruit", "bartender", "barmaid",
        "waitress", "grocer", "fish vendor", "fish merchant", "vintner", "wine vendor", "beverage", "cheese", "pie vendor")
        or has(ko, "식료품", "빵 상인", "고기 상인", "과일", "바텐더", "생선 상인", "푸줏간") then
        return "food"
    end
    if has(sub, "reagent") or has(ko, "마법 재료") then return "reagent" end
    local armsTitle = has(sub, "armor", "armorer", "weapon", "weaponsmith", "armorsmith", "blade", "bowyer", "gunsmith",
        "shield", "macecrafter", "axecrafter", "staff merchant", "staves", "clothier")
        or has(ko, "방어구", "무기", "갑옷")
    if not armsTitle and not has(sub, "festival", "holiday", "quartermaster", "supply officer")
        and (has(sub, "trade supplies", "trade goods", "trade supplier", "tradesman", "tradeswoman", "supplies", "supplier")
            or has(ko, "직업용품", "용품 상인", "재료 상인")) then
        return "trade"
    end
    if hasFlag(flags, F_REPAIR) or (flags == 0 and armsTitle and not has(sub, "quartermaster")) then
        return "repair"
    end
    return nil
end

-----------------------------------------------------------------------------
-- Indexes: service entries once, then one list per map (on first view)
-----------------------------------------------------------------------------
local serviceList     -- { { entry, typeKey, detail }, ... }
local mapCache = {}   -- mapID -> { { svc, spawn, mx, my }, ... }

function ServiceNpcPins.buildServiceList()
    if serviceList then return serviceList end
    serviceList = {}
    for _, e in ipairs(_G.EzWoWMapFinderData or {}) do
        if (e.kind == "npc" or e.kind == "object") and type(e.spawns) == "table" and e.spawns[1] then
            local ok, typeKey, detail = pcall(ServiceNpcPins.classify, e)
            if ok and typeKey then
                serviceList[#serviceList + 1] = { entry = e, typeKey = typeKey, detail = detail }
            end
        end
    end
    return serviceList
end

function ServiceNpcPins.spotsForMap(mapID)
    local cached = mapCache[mapID]
    if cached then return cached end
    local project = ns.ProjectSpawnToWorldMapCoords
    local list = {}
    if project then
        local bounds = ns.ZONE_BOUNDS_BY_ID and ns.ZONE_BOUNDS_BY_ID[mapID]
        local continent = bounds and bounds.mtype == 3 and bounds.mapID or nil
        for _, svc in ipairs(ServiceNpcPins.buildServiceList()) do
            for _, sp in ipairs(svc.entry.spawns) do
                -- spawns on another continent can't be on a known zone map
                if not continent or sp[1] == continent then
                    local ok, mapID2, mx, my = pcall(project, sp, mapID)
                    if ok and mapID2 == mapID and type(mx) == "number" and type(my) == "number" then
                        list[#list + 1] = { svc = svc, spawn = sp, mx = mx, my = my }
                    end
                end
            end
        end
    end
    mapCache[mapID] = list
    return list
end

-- "town" (city maps and small detail maps), "zone" (regular zone maps) or nil
local mapKindCache = {}
function ServiceNpcPins.mapKind(mapID)
    local cached = mapKindCache[mapID]
    if cached ~= nil then return cached or nil end
    local kind = false
    local bounds = ns.ZONE_BOUNDS_BY_ID and ns.ZONE_BOUNDS_BY_ID[mapID]
    if bounds then
        if bounds.isCity then kind = "town" elseif bounds.mtype == 3 then kind = "zone" end
    elseif C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        local mapType = ok and type(info) == "table" and info.mapType or nil
        if type(mapType) == "number" and not isSecret(mapType) then
            if mapType == 3 then
                kind = "zone"
            elseif mapType == 5 or mapType == 6 then
                kind = "town"
            end
        end
    end
    mapKindCache[mapID] = kind
    return kind or nil
end

local function typeEnabled(typeKey)
    local t = ns.DB and ns.DB.serviceNpcTypes
    return not (type(t) == "table" and t[typeKey] == false)
end
ServiceNpcPins.typeEnabled = typeEnabled

-----------------------------------------------------------------------------
-- Icons
-----------------------------------------------------------------------------
local profIconCache = {}
local function professionIcon(prof)
    local cached = profIconCache[prof]
    if cached then return cached end
    local info = PROFESSIONS[prof]
    if not info then return nil end
    local icon
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, info.spell)
        if ok and tex and not isSecret(tex) and (type(tex) == "number" or type(tex) == "string") then icon = tex end
    end
    if not icon and type(GetSpellTexture) == "function" then
        local ok, tex = pcall(GetSpellTexture, info.spell)
        if ok and tex and not isSecret(tex) then icon = tex end
    end
    icon = icon or info.icon
    profIconCache[prof] = icon
    return icon
end

-- texture, texcoords (or nil), round crop?
local function iconFor(typeKey, detail)
    local t = TYPE_BY_KEY[typeKey]
    if typeKey == "classTrainer" and detail then
        local coords = (type(_G.CLASS_ICON_TCOORDS) == "table" and _G.CLASS_ICON_TCOORDS[detail]) or CLASS_COORDS[detail]
        if coords then return CLASS_CIRCLES, coords, false end
    elseif typeKey == "profTrainer" and detail then
        local icon = professionIcon(detail)
        if icon then return icon, nil, true end
    end
    return t.tex, nil, t.round
end

-----------------------------------------------------------------------------
-- Pins
-----------------------------------------------------------------------------
local pins = {}

local function canvas()
    return (WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas())
        or (_G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock:GetCanvas())
        or WorldMapFrame
end

local function typeLabel(typeKey)
    return L["serviceType_" .. typeKey] or typeKey
end
ServiceNpcPins.typeLabel = typeLabel

local function showTooltip(self)
    local group = self.group
    if not group then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local t = TYPE_BY_KEY[group.typeKey]
    GameTooltip:SetText(typeLabel(group.typeKey), t.color[1], t.color[2], t.color[3])
    for index, svc in ipairs(group.list) do
        if index > TOOLTIP_MAX_NAMES then
            GameTooltip:AddLine(string.format(L.serviceNpcMore or "+%d more", #group.list - TOOLTIP_MAX_NAMES), unpack(Theme.muted))
            break
        end
        local e = svc.entry
        local nameText = ns.GetLocalizedEntityName and ns.GetLocalizedEntityName(e) or (e.names and e.names.enUS) or ""
        local title = e.kind == "npc" and ns.GetLocalizedEntitySubtitle and ns.GetLocalizedEntitySubtitle(e) or nil
        if title and title ~= "" then
            GameTooltip:AddDoubleLine(nameText, "<" .. title .. ">", 0.929, 0.957, 0.969, 0.655, 0.725, 0.773)
        else
            GameTooltip:AddLine(nameText, 0.929, 0.957, 0.969)
        end
    end
    GameTooltip:AddLine(L.serviceNpcHint or "Click: set waypoint", unpack(Theme.muted))
    GameTooltip:AddDoubleLine(" ", "EzWoW - Map Finder", 0, 0, 0, 0.5, 0.5, 0.5)
    GameTooltip:Show()
    if _G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.Refit then pcall(_G.EzWoWTooltipTagSizer.Refit, GameTooltip) end
end

local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function obtainPin(index)
    local pin = pins[index]
    if pin then return pin end
    pin = CreateFrame("Button", nil, canvas())
    pin:EnableMouse(true)
    pin:RegisterForClicks("LeftButtonUp")
    setPropagateClicks(pin, false)
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    pin:SetFrameStrata("HIGH")
    pin.rim = pin:CreateTexture(nil, "BACKGROUND", nil, 0)
    pin.rim:SetTexture(DISC)
    pin.rim:SetPoint("CENTER")
    pin.rim:SetSize(PIN_SIZE + 1, PIN_SIZE + 1)
    pin.back = pin:CreateTexture(nil, "BACKGROUND", nil, 1)
    pin.back:SetTexture(DISC)
    pin.back:SetPoint("CENTER")
    pin.back:SetSize(PIN_SIZE - 1, PIN_SIZE - 1)
    pin.back:SetVertexColor(0.06, 0.06, 0.06, 0.85)
    -- plain icon (tracking textures, class crests)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetPoint("CENTER")
    pin.icon:SetSize(PIN_SIZE - 1, PIN_SIZE - 1)
    -- square spell / item icons, cropped round
    pin.round = pin:CreateTexture(nil, "ARTWORK")
    pin.round:SetPoint("CENTER")
    pin.round:SetSize(PIN_SIZE - 3, PIN_SIZE - 3)
    if pin.CreateMaskTexture and pin.round.AddMaskTexture then
        local mask = pin:CreateMaskTexture()
        mask:SetTexture(DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(pin.round)
        pin.round:AddMaskTexture(mask)
    end
    pin:SetScript("OnEnter", showTooltip)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:HookScript("OnEnter", raisePin)
    pin:HookScript("OnLeave", lowerPin)
    pin:SetScript("OnClick", function(self)
        local sp = self.group and self.group.spawn
        if sp and ns.ApplyWaypointForSpawn then ns.ApplyWaypointForSpawn(sp) end
    end)
    if ns.PassMapRightClicks then ns.PassMapRightClicks(pin) end
    pins[index] = pin
    return pin
end

local function paintPin(pin, group)
    local t = TYPE_BY_KEY[group.typeKey]
    local tex, coords, round = iconFor(group.typeKey, group.detail)
    pin.rim:SetVertexColor(t.color[1], t.color[2], t.color[3], 0.95)
    local target, other = pin.icon, pin.round
    if round then target, other = pin.round, pin.icon end
    other:Hide()
    local ok, loaded = pcall(target.SetTexture, target, tex)
    if ok and loaded ~= false then
        if coords then
            target:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        elseif round then
            target:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            target:SetTexCoord(0, 1, 0, 1)
        end
        target:Show()
        pin.back:SetVertexColor(0.06, 0.06, 0.06, 0.85)
    else
        -- texture missing on this client: a plain coloured dot
        target:Hide()
        pin.back:SetVertexColor(t.color[1], t.color[2], t.color[3], 1)
    end
end

function ServiceNpcPins.hideAll()
    for _, pin in ipairs(pins) do pin:Hide() end
end

local function anchorPin(pin, canvasFrame, cw, ch, cScale)
    local group = pin.group
    local pinScale = zoomGrow(cScale) / cScale
    pin:SetScale(pinScale)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvasFrame, "TOPLEFT", group.mx * cw / pinScale, -group.my * ch / pinScale)
end

local function canvasMetrics()
    local canvasFrame = canvas()
    if not canvasFrame then return nil end
    local cw, ch = canvasFrame:GetWidth(), canvasFrame:GetHeight()
    if not cw or not ch or cw <= 0 or ch <= 0 then return nil end
    local cScale = (WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()) or 1
    if not cScale or cScale <= 0 then cScale = 1 end
    return canvasFrame, cw, ch, cScale
end

function ServiceNpcPins.refresh()
    ServiceNpcPins.hideAll()
    if not (ns.DB and ns.DB.serviceNpcPins ~= false) then return end
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if not mapID or isSecret(mapID) then return end
    local kind = ServiceNpcPins.mapKind(mapID)
    if not kind or (kind == "zone" and ns.DB.serviceNpcPinsZones ~= true) then return end
    local canvasFrame, cw, ch, cScale = canvasMetrics()
    if not canvasFrame then return end

    -- icons of one type closer than MERGE_PIXELS on screen share one icon
    local groups = {}
    local limit = MERGE_PIXELS / cScale
    for _, spot in ipairs(ServiceNpcPins.spotsForMap(mapID)) do
        local svc = spot.svc
        if typeEnabled(svc.typeKey) then
            local px, py = spot.mx * cw, spot.my * ch
            local group
            for _, g in ipairs(groups) do
                if g.typeKey == svc.typeKey and g.detail == svc.detail
                    and math.abs(g.px - px) < limit and math.abs(g.py - py) < limit then
                    group = g
                    break
                end
            end
            if not group then
                group = { typeKey = svc.typeKey, detail = svc.detail, px = px, py = py, mx = spot.mx, my = spot.my,
                    spawn = spot.spawn, list = {}, seen = {} }
                groups[#groups + 1] = group
            end
            if not group.seen[svc] then
                group.seen[svc] = true
                group.list[#group.list + 1] = svc
            end
        end
    end

    local baseLevel = canvasFrame:GetFrameLevel() or 10
    for index, group in ipairs(groups) do
        local pin = obtainPin(index)
        pin:SetParent(canvasFrame)
        -- below the quest marks (190-200) so those stay on top
        pin:SetFrameLevel(baseLevel + 150 + (TYPE_BY_KEY[group.typeKey].order or 0))
        pin.group = group
        paintPin(pin, group)
        anchorPin(pin, canvasFrame, cw, ch, cScale)
        pin:Show()
    end
end

-- zoom: keep the on-screen size at once, regroup once zooming stops
local regroupPending = false
local lastRescaleAt = 0
local REGROUP_DELAY = 0.3

local function regroupWhenSettled()
    local waited = GetTime() - lastRescaleAt
    if waited < REGROUP_DELAY then
        C_Timer.After(REGROUP_DELAY - waited, regroupWhenSettled)
        return
    end
    regroupPending = false
    ServiceNpcPins.refresh()
end

function ServiceNpcPins.rescale()
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    local canvasFrame, cw, ch, cScale = canvasMetrics()
    if not canvasFrame then return end
    local any = false
    for _, pin in ipairs(pins) do
        if pin:IsShown() and pin.group then
            anchorPin(pin, canvasFrame, cw, ch, cScale)
            any = true
        end
    end
    if not any then return end
    lastRescaleAt = GetTime()
    if not regroupPending and C_Timer and C_Timer.After then
        regroupPending = true
        C_Timer.After(REGROUP_DELAY, regroupWhenSettled)
    end
end

ns.RefreshServiceNpcPins = ServiceNpcPins.refresh
ns.RescaleServiceNpcPins = ServiceNpcPins.rescale

-----------------------------------------------------------------------------
-- Herb and ore spots: the places where herbs and ore veins can grow, for the
-- gathering skills this character has. Bright icons on the minimap (nearby)
-- and on zone maps; skill too low: dimmed. A spot is a place where a node can
-- appear, not a node that is there now.
-----------------------------------------------------------------------------
local GatherPins = {}
ns.GatherPins = GatherPins

local HERB_ICON = "Interface\\Icons\\INV_Misc_Flower_02"
local ORE_ICON = "Interface\\Icons\\INV_Ore_Copper_01"
local HERB_COLOR = { 0.38, 0.95, 0.55 }
local ORE_COLOR = { 1.00, 0.78, 0.35 }
local GATHER_MAP_SIZE = 12
local GATHER_MINI_SIZE = 14
local MAX_GATHER_MAP = 500
local MAX_GATHER_MINI = 40
local BUCKET = 250                 -- yards per grid cell for the nearby search
local MINI_OUTDOOR = { [0] = 466 + 2/3, 400, 333 + 1/3, 266 + 2/3, 200, 133 + 1/3 }
local MINI_INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

local function gatherOn()
    return ns.DB and ns.DB.gatherPins ~= false
end

-- gathering skills of this character: { herb = rank or nil, ore = rank or nil }
local skills = { herb = nil, ore = nil }
local function readSkills()
    skills.herb, skills.ore = nil, nil
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local list = { pcall(GetProfessions) }
        for i = 2, #list do
            local index = list[i]
            if type(index) == "number" then
                local ok, _, _, rank, _, _, _, skillLine = pcall(GetProfessionInfo, index)
                if ok then
                    if skillLine == 182 then skills.herb = tonumber(rank) or 1 end
                    if skillLine == 186 then skills.ore = tonumber(rank) or 1 end
                end
            end
        end
    end
    if not skills.herb and not skills.ore and type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
        for i = 1, GetNumSkillLines() do
            local ok, name, _, _, rank = pcall(GetSkillLineInfo, i)
            if ok and type(name) == "string" then
                local n = name:lower()
                if n == "약초채집" or n == "herbalism" then skills.herb = tonumber(rank) or 1 end
                if n == "채광" or n == "mining" then skills.ore = tonumber(rank) or 1 end
            end
        end
    end
end

-- every spot once: { kind = "herb"/"ore", need = skill, entry, spawn [, shared] }, by continent and grid cell
local spotsByContinent
local SHARED_SAME = 10             -- yards: a shared spot this close to a known one is the same place

local function addSpot(continent, x, y, spot)
    local grid = spotsByContinent[continent]
    if not grid then grid = {}; spotsByContinent[continent] = grid end
    local key = math.floor(x / BUCKET) .. ":" .. math.floor(y / BUCKET)
    local cell = grid[key]
    if not cell then cell = {}; grid[key] = cell end
    cell[#cell + 1] = spot
end

local function knownNear(continent, x, y)
    local grid = spotsByContinent[continent]
    if not grid then return false end
    local bx, by = math.floor(x / BUCKET), math.floor(y / BUCKET)
    for dx = -1, 1 do
        for dy = -1, 1 do
            local cell = grid[(bx + dx) .. ":" .. (by + dy)]
            if cell then
                for _, s in ipairs(cell) do
                    local ex, ey = s.spawn[2] - x, s.spawn[3] - y
                    if ex * ex + ey * ey <= SHARED_SAME * SHARED_SAME then return true end
                end
            end
        end
    end
    return false
end

local function buildSpots()
    if spotsByContinent then return end
    spotsByContinent = {}
    local herbs, ores = ns.HERB_SKILL_BY_OBJECT or {}, ns.MINE_SKILL_BY_OBJECT or {}
    local entryByID = {}
    for _, e in ipairs(_G.EzWoWMapFinderData or {}) do
        if e.kind == "object" and e.id and type(e.spawns) == "table" then
            local kind, need
            if herbs[e.id] then kind, need = "herb", herbs[e.id]
            elseif ores[e.id] then kind, need = "ore", ores[e.id] end
            if kind then
                entryByID[e.id] = entryByID[e.id] or e
                for _, sp in ipairs(e.spawns) do
                    local continent, x, y = sp[1], sp[2], sp[3]
                    if type(continent) == "number" and continent >= 0 and type(x) == "number" and type(y) == "number" then
                        addSpot(continent, x, y, { kind = kind, need = need, entry = e, spawn = sp })
                    end
                end
            end
        end
    end
    -- places other players of the EzWoW addons (and this character) gathered
    -- herbs and ore that the built-in data does not have (Libs/EzWoWShare)
    local share = ns.Share
    local gather = share and share.Data and share.Data().gather
    if type(gather) ~= "table" then return end
    for objectID, spots in pairs(gather) do
        local kind, need
        if herbs[objectID] then kind, need = "herb", herbs[objectID]
        elseif ores[objectID] then kind, need = "ore", ores[objectID] end
        local e = kind and entryByID[objectID]
        if e and type(spots) == "table" then
            for _, sp in ipairs(spots) do
                local continent, x, y = sp[1], sp[2], sp[3]
                if type(continent) == "number" and type(x) == "number" and type(y) == "number"
                    and not knownNear(continent, x, y) then
                    addSpot(continent, x, y, { kind = kind, need = need, entry = e, spawn = sp, shared = true })
                end
            end
        end
    end
end

-- new shared places: rebuilt on the next refresh
if ns.Share and ns.Share.RegisterCallback then
    ns.Share.RegisterCallback("EzWoW-MapFinder-Gather", function(kinds)
        if type(kinds) ~= "table" or not kinds.gather then return end
        spotsByContinent = nil
        if WorldMapFrame and WorldMapFrame:IsShown() and GatherPins.refresh then pcall(GatherPins.refresh) end
    end)
end

local function wanted(spot)
    local rank = skills[spot.kind]
    if not rank then return false end
    return true, rank >= (spot.need or 1)
end

local function spotName(spot)
    return (ns.GetLocalizedEntityName and ns.GetLocalizedEntityName(spot.entry)) or (spot.entry.names and spot.entry.names.enUS) or "?"
end

local function showGatherTooltip(self)
    local list = self.spots
    if not list or #list == 0 then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local first = list[1]
    local c = first.kind == "herb" and HERB_COLOR or ORE_COLOR
    GameTooltip:SetText(spotName(first), c[1], c[2], c[3])
    local seen = { [spotName(first)] = true }
    for i = 2, math.min(#list, 6) do
        local name = spotName(list[i])
        if not seen[name] then seen[name] = true; GameTooltip:AddLine(name, c[1], c[2], c[3]) end
    end
    local skillName = first.kind == "herb" and (L.herbSkill or "Herbalism") or (L.mineSkill or "Mining")
    local ok = (skills[first.kind] or 0) >= (first.need or 1)
    GameTooltip:AddLine(string.format("%s %d", skillName, first.need or 1), ok and 0.6 or 1, ok and 0.9 or 0.4, ok and 0.6 or 0.4)
    GameTooltip:AddLine(L.gatherSpotHint or "A place where it can grow (not always there)", unpack(Theme.muted))
    if first.shared then
        GameTooltip:AddLine(L.gatherShared or "Gathered here by an EzWoW user", 0.6, 0.8, 1)
    end
    GameTooltip:AddDoubleLine(" ", "EzWoW - Map Finder", 0, 0, 0, 0.5, 0.5, 0.5)
    GameTooltip:Show()
    if _G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.Refit then pcall(_G.EzWoWTooltipTagSizer.Refit, GameTooltip) end
end

local function paintGather(pin, spot, size)
    local can = select(2, wanted(spot))
    local c = spot.kind == "herb" and HERB_COLOR or ORE_COLOR
    pin:SetSize(size, size)
    pin.rim:SetSize(size + 2, size + 2)
    pin.rim:SetVertexColor(c[1], c[2], c[3], can and 1 or 0.5)
    pin.icon:SetSize(size - 2, size - 2)
    pin.icon:SetTexture(spot.kind == "herb" and HERB_ICON or ORE_ICON)
    pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pin.icon:SetDesaturated(not can)
    pin:SetAlpha(can and 1 or 0.55)
end

local function newGatherPin(parent)
    local pin = CreateFrame("Frame", nil, parent)
    pin.rim = pin:CreateTexture(nil, "BACKGROUND")
    pin.rim:SetTexture(DISC)
    pin.rim:SetPoint("CENTER")
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetPoint("CENTER")
    if pin.CreateMaskTexture and pin.icon.AddMaskTexture then
        local mask = pin:CreateMaskTexture()
        mask:SetTexture(DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(pin.icon)
        pin.icon:AddMaskTexture(mask)
    end
    pin:EnableMouse(true)
    setPropagateClicks(pin, true)
    pin:SetScript("OnEnter", showGatherTooltip)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:HookScript("OnEnter", raisePin)
    pin:HookScript("OnLeave", lowerPin)
    pin:Hide()
    return pin
end

-- World map (zone maps): every spot inside the map's bounds
local mapPins = {}
function GatherPins.hideMap() for _, pin in ipairs(mapPins) do pin:Hide() end end

function GatherPins.refresh()
    GatherPins.hideMap()
    if not gatherOn() or not (skills.herb or skills.ore) then return end
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if not mapID or isSecret(mapID) then return end
    local bounds = ns.ZONE_BOUNDS_BY_ID and ns.ZONE_BOUNDS_BY_ID[mapID]
    if not (bounds and bounds.mtype == 3) then return end
    local canvasFrame, cw, ch, cScale = canvasMetrics()
    if not canvasFrame then return end
    buildSpots()
    local grid = spotsByContinent[bounds.mapID]
    if not grid then return end
    local count = 0
    local merged = {}
    local limit = 10 / cScale
    local baseLevel = canvasFrame:GetFrameLevel() or 10
    for _, cell in pairs(grid) do
        for _, spot in ipairs(cell) do
            local x, y = spot.spawn[2], spot.spawn[3]
            if x >= bounds.xMin and x <= bounds.xMax and y >= bounds.yMin and y <= bounds.yMax and wanted(spot) then
                local mx = (bounds.yMax - y) / (bounds.yMax - bounds.yMin)
                local my = (bounds.xMax - x) / (bounds.xMax - bounds.xMin)
                local px, py = mx * cw, my * ch
                local key = spot.kind .. ":" .. math.floor(px / limit) .. ":" .. math.floor(py / limit)
                local pin = merged[key]
                if pin then
                    pin.spots[#pin.spots + 1] = spot
                elseif count < MAX_GATHER_MAP then
                    count = count + 1
                    pin = mapPins[count]
                    if not pin then pin = newGatherPin(canvasFrame); mapPins[count] = pin end
                    pin:SetParent(canvasFrame)
                    pin:SetFrameLevel(baseLevel + 140)
                    pin.spots = { spot }
                    pin.px, pin.py = px, py
                    paintGather(pin, spot, GATHER_MAP_SIZE)
                    pin:SetScale(zoomGrow(cScale) / cScale)
                    pin:ClearAllPoints()
                    pin:SetPoint("CENTER", canvasFrame, "TOPLEFT", px / pin:GetScale(), -py / pin:GetScale())
                    pin:Show()
                    merged[key] = pin
                end
            end
        end
    end
end

function GatherPins.rescale()
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    local canvasFrame, _, _, cScale = canvasMetrics()
    if not canvasFrame then return end
    for _, pin in ipairs(mapPins) do
        if pin:IsShown() and pin.px then
            pin:SetScale(zoomGrow(cScale) / cScale)
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", canvasFrame, "TOPLEFT", pin.px / pin:GetScale(), -pin.py / pin:GetScale())
        end
    end
end

-- Minimap: spots near the player, placed by yards from the player
local miniPins = {}
local function hideMini() for _, pin in ipairs(miniPins) do pin:Hide() end end

local function playerWorld()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then return nil end
    local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not okMap or type(mapID) ~= "number" or isSecret(mapID) then return nil end
    local okPos, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not okPos or not pos then return nil end
    local okWorld, continent, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, pos)
    if not okWorld or type(continent) ~= "number" or type(world) ~= "table" then return nil end
    local x, y = world.x, world.y
    if type(x) ~= "number" or type(y) ~= "number" or isSecret(x) or isSecret(y) then return nil end
    return continent, x, y
end

local function miniRadius()
    if C_Minimap and C_Minimap.GetViewRadius then
        local ok, r = pcall(C_Minimap.GetViewRadius)
        if ok and type(r) == "number" and not isSecret(r) and r > 0 then return r end
    end
    local zoom = Minimap and Minimap.GetZoom and Minimap:GetZoom()
    if type(zoom) ~= "number" or isSecret(zoom) then return nil end
    local indoors = type(IsIndoors) == "function" and IsIndoors() == true
    return (indoors and MINI_INDOOR or MINI_OUTDOOR)[zoom]
end

function GatherPins.updateMinimap()
    if not (Minimap and gatherOn() and (skills.herb or skills.ore)) then hideMini() return end
    if type(IsInInstance) == "function" and IsInInstance() then hideMini() return end
    local continent, px, py = playerWorld()
    local radius = miniRadius()
    if not (continent and radius) then hideMini() return end
    buildSpots()
    local grid = spotsByContinent[continent]
    if not grid then hideMini() return end
    local getCVar = (C_CVar and C_CVar.GetCVar) or (type(GetCVar) == "function" and GetCVar) or nil
    local okCVar, rotateValue = false, nil
    if getCVar then okCVar, rotateValue = pcall(getCVar, "rotateMinimap") end
    local rotate = okCVar and rotateValue == "1"
    local facing = 0
    if rotate then
        facing = type(GetPlayerFacing) == "function" and GetPlayerFacing() or nil
        if type(facing) ~= "number" or isSecret(facing) then hideMini() return end
    end
    local cf, sf = math.cos(facing), math.sin(facing)
    local halfW = (Minimap:GetWidth() or 0) / 2
    if halfW <= 0 then hideMini() return end
    local scale = halfW / radius
    local limit = radius * 0.92
    local count = 0
    local cx, cy = math.floor(px / BUCKET), math.floor(py / BUCKET)
    local reach = math.ceil(limit / BUCKET)
    for gx = cx - reach, cx + reach do
        for gy = cy - reach, cy + reach do
            local cell = grid[gx .. ":" .. gy]
            if cell then
                for _, spot in ipairs(cell) do
                    if count >= MAX_GATHER_MINI then break end
                    -- world x grows to the north, y to the west
                    local north, east = spot.spawn[2] - px, py - spot.spawn[3]
                    if north * north + east * east <= limit * limit and wanted(spot) then
                        local ex, ny = east, north
                        if rotate then
                            ex = east * cf + north * sf
                            ny = -east * sf + north * cf
                        end
                        count = count + 1
                        local pin = miniPins[count]
                        if not pin then
                            pin = newGatherPin(Minimap)
                            pin:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 4)
                            miniPins[count] = pin
                        end
                        pin.spots = { spot }
                        paintGather(pin, spot, GATHER_MINI_SIZE)
                        pin:ClearAllPoints()
                        pin:SetPoint("CENTER", Minimap, "CENTER", ex * scale, ny * scale)
                        pin:Show()
                    end
                end
            end
        end
    end
    for i = count + 1, #miniPins do miniPins[i]:Hide() end
end

local gatherDriver = CreateFrame("Frame")
local gatherElapsed = 0
gatherDriver:SetScript("OnUpdate", function(_, elapsed)
    gatherElapsed = gatherElapsed + (elapsed or 0)
    if gatherElapsed < 0.2 then return end
    gatherElapsed = 0
    pcall(GatherPins.updateMinimap)
end)
for _, event in ipairs({ "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE", "LEARNED_SPELL_IN_TAB" }) do
    pcall(gatherDriver.RegisterEvent, gatherDriver, event)
end
gatherDriver:SetScript("OnEvent", function()
    pcall(readSkills)
    if WorldMapFrame and WorldMapFrame:IsShown() then pcall(GatherPins.refresh) end
end)


-----------------------------------------------------------------------------
-- Gathering helpers (on by default, for characters with a gathering skill):
--  * the game's own icon over the nearest herb / vein / chest in front
--    (interact icons); the player's own values come back when turned off
--  * Find Herbs (or Find Minerals) minimap tracking switched on at login and
--    after coming back to life (it is lost on death). Turning it off by hand
--    is left alone until the next login or death.
-----------------------------------------------------------------------------
local INTERACT_CVARS = {
    SoftTargetInteract = "3",
    SoftTargetIconInteract = "1",
    SoftTargetIconGameObject = "1",
    SoftTargetInteractRange = "30",
}
local TRACK_SPELL = { herb = 2383, ore = 2580 }   -- Find Herbs, Find Minerals

local function cvarGet(name)
    local fn = (C_CVar and C_CVar.GetCVar) or (type(GetCVar) == "function" and GetCVar) or nil
    if not fn then return nil end
    local ok, v = pcall(fn, name)
    return ok and type(v) == "string" and v or nil
end
local function cvarSet(name, value)
    local fn = (C_CVar and C_CVar.SetCVar) or (type(SetCVar) == "function" and SetCVar) or nil
    if fn then pcall(fn, name, value) end
end

function GatherPins.applyInteractIcons()
    if not ns.DB or (InCombatLockdown and InCombatLockdown()) then return end
    if type(ns.DB.gatherCVarBackup) ~= "table" then ns.DB.gatherCVarBackup = {} end
    local backup = ns.DB.gatherCVarBackup
    local on = ns.DB.gatherInteractIcons ~= false and (skills.herb or skills.ore) and true or false
    for name, want in pairs(INTERACT_CVARS) do
        local current = cvarGet(name)
        if current ~= nil then
            if on then
                if backup[name] == nil then backup[name] = current end
                if current ~= want then cvarSet(name, want) end
            elseif backup[name] ~= nil then
                if current ~= backup[name] then cvarSet(name, backup[name]) end
                backup[name] = nil
            end
        end
    end
end

local function trackingEntry(index)
    local a, b, c, d, e, f = C_Minimap.GetTrackingInfo(index)
    if type(a) == "table" then return a.name, a.active, a.spellID end
    -- older form: name, texture, active, category, nested, spellID
    return a, c, f
end

function GatherPins.autoTrack()
    if not (ns.DB and ns.DB.gatherAutoTrack ~= false) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo and C_Minimap.SetTracking) then return end
    local spellID = (skills.herb and TRACK_SPELL.herb) or (skills.ore and TRACK_SPELL.ore)
    if not spellID then return end
    local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    local okCount, count = pcall(C_Minimap.GetNumTrackingTypes)
    for index = 1, (okCount and tonumber(count)) or 0 do
        local ok, name, active, id = pcall(trackingEntry, index)
        if ok and (id == spellID or (spellName and name == spellName)) then
            if not active then pcall(C_Minimap.SetTracking, index, true) end
            return
        end
    end
end

local helperEvents = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_UNGHOST", "PLAYER_ALIVE", "PLAYER_REGEN_ENABLED", "SKILL_LINES_CHANGED" }) do
    pcall(helperEvents.RegisterEvent, helperEvents, event)
end
local trackedOnce = false
helperEvents:SetScript("OnEvent", function(_, event)
    pcall(readSkills)
    if event == "PLAYER_REGEN_ENABLED" then
        -- settings asked for during combat
        pcall(GatherPins.applyInteractIcons)
        return
    end
    pcall(GatherPins.applyInteractIcons)
    if event == "PLAYER_ENTERING_WORLD" then
        if trackedOnce then return end   -- only the first loading screen of a session
        trackedOnce = true
    end
    if event == "SKILL_LINES_CHANGED" then return end
    -- the tracking list fills a moment after the loading screen
    if C_Timer and C_Timer.After then
        C_Timer.After(3, function() pcall(GatherPins.autoTrack) end)
    else
        pcall(GatherPins.autoTrack)
    end
end)

ns.RefreshServiceNpcPins = function()
    ServiceNpcPins.refresh()
    pcall(GatherPins.refresh)
end
ns.RescaleServiceNpcPins = function()
    ServiceNpcPins.rescale()
    pcall(GatherPins.rescale)
end
