-- Loot probe: aggregation, privacy, caps, persistence.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
M.install()
local say = {}
local ns = { actions = { say = function(m) say[#say + 1] = m end } }
LorestarDB = {}

local mapID, pos = 1411, { 0.5568, 0.6301 }
C_Map = { GetBestMapForUnit = function() return mapID end,
          GetPlayerMapPosition = function() if not pos then return nil end
            return { GetXY = function() return pos[1], pos[2] end } end }
function GetZoneText() return "Durotar" end
function GetSubZoneText() return "Razor Hill" end
local loot = {}
function GetNumLootItems() return #loot end
function GetLootSlotLink(i) return loot[i].link end
function GetLootSlotInfo(i) return "icon", "name", loot[i].qty, 0, 1 end
function GetLootSourceInfo(i) return loot[i].guid, 1 end
local secret = {}
function issecretvalue(v) return secret[v] == true end

C_Item = { GetItemInfo = function(link)
  if link:find("item:2770") then return "Copper Ore", link, 1, 1, 0, "Trade Goods", "Metal", 20, "", "icon", 5, 7 end
end }
assert(loadfile("Lorestar/Lorestar_Loot.lua"))("Lorestar", ns)
local L, check = ns.loot, M.check
local a

io.write("loot probe\n")
check("stats never create saved data", L.stats().opens == 0 and LorestarDB.loot == nil)
M.fire("LOOT_OPENED")
check("off by default: nothing recorded", LorestarDB.loot == nil or LorestarDB.loot.probe.opens == 0)

L.setEnabled(true)
local boar = "Creature-0-3023-0-11-3111-0000AAAA11"
loot = { { link = "|Hitem:2770::::|h[Copper Ore]|h", qty = 2, guid = boar },
         { link = "|Hitem:2771::::|h[Tin Ore]|h", qty = 1, guid = "GameObject-0-3023-0-11-1731-0000BBBB22" },
         { link = nil, qty = 1000, guid = boar } }   -- money slot has no link
M.fire("LOOT_OPENED")
a = LorestarDB.loot.agg
check("npc source aggregated by map cell", a["1411|27|31|npc:3111"] and a["1411|27|31|npc:3111"].items[2770] == 2)
check("object source aggregated", a["1411|27|31|obj:1731"] and a["1411|27|31|obj:1731"].items[2771] == 1)
check("money slot ignored", (function() for _, r in pairs(a) do for _, q in pairs(r.items) do if q == 1000 then return false end end end return true end)())
M.fire("LOOT_OPENED")
check("second window adds opens and quantity", a["1411|27|31|npc:3111"].opens == 2 and a["1411|27|31|npc:3111"].items[2770] == 4)
check("zone and subzone remembered", LorestarDB.loot.zones[1411] == "Durotar" and LorestarDB.loot.sub["1411|27|31"] == "Razor Hill")

check("looted items remember name, quality, sell price and class",
  LorestarDB.loot.names[2770] and LorestarDB.loot.names[2770].n == "Copper Ore" and LorestarDB.loot.names[2770].s == 5
  and LorestarDB.loot.names[2770].c == 7 and LorestarDB.loot.names[2770].st == 20)
check("an uncached item still gets its name from the link", LorestarDB.loot.names[2771] and LorestarDB.loot.names[2771].n == "Tin Ore")

local parts = {}
local function walk(t) for k, v in pairs(t) do parts[#parts + 1] = tostring(k); if type(v) == "table" then walk(v) else parts[#parts + 1] = tostring(v) end end end
walk(LorestarDB.loot)
local blob = table.concat(parts, " ")
check("no GUID or spawn id stored", not blob:find("0000AAAA") and not blob:find("Creature%-") and not blob:find("GameObject%-"))

pos = nil
loot = { { link = "|Hitem:2589::|h[Linen]|h", qty = 1, guid = boar } }
M.fire("LOOT_OPENED")
check("no position: kept under cell -1 and counted", a["1411|-1|-1|npc:3111"] ~= nil and LorestarDB.loot.probe.noPosition == 1)

pos = { 0.1, 0.1 }
loot = { { link = "|Hitem:2589::|h[Linen]|h", qty = 1, guid = "Item-4372-0-400000" } }
M.fire("LOOT_OPENED")
check("unknown source kept as '?'", a["1411|5|5|?"] ~= nil and LorestarDB.loot.probe.noSource == 1)

local realN = GetNumLootItems
secret[7] = true; GetNumLootItems = function() return 7 end
M.fire("LOOT_OPENED")
check("secret slot count is skipped and counted", LorestarDB.loot.probe.secret == 1)
GetNumLootItems = realN

pos = { 1.0, 1.0 }
loot = { { link = "|Hitem:2589::|h[Linen]|h", qty = 1, guid = boar } }
M.fire("LOOT_OPENED")
check("coordinates at the map edge are clamped", a["1411|49|49|npc:3111"] ~= nil)

LorestarDB.loot.nKeys = 4000
loot = { { link = "|Hitem:9::|h[x]|h", qty = 1, guid = "Creature-0-1-0-1-999-0000CCCC33" } }
pos = { 0.9, 0.2 }
M.fire("LOOT_OPENED")
check("record cap drops new keys", LorestarDB.loot.probe.droppedKeys == 1 and a["1411|45|10|npc:999"] == nil)
LorestarDB.loot.nKeys = 0
for _ in pairs(a) do LorestarDB.loot.nKeys = LorestarDB.loot.nKeys + 1 end

pos = { 0.3, 0.3 }
for i = 1, 90 do
  loot = { { link = "|Hitem:" .. (5000 + i) .. "::|h[x]|h", qty = 1, guid = boar } }
  M.fire("LOOT_OPENED")
end
local n = 0
for _ in pairs(a["1411|15|15|npc:3111"].items) do n = n + 1 end
check("distinct items per record capped at 80", n == 80)

local st = L.stats()
check("stats totals", st.records == LorestarDB.loot.nKeys and st.items > 0 and st.places >= 4)

for _, f in ipairs(M.frames) do f.events.LOOT_OPENED = nil end   -- simulate a fresh session
M.fire("PLAYER_LOGIN")
local resumed = false
for _, f in ipairs(M.frames) do if f.events.LOOT_OPENED then resumed = true end end
check("resumes after login when left on", resumed)

L.command("off")
local stillOn = false
for _, f in ipairs(M.frames) do if f.events.LOOT_OPENED then stillOn = true end end
check("off unregisters the event but keeps data", not stillOn and LorestarDB.loot.nKeys > 0)

L.command("clear")
check("clear wipes data and leaves it off", next(LorestarDB.loot.agg) == nil and LorestarDB.loot.enabled == false)
L.command("bogus")
check("unknown subcommand prints usage", say[#say]:find("Usage") ~= nil)

M.finish()
