-- Advisor: the shared rule cases, plus the runtime that reads bags, prices and recipes.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local json = require("json")
M.install()
local check = M.check

local ns = { actions = { say = function(m) M.printed[#M.printed + 1] = m end } }
LorestarDB = {}
assert(loadfile("Lorestar/Lorestar_Advisor.lua"))("Lorestar", ns)
local A = ns.advisor

local fh = assert(io.open("tests/rules_cases.json", "r"))
local cases = json.decode(fh:read("*a")).cases
fh:close()

io.write("advisor: shared rule cases\n")
check("cases loaded", #cases >= 15)
for _, c in ipairs(cases) do
  local r = A.evaluate(c.item, c.ctx, c.cfg)
  local ok = true
  local why = {}
  for field, want in pairs(c.expect) do
    if field == "notesInclude" then
      for _, note in ipairs(want) do
        local found = false
        for _, n in ipairs(r.notes) do if n == note then found = true end end
        if not found then ok = false; why[#why + 1] = "missing note " .. note end
      end
    elseif r[field] ~= want then
      ok = false
      why[#why + 1] = field .. "=" .. tostring(r[field]) .. " (wanted " .. tostring(want) .. ")"
    end
  end
  check(c.name .. (ok and "" or "  [" .. table.concat(why, "; ") .. "]"), ok)
end

io.write("advisor: reading bags, prices and recipes\n")
local bags = {
  [0] = { { itemID = 2589, stackCount = 20 }, { itemID = 2589, stackCount = 20 }, { itemID = 2589, stackCount = 12 },
          { itemID = 6948, stackCount = 1, isBound = true, hasNoValue = true },
          { itemID = 4567, stackCount = 1, isBound = true } },   -- plus 3 empty slots below
}
local SLOTS = 8
C_Container = {
  GetContainerNumSlots = function(bag) return bag == 0 and SLOTS or 0 end,
  GetContainerItemInfo = function(bag, slot) return bags[bag] and bags[bag][slot] or nil end,
}
local facts = {
  [2589] = { "Linen Cloth", "link", 1, 5, 1, "Trade Goods", "Cloth", 20, "", "icon", 13, 7 },
  [6948] = { "Hearthstone", "link", 1, 1, 1, "Misc", "Other", 1, "", "icon", 0, 15 },
  [4567] = { "Heavy Sword", "link", 3, 10, 1, "Weapon", "Sword", 1, "", "icon", 895, 2 },
}
C_Item = {
  GetItemInfo = function(id) local f = facts[id]; if f then return (table.unpack or unpack)(f) end end,
  RequestLoadItemDataByID = function() end,
}
LorestarDB = {
  prices = { time = "2026-11-14 15:48:28", ts = os.time(), items = {
    [2589] = { med = 29, p10 = 25, m = 18, n = 622, q = 19000 },
    [4567] = { med = 5000, p10 = 4800, m = 4500, n = 12, q = 12 },
  } },
  snapshot = { sections = { recipes = { byProfession = { ["First Aid"] = { modern = {
    [1] = { id = 1, learned = true, reagents = { [1] = { itemID = 2589, qty = 1 } } },
    [2] = { id = 2, learned = true, reagents = { [1] = { itemID = 2589, qty = 2 } } },
    [3] = { id = 3, learned = false, reagents = { [1] = { itemID = 2589, qty = 3 } } },
  } } } } } },
}
local idx, have = A.recipeIndex()
check("recipe index: learned and unlearned uses", have and idx[2589].learnedCount == 2 and idx[2589].learnedMax == 2 and idx[2589].unlearnedCount == 1)

local items, free = A.readBags()
check("bags are summed per item", items[2589].qty == 52 and items[2589].bound == false)
check("bound and no-value flags are read", items[4567].bound == true and items[6948].noValue == true)
check("free slots are counted", free == SLOTS - 5)

local list, summary = A.run()
local byId = {}
for _, r in ipairs(list) do byId[r.id] = r end
check("linen: keeps 20, sells 32 on the AH", byId[2589].action == "sell_ah" and byId[2589].keepQty == 20 and byId[2589].sellQty == 32)
check("hearthstone is kept", byId[6948].action == "keep" and byId[6948].reason == "keep_list")
check("bound gear goes to the vendor, not the AH", byId[4567].action == "vendor" and byId[4567].reason == "bound_vendor")
check("summary adds up", summary.sellAH == 32 * 27 and summary.vendor == 895 and summary.freeSlots == 3)
check("slots freed counts whole stacks", byId[2589].slotsFreed == (3 - 1))   -- 52 units = 3 stacks, keeping 20 = 1 stack

M.printed = {}
A.report()
check("report prints the lines and a summary", M.printedMatch("SELL AH") and M.printedMatch("Advisor: 1 to sell on the AH"))
check("report says nothing was moved", M.printedMatch("recommendation only"))
check("advice is saved for the web viewer", LorestarDB.advice and LorestarDB.advice.items[2589].a == "sell_ah" and LorestarDB.advice.items[2589].s == 32)

M.printed = {}
LorestarDB.prices, LorestarDB.snapshot = nil, nil
A.report()
check("warns when there is no recipe data and no scan", M.printedMatch("no recipe data") and M.printedMatch("no Auction House scan"))

LorestarDB.prices = { time = "x", ts = os.time() - 3 * 24 * 3600, items = {} }
M.printed = {}
A.report()
check("warns when the scan is old", M.printedMatch("more than a day old"))

M.finish()
