-- Lorestar UI: a minimap button that opens a small panel with buttons for the
-- same actions as the slash commands. Everything here is read-only with respect
-- to the game: it only triggers Lorestar's own data collection.
-- The whole UI is built inside pcall, so a failure here never breaks the addon.

local ADDON_NAME, ns = ...

-- Portfolio palette (same tokens as the web viewer).
local C = {
    bg      = { 0.047, 0.000, 0.008 },  -- #0c0002
    surface = { 0.110, 0.078, 0.063 },  -- #1c1410
    hover   = { 0.145, 0.102, 0.078 },  -- #251a14
    border  = { 0.180, 0.122, 0.094 },  -- #2e1f18
    gold    = { 0.949, 0.663, 0.173 },  -- #f2a92c
    red     = { 0.788, 0.020, 0.067 },  -- #c90511
    text    = { 0.937, 0.882, 0.741 },  -- #efe1bd
    muted   = { 0.784, 0.694, 0.616 },  -- #c8b19d
}

local PANEL_W, PAD, BTN_H, GAP = 292, 12, 24, 6
local panel, minimapButton

---------------------------------------------------------------------------
-- Small drawing helpers (plain textures: no dependency on Backdrop templates)
---------------------------------------------------------------------------

local function solid(frame, layer, c, a)
    local t = frame:CreateTexture(nil, layer)
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

