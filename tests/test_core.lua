-- Core addon: slash commands, price scan, item names, privacy of the scan.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
M.install()
local check = M.check

local ns = {}
assert(loadfile("Lorestar/Lorestar.lua"))("Lorestar", ns)
M.fire("ADDON_LOADED", "Lorestar")
local function cmd(s) SlashCmdList.LORESTAR(s) end

io.write("core\n")
check("loads and creates the saved table", LorestarDB ~= nil and LorestarDB.anonymous == true and LorestarDB.eventsActive == false)
check("exposes shared actions", type(ns.actions) == "table" and type(ns.actions.dump) == "function")

cmd(""); check("help lists the loot command", M.printedMatch("loot on|off"))
cmd("status"); check("status prints the version", M.printedMatch("snapshot:"))
cmd("anon off"); check("anon off", LorestarDB.anonymous == false)
cmd("anon on"); check("anon on", LorestarDB.anonymous == true)
cmd("events on"); check("events on registers events", LorestarDB.eventsActive == true)
cmd("events off"); check("events off", LorestarDB.eventsActive == false)
cmd("dump nonsense"); check("unknown section is reported", M.printedMatch("Unknown section"))
cmd("dump build")
check("dump of one section stores a snapshot", LorestarDB.snapshot and LorestarDB.snapshot.sections.build ~= nil)
cmd("dump")
check("full dump runs every section without failing the addon", LorestarDB.snapshot and LorestarDB.snapshot.sections.itemnames ~= nil)
check("snapshot carries the addon version", LorestarDB.snapshot.addonVersion ~= nil)

-- AH scan: robust prices and no seller data
C_AuctionHouse = {
  ReplicateItems = function() end,
  GetNumReplicateItems = function() return 4 end,
  GetReplicateItemInfo = function(i)
    local rows = {
      [0] = { 1, 100, 100 },     -- item 100: 1 unit at 100
      [1] = { 10, 1500, 100 },   -- item 100: 10 units at 150 each
      [2] = { 5, 50, 200 },      -- item 200: 5 units at 10 each
      [3] = { 1, 0, 300 },       -- item 300: no buyout (bid only)
    }
    local r = rows[i]
    return "Name", 1, r[1], 1, true, 1, 0, 0, 0, r[2], 0, "bidder-secret", "bidderfull", "SellerName", "SellerFull", 0, r[3], true
  end,
}
AuctionHouseFrame = { IsShown = function() return true end }
cmd("scan")
M.fire("REPLICATE_ITEM_LIST_UPDATE")
M.flushTimers(3)
local P = LorestarDB.prices
check("scan stores totals", P and P.rows == 4 and P.schema == 2)
check("min, p10 and weighted median", P.items[100].m == 100 and P.items[100].p10 == 150 and P.items[100].med == 150)
check("counts listings and quantity", P.items[100].n == 2 and P.items[100].q == 11)
check("single listing", P.items[200].m == 10 and P.items[200].med == 10)
check("listing without buyout has no price", P.items[300] and P.items[300].m == nil and P.items[300].med == nil)
check("temporary arrays are removed", P.items[100].u == nil and P.items[100].c == nil)
local parts = {}
local function walk(t) for k, v in pairs(t) do parts[#parts + 1] = tostring(k); if type(v) == "table" then walk(v) else parts[#parts + 1] = tostring(v) end end end
walk(P)
local blob = table.concat(parts, " ")
check("seller and bidder values are never stored", not blob:find("SellerName") and not blob:find("bidder%-secret"))

-- Item names: collected from recipes, retried while the client caches them
local known = { [100] = "Copper Bar", [101] = "Tin Bar" }
C_Item = {
  GetItemInfo = function(id) local n = known[id]; if n then return n, "link", 2, 5, 1, "x", "y", 20, "", "icon", id * 3 end end,
  RequestLoadItemDataByID = function() end,
}
LorestarDB.snapshot = { sections = { recipes = { byProfession = { Mining = { modern = {
  [1] = { id = 1, outputItemID = 100, reagents = { [1] = { itemID = 2770, qty = 1 }, [2] = { itemID = 101, qty = 2 } } },
} } } } } }
cmd("dump itemnames")
local sec = LorestarDB.snapshot.sections.itemnames
check("names resolved at once are stored", sec and sec.items[100] and sec.items[100].n == "Copper Bar" and sec.items[100].s == 300)
check("uncached names are pending", sec.pending == 1)
known[2770] = "Copper Ore"
M.flushTimers(2)
check("pending names are retried automatically", LorestarDB.snapshot.sections.itemnames.items[2770] ~= nil and LorestarDB.snapshot.sections.itemnames.pending == 0)
LorestarDB.snapshot = { sections = {} }
cmd("dump itemnames")
check("without recipe data it explains what to do", LorestarDB.snapshot.sections.itemnames.note ~= nil)

-- clear keeps loot data
LorestarDB.loot = { enabled = true, agg = { x = 1 } }
cmd("clear")
check("clear wipes collected data", LorestarDB.snapshot == nil and LorestarDB.prices == nil)
check("clear keeps loot data", LorestarDB.loot ~= nil and LorestarDB.loot.agg.x == 1)

M.finish()
