--===========================================================================
-- EzWoW - Map Finder
-- Modules/SearchEngine.lua : Multilingual NPC/Object/Rare/Pet Search & Coordinate Projector
--===========================================================================
local _, ns = ...
-- Text for the game's AddOns panel in the six languages without their own line: { deDE, frFR, esES, ruRU, zhCN, zhTW }
local PANEL_LANG_INDEX = { deDE = 1, frFR = 2, esES = 3, esMX = 3, ruRU = 4, zhCN = 5, zhTW = 6, de = 1, fr = 2, es = 3, ru = 4 }
local function panelText(code, ko, en, others)
    if code == "koKR" or code == "ko" then return ko end
    local index = PANEL_LANG_INDEX[code or ""]
    return (index and others and others[index]) or en
end

local EntitySearchEngine = ns.EntitySearchEngine or {}
ns.EntitySearchEngine = EntitySearchEngine

local lower = ns.ToLowerSafeString
local L = ns.L
local ROLES = ns.ROLES
local QUERY_SYNONYMS = ns.QUERY_SYNONYMS
local ZONE_BOUNDS = ns.ZONE_BOUNDS
local ZONE_BOUNDS_BY_ID = ns.ZONE_BOUNDS_BY_ID
local ZONE_ID_BY_KEY = ns.ZONE_ID_BY_KEY
local INSTANCE_ZONES = ns.INSTANCE_ZONES
local EXTRA_ZONE_KEY_BY_MAPID = ns.EXTRA_ZONE_KEY_BY_MAPID
local ZONE_NAMES = ns.ZONE_NAMES
local CONTINENT_FALLBACK_MAP = ns.CONTINENT_FALLBACK_MAP
local ZONE_KEYWORDS = ns.ZONE_KEYWORDS
local ZONE_PREFIX_LIST = ns.ZONE_PREFIX_LIST
local ALL_ZONE_KEYS = ns.ALL_ZONE_KEYS
local HERB_SKILL_BY_OBJECT = ns.HERB_SKILL_BY_OBJECT
local MINE_SKILL_BY_OBJECT = ns.MINE_SKILL_BY_OBJECT
local FRIENDLY_SUBNAME_KEYWORDS = ns.FRIENDLY_SUBNAME_KEYWORDS
local BADGE_PREFIX_POOLS = ns.BADGE_PREFIX_POOLS
local HERB_SKILL_BY_OBJECT = ns.HERB_SKILL_BY_OBJECT
local MINE_SKILL_BY_OBJECT = ns.MINE_SKILL_BY_OBJECT
local localizeZoneIdentifier = ns.FormatLocalizedZoneName

local SEARCH_POOLS = nil

function EntitySearchEngine.resolveLocalizedEntityName(e)
    if not e then return "" end
    local translationMap = EzWoWMapFinderTranslations
    if translationMap and e.id and translationMap[ns.activeLocale] and translationMap[ns.activeLocale][e.kind] and translationMap[ns.activeLocale][e.kind][e.id] then
        return translationMap[ns.activeLocale][e.kind][e.id]
    end
    if e.names and e.names[ns.activeLocale] and e.names[ns.activeLocale] ~= "" then
        return e.names[ns.activeLocale]
    end
    local clientLoc = (GetLocale and GetLocale()) or "enUS"
    if clientLoc == "esMX" then clientLoc = "esES" elseif clientLoc == "enGB" then clientLoc = "enUS" end
    if ns.activeLocale == clientLoc and e.id then
        if e.kind == "item" and C_Item and C_Item.GetItemNameByID then
            local nodeEntry = C_Item.GetItemNameByID(e.id)
            if nodeEntry and nodeEntry ~= "" then return nodeEntry end
        elseif e.kind == "quest" and C_QuestLog then
            local qTitle = (C_QuestLog.GetQuestInfo and C_QuestLog.GetQuestInfo(e.id))
                or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(e.id))
            if qTitle and qTitle ~= "" then return qTitle end
        elseif e.kind == "npc" and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
            if e._clientNpcName == nil then
                local isCallOk, payloadData = pcall(C_TooltipInfo.GetHyperlink, "unit:Creature-0-0-0-0-" .. tostring(e.id) .. "-0")
                local line1 = isCallOk and payloadData and payloadData.lines and payloadData.lines[1] and payloadData.lines[1].leftText
                if line1 and line1 ~= "" and not (issecretvalue and issecretvalue(line1)) then
                    e._clientNpcName = line1
                else
                    e._clientNpcName = false
                end
            end
            if e._clientNpcName then return e._clientNpcName end
        end
    end
    if e.names then
        if e.names[clientLoc] and e.names[clientLoc] ~= "" then return e.names[clientLoc] end
        if e.names.koKR and ns.activeLocale == "koKR" and e.names.koKR ~= "" then return e.names.koKR end
        if e.names.enUS and e.names.enUS ~= "" then return e.names.enUS end
    end
    if e.kind == "item" and e.id and C_Item and C_Item.GetItemNameByID then
        local nodeEntry = C_Item.GetItemNameByID(e.id)
        if nodeEntry and nodeEntry ~= "" then return nodeEntry end
    end
    return tostring(e.id or "")
