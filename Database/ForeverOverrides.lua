-- Forever-specific searchable metadata: verified zone names only; no invented map positions
EzWoWMapFinderData = EzWoWMapFinderData or {}
local function attach(kind, name, zone, flags, alias)
  local target
  for _, e in ipairs(EzWoWMapFinderData) do
    if e.kind == kind and e.names and e.names.enUS == name then target = e; break end
  end
  if not target then
    target = {kind=kind, names={enUS=name}, spawns={}}
    EzWoWMapFinderData[#EzWoWMapFinderData+1] = target
  end
  target.zone = zone
  if flags and flags ~= 0 then
    local current = target.flags or 0
    if math.floor(current / flags) % 2 == 0 then target.flags = current + flags end
  end
  target.aliases = target.aliases or {}
  for word in string.gmatch(alias or "", "%S+") do target.aliases[#target.aliases+1]=word end
end
attach("npc","Auctioneer Quickcoin","The Barrens / Redridge Mountains",4096,"경매 경매인")
attach("npc","Zelena Favorbreeze","Zephras Isle",4096,"경매 경매인")
attach("npc","Auctioneer Jaxon","Stormwind City",4096,"경매 경매인")
attach("npc","Auctioneer Graves","Stranglethorn Vale",4096,"경매 경매인")
attach("npc","Auctioneer Stampi","Thunder Bluff",4096,"경매 경매인")
attach("npc","Mystmane","Zephras Isle",0,"희귀 야수")
attach("npc","Brother Zendraas","Zephras Isle",1,"NPC")
attach("npc","Afadra Dunwall","Ironforge",1,"역사학자 NPC")
attach("npc","Gezzy Gunkgear","Stranglethorn Vale",4,"무법항 병참장교")
attach("npc","Shylamiir","Stormwind City",16,"약초채집 조련사")
attach("item","Cozy Sleeping Bag","Westfall / The Barrens / Stonetalon Mountains / Loch Modan / Hillsbrad Foothills",0,"편안한 침낭 숨겨진 아이템")
attach("item","Savory Whimsyfin Delight","Redridge Mountains",0,"요리 별미")
attach("item","Whimsyfin","Redridge Mountains",0,"물고기 낚시")
attach("item","Musical Gustjumper","Zephras Isle",0,"숨겨진 아이템 개구리")
attach("item","Rockslicer","The Deadmines",0,"도끼 광맥")
attach("item","Armor of the Fang","Wailing Caverns",0,"송곳니 갑옷")