local function addBorder(frame, c)
    local lines = {}
    local function line(a1, a2, w, h)
        local t = solid(frame, "BORDER", c)
        t:SetPoint(a1)
        t:SetPoint(a2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        lines[#lines + 1] = t
    end
    line("TOPLEFT", "TOPRIGHT", nil, 1)
    line("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    line("TOPLEFT", "BOTTOMLEFT", 1, nil)
    line("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    frame.borderLines = lines
end

local function setBorder(frame, c)
    for _, t in ipairs(frame.borderLines or {}) do t:SetColorTexture(c[1], c[2], c[3], 1) end
end

local function newText(parent, size, c)
    local fs
    local ok = pcall(function() fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") end)
    if not ok or not fs then
        fs = parent:CreateFontString(nil, "OVERLAY")
        fs:SetFont("Fonts\\FRIZQT__.TTF", size or 11, "")
    end
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

local function showTip(owner, text)
    if not text or not GameTooltip then return end
    pcall(function()
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
end

local function hideTip()
    if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end
end

local function makeButton(parent, label, w, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, BTN_H)
    b.bg = solid(b, "BACKGROUND", C.surface)
    b.bg:SetAllPoints()
    addBorder(b, C.border)
    b.label = newText(b, 11, C.text)
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 1)
        setBorder(self, C.gold)
        showTip(self, self.tip)
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(C.surface[1], C.surface[2], C.surface[3], 1)
        setBorder(self, self.active and C.gold or C.border)
        hideTip()
    end)
    b:SetScript("OnClick", function(self)
        local ok, err = pcall(onClick, self)
        if not ok then ns.actions.say("UI error: " .. tostring(err)) end
        if panel then
            if not self.noMark then panel.touched = true end
            if panel.refresh then panel.refresh() end
        end
    end)
    b.tip = tip
    return b
end

-- A toggle looks "on" with a gold label and border.
local function setActive(b, on, text)
    b.active = on
    b.label:SetText(text)
    local c = on and C.gold or C.text
    b.label:SetTextColor(c[1], c[2], c[3])
    setBorder(b, on and C.gold or C.border)
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local function db() return LorestarDB or {} end

local function buildPanel()
    local a = ns.actions
    local f = CreateFrame("Frame", "LorestarPanel", UIParent)
    f:SetSize(PANEL_W, 300)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.bg = solid(f, "BACKGROUND", C.bg, 0.96)
    f.bg:SetAllPoints()
    addBorder(f, C.border)

    local title = newText(f, 13, C.gold)
    title:SetPoint("TOPLEFT", PAD, -PAD)
    title:SetText("LORESTAR  v" .. a.version)

    local close = makeButton(f, "x", 20, function() f:Hide() end, "Close")
    close.noMark = true
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -8, -8)

    local half = (PANEL_W - PAD * 2 - GAP) / 2
    local y = -42

    local function heading(text)
        local h = newText(f, 10, C.muted)
        h:SetPoint("TOPLEFT", PAD, y)
        h:SetText(string.upper(text))
        y = y - 16
    end

    local function row(left, right)
        left:SetPoint("TOPLEFT", PAD, y)
        if right then right:SetPoint("TOPLEFT", PAD + half + GAP, y) end
        y = y - BTN_H - GAP
    end

    heading("Collect")
    row(
        makeButton(f, "Dump all", half, function() a.dump("") end, "Collect every section."),
        makeButton(f, "Dump items", half, function() a.dump("items") end, "Items in your bags.")
    )
    local btnRecipes = makeButton(f, "Dump recipes", half, function() a.dump("recipes") end,
        "Recipes of the profession window you have open. Open each profession first, then click.")
    local btnNames = makeButton(f, "Dump item names", half, function() a.dump("itemnames") end,
        "Names of reagents and crafted items. Run it after dumping recipes.")
    row(btnRecipes, btnNames)

    if ns.advisor then
        heading("Advisor")
        local btnAdvise = makeButton(f, "Advise: what to do with my bags", PANEL_W - PAD * 2, function() ns.advisor.report() end,
            "Recommends keep, sell on the AH, vendor, discard or review for each item in your bags. It only recommends; it never sells or moves anything.")
        btnAdvise.noMark = false
        row(btnAdvise)
    end

    heading("Auction House")
    local btnScan = makeButton(f, "Scan AH prices", PANEL_W - PAD * 2, function() a.scan() end,
        "With the Auction House open, record prices. The game allows about one scan every 15 minutes.")
    row(btnScan)

    heading("Options")
    local btnEvents = makeButton(f, "Events: OFF", half, function() a.events(not db().eventsActive) end,
        "Count game events and sample the auction searches you do. Turns off after a reload.")
    local btnAnon = makeButton(f, "Anonymous: ON", half, function() a.setAnon(not a.isAnon()) end,
        "Hide character name, realm and gold from the data (recommended).")
    row(btnEvents, btnAnon)
    local btnLoot
    if ns.loot then
        btnLoot = makeButton(f, "Loot: OFF", half, function() ns.loot.setEnabled(not ns.loot.isEnabled()) end,
            "Record what you loot and where (aggregated; no gold, names or GUIDs). Stays on after reloads.")
        row(btnLoot)
    end

    heading("Data")
    local btnReload = makeButton(f, "Reload UI (save)", half, function()
        if not pcall(ReloadUI) then a.say("Could not reload from here, type /reload.") end
    end, "Reload the interface. This is what writes the collected data to disk.")
    btnReload.noMark = true
    local btnClear = makeButton(f, "Clear data", half, function(self)
        local now = GetTime()
        if self.confirmUntil and now < self.confirmUntil then
            self.confirmUntil = nil
            a.clear()
        else
            self.confirmUntil = now + 5
        end
    end, "Wipe the collected data (loot data is kept). Click twice within 5 seconds.")
    row(btnReload, btnClear)

    local status = newText(f, 10, C.muted)
    status:SetPoint("TOPLEFT", PAD, y - 2)
    status:SetWidth(PANEL_W - PAD * 2)
    status:SetJustifyH("LEFT")
    status:SetSpacing(2)
    f.status = status

    function f.refresh()
        local d = db()
        local lines = {}
        local snap, prices = d.snapshot, d.prices
        lines[#lines + 1] = "Last dump: " .. ((snap and snap.time) or "never")
        lines[#lines + 1] = "Last scan: " .. ((prices and prices.time) or "never")
            .. ((prices and prices.distinct) and (" (" .. prices.distinct .. " items)") or "")
        local names = snap and snap.sections and snap.sections.itemnames
        if names and names.pending and names.pending > 0 then
            lines[#lines + 1] = "Item names pending: " .. names.pending .. " (dump item names again)"
        end
        local ah = AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown()
        lines[#lines + 1] = "Auction House: " .. (ah and "open" or "closed")
        if ProfessionsFrame and ProfessionsFrame.IsShown then
            lines[#lines + 1] = "Profession window: " .. (ProfessionsFrame:IsShown() and "open" or "closed")
        end
        if ns.loot then
            local st = ns.loot.stats()
            lines[#lines + 1] = "Loot: " .. st.opens .. " windows, " .. st.items .. " items, " .. st.places .. " places"
        end
        if f.touched then lines[#lines + 1] = "Data changed: Reload UI to save it to disk." end
        status:SetText(table.concat(lines, "\n"))
        f:SetHeight(-y + 12 + status:GetStringHeight())

        setActive(btnEvents, d.eventsActive and true or false, "Events: " .. (d.eventsActive and "ON" or "OFF"))
        setActive(btnAnon, a.isAnon(), "Anonymous: " .. (a.isAnon() and "ON" or "OFF"))
        if btnLoot then
            local on = ns.loot.isEnabled()
            setActive(btnLoot, on, "Loot: " .. (on and "ON" or "OFF"))
        end
        local confirming = btnClear.confirmUntil and GetTime() < btnClear.confirmUntil
        btnClear.label:SetText(confirming and "Click again" or "Clear data")
        local cc = confirming and C.red or C.text
        btnClear.label:SetTextColor(cc[1], cc[2], cc[3])
        setBorder(btnClear, confirming and C.red or C.border)
    end

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then
            elapsed = 0
            f.refresh()
        end
    end)
    f:SetScript("OnShow", function() f.refresh() end)

    pcall(function() tinsert(UISpecialFrames, "LorestarPanel") end)
    f:Hide()
    return f
end

function ns.togglePanel()
    if not panel then
        ns.actions.say("The UI panel is not available.")
        return
    end
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

---------------------------------------------------------------------------
-- Minimap button (draggable around the minimap, position saved)
---------------------------------------------------------------------------

local function placeMinimapButton()
    local angle = (db().minimap and db().minimap.angle) or 225
    local rad = math.rad(angle)
    local radius = (Minimap:GetWidth() / 2) + 5
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

local function buildMinimapButton()
    local b = CreateFrame("Button", "LorestarMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")

    local back = b:CreateTexture(nil, "BACKGROUND")
    back:SetSize(20, 20)
    back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    back:SetPoint("TOPLEFT", 7, -5)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")
    -- A texture instead of a letter: text at a half-pixel offset looked blurry on the minimap.
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -6)

    b:SetScript("OnClick", function() ns.togglePanel() end)
    b:SetScript("OnEnter", function(self)
        showTip(self, "Lorestar\nClick: open the panel\nDrag: move this button")
    end)
    b:SetScript("OnLeave", hideTip)

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            LorestarDB.minimap = LorestarDB.minimap or {}
            LorestarDB.minimap.angle = angle
            placeMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    return b
end

function ns.setMinimapShown(shown)
    LorestarDB.minimap = LorestarDB.minimap or {}
    LorestarDB.minimap.hidden = not shown
    if minimapButton then
        if shown then minimapButton:Show() else minimapButton:Hide() end
    end
    ns.actions.say("Minimap button " .. (shown and "shown." or "hidden. Use /lorestar ui to open the panel."))
end

---------------------------------------------------------------------------
-- Init (after login, so the minimap and the saved variables exist)
---------------------------------------------------------------------------

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    local ok, err = pcall(function()
        panel = buildPanel()
        minimapButton = buildMinimapButton()
        placeMinimapButton()
        if db().minimap and db().minimap.hidden then minimapButton:Hide() end
    end)
    if not ok then
        ns.actions.say("UI failed to load (" .. tostring(err) .. "). Slash commands still work.")
    end
end)
