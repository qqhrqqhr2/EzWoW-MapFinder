--===========================================================================
-- EzWoW - Map Finder
-- Modules/QuestLogPins.lua : World Map marks for quests in the player's quest log
--===========================================================================
-- Quests whose objectives are done get a yellow "?" at their quest giver /
-- turn-in spots (from the built-in quest locations). Quests still in progress
-- can be shown too (grey "?", option). Clicking a mark sets a map waypoint.
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, pcall = type, pairs, ipairs, tonumber, tostring, pcall

local QuestLogPins = ns.QuestLogPins or {}
ns.QuestLogPins = QuestLogPins

local L = ns.L
local Theme = ns.Theme

local ICON_READY = "Interface\\GossipFrame\\ActiveQuestIcon"
local ICON_ACTIVE = "Interface\\GossipFrame\\IncompleteQuestIcon"
local MERGE_PIXELS = 12

local pins = {}
local questIndex      -- questID -> quest entry of the built-in data
local npcBySpot       -- "continent:x:y" -> npc entry (name for the tooltip)

local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function spotKey(sp)
    if type(sp) ~= "table" or type(sp[2]) ~= "number" or type(sp[3]) ~= "number" then return nil end
    return tostring(sp[1]) .. ":" .. math.floor(sp[2] + 0.5) .. ":" .. math.floor(sp[3] + 0.5)
end

function QuestLogPins.buildIndexes()
    if questIndex then return end
    questIndex, npcBySpot = {}, {}
    for _, e in ipairs(_G.EzWoWMapFinderData or {}) do
        if e.kind == "quest" and e.id then
            questIndex[e.id] = e
        elseif e.kind == "npc" and e.spawns then
            for _, sp in ipairs(e.spawns) do
                local key = spotKey(sp)
                if key and not npcBySpot[key] then npcBySpot[key] = e end
            end
        end
    end
end

-----------------------------------------------------------------------------
-- Quest log (C_QuestLog first, older globals as fallback)
-----------------------------------------------------------------------------
function QuestLogPins.isQuestComplete(questID, legacyComplete)
    if C_QuestLog then
        if C_QuestLog.ReadyForTurnIn then
            local ok, ready = pcall(C_QuestLog.ReadyForTurnIn, questID)
            if ok and ready == true then return true end
        end
        if C_QuestLog.IsComplete then
            local ok, done = pcall(C_QuestLog.IsComplete, questID)
            if ok and type(done) == "boolean" then return done end
        end
    end
    return legacyComplete == 1 or legacyComplete == true
end