end

function EntitySearchEngine.resolveLocalizedSubTitle(e)
    if not e or e.kind ~= "npc" or not e.id then return nil end
    if e.subnames and e.subnames[ns.activeLocale] and e.subnames[ns.activeLocale] ~= "" then
        return e.subnames[ns.activeLocale]
    end
    local translationMap = EzWoWMapFinderTranslations
    if translationMap and translationMap[ns.activeLocale] and translationMap[ns.activeLocale].subname and translationMap[ns.activeLocale].subname[e.id] then
        return translationMap[ns.activeLocale].subname[e.id]
    end
    if e.subnames and e.subnames.koKR and ns.activeLocale == "koKR" and e.subnames.koKR ~= "" then
        return e.subnames.koKR
    end
    if EzWoWMapFinderSubNames and EzWoWMapFinderSubNames[e.id] then
        return EzWoWMapFinderSubNames[e.id]
    end
    return nil
end

local function localizeZoneIdentifier(key)
    if not key or key == "" then return "" end
    local ztVal = ZONE_NAMES[key]
    if ztVal then
        return ztVal[ns.activeLocale] or ztVal.enUS or key
    end
    if string.find(key, "/", 1, true) then
        local parts = {}
        for part in string.gmatch(key, "([^/]+)") do
            local trimmed = part:gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
            local resolvedValue = ZONE_NAMES[trimmed]
            parts[#parts + 1] = (resolvedValue and (resolvedValue[ns.activeLocale] or resolvedValue.enUS)) or trimmed
        end
        return table.concat(parts, " / ")
    end
    return key
end

function EntitySearchEngine.projectWorldSpawnToMap(spawn, targetMapID)
    if not spawn then return nil end
    local instID, wxVal, wyVal = spawn[1], spawn[2], spawn[3]
    if instID == -1 then
        local sMapID, smx, smy = spawn[2], spawn[3], spawn[4]
        local zbVal = sMapID and ZONE_BOUNDS_BY_ID[sMapID]
        local zKey = (zbVal and zbVal.key) or (sMapID and EXTRA_ZONE_KEY_BY_MAPID[sMapID])
        if not zKey and sMapID and C_Map and C_Map.GetMapInfo then
            local apiInfo = C_Map.GetMapInfo(sMapID)
            if apiInfo and apiInfo.name then zKey = apiInfo.name end
        end
        if not targetMapID or targetMapID == sMapID then
            return sMapID, smx, smy, zKey
        end
        local tbVal = ZONE_BOUNDS_BY_ID[targetMapID]
        if zbVal and tbVal and zbVal.mapID == tbVal.mapID and smx and smy then
            local worldY = zbVal.yMax - smx * (zbVal.yMax - zbVal.yMin)
            local worldX = zbVal.xMax - smy * (zbVal.xMax - zbVal.xMin)
            if worldX >= tbVal.xMin and worldX <= tbVal.xMax and worldY >= tbVal.yMin and worldY <= tbVal.yMax then
                local mxVal = (tbVal.yMax - worldY) / (tbVal.yMax - tbVal.yMin)
                local myVal = (tbVal.xMax - worldX) / (tbVal.xMax - tbVal.xMin)
                if mxVal >= 0 and mxVal <= 1 and myVal >= 0 and myVal <= 1 then
                    return targetMapID, mxVal, myVal, zKey
                end
            end
        end
        return nil, nil, nil, nil
    end
    local instInfo = INSTANCE_ZONES[instID]

    if targetMapID then
        if instInfo then
            if targetMapID == instInfo.uiMapID then
                return targetMapID, instInfo.mx, instInfo.my, instInfo.key
            end
            local zBound = ZONE_BOUNDS_BY_ID[instInfo.uiMapID]
            local tBound = ZONE_BOUNDS_BY_ID[targetMapID]
            if zBound and tBound and zBound.mapID == tBound.mapID then
                local worldY = zBound.yMax - instInfo.mx * (zBound.yMax - zBound.yMin)
                local worldX = zBound.xMax - instInfo.my * (zBound.xMax - zBound.xMin)
                if worldX >= tBound.xMin and worldX <= tBound.xMax and worldY >= tBound.yMin and worldY <= tBound.yMax then
                    local mxVal = (tBound.yMax - worldY) / (tBound.yMax - tBound.yMin)
                    local myVal = (tBound.xMax - worldX) / (tBound.xMax - tBound.xMin)
                    return targetMapID, mxVal, myVal, instInfo.key
                end
            end
        end
        local buttonWidget = ZONE_BOUNDS_BY_ID[targetMapID]
        if buttonWidget and buttonWidget.mapID == instID and wxVal and wyVal then
            if wxVal >= buttonWidget.xMin and wxVal <= buttonWidget.xMax and wyVal >= buttonWidget.yMin and wyVal <= buttonWidget.yMax then
                local mxVal = (buttonWidget.yMax - wyVal) / (buttonWidget.yMax - buttonWidget.yMin)
                local myVal = (buttonWidget.xMax - wxVal) / (buttonWidget.xMax - buttonWidget.xMin)
                if mxVal >= 0 and mxVal <= 1 and myVal >= 0 and myVal <= 1 then
                    return targetMapID, mxVal, myVal, buttonWidget.key
                end
            end
        end
        if C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D and wxVal and wyVal then
            local isCallOk, uiMapID, coordPos = pcall(C_Map.GetMapPosFromWorldPos, instID, CreateVector2D(wxVal, wyVal), targetMapID)
            if isCallOk and uiMapID and coordPos and coordPos.GetXY then
                local mxVal, myVal = coordPos:GetXY()
                if mxVal and myVal and mxVal >= 0 and mxVal <= 1 and myVal >= 0 and myVal <= 1 then
                    local zbVal = ZONE_BOUNDS_BY_ID[uiMapID]
                    return uiMapID, mxVal, myVal, zbVal and zbVal.key
                end
            end
        end
        return nil, nil, nil, nil
    end

    if instInfo then
        return instInfo.uiMapID, instInfo.mx, instInfo.my, instInfo.key
    end
    if wxVal and wyVal then
        local bestZone, bestMx, bestMy
        local bestScore = 999999
        for _, buttonWidget in ipairs(ZONE_BOUNDS) do
            if buttonWidget.mapID == instID and buttonWidget.mtype == 3 then
                if wxVal >= buttonWidget.xMin and wxVal <= buttonWidget.xMax and wyVal >= buttonWidget.yMin and wyVal <= buttonWidget.yMax then
                    local mxVal = (buttonWidget.yMax - wyVal) / (buttonWidget.yMax - buttonWidget.yMin)
                    local myVal = (buttonWidget.xMax - wxVal) / (buttonWidget.xMax - buttonWidget.xMin)
                    local dist = (mxVal - 0.5) * (mxVal - 0.5) + (myVal - 0.5) * (myVal - 0.5)
                    local score = dist
                    if buttonWidget.isCity and mxVal >= 0.05 and mxVal <= 0.95 and myVal >= 0.05 and myVal <= 0.95 then
                        score = dist - 10.0
                    end
                    if score < bestScore then
                        bestScore = score
                        bestZone = buttonWidget
                        bestMx = mxVal
                        bestMy = myVal
                    end
                end
            end
        end
        if bestZone then
            return bestZone.uiMapID, bestMx, bestMy, bestZone.key
        end
        for _, buttonWidget in ipairs(ZONE_BOUNDS) do
            if buttonWidget.mapID == instID and buttonWidget.mtype == 2 then
                if wxVal >= buttonWidget.xMin and wxVal <= buttonWidget.xMax and wyVal >= buttonWidget.yMin and wyVal <= buttonWidget.yMax then
                    local mxVal = (buttonWidget.yMax - wyVal) / (buttonWidget.yMax - buttonWidget.yMin)
                    local myVal = (buttonWidget.xMax - wxVal) / (buttonWidget.xMax - buttonWidget.xMin)
                    return buttonWidget.uiMapID, mxVal, myVal, buttonWidget.key
                end
            end
        end
    end
    local fallbackMap = CONTINENT_FALLBACK_MAP[instID]
    local WorldMapFilterButton = fallbackMap and ZONE_BOUNDS_BY_ID[fallbackMap]
    return fallbackMap, nil, nil, WorldMapFilterButton and WorldMapFilterButton.key
end

function EntitySearchEngine.indexEntityZonesByMap(e)
    if not e then return nil end
    if e._zoneMap then return e._zoneMap end
    local zmVal = {}
    local spawns = e.spawns
    if spawns and #spawns > 0 then
        local nodeEntry = #spawns
        local step = (nodeEntry > 24) and math.max(1, math.floor(nodeEntry / 24)) or 1
        for entryIndex = 1, nodeEntry, step do
            local uiMapID, _, _, zKey = EntitySearchEngine.projectWorldSpawnToMap(spawns[entryIndex], nil)
            if zKey and zKey ~= "" and not zmVal[zKey] then
                zmVal[zKey] = entryIndex
            end
            if entryIndex == 1 then
                e._cachedZoneKey = zKey or ""
                e._cachedUiMapID = uiMapID
            end
        end
        if nodeEntry > 1 and step > 1 then
            local _, _, _, lastKey = EntitySearchEngine.projectWorldSpawnToMap(spawns[nodeEntry], nil)
            if lastKey and lastKey ~= "" and not zmVal[lastKey] then
                zmVal[lastKey] = nodeEntry
            end
        end
    end
    if e.zone and e.zone ~= "" then
        for part in string.gmatch(e.zone, "([^/]+)") do
            local trimmed = part:gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
            if trimmed ~= "" and not zmVal[trimmed] then
                zmVal[trimmed] = 1
                if not e._cachedZoneKey or e._cachedZoneKey == "" then
                    e._cachedZoneKey = trimmed
                    e._cachedUiMapID = ZONE_ID_BY_KEY[trimmed]
                end
            end
        end
    end
    e._zoneMap = zmVal
    return zmVal
end

function EntitySearchEngine.resolveEntityZoneKey(e, spawnIdx)
    if not e then return nil, nil end
    if not spawnIdx then
        EntitySearchEngine.indexEntityZonesByMap(e)
        return e._cachedZoneKey, e._cachedUiMapID
    end
    local spawnCoord = e.spawns and e.spawns[spawnIdx]
    if spawnCoord then
        local uiMapID, _, _, zKey = EntitySearchEngine.projectWorldSpawnToMap(spawnCoord, nil)
        return zKey, uiMapID
    end
    EntitySearchEngine.indexEntityZonesByMap(e)
    return e._cachedZoneKey, e._cachedUiMapID
end

function EntitySearchEngine.resolveEntityZoneName(e, spawnIdx)
    local zKey = EntitySearchEngine.resolveEntityZoneKey(e, spawnIdx)
    if not zKey or zKey == "" then return "" end
    return localizeZoneIdentifier(zKey)
end

function EntitySearchEngine.doesZoneMatchQueryToken(zKey, tok)
    if not zKey or zKey == "" then return false end
    if string.find(lower(zKey), tok, 1, true) then return true end
    local ztVal = ZONE_NAMES[zKey]
    if ztVal then
        for _, zLocName in pairs(ztVal) do
            if string.find(lower(zLocName), tok, 1, true) then return true end
            local noSpace = zLocName:gsub("[ \t]+", "")
            if noSpace ~= zLocName and string.find(lower(noSpace), tok, 1, true) then return true end
        end
    end
    local kws = ZONE_KEYWORDS[zKey]
    if kws then
        for _, kwVal in ipairs(kws) do
            if string.find(lower(kwVal), tok, 1, true) then return true end
        end
    end
    return false
end

function EntitySearchEngine.buildGatheringSkillBadge(e)
    if not e or e.kind ~= "object" or not e.id then return nil end
    local hReq = HERB_SKILL_BY_OBJECT[e.id]
    if hReq then
        return string.format(" |cff60cea3[%s %d]|r", L.herbSkill or "Herbalism", hReq)
    end
    local mReq = MINE_SKILL_BY_OBJECT[e.id]
    if mReq then
        return string.format(" |cfff1bd57[%s %d]|r", L.mineSkill or "Mining", mReq)
    end
    return nil
end

function EntitySearchEngine.compileEntitySearchCorpus(e)
    if e._searchStr and e._searchLocale == ns.activeLocale then
        return e._searchStr
    end
    local parts = {}
    if e.id then parts[#parts + 1] = tostring(e.id) end
    if e.names then
        for _, entryValue in pairs(e.names) do
            if entryValue and entryValue ~= "" then parts[#parts + 1] = lower(entryValue) end
        end
    end
    if e.subnames then
        for _, entryValue in pairs(e.subnames) do
            if entryValue and entryValue ~= "" then parts[#parts + 1] = lower(entryValue) end
        end
    end
    if e.aliases then
        for _, alVal in ipairs(e.aliases) do
            if alVal and alVal ~= "" then parts[#parts + 1] = lower(alVal) end
        end
    end
    local translationMap = EzWoWMapFinderTranslations
    if translationMap and e.id then
        local locT = translationMap[ns.activeLocale]
        if locT then
            local ktVal = locT[e.kind]
            if ktVal and ktVal[e.id] then parts[#parts + 1] = lower(ktVal[e.id]) end
            if e.kind == "npc" and locT.subname and locT.subname[e.id] then
                parts[#parts + 1] = lower(locT.subname[e.id])
            end
        end
        if ns.activeLocale ~= "koKR" and translationMap.koKR then
            local ktVal = translationMap.koKR[e.kind]
            if ktVal and ktVal[e.id] then parts[#parts + 1] = lower(ktVal[e.id]) end
            if e.kind == "npc" and translationMap.koKR.subname and translationMap.koKR.subname[e.id] then
                parts[#parts + 1] = lower(translationMap.koKR.subname[e.id])
            end
        end
    end
    if e.kind == "npc" and e.id and EzWoWMapFinderSubNames and EzWoWMapFinderSubNames[e.id] then
        parts[#parts + 1] = lower(EzWoWMapFinderSubNames[e.id])
    end
    if e.kind == "object" and e.id then
        local hReq = HERB_SKILL_BY_OBJECT[e.id]
        if hReq then
            parts[#parts + 1] = "약초\n약초채집\n채집\nherb\nherbalism\n약초 " .. tostring(hReq) .. "\n" .. tostring(hReq)
        end
        local mReq = MINE_SKILL_BY_OBJECT[e.id]
        if mReq then
            parts[#parts + 1] = "광맥\n채광\n광석\nmine\nmining\nvein\nore\n채광 " .. tostring(mReq) .. "\n" .. tostring(mReq)
        end
    end
    if e.isRare then
        parts[#parts + 1] = "은테\n레어\n희귀\nrare"
    end
    if e.isPet and e.petInfo then
        parts[#parts + 1] = "야수\n길들이기\n사냥꾼\n펫\npet\ntameable\nhunter"
        local petInfo = e.petInfo
        local familyInfo = petInfo.family and EzWoWMapFinderPetFamilies and EzWoWMapFinderPetFamilies[petInfo.family]
        if familyInfo then
            if familyInfo.ko then parts[#parts + 1] = lower(familyInfo.ko) end
            if familyInfo.en then parts[#parts + 1] = lower(familyInfo.en) end
            if familyInfo.dietKo then parts[#parts + 1] = lower(familyInfo.dietKo) end
            if familyInfo.dietEn then parts[#parts + 1] = lower(familyInfo.dietEn) end
        end
        if petInfo.speed then
            local spdStr = string.format("%.1f", petInfo.speed):gsub("%.0$", ".0")
            parts[#parts + 1] = "공속 " .. spdStr .. "\n" .. spdStr .. "s\n" .. spdStr
        end
        if petInfo.skills and EzWoWMapFinderPetSkills then
            for _, spellIDVal in ipairs(petInfo.skills) do
                local skillInfo = EzWoWMapFinderPetSkills[spellIDVal]
                if skillInfo then
                    if skillInfo.ko then
                        local klVal = lower(skillInfo.ko)
                        parts[#parts + 1] = klVal
                        if skillInfo.rank then parts[#parts + 1] = klVal .. " " .. tostring(skillInfo.rank) .. "\n" .. klVal .. tostring(skillInfo.rank) end
                    end
                    if skillInfo.en then
                        local elVal = lower(skillInfo.en)
                        parts[#parts + 1] = elVal
                        if skillInfo.rank then parts[#parts + 1] = elVal .. " " .. tostring(skillInfo.rank) end
                    end
                end
            end
        end
    end
    local stateFlag = table.concat(parts, "\n")
    e._searchStr = stateFlag
    e._searchLocale = ns.activeLocale
    return stateFlag
end

function EntitySearchEngine.composePetRowTag(e)
    if not (e and e.isPet and e.petInfo) then return nil end
    local petInfo = e.petInfo
    local hasKo = (ns.activeLocale == "koKR")
    local familyInfo = petInfo.family and EzWoWMapFinderPetFamilies and EzWoWMapFinderPetFamilies[petInfo.family]
    local famName = familyInfo and (hasKo and familyInfo.ko or familyInfo.en) or panelText(ns.activeLocale, "야수", "Beast", { "Wildtier", "Bête", "Bestia", "Зверь", "野兽", "野獸" })
    local lvlStr
    if petInfo.minLvl and petInfo.minLvl > 0 then
        if petInfo.maxLvl and petInfo.maxLvl ~= petInfo.minLvl then
            lvlStr = string.format("Lv%d-%d", petInfo.minLvl, petInfo.maxLvl)
        else
            lvlStr = string.format("Lv%d", petInfo.minLvl)
        end
    end
    local spdStr = petInfo.speed and string.format("%.1fs", petInfo.speed) or nil
    local skillName
    if petInfo.skills and petInfo.skills[1] and EzWoWMapFinderPetSkills then
        local skillInfo = EzWoWMapFinderPetSkills[petInfo.skills[1]]
        if skillInfo then
            skillName = (hasKo and skillInfo.ko or skillInfo.en) .. (skillInfo.rank and (" " .. tostring(skillInfo.rank)) or "")
        end
    end
    local segs = { famName }
    if lvlStr then segs[#segs + 1] = lvlStr end
    if spdStr then segs[#segs + 1] = spdStr end
    if skillName then segs[#segs + 1] = skillName end
    return " |cff60cea3<" .. table.concat(segs, " · ") .. ">|r"
end

function EntitySearchEngine.addPetTooltipLines(e)
    if not (e and e.isPet and e.petInfo) then return end
    local petInfo = e.petInfo
    local hasKo = (ns.activeLocale == "koKR")
    local familyInfo = petInfo.family and EzWoWMapFinderPetFamilies and EzWoWMapFinderPetFamilies[petInfo.family]
    local famName = familyInfo and (hasKo and familyInfo.ko or familyInfo.en) or panelText(ns.activeLocale, "야수", "Beast", { "Wildtier", "Bête", "Bestia", "Зверь", "野兽", "野獸" })
    if petInfo.elite then
        famName = famName .. panelText(ns.activeLocale, "·정예", "·Elite", { "·Elite", "·Élite", "·Élite", "·Элита", "·精英", "·精英" })
    end
    local lvlStr = "?"
    if petInfo.minLvl and petInfo.minLvl > 0 then
        if petInfo.maxLvl and petInfo.maxLvl ~= petInfo.minLvl then
            lvlStr = string.format("Lv %d-%d", petInfo.minLvl, petInfo.maxLvl)
        else
            lvlStr = string.format("Lv %d", petInfo.minLvl)
        end
    end
    local spdStr = string.format("%.1f", petInfo.speed or 2.0)
    GameTooltip:AddLine(string.format(L.petLineFmt, famName, lvlStr, spdStr), 0.376, 0.808, 0.639)
    if familyInfo then
        local dietStr = hasKo and familyInfo.dietKo or familyInfo.dietEn
        local dmgPct = math.floor((familyInfo.dmg or 1) * 100 + 0.5)
        local armPct = math.floor((familyInfo.arm or 1) * 100 + 0.5)
        local hpPct  = math.floor((familyInfo.hp or 1) * 100 + 0.5)
        GameTooltip:AddLine(string.format(L.petDietFmt, dietStr or "-", dmgPct, armPct, hpPct), 0.78, 0.86, 0.90)
    end
    if petInfo.skills and #petInfo.skills > 0 and EzWoWMapFinderPetSkills then
        local sList = {}
        for _, spellIDVal in ipairs(petInfo.skills) do
            local skillInfo = EzWoWMapFinderPetSkills[spellIDVal]
            if skillInfo then
                local snVal = hasKo and skillInfo.ko or skillInfo.en
                if skillInfo.rank then
                    snVal = snVal .. (hasKo and (" " .. skillInfo.rank .. "등급") or (" " .. skillInfo.rank))
                end
                sList[#sList + 1] = snVal
            end
        end
        if #sList > 0 then
            GameTooltip:AddLine(string.format(L.petSkillFmt, table.concat(sList, ", ")), 0.945, 0.741, 0.341)
        end
    end
end

function EntitySearchEngine.compileSingleTokenMatcher(tok, allowSplits)
    local zoneKeySet = {}
    local containsZoneMatch = false
    for index = 1, #ALL_ZONE_KEYS do
        local zKey = ALL_ZONE_KEYS[index]
        if EntitySearchEngine.doesZoneMatchQueryToken(zKey, tok) then
            zoneKeySet[zKey] = true
            containsZoneMatch = true
        end
    end

    local roleMasks = {}
    for index = 1, #ROLES do
        local role = ROLES[index]
        local kwList = role[2]
        for subIndex = 1, #kwList do
            if string.find(lower(kwList[subIndex]), tok, 1, true) then
                roleMasks[#roleMasks + 1] = role[1]
                break
            end
        end
    end

    local synList = nil
    local rawSyns = QUERY_SYNONYMS[tok]
    if rawSyns then
        synList = {}
        for index = 1, #rawSyns do
            synList[#synList + 1] = lower(rawSyns[index])
        end
    end

    local splits = nil
    if allowSplits then
        for index = 1, #ZONE_PREFIX_LIST do
            local zpVal = ZONE_PREFIX_LIST[index]
            local zpLen = #zpVal
            if #tok > zpLen and string.sub(tok, 1, zpLen) == zpVal then
                local rest = string.sub(tok, zpLen + 1)
                local zMatcher = EntitySearchEngine.compileSingleTokenMatcher(zpVal, false)
                if zMatcher.hasZoneMatch then
                    splits = splits or {}
                    splits[#splits + 1] = {
                        zoneMatcher = zMatcher,
                        restMatcher = EntitySearchEngine.compileSingleTokenMatcher(rest, false),
                    }
                end
            end
        end
    end

    return {
        tok = tok,
        zoneKeySet = zoneKeySet,
        hasZoneMatch = containsZoneMatch,
        roleMasks = roleMasks,
        synList = synList,
        splits = splits,
    }
end

function EntitySearchEngine.parseSearchQueryTokens(q)
    local matchers = {}
    if not q or q == "" then return matchers end
    for tok in string.gmatch(q, "[^ \t\r\n,>;/]+") do
        matchers[#matchers + 1] = EntitySearchEngine.compileSingleTokenMatcher(tok, true)
    end
    return matchers
end

function EntitySearchEngine.matchEntityZoneAgainstToken(e, matcher)
    if not matcher.hasZoneMatch then return false, nil end
    local zmVal = EntitySearchEngine.indexEntityZonesByMap(e)
    if not zmVal then return false, nil end
    local zSet = matcher.zoneKeySet
    for zKey, spIdx in pairs(zmVal) do
        if zSet[zKey] then
            return true, spIdx
        end
    end
    return false, nil
end

function EntitySearchEngine.matchEntityCorpusAgainstToken(e, matcher)
    local tok = matcher.tok
    local stateFlag = EntitySearchEngine.compileEntitySearchCorpus(e)
    if stateFlag ~= "" and string.find(stateFlag, tok, 1, true) then
        return true
    end
    if e.kind == "npc" then
        local flags = e.flags or 0
        if flags > 0 then
            local masks = matcher.roleMasks
            for index = 1, #masks do
                if math.floor(flags / masks[index]) % 2 == 1 then
                    return true
                end
            end
        end
    end
    local syns = matcher.synList
    if syns and stateFlag ~= "" then
        for index = 1, #syns do
            if string.find(stateFlag, syns[index], 1, true) then
                return true
            end
        end
    end
    if e.kind == "item" and e.id and C_Item and C_Item.GetItemNameByID then
        if e._clientItemName == nil then
            local itemName = C_Item.GetItemNameByID(e.id)
            e._clientItemName = itemName and lower(itemName) or false
        end
        if e._clientItemName and string.find(e._clientItemName, tok, 1, true) then
            return true
        end
    end
    return false
end

function EntitySearchEngine.matchEntityAgainstSingleToken(e, matcher)
    local zOk, zSpIdx = EntitySearchEngine.matchEntityZoneAgainstToken(e, matcher)
    if zOk then
        return true, zSpIdx or 1
    end
    if EntitySearchEngine.matchEntityCorpusAgainstToken(e, matcher) then
        return true, nil
    end
    local splits = matcher.splits
    if splits then
        for index = 1, #splits do
            local spawnCoord = splits[index]
            local okZ, spIdx = EntitySearchEngine.matchEntityZoneAgainstToken(e, spawnCoord.zoneMatcher)
            if okZ and EntitySearchEngine.matchEntityCorpusAgainstToken(e, spawnCoord.restMatcher) then
                return true, spIdx or 1
            end
        end
    end
    return false, nil
end

function EntitySearchEngine.matchEntityAgainstAllTokens(e, matchers)
    local matchedSpIdx = nil
    for index = 1, #matchers do
        local isCallOk, spIdx = EntitySearchEngine.matchEntityAgainstSingleToken(e, matchers[index])
        if not isCallOk then
            return false, nil
        end
        if spIdx and not matchedSpIdx then
            matchedSpIdx = spIdx
        end
    end
    return true, matchedSpIdx
end

function EntitySearchEngine.isFriendlyServiceNpc(e)
    if not e then return false end
    if e.isMonster or e.isPet then
        return false
    end
    
    if (e.flags or 0) > 0 then
        return true
    end
    
    local rawSub = e.id and EzWoWMapFinderSubNames and EzWoWMapFinderSubNames[e.id]
    if rawSub and rawSub ~= "" then
        local lsVal = lower(rawSub)
        for index = 1, #FRIENDLY_SUBNAME_KEYWORDS do
            if string.find(lsVal, FRIENDLY_SUBNAME_KEYWORDS[index], 1, true) then
                return true
            end
        end
    end
    return false
end

function EntitySearchEngine.acquireCategoryEntityPool(cat)
    if not SEARCH_POOLS then
        SEARCH_POOLS = {
            all = {},
            monster = {},
            normalMonster = {},
            rare = {},
            pet = {},
            npc = {},
            object = {},
            quest = {},
            item = {},
        }
        local visitedMap = {}

        for _, e in ipairs(EzWoWMapFinderData or {}) do
            if e and not visitedMap[e] then
                visitedMap[e] = true
                local entryKey = e.kind
                if entryKey == "npc" then
                    if EntitySearchEngine.isFriendlyServiceNpc(e) then
                        e.isMonster = nil
                        e.isRare = nil
                        SEARCH_POOLS.npc[#SEARCH_POOLS.npc + 1] = e
                    else
                        e.isMonster = true
                        SEARCH_POOLS.monster[#SEARCH_POOLS.monster + 1] = e
                        if e.isPet then
                            SEARCH_POOLS.pet[#SEARCH_POOLS.pet + 1] = e
                        end
                        if e.isRare then
                            SEARCH_POOLS.rare[#SEARCH_POOLS.rare + 1] = e
                        else
                            SEARCH_POOLS.normalMonster[#SEARCH_POOLS.normalMonster + 1] = e
                        end
                    end
                elseif SEARCH_POOLS[entryKey] then
                    local anchorTarget = SEARCH_POOLS[entryKey]
                    anchorTarget[#anchorTarget + 1] = e
                end
            end
        end

        local all = SEARCH_POOLS.all
        for _, entryKey in ipairs({ "monster", "npc", "object", "quest", "item" }) do
            local anchorTarget = SEARCH_POOLS[entryKey]
            for index = 1, #anchorTarget do
                all[#all + 1] = anchorTarget[index]
            end
        end
    end
    return SEARCH_POOLS[cat] or SEARCH_POOLS.all
end

ns.GetLocalizedEntityName = EntitySearchEngine.resolveLocalizedEntityName
ns.GetLocalizedEntitySubtitle = EntitySearchEngine.resolveLocalizedSubTitle
ns.FormatLocalizedZoneName = localizeZoneIdentifier
ns.ProjectSpawnToWorldMapCoords = EntitySearchEngine.projectWorldSpawnToMap
ns.GetEntityZoneMap = EntitySearchEngine.indexEntityZonesByMap
ns.GetPrimaryEntityZoneKey = EntitySearchEngine.resolveEntityZoneKey
ns.GetPrimaryEntityZoneDisplayName = EntitySearchEngine.resolveEntityZoneName
ns.ZoneKeyMatchesToken = EntitySearchEngine.doesZoneMatchQueryToken
ns.FormatGatherSkillTag = EntitySearchEngine.buildGatheringSkillBadge
ns.GetEntitySearchText = EntitySearchEngine.compileEntitySearchCorpus
ns.FormatPetRowTag = EntitySearchEngine.composePetRowTag
ns.AddPetTooltipLines = EntitySearchEngine.addPetTooltipLines
ns.BuildTokenMatcher = EntitySearchEngine.compileSingleTokenMatcher
ns.ParseQueryMatchers = EntitySearchEngine.parseSearchQueryTokens
ns.MatchEntityZoneFast = EntitySearchEngine.matchEntityZoneAgainstToken
ns.MatchEntityContentFast = EntitySearchEngine.matchEntityCorpusAgainstToken
ns.MatchEntityTokenFast = EntitySearchEngine.matchEntityAgainstSingleToken
ns.MatchEntityAllTokens = EntitySearchEngine.matchEntityAgainstAllTokens
ns.IsFriendlyNpcEntity = EntitySearchEngine.isFriendlyServiceNpc
ns.GetSearchPool = EntitySearchEngine.acquireCategoryEntityPool

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
EntitySearchEngine.GetLocalizedEntityName = ns.GetLocalizedEntityName
EntitySearchEngine.GetLocalizedEntitySubtitle = ns.GetLocalizedEntitySubtitle
EntitySearchEngine.GetPrimaryEntityZoneKey = ns.GetPrimaryEntityZoneKey
EntitySearchEngine.GetPrimaryEntityZoneDisplayName = ns.GetPrimaryEntityZoneDisplayName
EntitySearchEngine.ProjectSpawnToWorldMapCoords = ns.ProjectSpawnToWorldMapCoords
EntitySearchEngine.FormatLocalizedZoneName = ns.FormatLocalizedZoneName
