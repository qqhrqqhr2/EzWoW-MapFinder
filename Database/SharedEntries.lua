-- EzWoW - Map Finder : Entries from EzWoW - Data (see Core/SharedData.lua); runs after Locations_*
local _, ns = ...
local Shared = ns.SharedData
if type(Shared) == "table" and type(Shared.AfterLocations) == "function" then
    local ok = pcall(Shared.AfterLocations)
    if not ok then Shared.active = false end
end
