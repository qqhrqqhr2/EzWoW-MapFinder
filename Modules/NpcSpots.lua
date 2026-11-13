--===========================================================================
-- EzWoW - Map Finder
-- Modules/NpcSpots.lua : NPC and monster spots checked in the game
--===========================================================================
-- NPCs: when the player talks to an NPC (dialog, shop, trainer, flight
-- master, bank...), the player stands next to it. An NPC the data doesn't
-- have, or has only far from there (moved on this server, or one that walks
-- around), is noted with that spot. The latest spot is the one shown: an NPC
-- with a single spot in the data is shown there only, one with several (the
-- same NPC standing in many places) gets it in front of the others.
-- Monsters: a corpse looted is where that monster was. Spots the data lacks
-- (nothing within MOB_GAP yards) are collected, several per monster, and
-- shown together with the data's spots.
-- Objects (chests, boxes, herbs, veins...): where EzWoW users looted them
-- (the shared gather records) are added to the object's spots the same way.
-- Rare monsters: where they were seen (shared sightings) is kept and added to
-- their spots like a looted monster's.
-- NPC and monster spots are shared with the other EzWoW users (record kind "N":
-- "npcID,continent,x,y,flags"; flags 0 = monster) and shipped with the addon
-- (Database/ShareSeed.lua, "npcs"). An NPC the data lacks gets an entry of
-- its own (its name comes from the name tables by ID).
local _, ns = ...

local KIND = "N"
local FAR = 30          -- yards: an NPC farther than this from every data spot is noted
local SAME = 15         -- yards: reports this close are the same spot
local MOB_GAP = 60      -- yards: a monster spot this far from every known spot is a new one
local MAX_MOB_SPOTS = 8 -- monster spots kept per monster (own and from others each)
local MAX_PEER_SPOTS = 4
local MAX_VOTERS = 8
local OBJ_GAP = 20      -- yards: an object spot this far from every known spot is a new one
local MAX_RARE_SEEN = 8 -- sighting spots kept per rare monster

local isSecret = _G.issecretvalue or function() return false end

local NpcSpots = {}
ns.NpcSpots = NpcSpots

local function share()
    return ns.Share
end

local function store()
    local s = share()
    if not (s and type(s.Store) == "function") then return nil end
    local ok, t = pcall(s.Store, KIND)
    return ok and type(t) == "table" and t or nil
end

local function near(a, b, yards)
    if type(a) ~= "table" or type(b) ~= "table" or a[1] ~= b[1] then return false end
    local ax, ay, bx, by = tonumber(a[2]), tonumber(a[3]), tonumber(b[2]), tonumber(b[3])
    if not (ax and ay and bx and by) then return false end
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy <= yards * yards
end

local function nearAny(list, spot, yards)
    for _, sp in ipairs(type(list) == "table" and list or {}) do
        if near(sp, spot, yards) then return true end
    end
    return false
end

local function validSpot(sp)
    return type(sp) == "table" and tonumber(sp[1]) and tonumber(sp[2]) and tonumber(sp[3]) and true or false
end

-----------------------------------------------------------------------------
-- The data's NPC entries by ID (with their own spots kept apart)
-----------------------------------------------------------------------------
local byID, objByID

local function buildIndex()
    byID, objByID = {}, {}
    for _, e in ipairs(_G.EzWoWMapFinderData or {}) do
        if type(e) == "table" and type(e.id) == "number" then
            if e.kind == "npc" and not byID[e.id] then
                byID[e.id] = e
            elseif e.kind == "object" and not objByID[e.id] then
                objByID[e.id] = e
            end
        end
    end
end

local function npcIndex()
    if not byID then buildIndex() end
    return byID
end

local function objectIndex()
    if not objByID then buildIndex() end
    return objByID
end