function QuestLogPins.collectQuests()
    local list = {}
    local seen = {}
    local function add(questID, title, legacyComplete)
        questID = tonumber(questID)
        if not questID or questID <= 0 or seen[questID] or isSecret(questID) then return end
        seen[questID] = true
        list[#list + 1] = { id = questID, title = title, complete = QuestLogPins.isQuestComplete(questID, legacyComplete) }
    end
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local ok, count = pcall(C_QuestLog.GetNumQuestLogEntries)
        if ok and type(count) == "number" then
            for index = 1, count do
                local okInfo, info = pcall(C_QuestLog.GetInfo, index)
                if okInfo and type(info) == "table" and not info.isHeader and not info.isHidden then
                    add(info.questID, info.title)
                end
            end
            return list
        end
    end
    if type(GetNumQuestLogEntries) == "function" and type(GetQuestLogTitle) == "function" then
        local count = GetNumQuestLogEntries()
        for index = 1, tonumber(count) or 0 do
            local title, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(index)
            if not isHeader then add(questID, title, isComplete) end
        end
    end
    return list
end

-----------------------------------------------------------------------------
-- Marks
-----------------------------------------------------------------------------
function QuestLogPins.canvas()
    return (WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas())
        or (_G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock:GetCanvas())
        or WorldMapFrame
end

function QuestLogPins.obtainPin(index)
    local pin = pins[index]
    if pin then return pin end
    local canvasFrame = QuestLogPins.canvas()
    pin = CreateFrame("Button", nil, canvasFrame)
    pin:EnableMouse(true)
    pin:RegisterForClicks("LeftButtonUp")
    if pin.SetPropagateMouseClicks then pin:SetPropagateMouseClicks(false) end
    pin:SetSize(18, 18)
    pin:SetFrameStrata("HIGH")
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin:SetScript("OnEnter", function(self)
        local group = self.group
        if not group then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(group.npcName or (L.title or "EzWoW - Map Finder"), unpack(Theme.accent))
        for _, quest in ipairs(group.quests) do
            local state = quest.complete and ("|cff40ff59" .. L.questPinReady .. "|r") or ("|cffa7b9c5" .. L.questPinActive .. "|r")
            GameTooltip:AddLine((quest.title or ("#" .. quest.id)) .. "  " .. state, 0.929, 0.957, 0.969, true)
        end
        GameTooltip:AddLine(L.questPinHint, unpack(Theme.muted))
        GameTooltip:AddLine("EzWoW - Map Finder", unpack(Theme.muted))
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:SetScript("OnClick", function(self)
        local sp = self.group and self.group.spawn
        if not sp then return end
        if ns.ApplyWaypointForSpawn then ns.ApplyWaypointForSpawn(sp) end
    end)
    pins[index] = pin
    return pin
end

function QuestLogPins.hideAll()
    for _, pin in ipairs(pins) do pin:Hide() end
end

function QuestLogPins.refresh()
    QuestLogPins.hideAll()
    if not (ns.DB and ns.DB.questLogPins ~= false) then return end
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    local project = ns.ProjectSpawnToWorldMapCoords
    if not project then return end
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if not mapID or isSecret(mapID) then return end
    local canvasFrame = QuestLogPins.canvas()
    local cw, ch = canvasFrame:GetWidth(), canvasFrame:GetHeight()
    if not cw or not ch or cw <= 0 or ch <= 0 then return end
    local cScale = (WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()) or 1
    if not cScale or cScale <= 0 then cScale = 1 end

    QuestLogPins.buildIndexes()
    local showAll = ns.DB.questLogPinsAll == true
    local groups = {}
    for _, quest in ipairs(QuestLogPins.collectQuests()) do
        local entry = (quest.complete or showAll) and questIndex[quest.id]
        if entry and entry.spawns then
            if not quest.title or quest.title == "" or isSecret(quest.title) then
                quest.title = ns.GetLocalizedEntityName and ns.GetLocalizedEntityName(entry) or nil
            end
            local seenSpot = {}
            for _, sp in ipairs(entry.spawns) do
                local key = spotKey(sp) or tostring(sp)
                if not seenSpot[key] then
                    seenSpot[key] = true
                    local mapID2, mx, my = project(sp, mapID)
                    if mx and my and mapID2 == mapID then
                        local px, py = mx * cw, my * ch
                        local group
                        for _, g in ipairs(groups) do
                            if math.abs(g.px - px) * cScale < MERGE_PIXELS and math.abs(g.py - py) * cScale < MERGE_PIXELS then
                                group = g
                                break
                            end
                        end
                        if not group then
                            local npc = npcBySpot[key]
                            group = { px = px, py = py, spawn = sp, quests = {}, ids = {},
                                npcName = npc and ns.GetLocalizedEntityName and ns.GetLocalizedEntityName(npc) or nil }
                            groups[#groups + 1] = group
                        end
                        if not group.ids[quest.id] then
                            group.ids[quest.id] = true
                            group.quests[#group.quests + 1] = quest
                            if quest.complete then group.complete = true end
                        end
                    end
                end
            end
        end
    end

    local pinScale = 1 / cScale
    for index, group in ipairs(groups) do
        local pin = QuestLogPins.obtainPin(index)
        pin:SetParent(canvasFrame)
        pin:SetFrameLevel((canvasFrame:GetFrameLevel() or 10) + (group.complete and 200 or 190))
        pin.group = group
        pin.icon:SetTexture(group.complete and ICON_READY or ICON_ACTIVE)
        pin:SetScale(pinScale)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvasFrame, "TOPLEFT", group.px / pinScale, -group.py / pinScale)
        pin:Show()
    end
end

-- quest log changes: redraw only while the map is open
local events = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
    pcall(events.RegisterEvent, events, event)
end
local queued = false
events:SetScript("OnEvent", function()
    if queued or not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    queued = true
    C_Timer.After(0.2, function()
        queued = false
        QuestLogPins.refresh()
    end)
end)

ns.RefreshQuestLogPins = QuestLogPins.refresh
