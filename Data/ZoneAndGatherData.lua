--===========================================================================
-- EzWoW - Map Finder
-- Data/ZoneAndGatherData.lua : Zone Bounds, Keywords, Gather Skills & Transit
--===========================================================================
local _, ns = ...
local lower = ns.ToLowerSafeString

local ROLES = {
	{ 4096,  { "경매", "경매인", "경매장", "경매사", "옥션", "auction", "auctioneer", "ah", "auktion", "enchère", "encheres", "subasta", "аукцион", "拍卖", "拍賣" } },
	{ 256,   { "은행", "은행원", "창고", "금고", "bank", "banker", "banque", "banco", "банк", "银行", "銀行" } },
	{ 128,   { "여관", "여관주인", "귀환", "귀환석", "inn", "innkeeper", "gasthaus", "gastwirt", "auberge", "aubergiste", "posada", "tabernero", "таверн", "трактир", "旅店" } },
	{ 4,     { "상인", "판매", "상점", "잡화", "vendor", "merchant", "händler", "haendler", "marchand", "vendeur", "vendedor", "торгов", "продав", "商人" } },
	{ 8,     { "비행", "조련사", "와이번", "그리폰", "박쥐", "히포그리프", "날탈", "항공", "flight", "gryphon", "wyvern", "wind rider", "bat handler", "hippogryph", "flugmeister", "maître de vol", "maestro de vuelo", "распорядитель полетов", "飞行", "飛行" } },
	{ 16,    { "조련", "훈련", "전문가", "상급자", "기술", "trainer", "lehrer", "maître", "instructeur", "instructor", "тренер", "учитель", "训练师", "訓練師" } },
	{ 16384, { "수리", "수리공", "대장장이", "방어구", "repair", "reparatur", "répar", "reparar", "ремонт", "修理" } },
}

local QUERY_SYNONYMS = {
	["기공"] = { "기계공학", "engineering" },
	["마부"] = { "마법부여", "enchanting" },
	["가세"] = { "가죽세공", "leatherworking" },
	["연금"] = { "연금술", "alchemy" },
	["대장"] = { "대장기술", "대장장이", "blacksmith" },
	["약초"] = { "약초채집", "herbalism" },
	["무두"] = { "무두질", "skinning" },
	["재봉"] = { "재봉술", "tailoring" },
	["응치"] = { "응급치료", "first aid" },
	["응급"] = { "응급치료", "first aid" },
	["흑마"] = { "흑마법사", "warlock" },
	["법사"] = { "마법사", "mage" },
	["술사"] = { "주술사", "shaman" },
	["냥꾼"] = { "사냥꾼", "hunter" },
	["드루"] = { "드루이드", "druid" },
	["기사"] = { "성기사", "paladin" },
	["우편"] = { "우체통", "mailbox" },
	["편지함"] = { "우체통", "mailbox" },
	["우체통"] = { "우체통", "mailbox" },
	["경매장"] = { "경매", "경매인", "auction" },
	["옥션"] = { "경매", "경매인", "auction" },
	["창고"] = { "은행", "은행원", "bank" },
	["귀환"] = { "여관", "여관주인", "innkeeper" },
	["날탈"] = { "비행", "와이번", "그리폰", "박쥐", "히포그리프" },
}

