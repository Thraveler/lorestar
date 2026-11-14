-- Lorestar loot probe (v0.4.7): records what you loot and where, aggregated.
--
-- On LOOT_OPENED it reads the open loot window (item slots only) and counts, per
-- map cell and loot source, how many times a source was looted and how many of
-- each item it gave. It is OFF by default, the switch is remembered across
-- reloads, and it only reads: it never loots, rolls or acts for you.
--
-- Privacy: no character name, no gold or currency, no GUIDs and no timestamps.
-- A source is stored as "npc:<npcID>" / "obj:<objectID>" (the spawn part of the
-- GUID is dropped), and positions are rounded to a coarse grid cell.

local ADDON_NAME, ns = ...

local GRID = 50             -- cells per map axis (each cell is 2% of the map)
local MAX_KEYS = 4000       -- distinct (map, cell, source) records kept
local MAX_ITEMS = 80        -- distinct items kept per record
local MAX_SAMPLES = 8       -- API-shape samples kept for the probe report

local frame = CreateFrame("Frame")

local function isSecret(v)
    if issecretvalue then
        local ok, res = pcall(issecretvalue, v)
        return ok and res or false
    end
    return false
end

local function say(msg)
    if ns.actions then ns.actions.say(msg) else print("Lorestar: " .. tostring(msg)) end
end

-- Saved data, created on demand: LorestarDB.loot
local function store()
    local l = LorestarDB.loot
    if type(l) ~= "table" then
        l = {}
        LorestarDB.loot = l
    end
    l.enabled = l.enabled and true or false
    l.agg = l.agg or {}           -- ["map|cx|cy|source"] = { opens = n, items = { [itemID] = qty } }
    l.zones = l.zones or {}       -- [mapID] = zone name
    l.sub = l.sub or {}           -- ["map|cx|cy"] = subzone name
    l.probe = l.probe or {}
    local p = l.probe
    p.opens = p.opens or 0        -- loot windows seen
    p.recorded = p.recorded or 0  -- loot windows that produced at least one record
    p.noPosition = p.noPosition or 0
    p.noSource = p.noSource or 0
    p.secret = p.secret or 0
    p.errors = p.errors or 0
    p.droppedKeys = p.droppedKeys or 0
    p.samples = p.samples or {}
    if not l.nKeys then
        local n = 0
        for _ in pairs(l.agg) do n = n + 1 end
        l.nKeys = n
    end
    return l
end

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- "Creature-0-3023-0-11-3257-0000EF92E2" -> "npc", 3257. The spawn part is never kept.
local function parseGUID(guid)
    if type(guid) ~= "string" or isSecret(guid) then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if not kind then return nil end
    if kind == "Creature" or kind == "Vehicle" then return "npc", tonumber(id) end
    if kind == "GameObject" then return "obj", tonumber(id) end
    return nil
end

local function currentPlace()
    local mapID, x, y
    pcall(function()
        mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if mapID and C_Map.GetPlayerMapPosition then
            local pos = C_Map.GetPlayerMapPosition(mapID, "player")
            if pos and pos.GetXY then x, y = pos:GetXY() end
        end
    end)
    if type(mapID) ~= "number" or isSecret(mapID) then mapID = nil end
    if type(x) ~= "number" or type(y) ~= "number" or isSecret(x) or isSecret(y) then x, y = nil, nil end
    return mapID, x, y
end

-- Which source a loot slot came from: the first GUID GetLootSourceInfo reports.
local function slotSource(slot, probeInfo)
    if type(GetLootSourceInfo) ~= "function" then return nil end
    local ok, guid = pcall(GetLootSourceInfo, slot)
    if probeInfo then
        probeInfo.sourceCall = ok
        probeInfo.guidType = ok and type(guid) or nil
        probeInfo.guidSecret = ok and isSecret(guid) or nil
    end
    if not ok then return nil end
    local kind, id = parseGUID(guid)
    if not kind then return nil end
    return kind .. ":" .. id
end

