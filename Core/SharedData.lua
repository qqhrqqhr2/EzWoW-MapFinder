--===========================================================================
-- EzWoW - Map Finder
-- Core/SharedData.lua : search data from EzWoW - Data when it is installed
--===========================================================================
-- EzWoW - Data is optional. When it is installed, enabled and its tables have
-- the shape this addon reads (formatVersion 2), the search data comes from it;
-- otherwise the built-in Database files are used exactly as before.
--
-- The built-in Database files always load (they are the fallback). With the
-- shared data, three small hook files swap their tables while this addon
-- loads, before anything reads them:
--   Database\SharedEntries.lua (after Locations_*)  entries rebuilt from the
--       shared spots (Spawns) and English names (Names-enUS), in the built-in
--       order (item, npc, object, quest; ids ascending). ForeverOverrides,
--       RareMonsters and HunterPets then run on these entries as before.
--   Database\SharedNames.lua   (after AllNames_*)   names of the client language
--       and Korean from the shared name tables; English subtitles. The other
--       languages are only needed when one is picked in the options: their
--       built-in tables are dropped and the shared table of that language is
--       loaded when it is picked (UseLocale). A language whose shared module is
--       not installed keeps its built-in table.
--   Database\SharedQuests.lua  (after QuestData)    quest table from the shared
--       quest data (QuestMap).
-- The shared tables are never changed: entries are new tables, and the name
-- tables are read through empty tables (RareMonsters and HunterPets write
-- their names into those).
-- Shared modules are loaded only out of combat. During combat (a /reload in a
-- fight) the built-in data is used for that session; a language picked during
-- combat is loaded when the combat ends.
local _, ns = ...
local type, pairs, ipairs, pcall, next, setmetatable = type, pairs, ipairs, pcall, next, setmetatable

local Shared = { active = false }
ns.SharedData = Shared

local FORMAT_VERSION = 2
-- order of the built-in Locations files
local ENTRY_KINDS = { "item", "npc", "object", "quest" }
-- name tables of the built-in AllNames files
local NAME_KINDS = { "item", "npc", "object", "quest", "subname" }
-- languages of the built-in AllNames files
local NAME_LOCALES = { "koKR", "deDE", "frFR", "esES", "ruRU", "zhCN", "zhTW" }
-- tables of the built-in QuestData file
local QUEST_TABLES = { "quests", "itemDrops", "itemObjects", "turnIns", "givers", "eventSpots" }

local lazyLocales = {}          -- locale -> true while its shared names are not loaded yet

local function inCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function api()
    local D = _G.EzWoW_Data
    if type(D) ~= "table" or D.formatVersion ~= FORMAT_VERSION then return nil end
    for _, fn in ipairs({ "Load", "IsAvailable", "Peek", "CanLoad" }) do
        if type(D[fn]) ~= "function" then return nil end
    end
    return D
end

-- Module table when it is loaded (now, out of combat) and in this format.
local function loadModule(D, key)
    local ok, available = pcall(D.IsAvailable, key)
    if not (ok and available) then
        if inCombat() then return nil end
        if not pcall(D.Load, key) then return nil end
    end
    local isOk, m = pcall(D.Peek, key)
    if not isOk or type(m) ~= "table" or m.formatVersion ~= FORMAT_VERSION then return nil end
    return m
end

local function hasTable(m, name)
    return type(m) == "table" and type(m[name]) == "table" and next(m[name]) ~= nil
end

local function readThrough(t)
    return setmetatable({}, { __index = t })
end

local function clientLocale(D)
    local ok, loc = pcall(D.ClientLocale)
    if ok and type(loc) == "string" then return loc end
    return "enUS"
end

-- name table of one language read through the shared tables (built-in kinds the module lacks stay)
local function sharedNames(m, builtIn)
    local t = {}
    for _, kind in ipairs(NAME_KINDS) do
        if type(m[kind]) == "table" then
            t[kind] = readThrough(m[kind])
        elseif type(builtIn) == "table" then
            t[kind] = builtIn[kind]
        end
    end
    return t
end

