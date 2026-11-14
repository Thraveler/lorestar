-- Minimal fake of the WoW client API, enough to load and exercise the addon under LuaJIT.
local M = { frames = {}, printed = {}, timers = {}, failures = 0 }

local function newObject(kind, name)
  local o = { _kind = kind, _name = name, scripts = {}, events = {}, shown = true, text = "" }
  local methods = {
    SetScript = function(self, n, fn) self.scripts[n] = fn end,
    GetScript = function(self, n) return self.scripts[n] end,
    RegisterEvent = function(self, e) self.events[e] = true end,
    UnregisterEvent = function(self, e) self.events[e] = nil end,
    SetText = function(self, t) self.text = t end,
    GetText = function(self) return self.text end,
    GetStringHeight = function() return 48 end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown end,
    SetSize = function(self, w, h) self.w, self.h = w, h end,
    SetHeight = function(self, h) self.h = h end,
    GetWidth = function(self) return self.w or 140 end,
    GetCenter = function() return 100, 100 end,
    GetEffectiveScale = function() return 1 end,
    CreateTexture = function() return newObject("tex") end,
    CreateFontString = function() return newObject("fs") end,
  }
  return setmetatable(o, { __index = function(_, k)
    if methods[k] then return methods[k] end
    -- Unknown capitalised names behave like harmless widget methods; anything else is a missing field.
    if type(k) == "string" and k:match("^%u") then return function() return newObject("child") end end
    return nil
  end })
end

function M.install()
  _G.CreateFrame = function(kind, name)
    local o = newObject(kind, name)
    M.frames[#M.frames + 1] = o
    if name then _G[name] = o end
    return o
  end
  _G.UIParent, _G.Minimap, _G.GameTooltip = newObject("UIParent"), newObject("Minimap"), newObject("tip")
  _G.UISpecialFrames, _G.tinsert = {}, table.insert
  _G.SlashCmdList = {}
  _G.date = os.date
  _G.time = os.time
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    M.printed[#M.printed + 1] = table.concat(parts, " ")
  end
  M.now = 1000
  _G.GetTime = function() return M.now end
  _G.C_Timer = { After = function(_, fn) M.timers[#M.timers + 1] = fn end }
  _G.GetCursorPosition = function() return 160, 100 end
  _G.GetBuildInfo = function() return "1.60.1", "70862", "Nov  6 2026", 16001 end
end

function M.flushTimers(rounds)
  for _ = 1, rounds or 1 do
    local q = M.timers
    M.timers = {}
    for _, fn in ipairs(q) do fn() end
  end
end

function M.fire(event, ...)
  for _, f in ipairs(M.frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

function M.lastPrinted() return M.printed[#M.printed] or "" end

function M.printedMatch(pat)
  for _, line in ipairs(M.printed) do if line:find(pat) then return true end end
  return false
end

function M.check(name, cond)
  if cond then
    io.write("  ok   " .. name .. "\n")
  else
    io.write("  FAIL " .. name .. "\n")
    M.failures = M.failures + 1
  end
end

function M.finish()
  if M.failures > 0 then
    io.stderr:write(M.failures .. " check(s) failed\n")
    os.exit(1)
  end
end

return M