local ZONE_BOUNDS = {
	{ uiMapID = 1411, mapID = 1, mtype = 3, isCity = false, xMin = -1716.67, yMin = -7250.0, xMax = 1808.33, yMax = -1962.5, key = "Durotar" },
	{ uiMapID = 1412, mapID = 1, mtype = 3, isCity = false, xMin = -3697.92, yMin = -3089.58, xMax = -272.92, yMax = 2047.92, key = "Mulgore" },
	{ uiMapID = 1413, mapID = 1, mtype = 3, isCity = false, xMin = -5143.75, yMin = -7510.42, xMax = 1612.5, yMax = 2622.92, key = "The Barrens" },
	{ uiMapID = 1414, mapID = 1, mtype = 2, isCity = false, xMin = -11733.3, yMin = -19733.21, xMax = 12799.9, yMax = 17066.6, key = "Kalimdor" },
	{ uiMapID = 1415, mapID = 0, mtype = 2, isCity = false, xMin = -16000.0, yMin = -19199.9, xMax = 7466.6, yMax = 16000.0, key = "Eastern Kingdoms" },
	{ uiMapID = 1416, mapID = 0, mtype = 3, isCity = false, xMin = -366.67, yMin = -2016.67, xMax = 1500.0, yMax = 783.33, key = "Alterac Mountains" },
	{ uiMapID = 1417, mapID = 0, mtype = 3, isCity = false, xMin = -2533.33, yMin = -4466.67, xMax = -133.33, yMax = -866.67, key = "Arathi Highlands" },
	{ uiMapID = 1418, mapID = 0, mtype = 3, isCity = false, xMin = -7547.92, yMin = -4566.67, xMax = -5889.58, yMax = -2079.17, key = "Badlands" },
	{ uiMapID = 1419, mapID = 0, mtype = 3, isCity = false, xMin = -12800.0, yMin = -4591.67, xMax = -10566.67, yMax = -1241.67, key = "Blasted Lands" },
	{ uiMapID = 1420, mapID = 0, mtype = 3, isCity = false, xMin = 825.0, yMin = -1485.42, xMax = 3837.5, yMax = 3033.33, key = "Tirisfal Glades" },
	{ uiMapID = 1421, mapID = 0, mtype = 3, isCity = false, xMin = -1133.33, yMin = -750.0, xMax = 1666.67, yMax = 3450.0, key = "Silverpine Forest" },
	{ uiMapID = 1422, mapID = 0, mtype = 3, isCity = false, xMin = 500.0, yMin = -3883.33, xMax = 3366.67, yMax = 416.67, key = "Western Plaguelands" },
	{ uiMapID = 1423, mapID = 0, mtype = 3, isCity = false, xMin = 1218.75, yMin = -6056.25, xMax = 3800.0, yMax = -2185.42, key = "Eastern Plaguelands" },
	{ uiMapID = 1424, mapID = 0, mtype = 3, isCity = false, xMin = -1733.33, yMin = -2133.33, xMax = 400.0, yMax = 1066.67, key = "Hillsbrad Foothills" },
	{ uiMapID = 1425, mapID = 0, mtype = 3, isCity = false, xMin = -1100.0, yMin = -5425.0, xMax = 1466.67, yMax = -1575.0, key = "The Hinterlands" },
	{ uiMapID = 1426, mapID = 0, mtype = 3, isCity = false, xMin = -7160.42, yMin = -3122.92, xMax = -3877.08, yMax = 1802.08, key = "Dun Morogh" },
	{ uiMapID = 1427, mapID = 0, mtype = 3, isCity = false, xMin = -7587.5, yMin = -2554.17, xMax = -6100.0, yMax = -322.92, key = "Searing Gorge" },
	{ uiMapID = 1428, mapID = 0, mtype = 3, isCity = false, xMin = -8983.33, yMin = -3195.83, xMax = -7031.25, yMax = -266.67, key = "Burning Steppes" },
	{ uiMapID = 1429, mapID = 0, mtype = 3, isCity = false, xMin = -10254.17, yMin = -1935.42, xMax = -7939.58, yMax = 1535.42, key = "Elwynn Forest" },
	{ uiMapID = 1430, mapID = 0, mtype = 3, isCity = false, xMin = -11533.33, yMin = -3333.33, xMax = -9866.67, yMax = -833.33, key = "Deadwind Pass" },
	{ uiMapID = 1431, mapID = 0, mtype = 3, isCity = false, xMin = -11516.67, yMin = -1866.67, xMax = -9716.67, yMax = 833.33, key = "Duskwood" },
	{ uiMapID = 1432, mapID = 0, mtype = 3, isCity = false, xMin = -6327.08, yMin = -4752.08, xMax = -4487.5, yMax = -1993.75, key = "Loch Modan" },
	{ uiMapID = 1433, mapID = 0, mtype = 3, isCity = false, xMin = -10022.92, yMin = -3741.67, xMax = -8575.0, yMax = -1570.83, key = "Redridge Mountains" },
	{ uiMapID = 1434, mapID = 0, mtype = 3, isCity = false, xMin = -15422.92, yMin = -4160.42, xMax = -11168.75, yMax = 2220.83, key = "Stranglethorn Vale" },
	{ uiMapID = 1435, mapID = 0, mtype = 3, isCity = false, xMin = -11150.0, yMin = -4516.67, xMax = -9620.83, yMax = -2222.92, key = "Swamp of Sorrows" },
	{ uiMapID = 1436, mapID = 0, mtype = 3, isCity = false, xMin = -11733.33, yMin = -483.33, xMax = -9400.0, yMax = 3016.67, key = "Westfall" },
	{ uiMapID = 1437, mapID = 0, mtype = 3, isCity = false, xMin = -4904.17, yMin = -4525.0, xMax = -2147.92, yMax = -389.58, key = "Wetlands" },
	{ uiMapID = 1438, mapID = 1, mtype = 3, isCity = false, xMin = 8437.5, yMin = -1277.08, xMax = 11831.25, yMax = 3814.58, key = "Teldrassil" },
	{ uiMapID = 1439, mapID = 1, mtype = 3, isCity = false, xMin = 3966.67, yMin = -3608.33, xMax = 8333.33, yMax = 2941.67, key = "Darkshore" },
	{ uiMapID = 1440, mapID = 1, mtype = 3, isCity = false, xMin = 829.17, yMin = -4066.67, xMax = 4672.92, yMax = 1700.0, key = "Ashenvale" },
	{ uiMapID = 1441, mapID = 1, mtype = 3, isCity = false, xMin = -6900.0, yMin = -4833.33, xMax = -3966.67, yMax = -433.33, key = "Thousand Needles" },
	{ uiMapID = 1442, mapID = 1, mtype = 3, isCity = false, xMin = -339.58, yMin = -1637.5, xMax = 2916.67, yMax = 3245.83, key = "Stonetalon Mountains" },
	{ uiMapID = 1443, mapID = 1, mtype = 3, isCity = false, xMin = -2545.83, yMin = -262.5, xMax = 452.08, yMax = 4233.33, key = "Desolace" },
	{ uiMapID = 1444, mapID = 1, mtype = 3, isCity = false, xMin = -7000.0, yMin = -1508.33, xMax = -2366.67, yMax = 5441.67, key = "Feralas" },
	{ uiMapID = 1445, mapID = 1, mtype = 3, isCity = false, xMin = -5533.33, yMin = -6225.0, xMax = -2033.33, yMax = -975.0, key = "Dustwallow Marsh" },
	{ uiMapID = 1446, mapID = 1, mtype = 3, isCity = false, xMin = -10475.0, yMin = -7118.75, xMax = -5875.0, yMax = -218.75, key = "Tanaris" },
	{ uiMapID = 1447, mapID = 1, mtype = 3, isCity = false, xMin = 1960.42, yMin = -8347.92, xMax = 5341.67, yMax = -3277.08, key = "Azshara" },
	{ uiMapID = 1448, mapID = 1, mtype = 3, isCity = false, xMin = 3300.0, yMin = -4108.33, xMax = 7133.33, yMax = 1641.67, key = "Felwood" },
	{ uiMapID = 1449, mapID = 1, mtype = 3, isCity = false, xMin = -8433.33, yMin = -3166.67, xMax = -5966.67, yMax = 533.33, key = "Un'Goro Crater" },
	{ uiMapID = 1450, mapID = 1, mtype = 3, isCity = false, xMin = 6952.08, yMin = -3689.58, xMax = 8491.67, yMax = -1381.25, key = "Moonglade" },
	{ uiMapID = 1451, mapID = 1, mtype = 3, isCity = false, xMin = -8281.25, yMin = -945.83, xMax = -5958.33, yMax = 2537.5, key = "Silithus" },
	{ uiMapID = 1452, mapID = 1, mtype = 3, isCity = false, xMin = 3800.0, yMin = -7416.67, xMax = 8533.33, yMax = -316.67, key = "Winterspring" },
	{ uiMapID = 1453, mapID = 0, mtype = 3, isCity = true, xMin = -9175.2, yMin = 36.7, xMax = -8278.85, yMax = 1380.97, key = "Stormwind City" },
	{ uiMapID = 1454, mapID = 1, mtype = 3, isCity = true, xMin = 1338.46, yMin = -5083.21, xMax = 2273.88, yMax = -3680.6, key = "Orgrimmar" },
	{ uiMapID = 1455, mapID = 0, mtype = 3, isCity = true, xMin = -5096.85, yMin = -1504.22, xMax = -4569.24, yMax = -713.59, key = "Ironforge" },
	{ uiMapID = 1456, mapID = 1, mtype = 3, isCity = true, xMin = -1545.83, yMin = -527.08, xMax = -850.0, yMax = 516.67, key = "Thunder Bluff" },
	{ uiMapID = 1457, mapID = 1, mtype = 3, isCity = true, xMin = 9532.59, yMin = 1880.03, xMax = 10238.32, yMax = 2938.36, key = "Darnassus" },
	{ uiMapID = 1458, mapID = 0, mtype = 3, isCity = true, xMin = 1237.84, yMin = -86.18, xMax = 1877.95, yMax = 873.19, key = "Undercity" },
	{ uiMapID = 1459, mapID = 30, mtype = 3, isCity = false, xMin = -1739.58, yMin = -2456.25, xMax = 1085.42, yMax = 1781.25, key = "Alterac Valley" },
	{ uiMapID = 1460, mapID = 489, mtype = 3, isCity = false, xMin = 862.5, yMin = 895.83, xMax = 1627.08, yMax = 2041.67, key = "Warsong Gulch" },
	{ uiMapID = 1461, mapID = 529, mtype = 3, isCity = false, xMin = 337.5, yMin = 102.08, xMax = 1508.33, yMax = 1858.33, key = "Arathi Basin" },
	{ uiMapID = 947, mapID = 0, mtype = 1, isCity = false, xMin = -16000.0, yMin = -7466.7, xMax = 6933.3, yMax = 8000.0, key = "Azeroth" },
}

local ZONE_BOUNDS_BY_ID = {}
local ZONE_ID_BY_KEY = {}
for _, b in ipairs(ZONE_BOUNDS) do
	ZONE_BOUNDS_BY_ID[b.uiMapID] = b
	if not ZONE_ID_BY_KEY[b.key] then
		ZONE_ID_BY_KEY[b.key] = b.uiMapID
	end
end

local INSTANCE_ZONES = {
	[33] = { uiMapID = 1421, mx = 0.448, my = 0.678, key = "Shadowfang Keep" },
	[34] = { uiMapID = 1453, mx = 0.506, my = 0.666, key = "The Stockade" },
	[36] = { uiMapID = 1436, mx = 0.426, my = 0.718, key = "The Deadmines" },
	[43] = { uiMapID = 1413, mx = 0.460, my = 0.364, key = "Wailing Caverns" },
	[47] = { uiMapID = 1413, mx = 0.415, my = 0.896, key = "Razorfen Kraul" },
	[48] = { uiMapID = 1440, mx = 0.145, my = 0.142, key = "Blackfathom Deeps" },
	[70] = { uiMapID = 1418, mx = 0.416, my = 0.116, key = "Uldaman" },
	[90] = { uiMapID = 1426, mx = 0.241, my = 0.398, key = "Gnomeregan" },
	[109] = { uiMapID = 1435, mx = 0.700, my = 0.536, key = "The Temple of Atal'Hakkar" },
	[129] = { uiMapID = 1413, mx = 0.490, my = 0.932, key = "Razorfen Downs" },
	[189] = { uiMapID = 1420, mx = 0.852, my = 0.322, key = "Scarlet Monastery" },
	[209] = { uiMapID = 1446, mx = 0.390, my = 0.200, key = "Zul'Farrak" },
	[229] = { uiMapID = 1428, mx = 0.294, my = 0.382, key = "Blackrock Spire" },
	[230] = { uiMapID = 1427, mx = 0.348, my = 0.850, key = "Blackrock Depths" },
	[249] = { uiMapID = 1445, mx = 0.526, my = 0.762, key = "Onyxia's Lair" },
	[289] = { uiMapID = 1422, mx = 0.694, my = 0.732, key = "Scholomance" },
	[309] = { uiMapID = 1434, mx = 0.538, my = 0.176, key = "Zul'Gurub" },
	[329] = { uiMapID = 1423, mx = 0.276, my = 0.116, key = "Stratholme" },
	[349] = { uiMapID = 1443, mx = 0.292, my = 0.626, key = "Maraudon" },
	[369] = { uiMapID = 1453, mx = 0.696, my = 0.308, key = "Deeprun Tram" },
	[389] = { uiMapID = 1454, mx = 0.526, my = 0.490, key = "Ragefire Chasm" },
	[409] = { uiMapID = 1427, mx = 0.348, my = 0.850, key = "Molten Core" },
	[429] = { uiMapID = 1444, mx = 0.604, my = 0.308, key = "Dire Maul" },
	[449] = { uiMapID = 1453, mx = 0.796, my = 0.692, key = "Stormwind City" },
	[450] = { uiMapID = 1454, mx = 0.382, my = 0.712, key = "Orgrimmar" },
	[469] = { uiMapID = 1428, mx = 0.294, my = 0.382, key = "Blackwing Lair" },
	[509] = { uiMapID = 1451, mx = 0.292, my = 0.934, key = "Ruins of Ahn'Qiraj" },
	[531] = { uiMapID = 1451, mx = 0.286, my = 0.958, key = "Ahn'Qiraj" },
	[533] = { uiMapID = 1423, mx = 0.394, my = 0.262, key = "Naxxramas" },
}
for _, info in pairs(INSTANCE_ZONES) do
	if not ZONE_ID_BY_KEY[info.key] then
		ZONE_ID_BY_KEY[info.key] = info.uiMapID
	end
