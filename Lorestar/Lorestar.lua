-- Lorestar: explores which APIs and data are available to addons in WoW Forever.
-- Everything is written to the SavedVariables file Lorestar.lua (flushed on /reload or logout).

local ADDON_NAME, ns = ...

local VERSION = "0.4.8"
local PREFIX = "|cff33ff99Lorestar|r: "
local MAX_DEPTH = 4

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function say(msg)
    print(PREFIX .. tostring(msg))
end

local function pack(...)
    return { n = select("#", ...), ... }
end

-- Anonymous mode (default ON): hides character name, realm, gold and the
-- free-text samples of events. Toggle with /lorestar anon on|off.
local function isAnon()
    return not LorestarDB or LorestarDB.anonymous ~= false
end

local function isSecret(v)
    if issecretvalue then
        local ok, res = pcall(issecretvalue, v)
        return ok and res or false
    end
    return false
end

-- Turns any value into something safe to store in SavedVariables:
-- primitives only, secrets masked, widgets/functions replaced by markers.
local function clean(v, depth)
    depth = depth or 0
    if isSecret(v) then return "<secret>" end
    local t = type(v)
    if t == "string" or t == "boolean" then return v end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return tostring(v) end
        return v
    end
    if t == "nil" then return "<nil>" end
    if t == "table" then
        if depth >= MAX_DEPTH then return "<table: depth limit>" end
        if issecrettable and issecrettable(v) then return "<secret table>" end
        local okW, isWidget = pcall(function() return type(v.GetObjectType) == "function" end)
        if okW and isWidget then return "<widget>" end
        local out, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 200 then
                out["<truncated>"] = true
                break
            end
            local kt = type(k)
            if (kt == "string" or kt == "number") and not isSecret(k) then
                out[k] = clean(val, depth + 1)
            end
        end
        return out
    end
    return "<" .. t .. ">"
end

-- Resolves "C_Container.GetContainerNumSlots" style paths from _G.
local function resolve(path)
    local cur = _G
    for part in string.gmatch(path, "[^%.]+") do
        if type(cur) ~= "table" then return nil end
        cur = cur[part]
        if cur == nil then return nil end
    end
    return cur
end

-- Calls a function by path, safely. Returns cleaned results:
--   "<missing>" if it does not exist, "<error: ...>" if it failed,
--   a single value, or a table of values if it returned several.
local function call(path, ...)
    local fn = resolve(path)
    if type(fn) ~= "function" then return "<missing>" end
    local r = pack(pcall(fn, ...))
    if not r[1] then return "<error: " .. tostring(r[2]) .. ">" end
    if r.n == 1 then return "<no return>" end
    if r.n == 2 then return clean(r[2]) end
    local out = {}
    for i = 2, r.n do out[i - 1] = clean(r[i]) end
    return out
end

local function firstNumber(v)
    if type(v) == "number" then return v end
    if type(v) == "table" and type(v[1]) == "number" then return v[1] end
    return nil
end

---------------------------------------------------------------------------
-- Data sections (each one runs in its own pcall, so one failure never
-- breaks the others)
---------------------------------------------------------------------------

-- Snapshot being built by the current /lorestar dump (lets later sections read earlier ones).
local activeSnap = nil

local sections = {}
local function addSection(name, fn)
    sections[#sections + 1] = { name = name, fn = fn }
end

addSection("build", function()
    local version, build, buildDate, toc = GetBuildInfo()
    return {
        version = version,
        build = build,
        date = buildDate,
        toc = toc,
        locale = call("GetLocale"),
        wowProjectID = WOW_PROJECT_ID,
        realm = isAnon() and "<hidden>" or call("GetRealmName"),
        hasIssecretvalue = issecretvalue ~= nil,
        hasCContainer = C_Container ~= nil,
        hasCAddOns = C_AddOns ~= nil,
        hasCReputation = C_Reputation ~= nil,
        hasCSpellBook = C_SpellBook ~= nil,
        hasCTradeSkillUI = C_TradeSkillUI ~= nil,
        hasCAuctionHouse = C_AuctionHouse ~= nil,
        hasCurrencyInfo = C_CurrencyInfo ~= nil,
    }
end)

addSection("player", function()
    local out = {}
    out.name = isAnon() and "<hidden>" or call("UnitName", "player")
    out.class = call("UnitClass", "player")
    out.race = call("UnitRace", "player")
    out.level = call("UnitLevel", "player")
    out.faction = call("UnitFactionGroup", "player")
    out.sex = call("UnitSex", "player")
    out.xp = call("UnitXP", "player")
    out.xpMax = call("UnitXPMax", "player")
    out.restedXP = call("GetXPExhaustion")
    out.money = isAnon() and "<hidden>" or call("GetMoney")
    out.zone = call("GetZoneText")
    out.subZone = call("GetSubZoneText")
    out.realZone = call("GetRealZoneText")
    out.mapID = call("C_Map.GetBestMapForUnit", "player")
    out.health = call("UnitHealth", "player")
    out.healthMax = call("UnitHealthMax", "player")
    out.power = call("UnitPower", "player")
    out.powerMax = call("UnitPowerMax", "player")
    out.powerType = call("UnitPowerType", "player")
    out.inCombat = call("InCombatLockdown")
    local ok, x, y = pcall(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        return pos:GetXY()
    end)
    if ok then
        out.position = { x = clean(x), y = clean(y) }
    else
        out.position = "<unavailable>"
    end
    return out
end)

addSection("stats", function()
    local out = {}
    local names = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }
    for i = 1, 5 do out[names[i]] = call("UnitStat", "player", i) end
    out.armor = call("UnitArmor", "player")
    out.attackPower = call("UnitAttackPower", "player")
    out.crit = call("GetCritChance")
    out.dodge = call("GetDodgeChance")
    out.parry = call("GetParryChance")
    out.block = call("GetBlockChance")
    out.haste = call("GetHaste")
    out.avgItemLevel = call("GetAverageItemLevel")
    return out
end)

