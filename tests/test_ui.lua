-- UI panel and minimap button.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
M.install()
LorestarDB = { eventsActive = false, anonymous = true,
  snapshot = { time = "2026-11-10 09:00:00", sections = { itemnames = { pending = 3 } } },
  prices = { time = "2026-11-10 09:05:00", distinct = 4459 } }

local calls, anon, lootOn = {}, true, false
local ns = { actions = {
  version = "0.0.0", say = function(m) calls[#calls + 1] = "say:" .. m end, isAnon = function() return anon end,
  dump = function(s) calls[#calls + 1] = "dump:" .. s end,
  events = function(on) calls[#calls + 1] = "events:" .. tostring(on); LorestarDB.eventsActive = on end,
  scan = function() calls[#calls + 1] = "scan" end,
  setAnon = function(on) anon = on; calls[#calls + 1] = "anon:" .. tostring(on) end,
  clear = function() calls[#calls + 1] = "clear" end, isScanning = function() return false end } }
ns.loot = { isEnabled = function() return lootOn end,
  setEnabled = function(on) lootOn = on; calls[#calls + 1] = "loot:" .. tostring(on) end,
  stats = function() return { opens = 9, items = 42, places = 3 } end }
ns.advisor = { report = function() calls[#calls + 1] = "advise" end }
local reloaded = false
function ReloadUI() reloaded = true end

assert(loadfile("Lorestar/Lorestar_UI.lua"))("Lorestar", ns)
M.fire("PLAYER_LOGIN")
local check = M.check
local panel, mini = LorestarPanel, LorestarMinimapButton

local function button(label)
  for _, o in ipairs(M.frames) do
    if o._kind == "Button" and o.label and o.label.text == label then return o end
  end
end
local function click(label)
  local b = button(label)
  assert(b, "no button '" .. label .. "'")
  b.scripts.OnClick(b)
end

io.write("ui\n")
check("panel and minimap button are built", panel ~= nil and mini ~= nil)
check("panel starts hidden", panel.shown == false)
ns.togglePanel(); panel.scripts.OnShow()
check("toggle shows the panel", panel.shown == true)
check("status shows last dump and scan", panel.status.text:find("Last dump: 2026%-11%-10") and panel.status.text:find("4459 items"))
check("status shows pending names and loot", panel.status.text:find("pending: 3") and panel.status.text:find("Loot: 9 windows"))

for _, l in ipairs({ "Dump all", "Dump items", "Dump recipes", "Dump item names", "Advise: what to do with my bags", "Scan AH prices", "Events: OFF", "Anonymous: ON", "Loot: OFF" }) do click(l) end
check("buttons trigger the right actions",
  table.concat(calls, " ") == "dump: dump:items dump:recipes dump:itemnames advise scan events:true anon:false loot:true")
check("toggle labels follow the state", button("Events: ON") and button("Anonymous: OFF") and button("Loot: ON"))

calls = {}
click("Clear data")
check("clear needs a confirmation click", #calls == 0 and button("Click again") ~= nil)
click("Click again")
check("second click clears", calls[1] == "clear")
calls = {}
click("Clear data"); M.now = M.now + 6; panel.refresh(); click("Clear data")
check("confirmation expires after 5 seconds", #calls == 0)

click("Reload UI (save)")
check("reload button calls ReloadUI", reloaded)
check("unsaved-changes hint appears", panel.status.text:find("Reload UI to save") ~= nil)

mini.scripts.OnDragStart(mini); mini.scripts.OnUpdate()
check("dragging saves an angle", type(LorestarDB.minimap.angle) == "number")
mini.scripts.OnDragStop(mini)
check("drag stops updating", mini.scripts.OnUpdate == nil)
mini.scripts.OnClick(mini)
check("minimap click toggles the panel", panel.shown == false)
ns.setMinimapShown(false)
check("minimap button can be hidden and the choice saved", mini.shown == false and LorestarDB.minimap.hidden == true)

M.finish()