end

local EXTRA_ZONE_KEY_BY_MAPID = {
	[2482] = "Mount Hyjal",
	[2521] = "Zephras Isle",
	[2548] = "Riverglades",
}
for mapID, zKey in pairs(EXTRA_ZONE_KEY_BY_MAPID) do
	if not ZONE_ID_BY_KEY[zKey] then
		ZONE_ID_BY_KEY[zKey] = mapID
	end
end

local ZONE_NAMES = {
	["Ahn'Qiraj"] = { enUS = "Ahn'Qiraj", koKR = "안퀴라즈", deDE = "Ahn'Qiraj", frFR = "Ahn'Qiraj", esES = "Ahn'Qiraj", ruRU = "Ан'Кираж", zhCN = "安其拉", zhTW = "安其拉" },
	["Alterac Mountains"] = { enUS = "Alterac Mountains", koKR = "알터랙 산맥", deDE = "Alteracgebirge", frFR = "Montagnes d'Alterac", esES = "Montañas de Alterac", ruRU = "Альтеракские горы", zhCN = "奥特兰克山脉", zhTW = "奧特蘭克山脈" },
	["Alterac Valley"] = { enUS = "Alterac Valley", koKR = "알터랙 계곡", deDE = "Alteractal", frFR = "Vallée d'Alterac", esES = "Valle de Alterac", ruRU = "Альтеракская долина", zhCN = "奥特兰克山谷", zhTW = "奧特蘭克山谷" },
	["Arathi Basin"] = { enUS = "Arathi Basin", koKR = "아라시 분지", deDE = "Arathibecken", frFR = "Bassin d'Arathi", esES = "Cuenca de Arathi", ruRU = "Низина Арати", zhCN = "阿拉希盆地", zhTW = "阿拉希盆地" },
	["Arathi Highlands"] = { enUS = "Arathi Highlands", koKR = "아라시 고원", deDE = "Arathihochland", frFR = "Hautes-terres d'Arathi", esES = "Tierras Altas de Arathi", ruRU = "Нагорье Арати", zhCN = "阿拉希高地", zhTW = "阿拉希高地" },
	["Ashenvale"] = { enUS = "Ashenvale", koKR = "잿빛 골짜기", deDE = "Eschental", frFR = "Orneval", esES = "Vallefresno", ruRU = "Ясеневый лес", zhCN = "灰谷", zhTW = "梣谷" },
	["Azeroth"] = { enUS = "Azeroth", koKR = "아제로스", deDE = "Azeroth", frFR = "Azeroth", esES = "Azeroth", ruRU = "Азерот", zhCN = "艾泽拉斯", zhTW = "艾澤拉斯" },
	["Azshara"] = { enUS = "Azshara", koKR = "아즈샤라", deDE = "Azshara", frFR = "Azshara", esES = "Azshara", ruRU = "Азшара", zhCN = "艾萨拉", zhTW = "艾薩拉" },
	["Badlands"] = { enUS = "Badlands", koKR = "황야의 땅", deDE = "Ödland", frFR = "Terres ingrates", esES = "Tierras Inhóspitas", ruRU = "Бесплодные земли", zhCN = "荒芜之地", zhTW = "荒蕪之地" },
	["Blackfathom Deeps"] = { enUS = "Blackfathom Deeps", koKR = "검은심연의 나락", deDE = "Tiefschwarze Grotte", frFR = "Profondeurs de Brassenoire", esES = "Cavernas de Brazanegra", ruRU = "Непроглядная Пучина", zhCN = "黑暗深渊", zhTW = "黑澗深淵" },
	["Blackrock Depths"] = { enUS = "Blackrock Depths", koKR = "검은바위 나락", deDE = "Schwarzfelstiefen", frFR = "Profondeurs de Blackrock", esES = "Profundidades de Roca Negra", ruRU = "Глубины Черной Горы", zhCN = "黑石深渊", zhTW = "黑石深淵" },
	["Blackrock Spire"] = { enUS = "Blackrock Spire", koKR = "검은바위 첨탑", deDE = "Blackrock Spitze", frFR = "Pic Blackrock", esES = "Cumbre de Roca Negra", ruRU = "Вершина Черной Горы", zhCN = "黑石塔", zhTW = "黑石塔" },
	["Blackwing Lair"] = { enUS = "Blackwing Lair", koKR = "검은날개 둥지", deDE = "Pechschwingenhort", frFR = "Repaire de l'Aile noire", esES = "Guarida Alanegra", ruRU = "Логово Крыла Тьмы", zhCN = "黑翼之巢", zhTW = "黑翼之巢" },
	["Blasted Lands"] = { enUS = "Blasted Lands", koKR = "저주받은 땅", deDE = "Verwüstete Lande", frFR = "Terres foudroyées", esES = "Las Tierras Devastadas", ruRU = "Выжженные земли", zhCN = "诅咒之地", zhTW = "詛咒之地" },
	["Burning Steppes"] = { enUS = "Burning Steppes", koKR = "불타는 평원", deDE = "Brennende Steppe", frFR = "Steppes ardentes", esES = "Las Estepas Ardientes", ruRU = "Пылающие степи", zhCN = "燃烧平原", zhTW = "燃燒平原" },
	["Darkshore"] = { enUS = "Darkshore", koKR = "어둠의 해안", deDE = "Dunkelküste", frFR = "Sombrivage", esES = "Costa Oscura", ruRU = "Темные берега", zhCN = "黑海岸", zhTW = "黑海岸" },
	["Darnassus"] = { enUS = "Darnassus", koKR = "다르나서스", deDE = "Darnassus", frFR = "Darnassus", esES = "Darnassus", ruRU = "Дарнасс", zhCN = "达纳苏斯", zhTW = "達納蘇斯" },
	["Deadwind Pass"] = { enUS = "Deadwind Pass", koKR = "죽음의 고개", deDE = "Gebirgspass der Totenwinde", frFR = "Défilé de Deuillevent", esES = "Paso de la Muerte", ruRU = "Перевал Мертвого Ветра", zhCN = "逆风小径", zhTW = "逆風小徑" },
	["Deeprun Tram"] = { enUS = "Deeprun Tram", koKR = "깊은굴 지하철", deDE = "Tiefenbahn", frFR = "Tram des profondeurs", esES = "Tren Subterráneo", ruRU = "Подземный поезд", zhCN = "矿道地铁", zhTW = "礦道地鐵" },
	["Desolace"] = { enUS = "Desolace", koKR = "잊혀진 땅", deDE = "Desolace", frFR = "Désolace", esES = "Desolace", ruRU = "Пустоши", zhCN = "凄凉之地", zhTW = "淒涼之地" },
	["Dire Maul"] = { enUS = "Dire Maul", koKR = "혈투의 전장", deDE = "Düsterbruch", frFR = "Hache-tripes", esES = "La Masacre", ruRU = "Забытый Город", zhCN = "厄运之槌", zhTW = "厄運之槌" },
	["Dun Morogh"] = { enUS = "Dun Morogh", koKR = "던 모로", deDE = "Dun Morogh", frFR = "Dun Morogh", esES = "Dun Morogh", ruRU = "Дун Морог", zhCN = "丹莫罗", zhTW = "丹莫洛" },
	["Durotar"] = { enUS = "Durotar", koKR = "듀로타", deDE = "Durotar", frFR = "Durotar", esES = "Durotar", ruRU = "Дуротар", zhCN = "杜隆塔尔", zhTW = "杜洛塔" },
	["Duskwood"] = { enUS = "Duskwood", koKR = "그늘숲", deDE = "Dämmerwald", frFR = "Bois de la Pénombre", esES = "Bosque del Ocaso", ruRU = "Сумеречный лес", zhCN = "暮色森林", zhTW = "暮色森林" },
	["Dustwallow Marsh"] = { enUS = "Dustwallow Marsh", koKR = "먼지진흙 습지대", deDE = "Düstermarschen", frFR = "Marécage d'Âprefange", esES = "Marjal Revolcafango", ruRU = "Пылевые топи", zhCN = "尘泥沼泽", zhTW = "塵泥沼澤" },
	["Eastern Kingdoms"] = { enUS = "Eastern Kingdoms", koKR = "동부 왕국", deDE = "Östliche Königreiche", frFR = "Royaumes de l'est", esES = "Reinos del Este", ruRU = "Восточные Королевства", zhCN = "东部王国", zhTW = "東部王國" },
	["Eastern Plaguelands"] = { enUS = "Eastern Plaguelands", koKR = "동부 역병지대", deDE = "Östliche Pestländer", frFR = "Maleterres de l'est", esES = "Tierras de la Peste del Este", ruRU = "Восточные Чумные земли", zhCN = "东瘟疫之地", zhTW = "東瘟疫之地" },
	["Elwynn Forest"] = { enUS = "Elwynn Forest", koKR = "엘윈 숲", deDE = "Wald von Elwynn", frFR = "Forêt d'Elwynn", esES = "Bosque de Elwynn", ruRU = "Элвиннский лес", zhCN = "艾尔文森林", zhTW = "艾爾文森林" },
	["Felwood"] = { enUS = "Felwood", koKR = "악령의 숲", deDE = "Teufelswald", frFR = "Gangrebois", esES = "Frondavil", ruRU = "Оскверненный лес", zhCN = "费伍德森林", zhTW = "費伍德森林" },
	["Feralas"] = { enUS = "Feralas", koKR = "페랄라스", deDE = "Feralas", frFR = "Féralas", esES = "Feralas", ruRU = "Фералас", zhCN = "菲拉斯", zhTW = "菲拉斯" },
	["Gnomeregan"] = { enUS = "Gnomeregan", koKR = "놈리건", deDE = "Gnomeregan", frFR = "Gnomeregan", esES = "Gnomeregan", ruRU = "Гномреган", zhCN = "诺莫瑞根", zhTW = "諾姆瑞根" },
	["Hillsbrad Foothills"] = { enUS = "Hillsbrad Foothills", koKR = "힐스브래드 구릉지", deDE = "Vorgebirge von Hillsbrad", frFR = "Contreforts d'Hillsbrad", esES = "Laderas de Trabalomas", ruRU = "Предгорья Хилсбрада", zhCN = "希尔斯布莱德丘陵", zhTW = "希爾斯布萊德丘陵" },
	["Ironforge"] = { enUS = "Ironforge", koKR = "아이언포지", deDE = "Eisenschmiede", frFR = "Ironforge", esES = "Forjaz", ruRU = "Стальгорн", zhCN = "铁炉堡", zhTW = "鐵爐堡" },
	["Kalimdor"] = { enUS = "Kalimdor", koKR = "칼림도어", deDE = "Kalimdor", frFR = "Kalimdor", esES = "Kalimdor", ruRU = "Калимдор", zhCN = "卡利姆多", zhTW = "卡林多" },
	["Loch Modan"] = { enUS = "Loch Modan", koKR = "모단 호수", deDE = "Loch Modan", frFR = "Loch Modan", esES = "Loch Modan", ruRU = "Лок Модан", zhCN = "洛克莫丹", zhTW = "洛克莫丹" },
	["Maraudon"] = { enUS = "Maraudon", koKR = "마라우돈", deDE = "Maraudon", frFR = "Maraudon", esES = "Maraudon", ruRU = "Марадон", zhCN = "玛拉顿", zhTW = "瑪拉頓" },
	["Molten Core"] = { enUS = "Molten Core", koKR = "화산 심장부", deDE = "Geschmolzener Kern", frFR = "Cœur du Magma", esES = "Núcleo de Magma", ruRU = "Огненные Недра", zhCN = "熔火之心", zhTW = "熔火之心" },
	["Moonglade"] = { enUS = "Moonglade", koKR = "달의 숲", deDE = "Mondlichtung", frFR = "Reflet-de-Lune", esES = "Claro de la Luna", ruRU = "Лунная поляна", zhCN = "月光林地", zhTW = "月光林地" },
	["Mount Hyjal"] = { enUS = "Mount Hyjal", koKR = "하이잘 산", deDE = "Berg Hyjal", frFR = "Mont Hyjal", esES = "Monte Hyjal", ruRU = "Гора Хиджал", zhCN = "海加尔山", zhTW = "海加爾山" },
	["Mulgore"] = { enUS = "Mulgore", koKR = "멀고어", deDE = "Mulgore", frFR = "Mulgore", esES = "Mulgore", ruRU = "Мулгор", zhCN = "莫高雷", zhTW = "莫高雷" },
	["Naxxramas"] = { enUS = "Naxxramas", koKR = "낙스라마스", deDE = "Naxxramas", frFR = "Naxxramas", esES = "Naxxramas", ruRU = "Наксрамас", zhCN = "纳克萨玛斯", zhTW = "納克薩瑪斯" },
	["Onyxia's Lair"] = { enUS = "Onyxia's Lair", koKR = "오닉시아의 둥지", deDE = "Onyxias Hort", frFR = "Repaire d'Onyxia", esES = "Guarida de Onyxia", ruRU = "Логово Ониксии", zhCN = "奥妮克希亚的巢穴", zhTW = "奧妮克希亞的巢穴" },
	["Orgrimmar"] = { enUS = "Orgrimmar", koKR = "오그리마", deDE = "Orgrimmar", frFR = "Orgrimmar", esES = "Orgrimmar", ruRU = "Оргриммар", zhCN = "奥格瑞玛", zhTW = "奧格瑪" },
	["Ragefire Chasm"] = { enUS = "Ragefire Chasm", koKR = "성난불길 협곡", deDE = "Flammenschlund", frFR = "Gouffre de Ragefeu", esES = "Sima Ígnea", ruRU = "Огненная пропасть", zhCN = "怒焰裂谷", zhTW = "怒焰裂谷" },
	["Razorfen Downs"] = { enUS = "Razorfen Downs", koKR = "가시덩굴 구릉", deDE = "Die Hügel von Razorfen", frFR = "Souilles de Tranchebauge", esES = "Zahúrda Rajacieno", ruRU = "Курганы Иглошкурых", zhCN = "剃刀高地", zhTW = "剃刀高地" },
	["Razorfen Kraul"] = { enUS = "Razorfen Kraul", koKR = "가시덩굴 우리", deDE = "Der Kral von Razorfen", frFR = "Kraal de Tranchebauge", esES = "Horado Rajacieno", ruRU = "Лабиринты Иглошкурых", zhCN = "剃刀沼泽", zhTW = "剃刀沼澤" },
	["Redridge Mountains"] = { enUS = "Redridge Mountains", koKR = "붉은마루 산맥", deDE = "Rotkammgebirge", frFR = "Les Carmines", esES = "Montañas Crestagrana", ruRU = "Красногорье", zhCN = "赤脊山", zhTW = "赤脊山" },
	["Riverglades"] = { enUS = "Riverglades", koKR = "강물숲", deDE = "Riverglades", frFR = "Riverglades", esES = "Riverglades", ruRU = "Речные поляны", zhCN = "河间林地", zhTW = "河間林地" },
	["Ruins of Ahn'Qiraj"] = { enUS = "Ruins of Ahn'Qiraj", koKR = "안퀴라즈 폐허", deDE = "Ruinen von Ahn'Qiraj", frFR = "Ruines d'Ahn'Qiraj", esES = "Ruinas de Ahn'Qiraj", ruRU = "Руины Ан'Киража", zhCN = "安其拉废墟", zhTW = "安其拉廢墟" },
	["Scarlet Monastery"] = { enUS = "Scarlet Monastery", koKR = "붉은십자군 수도원", deDE = "Das Scharlachrote Kloster", frFR = "Monastère écarlate", esES = "Monasterio Escarlata", ruRU = "Монастырь Алого Ордена", zhCN = "血色修道院", zhTW = "血色修道院" },
	["Scholomance"] = { enUS = "Scholomance", koKR = "스칼로맨스", deDE = "Scholomance", frFR = "Scholomance", esES = "Scholomance", ruRU = "Некроситет", zhCN = "通灵学院", zhTW = "通靈學院" },
	["Searing Gorge"] = { enUS = "Searing Gorge", koKR = "이글거리는 협곡", deDE = "Sengende Schlucht", frFR = "Gorge des Vents brûlants", esES = "La Garganta de Fuego", ruRU = "Тлеющее ущелье", zhCN = "灼热峡谷", zhTW = "灼熱峽谷" },
	["Shadowfang Keep"] = { enUS = "Shadowfang Keep", koKR = "그림자송곳니 성채", deDE = "Burg Shadowfang", frFR = "Donjon d'Ombrecroc", esES = "Castillo de Colmillo Oscuro", ruRU = "Крепость Темного Клыка", zhCN = "影牙城堡", zhTW = "影牙城堡" },
	["Silithus"] = { enUS = "Silithus", koKR = "실리더스", deDE = "Silithus", frFR = "Silithus", esES = "Silithus", ruRU = "Силитус", zhCN = "希利苏斯", zhTW = "希利蘇斯" },
	["Silverpine Forest"] = { enUS = "Silverpine Forest", koKR = "은빛소나무 숲", deDE = "Silberwald", frFR = "Forêt des Pins argentés", esES = "Bosque de Argénteos", ruRU = "Серебряный бор", zhCN = "银松森林", zhTW = "銀松森林" },
	["Stonetalon Mountains"] = { enUS = "Stonetalon Mountains", koKR = "돌발톱 산맥", deDE = "Steinkrallengebirge", frFR = "Les Serres-Rocheuses", esES = "Sierra Espolón", ruRU = "Когтистые горы", zhCN = "石爪山脉", zhTW = "石爪山脈" },
	["Stormwind City"] = { enUS = "Stormwind City", koKR = "스톰윈드", deDE = "Sturmwind", frFR = "Cité de Stormwind", esES = "Ciudad de Ventormenta", ruRU = "Штормград", zhCN = "暴风城", zhTW = "暴風城" },
	["Stranglethorn Vale"] = { enUS = "Stranglethorn Vale", koKR = "가시덤불 골짜기", deDE = "Schlingendorntal", frFR = "Vallée de Strangleronce", esES = "Vega de Tuercespina", ruRU = "Тернистая долина", zhCN = "荆棘谷", zhTW = "荊棘谷" },
	["Stratholme"] = { enUS = "Stratholme", koKR = "스트라솔름", deDE = "Stratholme", frFR = "Stratholme", esES = "Stratholme", ruRU = "Стратхольм", zhCN = "斯坦索姆", zhTW = "斯坦索姆" },
	["Swamp of Sorrows"] = { enUS = "Swamp of Sorrows", koKR = "슬픔의 늪", deDE = "Sümpfe des Elends", frFR = "Marais des Chagrins", esES = "Pantano de las Penas", ruRU = "Болото Печали", zhCN = "悲伤沼泽", zhTW = "悲傷沼澤" },
	["Tanaris"] = { enUS = "Tanaris", koKR = "타나리스", deDE = "Tanaris", frFR = "Tanaris", esES = "Tanaris", ruRU = "Танарис", zhCN = "塔纳利斯", zhTW = "塔納利斯" },
	["Teldrassil"] = { enUS = "Teldrassil", koKR = "텔드랏실", deDE = "Teldrassil", frFR = "Teldrassil", esES = "Teldrassil", ruRU = "Тельдрассил", zhCN = "泰达希尔", zhTW = "泰達希爾" },
	["The Barrens"] = { enUS = "The Barrens", koKR = "불모의 땅", deDE = "Das Brachland", frFR = "Les Tarides", esES = "Los Baldíos", ruRU = "Степи", zhCN = "贫瘠之地", zhTW = "貧瘠之地" },
	["The Deadmines"] = { enUS = "The Deadmines", koKR = "죽음의 폐광", deDE = "Die Todesminen", frFR = "Les Mortemines", esES = "Las Minas de la Muerte", ruRU = "Мертвые Копи", zhCN = "死亡矿井", zhTW = "死亡礦坑" },
	["The Hinterlands"] = { enUS = "The Hinterlands", koKR = "동부 내륙지", deDE = "Hinterland", frFR = "Les Hinterlands", esES = "Tierras del Interior", ruRU = "Внутренние земли", zhCN = "辛特兰", zhTW = "辛特蘭" },
	["The Stockade"] = { enUS = "The Stockade", koKR = "스톰윈드 지하감옥", deDE = "Das Verlies", frFR = "La Prison", esES = "Las Mazmorras", ruRU = "Тюрьма", zhCN = "监狱", zhTW = "暴風城監獄" },
	["The Temple of Atal'Hakkar"] = { enUS = "The Temple of Atal'Hakkar", koKR = "아탈학카르 신전", deDE = "Der Tempel von Atal'Hakkar", frFR = "Le temple d'Atal'Hakkar", esES = "Templo de Atal'Hakkar", ruRU = "Храм Атал'Хаккар", zhCN = "阿塔哈卡神庙", zhTW = "阿塔哈卡神廟" },
	["Thousand Needles"] = { enUS = "Thousand Needles", koKR = "버섯구름 봉우리", deDE = "Tausend Nadeln", frFR = "Mille pointes", esES = "Las Mil Agujas", ruRU = "Тысяча Игл", zhCN = "千针石林", zhTW = "千針石林" },
	["Thunder Bluff"] = { enUS = "Thunder Bluff", koKR = "썬더 블러프", deDE = "Donnerfels", frFR = "Thunder Bluff", esES = "Cima del Trueno", ruRU = "Громовой Утес", zhCN = "雷霆崖", zhTW = "雷霆崖" },
	["Tirisfal Glades"] = { enUS = "Tirisfal Glades", koKR = "티리스팔 숲", deDE = "Tirisfal", frFR = "Clairières de Tirisfal", esES = "Claros de Tirisfal", ruRU = "Тирисфальские леса", zhCN = "提瑞斯法林地", zhTW = "提里斯法林地" },
	["Uldaman"] = { enUS = "Uldaman", koKR = "울다만", deDE = "Uldaman", frFR = "Uldaman", esES = "Uldaman", ruRU = "Ульдаман", zhCN = "奥达曼", zhTW = "奧達曼" },
	["Un'Goro Crater"] = { enUS = "Un'Goro Crater", koKR = "운고로 분화구", deDE = "Krater von Un'Goro", frFR = "Cratère d'Un'Goro", esES = "Cráter de Un'Goro", ruRU = "Кратер Ун'Горо", zhCN = "安戈洛环形山", zhTW = "安戈洛環形山" },
	["Undercity"] = { enUS = "Undercity", koKR = "언더시티", deDE = "Unterstadt", frFR = "Undercity", esES = "Entrañas", ruRU = "Подгород", zhCN = "幽暗城", zhTW = "幽暗城" },
	["Wailing Caverns"] = { enUS = "Wailing Caverns", koKR = "통곡의 동굴", deDE = "Die Höhlen des Wehklagens", frFR = "Cavernes des lamentations", esES = "Cuevas de los Lamentos", ruRU = "Пещеры Стенаний", zhCN = "哀嚎洞穴", zhTW = "哀嚎洞穴" },
	["Warsong Gulch"] = { enUS = "Warsong Gulch", koKR = "전쟁노래 협곡", deDE = "Kriegshymnenschlucht", frFR = "Goulet des Warsong", esES = "Garganta Grito de Guerra", ruRU = "Ущелье Песни Войны", zhCN = "战歌峡谷", zhTW = "戰歌峽谷" },
	["Western Plaguelands"] = { enUS = "Western Plaguelands", koKR = "서부 역병지대", deDE = "Westliche Pestländer", frFR = "Maleterres de l'ouest", esES = "Tierras de la Peste del Oeste", ruRU = "Западные Чумные земли", zhCN = "西瘟疫之地", zhTW = "西瘟疫之地" },
	["Westfall"] = { enUS = "Westfall", koKR = "서부 몰락지대", deDE = "Westfall", frFR = "Marche de l'Ouest", esES = "Páramos de Poniente", ruRU = "Западный Край", zhCN = "西部荒野", zhTW = "西部荒野" },
	["Wetlands"] = { enUS = "Wetlands", koKR = "저습지", deDE = "Sumpfland", frFR = "Les Paluns", esES = "Los Humedales", ruRU = "Болотина", zhCN = "湿地", zhTW = "濕地" },
	["Winterspring"] = { enUS = "Winterspring", koKR = "여명의 설원", deDE = "Winterquell", frFR = "Berceau-de-l'Hiver", esES = "Cuna del Invierno", ruRU = "Зимние Ключи", zhCN = "冬泉谷", zhTW = "冬泉谷" },
	["Zephras Isle"] = { enUS = "Zephras Isle", koKR = "제프라스 섬", deDE = "Insel Zephras", frFR = "Île de Zephras", esES = "Isla Zephras", ruRU = "Остров Зефрас", zhCN = "泽弗拉斯岛", zhTW = "澤弗拉斯島" },
	["Zul'Farrak"] = { enUS = "Zul'Farrak", koKR = "줄파락", deDE = "Zul'Farrak", frFR = "Zul'Farrak", esES = "Zul'Farrak", ruRU = "Зул'Фаррак", zhCN = "祖尔法拉克", zhTW = "祖爾法拉克" },
	["Zul'Gurub"] = { enUS = "Zul'Gurub", koKR = "줄구룹", deDE = "Zul'Gurub", frFR = "Zul'Gurub", esES = "Zul'Gurub", ruRU = "Зул'Гуруб", zhCN = "祖尔格拉布", zhTW = "祖爾格拉布" },
}