addSection("professions", function()
    local out = {}
    -- Retail-style API
    local idx = call("GetProfessions")
    out.indices = idx
    if type(idx) == "table" then
        out.info = {}
        for _, i in ipairs(idx) do
            if type(i) == "number" then out.info[i] = call("GetProfessionInfo", i) end
        end
    end
    -- Classic-style skill lines
    local n = firstNumber(call("GetNumSkillLines"))
    out.numSkillLines = n
    if n then
        out.skillLines = {}
        for i = 1, math.min(n, 80) do out.skillLines[i] = call("GetSkillLineInfo", i) end
    end
    out.tradeSkillLines = call("C_TradeSkillUI.GetAllProfessionTradeSkillLines")
    return out
end)

addSection("bags", function()
    local out = { bags = {}, totals = {} }
    if not (C_Container and C_Container.GetContainerNumSlots) then
        out.note = "C_Container missing"
        out.legacySlots = call("GetContainerNumSlots", 0)
        return out
    end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = firstNumber(call("C_Container.GetContainerNumSlots", bag))
        if slots and slots > 0 then
            local used = 0
            for slot = 1, slots do
                local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                if ok and type(info) == "table" and not isSecret(info) then
                    used = used + 1
                    local id = info.itemID
                    if id then out.totals[id] = (out.totals[id] or 0) + (info.stackCount or 1) end
                    if not out.sampleItem then out.sampleItem = clean(info) end
                end
            end
            out.bags[bag] = {
                slots = slots,
                used = used,
                free = call("C_Container.GetContainerNumFreeSlots", bag),
            }
        end
    end
    return out
end)

addSection("equipment", function()
    local out = {}
    for slot = 1, 19 do
        out[slot] = {
            id = call("GetInventoryItemID", "player", slot),
            link = call("GetInventoryItemLink", "player", slot),
            durability = call("GetInventoryItemDurability", slot),
        }
    end
    return out
end)

addSection("reputation", function()
    local out = {}
    local modernCount = firstNumber(call("C_Reputation.GetNumFactions"))
    local legacyCount = firstNumber(call("GetNumFactions"))
    out.modernCount = modernCount
    out.legacyCount = legacyCount
    if modernCount then
        out.modern = {}
        for i = 1, math.min(modernCount, 80) do
            out.modern[i] = call("C_Reputation.GetFactionDataByIndex", i)
        end
    end
    if legacyCount then
        out.legacy = {}
        for i = 1, math.min(legacyCount, 80) do
            out.legacy[i] = call("GetFactionInfo", i)
        end
    end
    return out
end)

addSection("quests", function()
    local out = {}
    local n = firstNumber(call("C_QuestLog.GetNumQuestLogEntries"))
    out.modernCount = call("C_QuestLog.GetNumQuestLogEntries")
    out.legacyCount = call("GetNumQuestLogEntries")
    if n then
        out.entries = {}
        for i = 1, math.min(n, 60) do
            out.entries[i] = call("C_QuestLog.GetInfo", i)
        end
    end
    return out
end)

addSection("currencies", function()
    local out = {}
    local n = firstNumber(call("C_CurrencyInfo.GetCurrencyListSize"))
    out.count = n
    if n then
        out.entries = {}
        for i = 1, math.min(n, 60) do
            out.entries[i] = call("C_CurrencyInfo.GetCurrencyListInfo", i)
        end
    end
    return out
end)