-- the spots the data itself has for this entry (before anything was put in)
local function dataSpots(entry)
    if type(entry) ~= "table" then return {} end
    if not entry.dataSpawns then
        local list = {}
        for _, sp in ipairs(type(entry.spawns) == "table" and entry.spawns or {}) do list[#list + 1] = sp end
        entry.dataSpawns = list
    end
    return entry.dataSpawns
end

local function entryFor(npcID, flags)
    local index = npcIndex()
    local entry = index[npcID]
    if entry then return entry end
    local data = _G.EzWoWMapFinderData
    if type(data) ~= "table" then return nil end
    entry = { id = npcID, kind = "npc", names = {}, flags = tonumber(flags) or 1, spawns = {} }
    data[#data + 1] = entry
    index[npcID] = entry
    return entry
end

local function copySpot(sp)
    return { tonumber(sp[1]), tonumber(sp[2]), tonumber(sp[3]), 0 }
end

-----------------------------------------------------------------------------
-- What is shown
-----------------------------------------------------------------------------
-- spots learned for one ID: { latest = spot (NPC), mobs = { spots } }
local learned = {}

-- the entry's spawns again from the data's spots and the learned ones
local function rebuild(npcID)
    local info = learned[npcID]
    if not info then return end
    local entry = entryFor(npcID, info.flags)
    if not entry then return end
    local base = dataSpots(entry)
    local list = {}
    if info.mob then
        for _, sp in ipairs(base) do list[#list + 1] = sp end
        for _, sp in ipairs(info.mobs or {}) do
            if not nearAny(list, sp, MOB_GAP) then list[#list + 1] = copySpot(sp) end
        end
    elseif info.latest then
        list[1] = copySpot(info.latest)
        -- one NPC in many places (guards, vendors of a kind): the others stay
        if #base > 1 then
            for _, sp in ipairs(base) do
                if not near(sp, info.latest, SAME) then list[#list + 1] = sp end
            end
        end
    else
        for _, sp in ipairs(base) do list[#list + 1] = sp end
    end
    entry.spawns = list
end

local function learnLatest(npcID, spot, flags)
    if not (type(npcID) == "number" and validSpot(spot)) then return end
    local info = learned[npcID] or {}
    learned[npcID] = info
    if info.mob then return end
    info.latest = spot
    info.flags = info.flags or flags
    rebuild(npcID)
end

local function learnMob(npcID, spot)
    if not (type(npcID) == "number" and validSpot(spot)) then return end
    local info = learned[npcID] or {}
    learned[npcID] = info
    info.mob = true
    info.flags = 0
    info.latest = nil
    info.mobs = info.mobs or {}
    if nearAny(info.mobs, spot, MOB_GAP) then return end
    info.mobs[#info.mobs + 1] = spot
    rebuild(npcID)
end

-- objects: spots added to the data's (objects the data lacks are left out:
-- their names are not known here)
local learnedObjects = {}

local function learnObject(objectID, spot)
    if not (type(objectID) == "number" and validSpot(spot)) then return end
    local entry = objectIndex()[objectID]
    if not entry then return end
    local base = dataSpots(entry)
    if nearAny(base, spot, OBJ_GAP) then return end
    local list = learnedObjects[objectID] or {}
    learnedObjects[objectID] = list
    if nearAny(list, spot, OBJ_GAP) then return end
    list[#list + 1] = spot
    local spawns = {}
    for _, sp in ipairs(base) do spawns[#spawns + 1] = sp end
    for _, sp in ipairs(list) do spawns[#spawns + 1] = copySpot(sp) end
    entry.spawns = spawns
end

function NpcSpots.ApplyGather()
    local s = share()
    if not s then return end
    local okData, data = pcall(s.Data)
    local gather = okData and type(data) == "table" and data.gather
    for objectID, spots in pairs(type(gather) == "table" and gather or {}) do
        if type(objectID) == "number" and type(spots) == "table" then
            for _, sp in ipairs(spots) do learnObject(objectID, sp) end
        end
    end
    local seed = type(s.Seed) == "function" and s.Seed("gather")
    for objectID, spots in pairs(type(seed) == "table" and seed or {}) do
        if type(objectID) == "number" and type(spots) == "table" then
            for _, sp in ipairs(spots) do learnObject(objectID, sp) end
        end
    end
end

-- confirmed spots of other players (newest first)
local function confirmedPeers(row)
    local out = {}
    for _, sp in ipairs(type(row.peers) == "table" and row.peers or {}) do
        if type(sp) == "table" and sp.ok and validSpot(sp) then out[#out + 1] = sp end
    end
    return out
end

-- a sighting { m = mapID, x, y } (map position) -> world spot
local function sightingSpot(r)
    if type(r) ~= "table" or type(r.m) ~= "number" or type(r.x) ~= "number" or type(r.y) ~= "number" then return nil end
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, r.m, CreateVector2D(r.x, r.y))
    if not ok or type(continent) ~= "number" or isSecret(continent) or type(world) ~= "table" then return nil end
    local x, y = world.x, world.y
    if type(world.GetXY) == "function" then
        local okXY, a, b = pcall(world.GetXY, world)
        if okXY then x, y = a, b end
    end
    if type(x) ~= "number" or type(y) ~= "number" or isSecret(x) or isSecret(y) then return nil end
    return { continent, math.floor(x * 10 + 0.5) / 10, math.floor(y * 10 + 0.5) / 10 }
end

-- the rare sightings now in the shared data: kept per rare (they are replaced
-- by newer ones there) and put in like a looted monster's spots
function NpcSpots.ApplyRares()
    local s = share()
    if not s then return end
    local okData, data = pcall(s.Data)
    local rare = okData and type(data) == "table" and data.rare
    local t = store()
    if not t then return end
    for npcID, r in pairs(type(rare) == "table" and rare or {}) do
        local spot = type(npcID) == "number" and sightingSpot(r)
        if spot then
            local row = type(t[npcID]) == "table" and t[npcID] or {}
            -- an NPC this character talked to is not a rare monster
            if not (row.own and not row.mob) then
                row.seen = type(row.seen) == "table" and row.seen or {}
                if not nearAny(row.seen, spot, MOB_GAP) and #row.seen < MAX_RARE_SEEN then
                    row.seen[#row.seen + 1] = spot
                end
                row.mob = true
                row.flags = 0
                t[npcID] = row
            end
        end
    end
    for key, row in pairs(t) do
        local npcID = tonumber(key)
        if npcID and type(row) == "table" and row.mob then
            for _, sp in ipairs(type(row.seen) == "table" and row.seen or {}) do learnMob(npcID, sp) end
        end
    end
end

function NpcSpots.ApplyAll()
    local s = share()
    local seed = s and type(s.Seed) == "function" and s.Seed("npcs")
    -- shipped first, then what was received, then this character's own (the latest)
    for npcID, rec in pairs(type(seed) == "table" and seed or {}) do
        if type(npcID) == "number" and type(rec) == "table" then
            for _, sp in ipairs(rec) do
                if validSpot(sp) then
                    if tonumber(sp[4]) == 0 then learnMob(npcID, sp) else learnLatest(npcID, sp, sp[4]) end
                end
            end
        end
    end
    for key, row in pairs(store() or {}) do
        local npcID = tonumber(key)
        if npcID and type(row) == "table" then
            local peers = confirmedPeers(row)
            if row.mob then
                for _, sp in ipairs(peers) do learnMob(npcID, sp) end
                for _, sp in ipairs(type(row.spots) == "table" and row.spots or {}) do learnMob(npcID, sp) end
            else
                for i = #peers, 1, -1 do learnLatest(npcID, peers[i], row.flags) end
                if validSpot(row.own) then learnLatest(npcID, row.own, row.flags) end
            end
        end
    end
end

-----------------------------------------------------------------------------
-- Noting
-----------------------------------------------------------------------------
local function playerSpot()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then
        return nil
    end
    local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not okMap or type(mapID) ~= "number" or isSecret(mapID) then return nil end
    local okPos, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not okPos or not pos then return nil end
    local okWorld, continent, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, pos)
    if not okWorld or type(continent) ~= "number" or isSecret(continent) or type(world) ~= "table" then return nil end
    local x, y = world.x, world.y
    if type(x) ~= "number" or type(y) ~= "number" or isSecret(x) or isSecret(y) then return nil end
    return { continent, math.floor(x * 10 + 0.5) / 10, math.floor(y * 10 + 0.5) / 10 }
end

local function creatureID(guid)
    if type(guid) ~= "string" or isSecret(guid) then return nil end
    local unitType, _, _, _, _, id = strsplit("-", guid)
    id = tonumber(id)
    if id and (unitType == "Creature" or unitType == "Vehicle") then return id end
    return nil
end

local function talkingNpcID()
    for _, unit in ipairs({ "npc", "questnpc" }) do
        local ok, guid = pcall(UnitGUID, unit)
        local id = ok and creatureID(guid)
        if id then return id end
    end
    return nil
end

-- flags of a new entry: 4 sells things, 1 has something to say
local EVENT_FLAGS = { MERCHANT_SHOW = 5 }

local function noteHere(event)
    if IsInInstance and IsInInstance() then return end
    local npcID = talkingNpcID()
    if not npcID then return end
    local spot = playerSpot()
    if not spot then return end
    local t = store()
    if not t then return end
    local row = type(t[npcID]) == "table" and t[npcID] or nil
    if row and row.mob then return end
    local entry = npcIndex()[npcID]
    -- standing where the data has it, and nothing noted before: nothing to note
    if not (row and row.own) and entry and nearAny(dataSpots(entry), spot, FAR) then return end
    if row and row.own and near(row.own, spot, SAME) then return end
    row = row or {}
    t[npcID] = row
    row.own = spot
    row.flags = row.flags or EVENT_FLAGS[event] or 1
    learnLatest(npcID, spot, row.flags)
end

local function noteLooted()
    if IsInInstance and IsInInstance() then return end
    if type(GetLootSourceInfo) ~= "function" then return end
    local okGuid, guid = pcall(GetLootSourceInfo, 1)
    local npcID = okGuid and creatureID(guid)
    if not npcID then return end
    local spot = playerSpot()
    if not spot then return end
    local entry = npcIndex()[npcID]
    if entry and nearAny(dataSpots(entry), spot, MOB_GAP) then return end
    local t = store()
    if not t then return end
    local row = type(t[npcID]) == "table" and t[npcID] or {}
    -- an NPC this character talked to is not a monster
    if row.own and not row.mob then return end
    row.mob = true
    row.flags = 0
    row.spots = type(row.spots) == "table" and row.spots or {}
    if nearAny(row.spots, spot, MOB_GAP) then return end
    if #row.spots >= MAX_MOB_SPOTS then return end
    row.spots[#row.spots + 1] = spot
    t[npcID] = row
    learnMob(npcID, spot)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "GOSSIP_SHOW", "MERCHANT_SHOW", "TRAINER_SHOW", "TAXIMAP_OPENED", "BANKFRAME_OPENED",
    "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "PET_STABLE_SHOW", "AUCTION_HOUSE_SHOW",
    "LOOT_OPENED", "PLAYER_LOGIN" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        pcall(NpcSpots.ApplyAll)
        pcall(NpcSpots.ApplyGather)
        pcall(NpcSpots.ApplyRares)
    elseif event == "LOOT_OPENED" then
        pcall(noteLooted)
    else
        pcall(noteHere, event)
    end
end)

-----------------------------------------------------------------------------
-- Sharing
-----------------------------------------------------------------------------
local function body(npcID, sp, flags)
    return string.format("%d,%d,%.1f,%.1f,%d", npcID, sp[1], sp[2], sp[3], flags)
end

-- new looting places and sightings from other players: put in a moment later
local s = share()
if s and type(s.RegisterCallback) == "function" then
    local queued = {}
    s.RegisterCallback("EzWoW-MapFinder-Spots", function(kinds)
        if type(kinds) ~= "table" then return end
        for kind, fn in pairs({ gather = NpcSpots.ApplyGather, rare = NpcSpots.ApplyRares }) do
            if kinds[kind] and not queued[kind] then
                queued[kind] = true
                local function run()
                    queued[kind] = nil
                    pcall(fn)
                end
                if C_Timer and C_Timer.After then C_Timer.After(2, run) else run() end
            end
        end
    end)
end

if s and type(s.RegisterKind) == "function" then
    s.RegisterKind(KIND, {
        own = function()
            local out = {}
            for npcID, row in pairs(store() or {}) do
                if type(npcID) == "number" and type(row) == "table" then
                    if row.mob then
                        for _, sp in ipairs(type(row.spots) == "table" and row.spots or {}) do
                            if validSpot(sp) then out[#out + 1] = body(npcID, sp, 0) end
                        end
                    elseif validSpot(row.own) then
                        out[#out + 1] = body(npcID, row.own, tonumber(row.flags) or 1)
                    end
                end
            end
            return out
        end,
        -- needed: how many different players must report a spot before it is used
        receive = function(text, hash, needed)
            local npcID, c, x, y, flags = text:match("^(%d+),(%d+),(%-?[%d%.]+),(%-?[%d%.]+),?(%d*)$")
            npcID, c, x, y, flags = tonumber(npcID), tonumber(c), tonumber(x), tonumber(y), tonumber(flags)
            if not (npcID and c and x and y) or npcID < 1 or npcID > 10000000 or c < 0 or c > 10000
                or math.abs(x) > 100000 or math.abs(y) > 100000 then return false end
            local t = store()
            if not t then return false end
            local spot = { c, x, y }
            local mob = flags == 0
            local entry = npcIndex()[npcID]
            -- the data already has it there
            if entry and nearAny(dataSpots(entry), spot, mob and MOB_GAP or FAR) then return false end
            local row = type(t[npcID]) == "table" and t[npcID] or {}
            -- monster and NPC reports for one ID do not mix
            if (row.mob and not mob) or (mob and row.own and not row.mob) then return false end
            t[npcID] = row
            if mob then
                row.mob = true
                row.flags = 0
            elseif not row.flags and flags and flags > 0 and flags < 64 then
                row.flags = flags
            end
            row.peers = type(row.peers) == "table" and row.peers or {}
            local gap = mob and MOB_GAP or SAME
            local found
            for _, sp in ipairs(row.peers) do
                if near(sp, spot, gap) then found = sp break end
            end
            local maxSpots = mob and MAX_MOB_SPOTS or MAX_PEER_SPOTS
            if not found then
                if #row.peers >= maxSpots then
                    -- an NPC: the oldest unconfirmed report makes room for a new one
                    if mob then return false end
                    local drop
                    for i = #row.peers, 1, -1 do
                        if not row.peers[i].ok then drop = i break end
                    end
                    if not drop then drop = #row.peers end
                    table.remove(row.peers, drop)
                end
                found = { c, x, y, by = {}, n = 0 }
                table.insert(row.peers, 1, found)
            end
            found.by = type(found.by) == "table" and found.by or {}
            local h = tostring(hash or "?")
            if found.by[h] or (found.n or 0) >= MAX_VOTERS then return false end
            local wasOk = found.ok
            found.by[h] = true
            found.n = (found.n or 0) + 1
            if not found.ok and found.n >= (tonumber(needed) or 2) then
                found.ok = true
                if mob then
                    learnMob(npcID, found)
                elseif not validSpot(row.own) then
                    -- this character's own (newer to it) stays in front
                    learnLatest(npcID, found, row.flags)
                end
            end
            -- "wait": kept until enough players sent that spot; false: in use already
            if not found.ok then return "wait" end
            return not wasOk
        end,
    })
end
