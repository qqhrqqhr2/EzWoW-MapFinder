-- EzWoW - Map Finder : Names from EzWoW - Data (see Core/SharedData.lua); runs after AllNames_*
local _, ns = ...
local Shared = ns.SharedData
if type(Shared) == "table" and type(Shared.AfterNames) == "function" then
    local ok = pcall(Shared.AfterNames)
    if not ok then Shared.active = false end
end