local CONTINENT_FALLBACK_MAP = {
	[0] = 1415, -- 동부 왕국 (Eastern Kingdoms)
	[1] = 1414, -- 칼림도어 (Kalimdor)
}

-- 지역 약칭·줄임말·하위 마을(무법항, 가젯잔, 눈망루 등) 매핑
local ZONE_KEYWORDS = {
	["Orgrimmar"]           = { "오그리마", "오그", "orgrimmar", "org" },
	["Stormwind City"]      = { "스톰윈드", "스톰", "stormwind", "sw" },
	["Ironforge"]           = { "아이언포지", "아포", "아언", "ironforge", "if" },
	["Undercity"]           = { "언더시티", "언더", "undercity", "uc" },
	["Thunder Bluff"]       = { "썬더 블러프", "썬더블러프", "썬더", "썬블", "thunder bluff", "tb" },
	["Darnassus"]           = { "다르나서스", "다르", "달나", "darnassus", "darn" },
	["Tanaris"]             = { "타나리스", "타나", "가젯잔", "가젯", "gadgetzan" },
	["Stranglethorn Vale"]  = { "가시덤불 골짜기", "가시덤불", "가덤", "무법항", "무법", "그롬골", "booty bay", "grom'gol", "stv" },
	["Winterspring"]        = { "여명의 설원", "여명의설원", "여명", "눈망루", "everlook" },
	["The Barrens"]         = { "불모의 땅", "불모의땅", "불모", "톱니항", "톱니", "크로스로드", "크로", "타우라조", "ratchet", "crossroads", "xr" },
	["Durotar"]             = { "듀로타", "칼바위 언덕", "칼바위", "센진", "razor hill", "sen'jin" },
	["Mulgore"]             = { "멀고어", "블러드후프", "bloodhoof" },
	["Elwynn Forest"]       = { "엘윈 숲", "엘윈숲", "엘윈", "골드샤이어", "goldshire" },
	["Dun Morogh"]          = { "던 모로", "던모로", "카라노스", "kharanos" },
	["Tirisfal Glades"]     = { "티리스팔 숲", "티리스팔", "티리스", "브릴", "brill" },
	["Westfall"]            = { "서부 몰락지대", "서부몰락지대", "서부몰락", "서몰", "감시의 언덕", "sentinel hill" },
	["Redridge Mountains"]  = { "붉은마루 산맥", "붉은마루", "붉마", "레이크샤이어", "lakeshire" },
	["Duskwood"]            = { "그늘숲", "그늘", "다크샤이어", "darkshire" },
	["Loch Modan"]          = { "모단 호수", "모단호수", "모단", "텔사마", "thelsamar" },
	["Wetlands"]            = { "저습지", "저습", "메네실", "menethil" },
	["Hillsbrad Foothills"] = { "힐스브래드 구릉지", "힐스브래드", "힐스", "타렌 밀농장", "타렌밀", "사우스쇼어", "tarren mill", "southshore" },
	["Arathi Highlands"]    = { "아라시 고원", "아라시", "해머폴", "임시 주둔지", "hammerfall", "refuge pointe" },
	["Alterac Mountains"]   = { "알터랙 산맥", "알터랙", "알터" },
	["Silverpine Forest"]   = { "은빛소나무 숲", "은빛소나무", "은빛", "공동묘지", "sepulcher" },
	["Western Plaguelands"] = { "서부 역병지대", "서부역병지대", "서부역병", "서역", "서리바람", "안돌할" },
	["Eastern Plaguelands"] = { "동부 역병지대", "동부역병지대", "동부역병", "동역", "희망의 빛", "light's hope" },
	["The Hinterlands"]     = { "동부 내륙지", "동부내륙지", "동부내륙", "동내", "맹금의 봉우리", "레반터스크", "aerie peak", "revantusk" },
	["Searing Gorge"]       = { "이글거리는 협곡", "이글협곡", "이글", "토륨 대장조합", "토륨", "thorium point" },
	["Burning Steppes"]     = { "불타는 평원", "불타는평원", "불평", "모건의 망루", "모건", "화염마루", "morgan's vigil", "flame crest" },
	["Badlands"]            = { "황야의 땅", "황야의땅", "황야", "카르가스", "kargath" },
	["Swamp of Sorrows"]    = { "슬픔의 늪", "슬픔의늪", "슬픔", "스토나드", "stonard" },
	["Blasted Lands"]       = { "저주받은 땅", "저주받은땅", "저주땅", "저주", "네더가드", "nethergarde" },
	["Deadwind Pass"]       = { "죽음의 고개", "죽음의고개", "죽고", "카라잔" },
	["Teldrassil"]          = { "텔드랏실", "돌라나르", "루테란", "dolanaar" },
	["Darkshore"]           = { "어둠의 해안", "어둠의해안", "어둠해안", "어둠", "아우버다인", "auberdine" },
	["Ashenvale"]           = { "잿빛 골짜기", "잿빛골짜기", "잿빛", "아스트라나르", "토막나무", "조람가르", "astranaar", "splintertree" },
	["Stonetalon Mountains"]= { "돌발톱 산맥", "돌발톱", "해바위", "sun rock" },
	["Desolace"]            = { "잊혀진 땅", "잊혀진땅", "잊땅", "나이젤", "그늘수렵", "nijel", "shadowprey" },
	["Feralas"]             = { "페랄라스", "페랄", "페더문", "모자케", "feathermoon", "mojache" },
	["Dustwallow Marsh"]    = { "먼지진흙 습지대", "먼지진흙", "먼지", "테라모어", "담쟁이", "theramore", "brackenwall" },
	["Thousand Needles"]    = { "버섯구름 봉우리", "버섯구름", "버섯", "높새바람", "소금 평원", "freewind" },
	["Un'Goro Crater"]      = { "운고로 분화구", "운고로", "마샬", "ungoro" },
	["Silithus"]            = { "실리더스", "실리", "세나리온 요새", "세나리온", "cenarion" },
	["Felwood"]             = { "악령의 숲", "악령의숲", "악령숲", "악령", "피독소", "에메랄드 성소" },
	["Moonglade"]           = { "달의 숲", "달의숲", "달숲", "나이트헤이븐", "nighthaven" },
	["Azshara"]             = { "아즈샤라", "아즈", "탈렌드리스", "발로르모크" },
	["Mount Hyjal"]         = { "하이잘 산", "하이잘산", "하이잘", "hyjal", "mount hyjal" },
	["Zephras Isle"]        = { "제프라스 섬", "제프라스섬", "제프라스", "zephras" },
	["Riverglades"]         = { "강물숲", "리버글레이즈", "riverglades" },
}