-----------------------------------------------------------------------------
-- After Database\Locations_*: decide, then rebuild the entries
-----------------------------------------------------------------------------
function Shared.AfterLocations()
    local D = api()
    if not D then return end
    local spawns = loadModule(D, "Spawns")
    if not spawns then return end
    for _, kind in ipairs(ENTRY_KINDS) do
        if not hasTable(spawns, kind) then return end
    end
    local english = loadModule(D, "Names-enUS")
    if not (english and hasTable(english, "npc")) then return end
    local korean = loadModule(D, "Names-koKR")
    if not (korean and hasTable(korean, "npc")) then return end

    local entries = {}
    for _, kind in ipairs(ENTRY_KINDS) do
        local spots = spawns[kind]
        local flags = type(spawns[kind .. "Flags"]) == "table" and spawns[kind .. "Flags"] or {}
        local names = type(english[kind]) == "table" and english[kind] or {}
        local ids = {}
        for id in pairs(spots) do
            if type(id) == "number" then ids[#ids + 1] = id end
        end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local spot = spots[id]
            entries[#entries + 1] = {
                id = id,
                kind = kind,
                names = { enUS = names[id] },
                flags = flags[id] or 0,
                spawns = type(spot) == "table" and spot or {},
            }
        end
    end
    if #entries == 0 then return end

    -- name tables: Korean and the client language (English names are in the entries)
    local nameModules = { koKR = korean }
    local client = clientLocale(D)
    if client ~= "enUS" and client ~= "koKR" then
        local m = loadModule(D, "Names-" .. client)
        if m then nameModules[client] = m end
    end

    Shared.active = true
    Shared.english = english
    Shared.names = nameModules
    Shared.quests = loadModule(D, "QuestMap")
    _G.EzWoWMapFinderData = entries
    ns.Data = entries
end

-----------------------------------------------------------------------------
-- After Database\AllNames_*: shared name tables
-----------------------------------------------------------------------------
function Shared.AfterNames()
    if not Shared.active then return end
    local D = api()
    local translations = _G.EzWoWMapFinderTranslations
    if type(translations) ~= "table" then
        translations = {}
        _G.EzWoWMapFinderTranslations = translations
    end
    for loc, m in pairs(Shared.names or {}) do
        translations[loc] = sharedNames(m, translations[loc])
    end
    -- the other languages: loaded when picked (see UseLocale); built-in kept when not installed
    if D then
        for _, loc in ipairs(NAME_LOCALES) do
            if not (Shared.names or {})[loc] and type(translations[loc]) == "table" then
                local ok, canLoad = pcall(D.CanLoad, "Names-" .. loc)
                if ok and canLoad then
                    translations[loc] = {}
                    lazyLocales[loc] = true
                end
            end
        end
    end
    local english = Shared.english
    if english and type(english.subname) == "table" then
        _G.EzWoWMapFinderSubNames = readThrough(english.subname)
    end
    Shared.names = nil
    Shared.english = nil
end

-- the shared names of one language were loaded: use them and drop search texts made without them
local function useLoadedLocale(loc)
    local D = api()
    if not (D and lazyLocales[loc]) then return end
    local ok, m = pcall(D.Peek, "Names-" .. loc)
    if not ok or type(m) ~= "table" then return end
    lazyLocales[loc] = nil
    local translations = _G.EzWoWMapFinderTranslations
    if type(translations) ~= "table" then return end
    translations[loc] = sharedNames(m, nil)
    for _, e in ipairs(ns.Data or {}) do
        if e._searchLocale == loc then e._searchStr, e._searchLocale = nil, nil end
    end
end

-- Called when the language Map Finder shows is set (Core/Locales.lua). Loads the shared names
-- of a language whose built-in table was dropped (out of combat; after the combat otherwise).
-- Not called from tooltips or other combat paths.
function Shared.UseLocale(loc)
    if not (Shared.active and type(loc) == "string" and lazyLocales[loc]) then return end
    local D = api()
    if not D then return end
    pcall(D.Load, "Names-" .. loc, function(_, success)
        if success then useLoadedLocale(loc) end
    end)
end

-----------------------------------------------------------------------------
-- After Database\QuestData: shared quest tables
-----------------------------------------------------------------------------
function Shared.AfterQuests()
    local m = Shared.quests
    Shared.quests = nil
    if not (Shared.active and m) then return end
    local builtIn = _G.EzWoWMapFinderQuestData
    local t = {}
    for _, key in ipairs(QUEST_TABLES) do
        if type(m[key]) == "table" then
            t[key] = m[key]
        elseif type(builtIn) == "table" then
            t[key] = builtIn[key]
        end
    end
    if type(builtIn) == "table" then
        for k, v in pairs(builtIn) do
            if t[k] == nil then t[k] = v end
        end
    end
    _G.EzWoWMapFinderQuestData = t
end
