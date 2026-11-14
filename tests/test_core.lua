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
check("scan stores an epoch timestamp for age checks", type(P.ts) == "number")
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

-- Recipes: skill data and units made per craft (v0.4.8)
C_TradeSkillUI = {
  GetAllRecipeIDs = function() return { 11, 12 } end,
  GetRecipeInfo = function(id) return { name = "Recipe " .. id, learned = id == 11, categoryID = 3, relativeDifficulty = 2, maxTrivialLevel = 90, canSkillUp = true } end,
  GetRecipeSchematic = function(id) return { outputItemID = 500 + id, quantityMin = 1, quantityMax = 3,
    reagentSlotSchematics = { { quantityRequired = 2, reagents = { { itemID = 2770 } } } } } end,
  GetBaseProfessionInfo = function() return { professionName = "Mining" } end,
}
cmd("dump recipes")
local rec = LorestarDB.snapshot.sections.recipes.byProfession.Mining
check("recipes keep skill data", rec and rec.modern[1].diff == 2 and rec.modern[1].trivial == 90 and rec.modern[1].skillUp == true)
check("recipes keep the units made per craft", rec.modern[1].outMin == 1 and rec.modern[1].outMax == 3 and rec.modern[1].reagents[1].qty == 2)

-- Auction search samples: anonymous mode must scrub character GUIDs (crafted item links) and drop seller keys
C_AuctionHouse.GetNumItemSearchResults = function() return 1 end
C_AuctionHouse.GetItemSearchResultInfo = function()
  return { itemLink = "|Hitem:1::::|h[Crafted]|h by Player-1234-0ABCDEF9", owner = "SellerName", buyoutAmount = 5 }
end
LorestarDB.auctionSamples = nil
cmd("anon on"); cmd("events on")
M.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 1 })
local sample = LorestarDB.auctionSamples and LorestarDB.auctionSamples[1]
local sparts = {}
local function swalk(t) for k, v in pairs(t) do sparts[#sparts + 1] = tostring(k); if type(v) == "table" then swalk(v) else sparts[#sparts + 1] = tostring(v) end end end
if sample then swalk(sample) end
local sblob = table.concat(sparts, " ")
check("auction sample is recorded", sample ~= nil and sample.first ~= nil)
check("anonymous mode scrubs crafter GUIDs in samples", sample ~= nil and not sblob:find("0ABCDEF9") and sblob:find("<guid>") ~= nil)
check("seller keys are dropped from samples", sample ~= nil and not sblob:find("SellerName"))
cmd("events off")

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
