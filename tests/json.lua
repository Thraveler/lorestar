-- Tiny JSON decoder for the tests (LuaJIT has none built in). null becomes nil.
local M = {}

local function skip(s, i)
  return s:find("[^ \t\r\n]", i) or #s + 1
end

local function str(s, i)
  local out, j = {}, i + 1
  while true do
    local c = s:sub(j, j)
    if c == '"' then return table.concat(out), j + 1 end
    if c == "\\" then
      local n = s:sub(j + 1, j + 1)
      local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
      if n == "u" then
        out[#out + 1] = utf8 and utf8.char(tonumber(s:sub(j + 2, j + 5), 16)) or "?"
        j = j + 6
      else
        out[#out + 1] = map[n] or n
        j = j + 2
      end
    elseif c == "" then
      error("unterminated string")
    else
      out[#out + 1] = c
      j = j + 1
    end
  end
end

local value
local function arr(s, i)
  local t, n = {}, 0
  i = skip(s, i + 1)
  if s:sub(i, i) == "]" then return t, i + 1 end
  while true do
    local v
    v, i = value(s, i)
    n = n + 1
    t[n] = v
    i = skip(s, i)
    local c = s:sub(i, i)
    if c == "]" then return t, i + 1 end
    if c ~= "," then error("expected , or ] at " .. i) end
    i = i + 1
  end
end

local function obj(s, i)
  local t = {}
  i = skip(s, i + 1)
  if s:sub(i, i) == "}" then return t, i + 1 end
  while true do
    i = skip(s, i)
    local k
    k, i = str(s, i)
    i = skip(s, i)
    if s:sub(i, i) ~= ":" then error("expected : at " .. i) end
    local v
    v, i = value(s, skip(s, i + 1))
    t[k] = v
    i = skip(s, i)
    local c = s:sub(i, i)
    if c == "}" then return t, i + 1 end
    if c ~= "," then error("expected , or } at " .. i) end
    i = i + 1
  end
end

function value(s, i)
  i = skip(s, i)
  local c = s:sub(i, i)
  if c == "{" then return obj(s, i) end
  if c == "[" then return arr(s, i) end
  if c == '"' then return str(s, i) end
  if s:sub(i, i + 3) == "true" then return true, i + 4 end
  if s:sub(i, i + 4) == "false" then return false, i + 5 end
  if s:sub(i, i + 3) == "null" then return nil, i + 4 end
  local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
  if num and #num > 0 then return tonumber(num), i + #num end
  error("unexpected character at " .. i)
end

function M.decode(s)
  local v = value(s, 1)
  return v
end

return M