addSection("spellbook", function()
    local out = {}
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local lines = firstNumber(call("C_SpellBook.GetNumSpellBookSkillLines"))
    out.skillLineCount = lines
    if lines then
        out.lines, out.spells = {}, {}
        for i = 1, lines do
            local ok, info = pcall(C_SpellBook.GetSpellBookSkillLineInfo, i)
            out.lines[i] = ok and clean(info) or "<error>"
            if ok and type(info) == "table" and not isSecret(info) then
                local offset = info.itemIndexOffset or 0
                local num = info.numSpellBookItems or 0
                for j = offset + 1, offset + num do
                    if #out.spells >= 300 then break end
                    out.spells[#out.spells + 1] = call("C_SpellBook.GetSpellBookItemInfo", j, bank)
                end
            end
        end
    else
        -- Classic-style fallback
        out.legacyTabs = call("GetNumSpellTabs")
    end
    return out
end)

addSection("talents", function()
    local out = {}
    out.activeConfig = call("C_ClassTalents.GetActiveConfigID")
    local tabs = firstNumber(call("GetNumTalentTabs"))
    out.legacyTabCount = tabs
    if tabs then
        out.tabs = {}
        for t = 1, tabs do
            local tab = { info = call("GetTalentTabInfo", t), talents = {} }
            local num = firstNumber(call("GetNumTalents", t))
            if num then
                for i = 1, math.min(num, 40) do
                    tab.talents[i] = call("GetTalentInfo", t, i)
                end
            end
            out.tabs[t] = tab
        end
    end
    return out
end)

addSection("secrets", function()
    local out = {}
    out.hasIssecretvalue = issecretvalue ~= nil
    out.hasIssecrettable = issecrettable ~= nil
    out.hasCanaccessvalue = canaccessvalue ~= nil
    local ok, hp = pcall(UnitHealth, "player")
    out.unitHealthIsSecretNow = ok and isSecret(hp) or false
    out.inCombatNow = call("InCombatLockdown")
    out.combatLogFunction = type(CombatLogGetCurrentEventInfo) == "function"
    return out
end)

-- Returns { [itemID] = count } for everything currently in the player's bags.
local function bagTotals()
    local totals = {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return totals end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = firstNumber(call("C_Container.GetContainerNumSlots", bag))
        if slots and slots > 0 then
            for slot = 1, slots do
                local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                if ok and type(info) == "table" and not isSecret(info) and info.itemID then
                    totals[info.itemID] = (totals[info.itemID] or 0) + (info.stackCount or 1)
                end
            end
        end
    end
    return totals
end

-- Item details for everything in the bags. Needed to judge vendor value,
-- item class and whether an item is a crafting reagent.
-- GetItemInfo returns, in order: 1 name, 2 link, 3 quality, 4 itemLevel,
-- 5 minLevel, 6 type, 7 subType, 8 stackCount, 9 equipLoc, 10 icon,
-- 11 sellPrice (copper), 12 classID, 13 subclassID, 14 bindType,
-- 15 expansionID, 16 setID, 17 isCraftingReagent.
-- Items the client has not cached yet come back empty: run the section
-- again a few seconds later and they will be filled in.
addSection("items", function()
    local out = { items = {}, pending = 0, apis = {} }
    out.apis.hasCItemGetItemInfo = (C_Item ~= nil and C_Item.GetItemInfo ~= nil)
    out.apis.hasLegacyGetItemInfo = (type(GetItemInfo) == "function")
    out.apis.hasCItemGetItemInfoInstant = (C_Item ~= nil and C_Item.GetItemInfoInstant ~= nil)
    out.apis.hasLegacyGetItemInfoInstant = (type(GetItemInfoInstant) == "function")
    local infoPath = (C_Item and C_Item.GetItemInfo) and "C_Item.GetItemInfo" or "GetItemInfo"
    local instantPath = (C_Item and C_Item.GetItemInfoInstant) and "C_Item.GetItemInfoInstant" or "GetItemInfoInstant"
    local n = 0
    for itemID, count in pairs(bagTotals()) do
        n = n + 1
        if n > 150 then
            out.truncated = true
            break
        end
        local entry = { count = count }
        entry.instant = call(instantPath, itemID)
        entry.info = call(infoPath, itemID)
        if entry.info == "<nil>" or entry.info == "<no return>" then
            out.pending = out.pending + 1
            pcall(function() C_Item.RequestLoadItemDataByID(itemID) end)
        end
        out.items[itemID] = entry
    end
    return out
end)

-- Known recipes and their reagents. Profession data is only available while
-- a profession window is open, so open one (for example Blacksmithing) first.
addSection("recipes", function()
    local out = {}
    out.api = {
        hasModern = (C_TradeSkillUI ~= nil and C_TradeSkillUI.GetAllRecipeIDs ~= nil),
        hasLegacy = (type(GetNumTradeSkills) == "function"),
    }
    out.tradeSkillReady = call("C_TradeSkillUI.IsTradeSkillReady")
    out.tradeSkillLine = call("C_TradeSkillUI.GetTradeSkillLine")
    out.baseProfession = call("C_TradeSkillUI.GetBaseProfessionInfo")

    -- Modern (Retail-style) API
    local getIDs = resolve("C_TradeSkillUI.GetAllRecipeIDs")
    if type(getIDs) == "function" then
        local ok, list = pcall(getIDs)
        if ok and type(list) == "table" and not isSecret(list) then
            out.modernCount = #list
            out.modern = {}
            -- v0.4.0: all recipes (cap raised from 150), compact rows (no hyperlink).
            for i = 1, math.min(#list, 2000) do
                local id = list[i]
                local row = { id = id }
                local okI, info = pcall(C_TradeSkillUI.GetRecipeInfo, id)
                if okI and type(info) == "table" and not isSecret(info) then
                    row.name = clean(info.name)
                    row.learned = clean(info.learned)
                    row.categoryID = clean(info.categoryID)
                    -- v0.4.8: skill data, for knowing which recipes still level you up
                    row.diff = clean(info.relativeDifficulty)
                    row.trivial = clean(info.maxTrivialLevel)
                    row.skillUp = clean(info.canSkillUp)
                    if i == 1 then row.sampleInfo = clean(info) end
                elseif not okI then
                    row.infoError = tostring(info)
                end
                local okS, schem = pcall(C_TradeSkillUI.GetRecipeSchematic, id, false)
                if okS and type(schem) == "table" and not isSecret(schem) then
                    row.outputItemID = clean(schem.outputItemID)
                    row.outMin = clean(schem.quantityMin)   -- v0.4.8: units made per craft
                    row.outMax = clean(schem.quantityMax)
                    row.reagents = {}
                    local slots = schem.reagentSlotSchematics
                    if type(slots) == "table" then
                        for _, slot in ipairs(slots) do
                            if type(slot) == "table" and type(slot.reagents) == "table" then
                                for _, reagent in ipairs(slot.reagents) do
                                    if type(reagent) == "table" then
                                        row.reagents[#row.reagents + 1] = {
                                            itemID = clean(reagent.itemID),
                                            qty = clean(slot.quantityRequired),
                                        }
                                    end
                                end
                            end
                        end
                    end
                    if i == 1 then
                        local keys = {}
                        for k in pairs(schem) do
                            if type(k) == "string" then keys[#keys + 1] = k end
                        end
                        table.sort(keys)
                        row.schematicKeys = keys
                    end
                elseif not okS then
                    row.schematicError = tostring(schem)
                end
                out.modern[i] = row
            end
        end
    end

    -- Legacy (Classic-style) API
    local n = firstNumber(call("GetNumTradeSkills"))
    out.legacyCount = n
    if n and n > 0 then
        out.legacy = {}
        for i = 1, math.min(n, 150) do
            local row = {
                info = call("GetTradeSkillInfo", i),
                link = call("GetTradeSkillItemLink", i),
            }
            local nr = firstNumber(call("GetTradeSkillNumReagents", i))
            if nr then
                row.reagents = {}
                for j = 1, nr do
                    row.reagents[j] = {
                        info = call("GetTradeSkillReagentInfo", i, j),
                        link = call("GetTradeSkillReagentItemLink", i, j),
                    }
                end
            end
            out.legacy[i] = row
        end
    end

    if not (out.modern or out.legacy) then
        out.note = "No recipe data. Open a profession window (for example Blacksmithing) and run this section again."
    end

    -- v0.4.1: keep one entry per profession, so several profession windows can be
    -- dumped one after another and written to disk with a single /reload.
    -- Entries from earlier dumps are carried forward, so a later dump with the
    -- window closed no longer wipes them.
    local prev = LorestarDB and LorestarDB.snapshot and LorestarDB.snapshot.sections
        and LorestarDB.snapshot.sections.recipes
    local result = { byProfession = {} }
    if type(prev) == "table" and type(prev.byProfession) == "table" then
        -- Skip empty keys and entries without rows: v0.4.1 could save an empty
        -- entry under '' and it would otherwise be carried forward forever.
        for k, v in pairs(prev.byProfession) do
            if k ~= "" and type(v) == "table" and ((v.modern and next(v.modern) ~= nil)
                or (v.legacy and next(v.legacy) ~= nil)) then
                result.byProfession[k] = v
            end
        end
    end
    local hasRows = (out.modern and next(out.modern) ~= nil) or (out.legacy and next(out.legacy) ~= nil)
    if hasRows then
        local key
        local bp = out.baseProfession
        if type(bp) == "table" and type(bp.professionName) == "string" then
            key = bp.professionName
        end
        if not key then
            -- Name unavailable: fall back to the first recipe ID, which differs per profession.
            local first = out.modern and out.modern[1]
            key = "recipe-set-" .. tostring(first and first.id or "legacy")
        end
        result.byProfession[key] = out
        result.last = key
    else
        result.note = out.note
            or "Profession window is open but has no recipes (or the window is closed). Nothing saved."
    end
    return result
end)

-- v0.4.4: names for every item that appears in a dumped recipe (reagents and
-- crafted outputs), not only for items in the bags. Run it after `dump recipes`.
-- Names the client has not cached yet are requested and re-read a few seconds later.
local MAX_NAME_IDS = 2000

local function collectRecipeItemIDs(recipes)
    local seen, ids = {}, {}
    local function add(id)
        if type(id) == "number" and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    local byProfession = type(recipes) == "table" and recipes.byProfession
    if type(byProfession) ~= "table" then return ids end
    for _, entry in pairs(byProfession) do
        if type(entry) == "table" and type(entry.modern) == "table" then
            for _, row in pairs(entry.modern) do
                if type(row) == "table" then
                    add(row.outputItemID)
                    if type(row.reagents) == "table" then
                        for _, reagent in pairs(row.reagents) do
                            if type(reagent) == "table" then add(reagent.itemID) end
                        end
                    end
                end
            end
        end
    end
    table.sort(ids)
    return ids
end

-- Reads names into `store` ([itemID] = { n = name, q = quality, s = sellPrice }); returns how many are still pending.
local function resolveItemNames(ids, store)
    local pending = 0
    for _, id in ipairs(ids) do
        if not store[id] then
            local ok, name, _, quality, _, _, _, _, _, _, _, sell = pcall(C_Item.GetItemInfo, id)
            if ok and type(name) == "string" and not isSecret(name) then
                store[id] = { n = name, q = clean(quality), s = clean(sell) }
            else
                pending = pending + 1
                pcall(C_Item.RequestLoadItemDataByID, id)
            end
        end
    end
    return pending
end

local function retryItemNames(ids, attempt)
    local sec = LorestarDB and LorestarDB.snapshot and LorestarDB.snapshot.sections
        and LorestarDB.snapshot.sections.itemnames
    if not sec then return end
    sec.pending = resolveItemNames(ids, sec.items)
    if sec.pending > 0 and attempt < 3 and C_Timer and C_Timer.After then
        C_Timer.After(3, function() retryItemNames(ids, attempt + 1) end)
    else
        say("itemnames: " .. (#ids - sec.pending) .. " of " .. #ids .. " names resolved"
            .. (sec.pending > 0 and (", " .. sec.pending .. " still pending (run /lorestar dump itemnames again)") or "")
            .. ". Type /reload to write the file.")
    end
end

addSection("itemnames", function()
    local out = { items = {}, pending = 0, total = 0 }
    local recipes = (activeSnap and activeSnap.sections and activeSnap.sections.recipes)
        or (LorestarDB and LorestarDB.snapshot and LorestarDB.snapshot.sections
            and LorestarDB.snapshot.sections.recipes)
    local ids = collectRecipeItemIDs(recipes)
    if #ids == 0 then
        out.note = "No recipe data found. Run /lorestar dump recipes (with a profession window open) first."
        return out
    end
    if #ids > MAX_NAME_IDS then
        out.truncated = #ids
        for i = #ids, MAX_NAME_IDS + 1, -1 do ids[i] = nil end
    end
    out.total = #ids
    -- Carry names resolved by earlier dumps forward.
    local prev = LorestarDB and LorestarDB.snapshot and LorestarDB.snapshot.sections
        and LorestarDB.snapshot.sections.itemnames
    if type(prev) == "table" and type(prev.items) == "table" then
        for id, v in pairs(prev.items) do
            if type(id) == "number" and type(v) == "table" and v.n then out.items[id] = v end
        end
    end
    out.pending = resolveItemNames(ids, out.items)
    if out.pending > 0 and C_Timer and C_Timer.After then
        C_Timer.After(3, function() retryItemNames(ids, 1) end)
    end
    return out
end)

-- Which auction house functions exist, and a few state checks. Prices are not
-- read here: they are sampled passively while event tracking is on and you
-- search the auction house yourself (see /lorestar events on).
addSection("auction", function()
    local out = {}
    local ns = C_AuctionHouse
    out.hasNamespace = (ns ~= nil)
    if type(ns) == "table" then
        local names = {}
        pcall(function()
            for k in pairs(ns) do
                if type(k) == "string" then names[#names + 1] = k end
            end
        end)
        table.sort(names)
        out.functions = names
    end
    local okF, shown = pcall(function() return AuctionHouseFrame and AuctionHouseFrame:IsShown() end)
    out.frameShown = (okF and shown) and true or false
    out.throttleReady = call("C_AuctionHouse.IsThrottledMessageSystemReady")
    out.ownedAuctions = call("C_AuctionHouse.GetNumOwnedAuctions")
    out.samplesRecorded = LorestarDB and LorestarDB.auctionSamples and #LorestarDB.auctionSamples or 0
    return out
end)

local function sectionNames()
    local names = {}
    for _, s in ipairs(sections) do names[#names + 1] = s.name end
    return table.concat(names, ", ")
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

-- Safety net for anonymous mode: replaces any remaining occurrence of the
-- character name or realm inside the collected strings.
local function escapePattern(s)
    return (s:gsub("%p", "%%%0"))
end

local function nameScrubPatterns()
    local patterns = {}
    local okN, name = pcall(UnitName, "player")
    if okN and type(name) == "string" and not isSecret(name) and name ~= "" then
        patterns[#patterns + 1] = { pattern = escapePattern(name), label = "<name>" }
    end
    local okR, realm = pcall(GetRealmName)
    if okR and type(realm) == "string" and not isSecret(realm) and realm ~= "" then
        patterns[#patterns + 1] = { pattern = escapePattern(realm), label = "<realm>" }
    end
    -- Character GUIDs can hide inside item links (crafted items carry the crafter's GUID).
    patterns[#patterns + 1] = { pattern = "Player%-%d+%-%x+", label = "<guid>" }
    return patterns
end

local function scrub(v, patterns)
    if type(v) == "string" then
        for _, p in ipairs(patterns) do
            v = v:gsub(p.pattern, p.label)
        end
        return v
    end
    if type(v) == "table" then
        for k, val in pairs(v) do
            v[k] = scrub(val, patterns)
        end
    end
    return v
end

local function runDump(only)
    local db = LorestarDB
    local snap = {
        time = date("%Y-%m-%d %H:%M:%S"),
        addonVersion = VERSION,
        sections = {},
        errors = {},
    }
    local ran = 0
    activeSnap = snap
    for _, s in ipairs(sections) do
        if only == "" or only == s.name then
            ran = ran + 1
            local ok, res = pcall(s.fn)
            if ok then
                snap.sections[s.name] = res
            else
                snap.errors[s.name] = tostring(res)
            end
        end
    end
    activeSnap = nil
    if ran == 0 then
        say("Unknown section '" .. only .. "'. Sections: " .. sectionNames())
        return
    end
    snap.anonymous = isAnon()
    if snap.anonymous then
        local pats = nameScrubPatterns()
        snap.sections = scrub(snap.sections, pats)
        snap.errors = scrub(snap.errors, pats)
    end
    if only == "" or not db.snapshot then
        db.snapshot = snap
    else
        db.snapshot.anonymous = db.snapshot.anonymous and snap.anonymous
        for k, v in pairs(snap.sections) do db.snapshot.sections[k] = v end
        for k, v in pairs(snap.errors) do db.snapshot.errors[k] = v end
        db.snapshot.time = snap.time
    end
    local errCount = 0
    for _ in pairs(snap.errors) do errCount = errCount + 1 end
    say(ran .. " section(s) dumped, " .. errCount .. " with errors. Type /reload to write the file to disk.")
    if errCount > 0 then
        for name, err in pairs(snap.errors) do say("  " .. name .. ": " .. err) end
    end
    local itemsSection = snap.sections.items
    if itemsSection and itemsSection.pending and itemsSection.pending > 0 then
        say(itemsSection.pending .. " item(s) were not cached yet. Wait a few seconds and run /lorestar dump items again.")
    end
    local namesSection = snap.sections.itemnames
    if namesSection and namesSection.note then
        say("itemnames: " .. namesSection.note)
    elseif namesSection and namesSection.pending and namesSection.pending > 0 then
        say("itemnames: " .. namesSection.pending .. " of " .. namesSection.total .. " names not cached yet, retrying for a few seconds...")
    end
    local recipesSection = snap.sections.recipes
    if recipesSection and recipesSection.note then
        say("recipes: " .. recipesSection.note)
    elseif recipesSection and recipesSection.last then
        say("recipes: saved '" .. tostring(recipesSection.last) .. "'")
    end
end

-- Lists every global function and every C_* namespace member available in
-- this client. Useful to compare against Retail/Classic.
local function runApi()
    local funcs, namespaces, enums = {}, {}, {}
    for k, v in pairs(_G) do
        if type(k) == "string" then
            local t = type(v)
            if t == "function" then
                funcs[#funcs + 1] = k
            elseif t == "table" and k:find("^C_") then
                local members = {}
                pcall(function()
                    for mk in pairs(v) do
                        if type(mk) == "string" then members[#members + 1] = mk end
                    end
                end)
                table.sort(members)
                namespaces[k] = members
            end
        end
    end
    table.sort(funcs)
    if type(Enum) == "table" then
        for k in pairs(Enum) do
            if type(k) == "string" then enums[#enums + 1] = k end
        end
        table.sort(enums)
    end
    local nsCount = 0
    for _ in pairs(namespaces) do nsCount = nsCount + 1 end
    LorestarDB.api = {
        time = date("%Y-%m-%d %H:%M:%S"),
        build = select(2, GetBuildInfo()),
        functionCount = #funcs,
        functions = funcs,
        namespaces = namespaces,
        enums = enums,
    }
    say(#funcs .. " global functions, " .. nsCount .. " C_ namespaces, " .. #enums .. " Enums recorded. Type /reload to write the file.")
end

-- Event tracking: counts how often each event fires and what argument types
-- it carries. Turn it on, play a bit, then /reload.
local TRACKED_EVENTS = {
    "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "PLAYER_MONEY",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE",
    "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
    "BAG_UPDATE_DELAYED", "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
    "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "TRADE_SKILL_SHOW",
    "UPDATE_FACTION", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "QUEST_REMOVED",
    "LOOT_OPENED", "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_COMBAT_XP_GAIN",
    "MERCHANT_SHOW", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "OWNED_AUCTIONS_UPDATED",
    "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED",
    "UNIT_SPELLCAST_SUCCEEDED", "SPELLS_CHANGED",
    "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "COMBAT_RATING_UPDATE",
    "TIME_PLAYED_MSG",
}

-- Passive auction house sampling: while event tracking is on, every search
-- result YOU trigger in the auction house is sampled (first result only, max 20)
-- to learn what the API returns and which fields exist. Nothing is queried
-- automatically. Seller/bidder names are always stripped.
local AUCTION_SAMPLE_EVENTS = {
    COMMODITY_SEARCH_RESULTS_UPDATED = true,
    ITEM_SEARCH_RESULTS_UPDATED = true,
}
local PRIVATE_KEYS = {
    owner = true, owners = true, ownerName = true, ownerAccountID = true,
    bidder = true, bidderName = true, buyer = true, seller = true,
}

local function dropPrivateKeys(v)
    if type(v) == "table" then
        for k, val in pairs(v) do
            if type(k) == "string" and PRIVATE_KEYS[k] then
                v[k] = nil
            else
                dropPrivateKeys(val)
            end
        end
    end
    return v
end

local function sampleAuction(event, ...)
    local db = LorestarDB
    db.auctionSamples = db.auctionSamples or {}
    if #db.auctionSamples >= 20 then return end
    local arg1 = ...
    local entry = { event = event, time = date("%H:%M:%S") }
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        entry.itemID = clean(arg1)
        entry.count = call("C_AuctionHouse.GetNumCommoditySearchResults", arg1)
        entry.first = call("C_AuctionHouse.GetCommoditySearchResultInfo", arg1, 1)
    else
        entry.itemKey = clean(arg1)
        entry.count = call("C_AuctionHouse.GetNumItemSearchResults", arg1)
        entry.first = call("C_AuctionHouse.GetItemSearchResultInfo", arg1, 1)
    end
    dropPrivateKeys(entry)
    -- Samples bypass runDump, so anonymous mode has to scrub them here: item links of crafted
    -- items carry the crafter's character GUID.
    if isAnon() then scrub(entry, nameScrubPatterns()) end
    db.auctionSamples[#db.auctionSamples + 1] = entry
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    local db = LorestarDB
    if not db then return end
    local rec = db.events[event]
    local argc = select("#", ...)
    if not rec then
        rec = { count = 0, argc = argc, types = {}, sample = {} }
        db.events[event] = rec
        for i = 1, math.min(argc, 12) do
            local v = select(i, ...)
            if isSecret(v) then
                rec.types[i] = "secret"
            else
                local t = type(v)
                rec.types[i] = t
                if t == "string" then
                    if not isAnon() then
                        rec.sample[i] = #v > 80 and v:sub(1, 80) or v
                    end
                elseif t == "number" or t == "boolean" then
                    rec.sample[i] = v
                end
            end
        end
    end
    rec.count = rec.count + 1
    if AUCTION_SAMPLE_EVENTS[event] then pcall(sampleAuction, event, ...) end
end)

local function setEvents(on)
    local db = LorestarDB
    db.eventStatus = db.eventStatus or {}
    for _, ev in ipairs(TRACKED_EVENTS) do
        if on then
            local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, ev)
            db.eventStatus[ev] = ok and "registered" or ("error: " .. tostring(err))
        else
            pcall(eventFrame.UnregisterEvent, eventFrame, ev)
            if db.eventStatus[ev] == "registered" then db.eventStatus[ev] = "unregistered" end
        end
    end
    db.eventsActive = on
    say(on and "Event tracking ON. Play a bit, then /reload to write the file." or "Event tracking OFF.")
end

-- Manual auction house price scan (/lorestar scan). Read-only: asks the game
-- for the full replicate list (the game throttles this to roughly once per
-- 15 minutes), then keeps per itemID: listing count (n), total quantity (q),
-- lowest unit buyout (m), and two robust prices weighted by quantity: p10 (unit
-- price below which the cheapest 10% of units sit) and med (quantity-weighted
-- median). Seller and bidder values are discarded and never stored.
local scanFrame = CreateFrame("Frame")
local scanning = false

-- Computes p10 and med per item (a few hundred items per frame) and stores the result.
local function finalizePrices(items, total, probe)
    local keys = {}
    for id in pairs(items) do keys[#keys + 1] = id end
    local k = 0
    local function fin()
        local last = math.min(k + 199, #keys)
        for j = k + 1, last do
            local rec = items[keys[j]]
            local u, c = rec.u, rec.c
            rec.u, rec.c = nil, nil
            local cnt = u and #u or 0
            if cnt > 0 then
                local idx = {}
                for x = 1, cnt do idx[x] = x end
                table.sort(idx, function(a, b) return u[a] < u[b] end)
                local totalQ, cum = 0, 0
                for x = 1, cnt do totalQ = totalQ + c[x] end
                local p10, med
                for _, x in ipairs(idx) do
                    cum = cum + c[x]
                    if not p10 and cum >= totalQ * 0.10 then p10 = u[x] end
                    if not med and cum >= totalQ * 0.50 then med = u[x] break end
                end
                rec.p10, rec.med = p10, med
            end
        end
        k = last
        if k < #keys then
            C_Timer.After(0, fin)
        else
            LorestarDB.prices = {
                time = date("%Y-%m-%d %H:%M:%S"), ts = time(), rows = total, distinct = #keys,
                probe = probe, items = items, schema = 2,
            }
            scanning = false
            say("Scan done: " .. total .. " listings, " .. #keys .. " distinct items. Type /reload to write the file.")
        end
    end
    fin()
end

local function processReplicate()
    local db = LorestarDB
    local total = firstNumber(call("C_AuctionHouse.GetNumReplicateItems")) or 0
    local items, probe = {}, nil
    local i = 0
    local function step()
        local last = math.min(i + 499, total - 1)
        for idx = i, last do
            local ok, name, _, count, quality, _, level, _, _, _, buyout, _, _, _, _, _, _, itemID =
                pcall(C_AuctionHouse.GetReplicateItemInfo, idx)
            if ok and itemID and not isSecret(itemID) and type(itemID) == "number" then
                if not probe then
                    probe = { nameType = type(name), countType = type(count), buyoutType = type(buyout), itemID = itemID }
                end
                if type(buyout) == "number" and not isSecret(buyout)
                    and type(count) == "number" and not isSecret(count) and count > 0 then
                    local rec = items[itemID]
                    if not rec then
                        rec = { n = 0, q = 0, u = {}, c = {} }
                        items[itemID] = rec
                    end
                    rec.n = rec.n + 1
                    rec.q = rec.q + count
                    if buyout > 0 then
                        local unit = math.floor(buyout / count)
                        if not rec.m or unit < rec.m then rec.m = unit end
                        rec.u[#rec.u + 1] = unit
                        rec.c[#rec.c + 1] = count
                    end
                end
            end
        end
        i = last + 1
        if i < total then
            C_Timer.After(0, step)
        else
            finalizePrices(items, total, probe)
        end
    end
    if total == 0 then
        scanning = false
        say("Scan returned 0 listings (the game may have throttled the request). Try again later.")
        return
    end
    step()
end

scanFrame:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    pcall(processReplicate)
end)

local function runScan()
    if scanning then say("A scan is already running.") return end
    local okF, shown = pcall(function() return AuctionHouseFrame and AuctionHouseFrame:IsShown() end)
    if not (okF and shown) then
        say("Open the auction house first, then run /lorestar scan.")
        return
    end
    local fn = resolve("C_AuctionHouse.ReplicateItems")
    if type(fn) ~= "function" then
        say("C_AuctionHouse.ReplicateItems is not available in this client.")
        return
    end
    scanning = true
    scanFrame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    local ok, err = pcall(fn)
    if not ok then
        scanning = false
        scanFrame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
        say("Scan request failed: " .. tostring(err))
        return
    end
    say("Scan requested. Waiting for the auction house data...")
end

local function showStatus()
    local db = LorestarDB
    local evCount = 0
    for _ in pairs(db.events) do evCount = evCount + 1 end
    say("v" .. VERSION .. " | snapshot: " .. (db.snapshot and db.snapshot.time or "none")
        .. " | api: " .. (db.api and db.api.time or "none")
        .. " | anonymous: " .. (isAnon() and "ON" or "OFF")
        .. " | events tracking: " .. (db.eventsActive and "ON" or "OFF")
        .. " (" .. evCount .. " distinct events seen)")
end

local function showHelp()
    say("v" .. VERSION .. " commands:")
    say("  /lorestar dump [section]   collect data (sections: " .. sectionNames() .. ")")
    say("  /lorestar api              record all global functions and C_* namespaces")
    say("  /lorestar events on|off    track events and sample auction house results you search")
    say("  /lorestar scan             with the auction house open, record lowest buyout per item")
    say("  /lorestar anon on|off      hide (default) or include name, realm, gold and event text")
    say("  /lorestar advise [all]     recommend what to do with each item in your bags (never acts)")
    say("  /lorestar loot on|off|status|clear  record what you loot and where (aggregated, off by default)")
    say("  /lorestar ui               open the panel (also: click the minimap button)")
    say("  /lorestar minimap show|hide  show or hide the minimap button")
    say("  /lorestar status           show what is recorded")
    say("  /lorestar clear            wipe everything recorded")
    say("Open a profession window before dumping 'recipes'.")
    say("After any command, /reload writes the data to SavedVariables.")
end

-- Actions shared by the slash commands and the UI panel (Lorestar_UI.lua).
local function setAnon(on)
    LorestarDB.anonymous = on and true or false
    if on then
        say("Anonymous mode ON: name, realm, gold and event text samples are hidden.")
    else
        say("Anonymous mode OFF: new dumps will include name, realm, gold and event text. Clear first to remove older data.")
    end
end

local function clearAll()
    setEvents(false)
    LorestarDB.snapshot = nil
    LorestarDB.api = nil
    LorestarDB.events = {}
    LorestarDB.eventStatus = {}
    LorestarDB.auctionSamples = nil
    LorestarDB.prices = nil
    say("Cleared (loot data is kept: /lorestar loot clear). Type /reload to write the empty file.")
end

ns.actions = {
    version = VERSION,
    say = say,
    isAnon = isAnon,
    dump = runDump,
    events = setEvents,
    scan = runScan,
    setAnon = setAnon,
    clear = clearAll,
    isScanning = function() return scanning end,
}

SLASH_LORESTAR1 = "/lorestar"
SlashCmdList["LORESTAR"] = function(msg)
    if not LorestarDB then
        say("Not initialised yet, try again in a moment.")
        return
    end
    msg = ((msg or ""):match("^%s*(.-)%s*$")):lower()
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    if cmd == "dump" then
        runDump(rest or "")
    elseif cmd == "api" then
        runApi()
    elseif cmd == "events" then
        if rest == "on" then
            setEvents(true)
        elseif rest == "off" then
            setEvents(false)
        else
            say("Usage: /lorestar events on|off")
        end
    elseif cmd == "scan" then
        runScan()
    elseif cmd == "anon" then
        if rest == "on" then
            setAnon(true)
        elseif rest == "off" then
            setAnon(false)
        else
            say("Anonymous mode is " .. (isAnon() and "ON" or "OFF") .. ". Usage: /lorestar anon on|off")
        end
    elseif cmd == "status" then
        showStatus()
    elseif cmd == "clear" then
        clearAll()
    elseif cmd == "advise" or cmd == "advice" then
        if ns.advisor then ns.advisor.command(rest or "") else say("The advisor module is not available.") end
    elseif cmd == "loot" then
        if ns.loot then ns.loot.command(rest or "") else say("The loot module is not available.") end
    elseif cmd == "ui" then
        if ns.togglePanel then ns.togglePanel() else say("The UI panel is not available.") end
    elseif cmd == "minimap" then
        if ns.setMinimapShown and (rest == "show" or rest == "hide") then
            ns.setMinimapShown(rest == "show")
        else
            say("Usage: /lorestar minimap show|hide")
        end
    else
        showHelp()
    end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name ~= ADDON_NAME then return end
    LorestarDB = LorestarDB or {}
    LorestarDB.events = LorestarDB.events or {}
    LorestarDB.eventStatus = LorestarDB.eventStatus or {}
    -- Event tracking never resumes by itself after a reload.
    LorestarDB.eventsActive = false
    if LorestarDB.anonymous == nil then LorestarDB.anonymous = true end
    self:UnregisterEvent("ADDON_LOADED")
    say("loaded v" .. VERSION .. ". Type /lorestar for commands.")
end)