-- 띄어쓰기 없이 붙여서 검색할 때("오그경매", "아포은행" 등) 분리용 접두어 목록
local ZONE_PREFIX_LIST = {}
do
	local seen = {}
	local function addPrefix(p)
		p = lower((p or ""):gsub("[ \t]+", ""))
		if #p >= 2 and not seen[p] then
			seen[p] = true
			ZONE_PREFIX_LIST[#ZONE_PREFIX_LIST + 1] = p
		end
	end
	for _, zt in pairs(ZONE_NAMES) do
		if zt.koKR then addPrefix(zt.koKR) end
	end
	for _, kwList in pairs(ZONE_KEYWORDS) do
		for _, kw in ipairs(kwList) do
			addPrefix(kw)
		end
	end
	table.sort(ZONE_PREFIX_LIST, function(a, b) return #a > #b end)
end

local ALL_ZONE_KEYS = {}
do
	local seen = {}
	local function addZoneKey(k)
		if k and k ~= "" and not seen[k] then
			seen[k] = true
			ALL_ZONE_KEYS[#ALL_ZONE_KEYS + 1] = k
		end
	end
	for k in pairs(ZONE_NAMES) do addZoneKey(k) end
	for k in pairs(ZONE_KEYWORDS) do addZoneKey(k) end
	for _, b in ipairs(ZONE_BOUNDS) do addZoneKey(b.key) end
	for _, info in pairs(INSTANCE_ZONES) do addZoneKey(info.key) end
end

local HERB_SKILL_BY_OBJECT = {
	[1618] = 1,   [3724] = 1,   -- 평온초 (Peacebloom)
	[1617] = 1,   [3725] = 1,   -- 은엽수 잎 (Silverleaf)
	[1619] = 15,  [3726] = 15,  -- 뱀뿌리 (Earthroot)
	[1620] = 50,  [3727] = 50,  -- 마법초 (Mageroyal)
	[1621] = 70,  [3729] = 70,  -- 찔레가시 (Briarthorn)
	[2045] = 85,                -- 갈래물풀 (Stranglekelp)
	[1622] = 100, [3730] = 100, -- 생채기풀 (Bruiseweed)
	[1623] = 115,               -- 야생 철쭉 (Wild Steelbloom)
	[1628] = 120,               -- 무덤이끼 (Grave Moss)
	[1624] = 125,               -- 왕꽃잎풀 (Kingsblood)
	[2041] = 150,               -- 생명의 뿌리 (Liferoot)
	[2042] = 160,               -- 미명초잎 (Fadeleaf)
	[2046] = 170,               -- 황금가시 (Goldthorn)
	[2043] = 185,               -- 카드가의 수염 (Khadgar's Whisker)
	[2044] = 195,               -- 겨울서리풀 (Wintersbite)
	[2866] = 205,               -- 화염초 (Firebloom)
	[142140] = 210, [180165] = 210, -- 보라 연꽃 (Purple Lotus)
	[142141] = 220, [176642] = 220, -- 아서스의 눈물 (Arthas' Tears)
	[142142] = 230, [176636] = 230, [180164] = 230, -- 태양풀 (Sungrass)
	[142143] = 235,             -- 실명초 (Blindweed)
	[142144] = 245,             -- 유령버섯 (Ghost Mushroom)
	[142145] = 250, [176637] = 250, -- 그롬의 피 (Gromsblood)
	[176583] = 260, [176638] = 260, [180167] = 260, -- 황금 산삼 (Golden Sansam)
	[176584] = 270, [176639] = 270, [180168] = 270, -- 꿈풀 (Dreamfoil)
	[176586] = 280, [176640] = 280, [180166] = 280, -- 은초롱이 (Mountain Silversage)
	[176587] = 285,             -- 역병초 (Plaguebloom)
	[176588] = 290,             -- 얼음송이 (Icecap)
	[176589] = 300,             -- 검은 연꽃 (Black Lotus)
}

local MINE_SKILL_BY_OBJECT = {
	[1731] = 1,   [2055] = 1,   [103713] = 1, -- 구리 광맥 (Copper Vein)
	[1732] = 65,  [2054] = 65,  [103711] = 65, [1610] = 65, -- 주석 광맥 (Tin Vein)
	[1733] = 75,  [105569] = 75, [2653] = 75,  [73940] = 75, -- 은 광맥 (Silver Vein)
	[1735] = 125,                             -- 철 광맥 (Iron Deposit)
	[19903] = 150,                            -- 인두리움 광맥 (Indurium Mineral Vein)
	[1734] = 155, [150080] = 155, [73941] = 155, -- 금 광맥 (Gold Vein)
	[2040] = 175, [150079] = 175, [123310] = 175, -- 미스릴 광맥 (Mithril Deposit)
	[2047] = 230, [150081] = 230, [123309] = 230, -- 진은 광맥 (Truesilver Deposit)
	[165658] = 230,                           -- 검은무쇠 광맥 (Dark Iron Deposit)
	[324] = 245,  [150082] = 245, [123848] = 245, -- 작은 토륨 광맥 (Small Thorium Vein)
	[180215] = 250,                           -- 학카리 토륨 광맥 (Hakkari Thorium Vein)
	[175404] = 275, [177388] = 275,           -- 풍부한 토륨 광맥 (Rich Thorium Vein)
}

local FRIENDLY_SUBNAME_KEYWORDS = {
	"militia", "night watch", "argent dawn", "explorers' league", "cenarion circle",
	"thorium brotherhood", "stormpike", "kargath expeditionary", "royal apothecary",
	"dwarven mortar", "ambassador", "mayor", "recruiter", "orphanage", "stable master",
	"announcer", "starter", "landscape architect", "school mistress", "team captain",
	"away team", "guardian", "pet", "protector", "sergeant", "rebel soldier",
	"blackwater raiders", "tradeswoman", "camp trader", "waitress", "bartender", "vintner",
}

local BADGE_PREFIX_POOLS = {
	m = "normalMonster",
	r = "rare",
	p = "pet",
	n = "npc",
	o = "object",
	q = "quest",
	i = "item",
}

local ZONE_LEVEL_DATA = {
	-- 동부 왕국 (Eastern Kingdoms)
	[1426] = { 1, 10, 1 },   [1429] = { 1, 10, 1 },   [1420] = { 1, 10, 1 },   [1941] = { 1, 10, 1 },
	[1436] = { 10, 20, 20 }, [1432] = { 10, 20, 20 }, [1421] = { 10, 20, 20 }, [1942] = { 10, 20, 20 }, [1433] = { 15, 25, 55 },
	[1431] = { 18, 30, 55 }, [1437] = { 20, 30, 55 }, [1424] = { 20, 30, 55 }, [1416] = { 30, 40, 130 },[1417] = { 30, 40, 130 },
	[1434] = { 30, 45, 130 },[1418] = { 35, 45, 130 },[1435] = { 35, 45, 130 },[1425] = { 40, 50, 205 },
	[1427] = { 43, 50, 205 },[1419] = { 45, 55, 205 },[1428] = { 50, 58, 330 },[1422] = { 51, 58, 205 },[1423] = { 53, 60, 330 },
	[1430] = { 55, 60, 330 },[1957] = { 70, 70, 355 },
	-- 칼림도어 (Kalimdor)
	[1411] = { 1, 10, 1 },   [1412] = { 1, 10, 1 },   [1438] = { 1, 10, 1 },   [1943] = { 1, 10, 1 },   [1439] = { 10, 20, 20 },
	[1950] = { 10, 20, 20 }, [1413] = { 10, 25, 20 }, [1442] = { 15, 27, 55 }, [1440] = { 18, 30, 55 }, [1441] = { 25, 35, 130 },
	[1443] = { 30, 40, 130 },[1445] = { 35, 45, 130 },[1444] = { 40, 50, 205 },[1446] = { 40, 50, 205 },[1447] = { 45, 55, 205 },
	[1448] = { 48, 55, 205 },[1449] = { 48, 55, 205 },[1450] = { 50, 58, 205 },[1452] = { 53, 60, 330 },[1451] = { 55, 60, 330 },
	-- 아웃랜드 (Outland)
	[1944] = { 58, 63, 280 },[1946] = { 60, 64, 305 },[1952] = { 62, 65, 355 },[1951] = { 64, 67, 380 },[1949] = { 65, 68, 355 },
	[1953] = { 67, 70, 380 },[1948] = { 67, 70, 380 },
	-- 노스렌드 (Northrend)
	[114] = { 68, 72, 380 }, [117] = { 68, 72, 380 }, [115] = { 71, 74, 380 }, [116] = { 73, 75, 380 }, [121] = { 74, 77, 380 },
	[119] = { 76, 78, 430 }, [123] = { 77, 80, 430 }, [120] = { 77, 80, 430 }, [118] = { 77, 80, 430 }, [127] = { 77, 80, 405 },
	[170] = { 80, 80, 455 },
}

local TRANSIT_DATA = {
	-- 동부 왕국 (Eastern Kingdoms)
	[1416] = {
		{ kind = "boat",   fac = "A", x = 12.8, y = 51.2, dest = 2521, ko = "제프라스 섬행 배", en = "Boat to Zephras Isle" },
		{ kind = "portal", fac = "A", x = 12.0, y = 56.2, dest = 1453, ko = "스톰윈드 차원문", en = "Portal to Stormwind" },
	},
	[1420] = {
		{ kind = "zepp",   fac = "H", x = 61.9, y = 58.9, dest = 1434, ko = "그롬골 주둔지행 비행선 (가시덤불 골짜기)", en = "Zeppelin to Grom'gol, Stranglethorn" },
		{ kind = "zepp",   fac = "H", x = 60.6, y = 58.9, dest = 1411, ko = "오그리마행 비행선 (듀로타)", en = "Zeppelin to Orgrimmar, Durotar" },
	},
	[1424] = {
		{ kind = "boat",   fac = "A", x = 50.7, y = 70.4, dest = 1439, ko = "아우버다인(어둠의 해안) · 메네실 항구(저습지)행 배", en = "Boat to Auberdine, Darkshore & Menethil Harbor" },
	},
	[1434] = {
		{ kind = "zepp",   fac = "H", x = 31.2, y = 30.4, dest = 1454, ko = "오그리마행 비행선 (듀로타)", en = "Zeppelin to Orgrimmar, Durotar" },
		{ kind = "zepp",   fac = "H", x = 31.5, y = 29.1, dest = 1420, ko = "언더시티행 비행선 (티리스팔 숲)", en = "Zeppelin to Undercity, Tirisfal" },
		{ kind = "boat",   fac = "N", x = 25.7, y = 73.1, dest = 1413, ko = "톱니항행 배 (불모의 땅)", en = "Boat to Ratchet, The Barrens" },
	},
	[1437] = {
		{ kind = "boat",   fac = "A", x = 4.5,  y = 56.7, dest = 1424, ko = "사우스쇼어(힐스브래드) · 아우버다인(어둠의 해안)행 배", en = "Boat to Southshore & Auberdine" },
		{ kind = "boat",   fac = "A", x = 4.7,  y = 63.8, dest = 1445, ko = "테라모어 섬행 배 (먼지진흙 습지대)", en = "Boat to Theramore, Dustwallow Marsh" },
	},
	[1453] = {
		{ kind = "tram",   fac = "A", x = 66.6, y = 34.7, dest = 1455, ko = "아이언포지행 깊은굴 지하철", en = "Deeprun Tram to Ironforge" },
		{ kind = "portal", fac = "A", x = 50.0, y = 86.9, dest = 1416, ko = "달라란 차원문 (알터랙 산맥)", en = "Portal to Dalaran, Alterac Mountains" },
		{ kind = "boat",   fac = "A", x = 21.8, y = 56.9, dest = 1439, ko = "아우버다인행 배 (어둠의 해안)", en = "Boat to Auberdine, Darkshore" },
	},
	[1455] = {
		{ kind = "tram",   fac = "A", x = 73.0, y = 50.2, dest = 1453, ko = "스톰윈드행 깊은굴 지하철", en = "Deeprun Tram to Stormwind" },
	},
	[2548] = {
		{ kind = "boat",   fac = "H", x = 80.6, y = 54.6, dest = 1446, ko = "타나리스행 배", en = "Boat to Tanaris" },
	},
	-- 칼림도어 (Kalimdor) 및 섬 지역
	[1411] = {
		{ kind = "zepp",   fac = "H", x = 50.5, y = 12.7, dest = 1434, ko = "그롬골 주둔지행 비행선 (가시덤불 골짜기)", en = "Zeppelin to Grom'gol, Stranglethorn" },
		{ kind = "zepp",   fac = "H", x = 51.0, y = 13.9, dest = 1420, ko = "언더시티행 비행선 (티리스팔 숲)", en = "Zeppelin to Undercity, Tirisfal" },
	},
	[1412] = {
		{ kind = "zepp",   fac = "H", x = 34.3, y = 26.1, dest = 2521, ko = "제프라스 섬행 비행선", en = "Zeppelin to Zephras Isle" },
	},
	[1413] = {
		{ kind = "boat",   fac = "N", x = 63.8, y = 38.8, dest = 1434, ko = "무법항행 배 (가시덤불 골짜기)", en = "Boat to Booty Bay, Stranglethorn" },
	},
	[1438] = {
		{ kind = "boat",   fac = "A", x = 54.8, y = 97.2, dest = 1439, ko = "아우버다인행 배 (어둠의 해안)", en = "Boat to Auberdine, Darkshore" },
	},
	[1439] = {
		{ kind = "boat",   fac = "A", x = 32.3, y = 44.1, dest = 1437, ko = "메네실 항구(저습지) · 사우스쇼어(힐스브래드)행 배", en = "Boat to Menethil Harbor & Southshore" },
		{ kind = "boat",   fac = "A", x = 33.3, y = 39.8, dest = 1438, ko = "루테란 마을행 배 (텔드랏실)", en = "Boat to Rut'theran Village, Teldrassil" },
		{ kind = "boat",   fac = "A", x = 30.5, y = 40.9, dest = 1453, ko = "스톰윈드행 배", en = "Boat to Stormwind City" },
	},
	[1444] = {
		{ kind = "boat",   fac = "A", x = 43.1, y = 42.8, dest = 1444, ko = "페더문 요새행 배", en = "Boat to Feathermoon Stronghold" },
		{ kind = "boat",   fac = "A", x = 31.0, y = 39.5, dest = 1444, ko = "페랄라스 본토행 배", en = "Boat to Feralas Mainland" },
	},
	[1445] = {
		{ kind = "boat",   fac = "A", x = 71.7, y = 56.7, dest = 1437, ko = "메네실 항구행 배 (저습지)", en = "Boat to Menethil Harbor, Wetlands" },
	},
	[1446] = {
		{ kind = "boat",   fac = "H", x = 68.6, y = 23.0, dest = 2548, ko = "강물숲행 배", en = "Boat to Riverglades" },
	},
	[2521] = {
		{ kind = "boat",   fac = "N", x = 64.9, y = 80.9, dest = 1416, ko = "달라란(알터랙 산맥)행 배", en = "Boat to Dalaran, Alterac Mountains" },
	},
}

local FACTION_COLORS = {
	A = { 0.290, 0.620, 1.000 }, -- 얼라이언스 블루
	H = { 0.910, 0.314, 0.294 }, -- 호드 레드
	N = { 0.945, 0.741, 0.341 }, -- 중립 골드
}

ns.ROLES = ROLES
ns.QUERY_SYNONYMS = QUERY_SYNONYMS
ns.ZONE_BOUNDS = ZONE_BOUNDS
ns.ZONE_BOUNDS_BY_ID = ZONE_BOUNDS_BY_ID
ns.ZONE_ID_BY_KEY = ZONE_ID_BY_KEY
ns.INSTANCE_ZONES = INSTANCE_ZONES
ns.EXTRA_ZONE_KEY_BY_MAPID = EXTRA_ZONE_KEY_BY_MAPID
ns.ZONE_NAMES = ZONE_NAMES
ns.CONTINENT_FALLBACK_MAP = CONTINENT_FALLBACK_MAP
ns.ZONE_KEYWORDS = ZONE_KEYWORDS
ns.ZONE_PREFIX_LIST = ZONE_PREFIX_LIST
ns.ALL_ZONE_KEYS = ALL_ZONE_KEYS
ns.HERB_SKILL_BY_OBJECT = HERB_SKILL_BY_OBJECT
ns.MINE_SKILL_BY_OBJECT = MINE_SKILL_BY_OBJECT
ns.FRIENDLY_SUBNAME_KEYWORDS = FRIENDLY_SUBNAME_KEYWORDS
ns.BADGE_PREFIX_POOLS = BADGE_PREFIX_POOLS
ns.ZONE_LEVEL_DATA = ZONE_LEVEL_DATA
ns.TRANSIT_DATA = TRANSIT_DATA
ns.FACTION_COLORS = FACTION_COLORS
