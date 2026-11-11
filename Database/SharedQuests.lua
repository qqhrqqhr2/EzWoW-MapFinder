-- EzWoW - Map Finder : Quest table from EzWoW - Data (see Core/SharedData.lua); runs after QuestData
local _, ns = ...
local Shared = ns.SharedData
if type(Shared) == "table" and type(Shared.AfterQuests) == "function" then
    local ok = pcall(Shared.AfterQuests)
    if not ok then Shared.active = false end
end
