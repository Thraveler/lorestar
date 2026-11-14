-- Lorestar advisor (v0.4.8): recommends what to do with each item in your bags.
--
-- keep     : you probably need it (quest item, or a reagent of a recipe you know)
-- sell_ah  : the Auction House pays clearly more than the vendor
-- vendor   : sell it to a vendor
-- discard  : worthless and your bags are nearly full
-- review   : it cannot be decided automatically; look at it yourself
--
-- It only RECOMMENDS. It never sells, posts, destroys or moves anything.
--
-- The rules live in A.evaluate, a pure function (no game API) that is tested against
-- tests/rules_cases.json. The web viewer has the same rules in web/src/lib/rules.ts,
-- tested against the same file: change one, change the other.

local ADDON_NAME, ns = ...

local A = {}

-- All prices are copper per unit.
A.defaults = {
    ahCut = 0.05,          -- the Auction House keeps this share of a sale
    ahRatio = 1.5,         -- the AH price (after the cut) must be at least this many times the vendor price
    minGainPerItem = 2,    -- and beat the vendor by at least this much per unit
    minListings = 3,       -- fewer listings than this: the AH price is not reliable
    craftsToKeep = 10,     -- keep reagents for this many crafts of the recipes you know
    saturation = 0.25,     -- holding more than this share of the listed units: selling would move the price
    lowFreeSlots = 4,      -- at or below this many free slots, worthless items are discarded
    maxSpread = 4,         -- median above this many times the p10: the median is not trusted, the p10 is used
    keepIds = { [6948] = true },   -- Hearthstone
}

A.REASONS = {
    keep_list = "On the keep list",
    quest = "Quest item",
    recipe_item = "Recipe or pattern: learn it or sell it, your call",
    reagent_learned = "Reagent for a recipe you know",
    ah_better = "The Auction House pays clearly more than the vendor",
    ah_only = "The vendor pays nothing, the Auction House has a price",
    vendor_better = "The vendor pays about the same as the Auction House",
    vendor_only = "No Auction House price known",
    bound_vendor = "Bound to you: it cannot be auctioned",
    no_value = "No sell value",
}

A.NOTES = {
    unlearned_recipes = "used by recipes you have not learned",
    check_upgrade = "gear: check that it is not an upgrade first",
    thin_market = "few Auction House listings: the price is not reliable",
    saturation = "you hold a big share of the market: the price would drop",
    wide_spread = "the median is far above the cheap end: priced at the cheap end instead",
}

local function merge(over)
    local cfg = {}
    for k, v in pairs(A.defaults) do cfg[k] = v end
    if over then
        for k, v in pairs(over) do cfg[k] = v end
    end
    return cfg
end