local function onLootOpened()
    local l = store()
    local p = l.probe
    p.opens = p.opens + 1

    if type(GetNumLootItems) ~= "function" or type(GetLootSlotInfo) ~= "function" then
        p.errors = p.errors + 1
        return
    end
    local okN, count = pcall(GetNumLootItems)
    if not okN or type(count) ~= "number" or isSecret(count) then
        p.secret = p.secret + 1
        return
    end

    local mapID, x, y = currentPlace()
    local cx, cy = -1, -1
    if mapID and x then
        cx = math.min(GRID - 1, math.max(0, math.floor(x * GRID)))
        cy = math.min(GRID - 1, math.max(0, math.floor(y * GRID)))
    else
        p.noPosition = p.noPosition + 1
    end
    local mapKey = mapID or 0

    local sample = #p.samples < MAX_SAMPLES and {
        slots = count, hasMap = mapID ~= nil, hasPosition = x ~= nil,
    } or nil

    local gotItem = false
    local opened = {}   -- sources already counted for this window
    for slot = 1, count do
        -- Only item slots: money and currency are skipped on purpose.
        local link
        pcall(function() link = GetLootSlotLink and GetLootSlotLink(slot) end)
        if type(link) == "string" and not isSecret(link) then
            local itemID = tonumber(link:match("item:(%d+)"))
            local okI, _, _, qty = pcall(GetLootSlotInfo, slot)
            if not okI or type(qty) ~= "number" or isSecret(qty) then qty = 1 end
            local source = slotSource(slot, sample)
            if itemID then
                if not source then
                    source = "?"
                    p.noSource = p.noSource + 1
                end
                local key = mapKey .. "|" .. cx .. "|" .. cy .. "|" .. source
                local rec = l.agg[key]
                if not rec and l.nKeys >= MAX_KEYS then
                    p.droppedKeys = p.droppedKeys + 1
                else
                    if not rec then
                        rec = { opens = 0, items = {} }
                        l.agg[key] = rec
                        l.nKeys = l.nKeys + 1
                    end
                    if not opened[key] then
                        opened[key] = true
                        rec.opens = rec.opens + 1
                    end
                    if rec.items[itemID] or countKeys(rec.items) < MAX_ITEMS then
                        rec.items[itemID] = (rec.items[itemID] or 0) + qty
                        gotItem = true
                    end
                end
            end
        end
    end

    if gotItem then
        p.recorded = p.recorded + 1
        if mapID then
            pcall(function()
                local zone = GetZoneText and GetZoneText()
                if type(zone) == "string" and zone ~= "" and not isSecret(zone) then l.zones[mapID] = zone end
                local sub = GetSubZoneText and GetSubZoneText()
                local subKey = mapKey .. "|" .. cx .. "|" .. cy
                if type(sub) == "string" and sub ~= "" and not isSecret(sub) then l.sub[subKey] = sub end
            end)
        end
    end
    if sample then
        sample.recorded = gotItem
        p.samples[#p.samples + 1] = sample
    end
end

frame:SetScript("OnEvent", function(self, event)
    if event == "LOOT_OPENED" then
        local ok = pcall(onLootOpened)
        if not ok then
            local l = store()
            l.probe.errors = l.probe.errors + 1
        end
    end
end)

local api = {}

function api.isEnabled()
    return LorestarDB and LorestarDB.loot and LorestarDB.loot.enabled and true or false
end

function api.setEnabled(on)
    local l = store()
    l.enabled = on and true or false
    if on then
        pcall(frame.RegisterEvent, frame, "LOOT_OPENED")
        say("Loot recording ON. It stays on after reloads. Type /reload to write the data to disk.")
    else
        pcall(frame.UnregisterEvent, frame, "LOOT_OPENED")
        say("Loot recording OFF. Data collected so far is kept (/lorestar loot clear to wipe it).")
    end
end

-- Totals for the status line and the panel.
function api.stats()
    local l = store()
    local items, places = 0, {}
    for key, rec in pairs(l.agg) do
        for _, q in pairs(rec.items) do items = items + q end
        places[key:match("^(%d+|%-?%d+|%-?%d+)|") or key] = true
    end
    local nPlaces = 0
    for _ in pairs(places) do nPlaces = nPlaces + 1 end
    return { opens = l.probe.opens, recorded = l.probe.recorded, records = l.nKeys, items = items, places = nPlaces }
end

function api.clear()
    LorestarDB.loot = nil
    local l = store()
    l.enabled = false
    pcall(frame.UnregisterEvent, frame, "LOOT_OPENED")
    say("Loot data cleared and recording OFF. Type /reload to write the empty file.")
end

function api.status()
    local l = store()
    local s = api.stats()
    local p = l.probe
    say("loot: " .. (l.enabled and "ON" or "OFF") .. " | windows seen " .. p.opens .. ", recorded " .. p.recorded
        .. " | records " .. l.nKeys .. " (" .. s.places .. " places), items " .. s.items)
    say("  no position " .. p.noPosition .. ", no source " .. p.noSource .. ", secret " .. p.secret
        .. ", errors " .. p.errors .. ", dropped " .. p.droppedKeys)
end

function api.command(rest)
    if not LorestarDB then return end
    if rest == "on" then
        api.setEnabled(true)
    elseif rest == "off" then
        api.setEnabled(false)
    elseif rest == "clear" then
        api.clear()
    elseif rest == "" or rest == "status" then
        api.status()
    else
        say("Usage: /lorestar loot on|off|status|clear")
    end
end

ns.loot = api

-- Resume after login if it was left on (the saved variables exist by now).
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if api.isEnabled() then
        pcall(frame.RegisterEvent, frame, "LOOT_OPENED")
        say("Loot recording is ON (" .. store().nKeys .. " records so far). /lorestar loot off to stop.")
    end
end)