-- item: { id, qty, quality, classID, vendor, stack, bound }
-- ctx : { price = { med, p10, m, n, q }, recipes = { learnedCount, learnedMax, unlearnedCount }, freeSlots }
function A.evaluate(item, ctx, over)
    local cfg = merge(over)
    ctx = ctx or {}
    local qty = item.qty or 0
    local vendor = item.vendor or 0
    local stack = item.stack or 1
    local price = ctx.price
    local recipes = ctx.recipes or {}
    local notes = {}

    local function result(action, keepQty, sellQty, unit, reason, confidence)
        local freed = 0
        if sellQty > 0 and (action == "sell_ah" or action == "vendor" or action == "discard") then
            freed = math.ceil(qty / stack) - math.ceil(keepQty / stack)
        end
        return {
            action = action, keepQty = keepQty, sellQty = sellQty, unit = unit, total = sellQty * unit,
            reason = reason, confidence = confidence, notes = notes, slotsFreed = freed,
        }
    end

    if cfg.keepIds[item.id] then return result("keep", qty, 0, 0, "keep_list", "high") end
    if item.classID == 12 then return result("keep", qty, 0, 0, "quest", "high") end
    if item.classID == 9 then return result("review", qty, 0, 0, "recipe_item", "medium") end

    local keepQty = 0
    if (recipes.learnedCount or 0) > 0 then
        keepQty = math.min(qty, (recipes.learnedMax or 1) * cfg.craftsToKeep)
    end
    local surplus = qty - keepQty
    if surplus <= 0 then return result("keep", qty, 0, 0, "reagent_learned", "high") end

    if (recipes.unlearnedCount or 0) > 0 then notes[#notes + 1] = "unlearned_recipes" end
    if (item.quality or 0) >= 2 and (item.classID == 2 or item.classID == 4) then
        notes[#notes + 1] = "check_upgrade"
    end

    -- Some markets are bimodal: most units listed at silly prices while the cheap ones are what sells.
    local ref = price and price.med or nil
    local wide = false
    if ref and price.p10 and price.p10 > 0 and ref > price.p10 * cfg.maxSpread then
        ref = price.p10
        wide = true
    end
    local net = ref and ref * (1 - cfg.ahCut) or nil
    local thin = price ~= nil and (price.n or 0) < cfg.minListings
    local saturated = price ~= nil and (price.q or 0) > 0 and surplus > cfg.saturation * price.q

    if net and not item.bound and (vendor == 0 or net >= vendor * cfg.ahRatio) and (net - vendor) >= cfg.minGainPerItem then
        local confidence = "high"
        if wide then
            confidence = "low"
            notes[#notes + 1] = "wide_spread"
        end
        if thin then
            confidence = "low"
            notes[#notes + 1] = "thin_market"
        elseif saturated and confidence == "high" then
            confidence = "medium"
        end
        if saturated then notes[#notes + 1] = "saturation" end
        return result("sell_ah", keepQty, surplus, math.floor(net), vendor == 0 and "ah_only" or "ah_better", confidence)
    end

    if vendor > 0 then
        local reason = "vendor_only"
        if item.bound and price then reason = "bound_vendor" elseif price then reason = "vendor_better" end
        return result("vendor", keepQty, surplus, vendor, reason, "high")
    end

    local action = (ctx.freeSlots or 99) <= cfg.lowFreeSlots and "discard" or "review"
    if (recipes.unlearnedCount or 0) > 0 then action = "review" end
    return result(action, keepQty, surplus, 0, "no_value", "medium")
end

---------------------------------------------------------------------------
-- Runtime: gathers your bags, the saved prices and recipes, and runs the rules
---------------------------------------------------------------------------

local function isSecret(v)
    if issecretvalue then
        local ok, res = pcall(issecretvalue, v)
        return ok and res or false
    end
    return false
end

-- Reagent index from the recipes saved by `dump recipes`: [itemID] = { learnedCount, learnedMax, unlearnedCount }.
function A.recipeIndex()
    local index = {}
    local snap = LorestarDB and LorestarDB.snapshot
    local rec = snap and snap.sections and snap.sections.recipes
    local byProfession = type(rec) == "table" and rec.byProfession
    if type(byProfession) ~= "table" then return index, false end
    for _, entry in pairs(byProfession) do
        if type(entry) == "table" and type(entry.modern) == "table" then
            for _, row in pairs(entry.modern) do
                if type(row) == "table" and type(row.reagents) == "table" then
                    for _, reagent in pairs(row.reagents) do
                        if type(reagent) == "table" and type(reagent.itemID) == "number" then
                            local r = index[reagent.itemID]
                            if not r then
                                r = { learnedCount = 0, learnedMax = 0, unlearnedCount = 0 }
                                index[reagent.itemID] = r
                            end
                            if row.learned == true then
                                r.learnedCount = r.learnedCount + 1
                                if (reagent.qty or 1) > r.learnedMax then r.learnedMax = reagent.qty or 1 end
                            else
                                r.unlearnedCount = r.unlearnedCount + 1
                            end
                        end
                    end
                end
            end
        end
    end
    return index, true
end

-- What is in the bags right now: { [itemID] = { qty, bound } } and the number of free slots.
function A.readBags()
    local items, free = {}, 0
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
        return items, nil
    end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local okS, slots = pcall(C_Container.GetContainerNumSlots, bag)
        if okS and type(slots) == "number" and not isSecret(slots) then
            for slot = 1, slots do
                local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                if ok and type(info) == "table" and not isSecret(info) and info.itemID then
                    local it = items[info.itemID]
                    if not it then
                        it = { qty = 0, bound = false }
                        items[info.itemID] = it
                    end
                    it.qty = it.qty + (info.stackCount or 1)
                    if info.isBound then it.bound = true end
                    if info.hasNoValue then it.noValue = true end
                else
                    free = free + 1
                end
            end
        end
    end
    return items, free
end

-- Live item facts. Returns nil while the client has not cached the item yet.
local function itemFacts(id)
    local ok, name, _, quality, _, _, _, _, stack, _, _, sell, classID = pcall(C_Item.GetItemInfo, id)
    if not ok or type(name) ~= "string" or isSecret(name) then return nil end
    return { name = name, quality = quality or 1, stack = stack or 1, vendor = sell or 0, classID = classID }
end

-- Runs the rules over the bags. Returns a list sorted by gain, plus a summary.
function A.run(over)
    local bags, free = A.readBags()
    local index, haveRecipes = A.recipeIndex()
    local prices = LorestarDB and LorestarDB.prices
    local priceItems = prices and prices.items or {}
    local list, summary = {}, { sellAH = 0, vendor = 0, slots = 0, pending = 0, haveRecipes = haveRecipes,
        priceTime = prices and prices.time, priceTs = prices and prices.ts, freeSlots = free, counts = {} }

    for id, bag in pairs(bags) do
        local facts = itemFacts(id)
        if not facts then
            summary.pending = summary.pending + 1
            pcall(C_Item.RequestLoadItemDataByID, id)
        else
            local p = priceItems[id]
            local item = {
                id = id, qty = bag.qty, quality = facts.quality, classID = facts.classID,
                vendor = bag.noValue and 0 or facts.vendor, stack = facts.stack, bound = bag.bound,
            }
            local r = A.evaluate(item, { price = p, recipes = index[id], freeSlots = free }, over)
            r.id, r.name, r.qty, r.bound = id, facts.name, bag.qty, bag.bound
            list[#list + 1] = r
            summary.counts[r.action] = (summary.counts[r.action] or 0) + 1
            if r.action == "sell_ah" then summary.sellAH = summary.sellAH + r.total end
            if r.action == "vendor" then summary.vendor = summary.vendor + r.total end
            summary.slots = summary.slots + r.slotsFreed
        end
    end
    table.sort(list, function(a, b)
        if a.action ~= b.action then return a.action < b.action end
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    return list, summary
end

---------------------------------------------------------------------------
-- Output (chat) and saved advice
---------------------------------------------------------------------------

local function money(c)
    c = math.floor(c or 0)
    local g, s, cp = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
    if g > 0 then return g .. "g " .. s .. "s " .. cp .. "c" end
    if s > 0 then return s .. "s " .. cp .. "c" end
    return cp .. "c"
end
A.money = money

local COLORS = {
    keep = "ff9a948c", sell_ah = "fff2a92c", vendor = "ffefe1bd", discard = "ffc90511", review = "ff6fbf5a",
}
local LABEL = { keep = "KEEP", sell_ah = "SELL AH", vendor = "VENDOR", discard = "DISCARD", review = "REVIEW" }
local ORDER = { "sell_ah", "vendor", "discard", "review", "keep" }

function A.line(r)
    local c = COLORS[r.action] or "ffffffff"
    local qty = (r.keepQty > 0 and r.sellQty > 0)
        and ("keep " .. r.keepQty .. ", " .. (r.action == "review" and "review " or "sell ") .. r.sellQty)
        or tostring(r.qty)
    local worth = r.total > 0 and (" for ~" .. money(r.total)) or ""
    return string.format("|c%s%s|r %s x%s%s - %s%s", c, LABEL[r.action] or r.action, r.name, qty, worth,
        A.REASONS[r.reason] or r.reason, r.confidence == "low" and " (low confidence)" or "")
end

-- Saves a compact copy of the advice so the web viewer can compare it with its own result.
local function save(list, summary)
    local out = { time = date("%Y-%m-%d %H:%M:%S"), priceTime = summary.priceTime, items = {} }
    for _, r in ipairs(list) do
        out.items[r.id] = { a = r.action, k = r.keepQty, s = r.sellQty, u = r.unit, r = r.reason, c = r.confidence, b = r.bound and 1 or 0 }
    end
    LorestarDB.advice = out
end

function A.report(over)
    local say = ns.actions and ns.actions.say or print
    local list, summary = A.run(over)
    if not summary.haveRecipes then
        say("Advisor: no recipe data saved yet. Open each profession and use Dump recipes first, or reagents will not be protected.")
    end
    if not LorestarDB.prices then
        say("Advisor: no Auction House scan saved. Open the Auction House and use Scan AH prices for better advice.")
    elseif summary.priceTs and (time() - summary.priceTs) > 24 * 3600 then
        say("Advisor: the last Auction House scan is more than a day old (" .. tostring(summary.priceTime) .. ").")
    end
    if summary.pending > 0 then
        say("Advisor: " .. summary.pending .. " item(s) are not cached yet; run it again in a few seconds.")
    end
    local shown = 0
    for _, action in ipairs(ORDER) do
        for _, r in ipairs(list) do
            if r.action == action and (action ~= "keep") then
                say(A.line(r))
                shown = shown + 1
            end
        end
    end
    say(string.format("Advisor: %d to sell on the AH (~%s), %d to vendor (~%s), %d to discard, %d to review, %d to keep. Free slots now: %s, would free about %d.",
        summary.counts.sell_ah or 0, money(summary.sellAH), summary.counts.vendor or 0, money(summary.vendor),
        summary.counts.discard or 0, summary.counts.review or 0, summary.counts.keep or 0,
        tostring(summary.freeSlots or "?"), summary.slots))
    save(list, summary)
    say("This is a recommendation only: nothing was sold or moved. /reload saves the advice for the web viewer.")
    return list, summary
end

function A.command(rest)
    if not LorestarDB then return end
    if rest == "all" then
        local say = ns.actions and ns.actions.say or print
        local list = A.run()
        for _, r in ipairs(list) do say(A.line(r)) end
    else
        A.report()
    end
end

ns.advisor = A
