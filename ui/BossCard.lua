-- Boss Card -- see https://github.com/fooxytv/TankAssist/issues/38
--
-- A per-boss tanking diagram: where to stand, which way to point the boss, what
-- the frontal wants, what the buster wants. Tank information only.
--
-- It lives inside the Encounter Journal rather than in a window of its own. The
-- Journal is already where you go to read about a boss, it already knows which
-- boss you are looking at, and it already has the portrait and the dungeon --
-- so the card augments the page you are on instead of asking you to find a
-- second window and re-pick the same boss in it. Click a boss, hit Tank.
--
-- Falls back to a standalone window if the Journal cannot be reached, so the
-- diagram is always inspectable.
--
-- This is still the first pass and deliberately has no data layer: the two
-- layouts below are hardcoded, and the only real data pulled from the client is
-- the boss name, its portrait and the dungeon art. The question it exists to
-- answer is whether the diagram reads at all.
--
--   /ta bosscard         open the Journal and show the card
--   /ta bosscard debug   report which client APIs resolved here

local ADDON_NAME, TankAssist = ...

TankAssist.BossCard = {}
local bc = TankAssist.BossCard

local MEDIA = "Interface\\AddOns\\TankAssist\\media\\diagram\\"

local TEX = {
    cone60  = MEDIA .. "cone60",
    cone90  = MEDIA .. "cone90",
    cone120 = MEDIA .. "cone120",
    arrow   = MEDIA .. "arrow",
    ring    = MEDIA .. "ring",
    disc    = MEDIA .. "disc",
}

-- The whole point is that these are read, not decoded. Danger is always the
-- same red, safe is always the same blue, and nothing else uses either.
local COLOR = {
    panel   = { 0.05, 0.06, 0.08, 0.94 },
    canvas  = { 0.08, 0.09, 0.12, 1.00 },
    border  = { 0.20, 0.22, 0.28, 1.00 },
    grid    = { 1.00, 1.00, 1.00, 0.05 },
    wall    = { 0.52, 0.56, 0.64, 0.90 },

    boss    = { 0.90, 0.30, 0.30, 1.00 },
    tank    = { 0.20, 0.72, 0.95, 1.00 },
    healer  = { 0.35, 0.85, 0.45, 1.00 },
    dps     = { 0.92, 0.58, 0.25, 1.00 },

    danger  = { 0.95, 0.22, 0.22, 0.50 },  -- cone the group must not be in
    safe    = { 0.25, 0.70, 1.00, 0.42 },  -- cone the group is meant to stand in
    accent  = { 0.00, 0.75, 0.95, 1.00 },
    dim     = { 0.62, 0.62, 0.66, 1.00 },
    text    = { 0.92, 0.92, 0.94, 1.00 },
}

local ROLE_COLOR = { TANK = COLOR.tank, HEALER = COLOR.healer, DAMAGER = COLOR.dps }

-- Buster tiers. A glyph, not a sentence: size and colour carry the meaning.
local BUSTER = {
    MAJOR    = { size = 30, color = { 0.95, 0.30, 0.30 } },
    PERSONAL = { size = 22, color = { 0.95, 0.78, 0.25 } },
    NONE     = { size = 18, color = { 0.45, 0.45, 0.48 } },
}
local BUSTER_ICON = "Interface\\Icons\\Spell_Holy_DefensiveStance"
local FALLBACK_PORTRAIT = "Interface\\Icons\\Ability_Creature_Cursed_02"

local CYCLE = 6.0            -- seconds per animation loop
local DEFAULT_CANVAS = 340
local MIN_CANVAS = 220
local CHROME_HEIGHT = 128    -- header plus footer, around the canvas

local JOURNAL_ADDON = "Blizzard_EncounterJournal"

----------------------------------------------------------------------------
-- Layouts
--
-- Coordinates are 0..1 across the canvas, so a layout is resolution
-- independent and the same archetype can be reused at any panel size -- which
-- matters now that the card sizes itself to whatever room the Journal has.
-- Facing is degrees clockwise from "up".
----------------------------------------------------------------------------

local LAYOUTS = {
    {
        key      = "away",
        title    = "Turn it away",
        subtitle = "Frontal the group must not be in",
        buster   = "MAJOR",
        cone     = { texture = TEX.cone90, reach = 0.44 },
        walls    = { { 0.06, 0.10, 0.94, 0.10 } },
        boss     = { x = 0.50, y = 0.42 },
        -- The tank stands between the boss and the wall, so the boss's face --
        -- and the cone with it -- is pulled off the group entirely.
        tank     = { from = { x = 0.50, y = 0.62 }, to = { x = 0.50, y = 0.24 } },
        group    = {
            { role = "HEALER",  x = 0.34, y = 0.80 },
            { role = "DAMAGER", x = 0.46, y = 0.84 },
            { role = "DAMAGER", x = 0.58, y = 0.80 },
            { role = "DAMAGER", x = 0.50, y = 0.72 },
        },
        facingFrom = 180,
        facingTo   = 0,
        flashGroupAtStart = true,
    },
    {
        key      = "soak",
        title    = "Soak it together",
        subtitle = "Frontal that splits -- everyone stands in it",
        buster   = "PERSONAL",
        cone     = { texture = TEX.cone90, reach = 0.44 },
        walls    = {},
        boss     = { x = 0.50, y = 0.34 },
        tank     = { from = { x = 0.50, y = 0.58 }, to = { x = 0.50, y = 0.58 } },
        group    = {
            -- Start scattered, then collapse into the cone with the tank.
            { role = "HEALER",  x = 0.20, y = 0.86, toX = 0.40, toY = 0.66 },
            { role = "DAMAGER", x = 0.44, y = 0.92, toX = 0.50, toY = 0.70 },
            { role = "DAMAGER", x = 0.78, y = 0.86, toX = 0.60, toY = 0.66 },
            { role = "DAMAGER", x = 0.84, y = 0.62, toX = 0.55, toY = 0.62 },
        },
        facingFrom = 180,
        facingTo   = 180,
        coneSafeAlways = true,
    },
}

----------------------------------------------------------------------------
-- Client data
--
-- Every lookup is optional. This runs on whatever build the player has, and a
-- missing API should cost us a portrait, not the whole panel -- so each probe
-- records what it found and `/ta bosscard debug` prints the lot. That report is
-- what decides whether the Journal can auto-build the boss skeleton later.
----------------------------------------------------------------------------

local probe = {}

local function try(name, fn)
    local ok, a, b, c, d, e = pcall(fn)
    if not ok then
        probe[name] = "error: " .. tostring(a)
        return nil
    end
    probe[name] = (a ~= nil) and "ok" or "nil"
    return a, b, c, d, e
end

-- Current season's Mythic+ dungeon list, straight from the client. Nothing
-- about the season is hardcoded anywhere, which is the whole reason to use it.
function bc:GetSeasonMaps()
    local maps = try("C_ChallengeMode.GetMapTable", function()
        return C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable()
    end)
    if type(maps) == "table" and #maps > 0 then
        probe["C_ChallengeMode.GetMapTable"] = ("ok (%d dungeons)"):format(#maps)
        return maps
    end
    return nil
end

-- Best-effort: find the Journal instance matching a season dungeon, so the
-- fallback demo shows a boss the player will actually meet. Only used when the
-- Journal has not told us what is selected.
local function findJournalDungeon(wantedName)
    if not EJ_GetNumTiers or not EJ_SelectTier or not EJ_GetInstanceByIndex then
        return nil
    end

    if EJ_GetCurrentTier then
        EJ_SelectTier(EJ_GetCurrentTier())
    end

    local first
    for index = 1, 60 do
        local instanceID, name = EJ_GetInstanceByIndex(index, false)
        if not instanceID then break end
        first = first or { id = instanceID, name = name }
        if wantedName and name == wantedName then
            return { id = instanceID, name = name }
        end
    end
    return first
end

-- Dungeon art for the diagram backdrop. Two sources, because neither is
-- reliably present: the Mythic+ map info carries a background for season
-- dungeons, and the Journal carries one for everything it knows about.
local function resolveBackground(instanceID, dungeonName)
    local maps = bc:GetSeasonMaps()
    if maps and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        for _, mapID in ipairs(maps) do
            local name, _, _, texture, background = try("C_ChallengeMode.GetMapUIInfo", function()
                return C_ChallengeMode.GetMapUIInfo(mapID)
            end)
            if name and (not dungeonName or name == dungeonName) then
                if background or texture then
                    probe["background source"] = "C_ChallengeMode.GetMapUIInfo"
                    return background or texture
                end
            end
        end
    end

    if instanceID and EJ_GetInstanceInfo then
        -- name, description, bgImage, buttonImage, loreImage, ...
        local _, _, bgImage, _, loreImage = try("EJ_GetInstanceInfo", function()
            return EJ_GetInstanceInfo(instanceID)
        end)
        if bgImage or loreImage then
            probe["background source"] = "EJ_GetInstanceInfo"
            return bgImage or loreImage
        end
    end

    probe["background source"] = "none found"
    return nil
end

-- What the Journal currently has selected. This is the normal path once the
-- card is attached: the player clicks a boss, we follow.
function bc:ReadJournalSelection()
    local ej = _G.EncounterJournal
    local encounterID = ej and ej.encounterID
    if not encounterID or not EJ_GetEncounterInfo then return nil end

    local name, _, _, _, _, journalInstanceID = try("EJ_GetEncounterInfo", function()
        return EJ_GetEncounterInfo(encounterID)
    end)
    if not name then return nil end

    local selection = { bossName = name, encounterID = encounterID }

    if EJ_GetCreatureInfo then
        local _, _, _, _, icon = try("EJ_GetCreatureInfo", function()
            return EJ_GetCreatureInfo(1, encounterID)
        end)
        selection.portrait = icon
    end

    local instanceID = journalInstanceID or (EJ_GetCurrentInstance and EJ_GetCurrentInstance())
    if instanceID and EJ_GetInstanceInfo then
        local instanceName = try("EJ_GetInstanceInfo", function()
            return EJ_GetInstanceInfo(instanceID)
        end)
        selection.dungeonName = instanceName
    end
    selection.background = resolveBackground(instanceID, selection.dungeonName)

    return selection
end

-- Used only when nothing is selected -- opening the card cold, or the fallback
-- window. Picks the first boss of the first season dungeon.
function bc:ResolveDemoBoss()
    if self.demo then return self.demo end

    local demo = { bossName = "Select a boss", dungeonName = nil }

    local wantedName
    local maps = self:GetSeasonMaps()
    if maps and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        wantedName = try("C_ChallengeMode.GetMapUIInfo", function()
            return C_ChallengeMode.GetMapUIInfo(maps[1])
        end)
    end

    local dungeon = try("findJournalDungeon", function() return findJournalDungeon(wantedName) end)
    if dungeon then
        demo.dungeonName = dungeon.name
        if EJ_SelectInstance then pcall(EJ_SelectInstance, dungeon.id) end

        local encName, _, encounterID = try("EJ_GetEncounterInfoByIndex", function()
            return EJ_GetEncounterInfoByIndex(1, dungeon.id)
        end)
        if encName then
            demo.bossName = encName
            demo.encounterID = encounterID
        end

        if encounterID and EJ_GetCreatureInfo then
            local _, _, _, _, icon = try("EJ_GetCreatureInfo", function()
                return EJ_GetCreatureInfo(1, encounterID)
            end)
            demo.portrait = icon
        end

        demo.background = resolveBackground(dungeon.id, dungeon.name)
    end

    -- Not used yet, but this is the call that would place bosses on a real
    -- dungeon map instead of hand-placed coordinates, so probe it now.
    try("C_EncounterJournal.GetEncountersOnMap", function()
        local uiMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if not uiMapID or not C_EncounterJournal or not C_EncounterJournal.GetEncountersOnMap then
            return nil
        end
        local list = C_EncounterJournal.GetEncountersOnMap(uiMapID)
        if type(list) == "table" and #list > 0 then
            probe["C_EncounterJournal.GetEncountersOnMap"] = ("ok (%d here)"):format(#list)
            return list
        end
        return nil
    end)

    self.demo = demo
    return demo
end

local function roleTexCoords(role)
    if GetTexCoordsForRoleSmallCircle then
        local ok, l, r, t, b = pcall(GetTexCoordsForRoleSmallCircle, role)
        if ok and l then return l, r, t, b end
    end
    return nil
end

----------------------------------------------------------------------------
-- Primitives
----------------------------------------------------------------------------

local function setColor(texture, color, alphaOverride)
    texture:SetVertexColor(color[1], color[2], color[3], alphaOverride or color[4] or 1)
end

local function canvasSize()
    return bc.canvasSize or DEFAULT_CANVAS
end

-- Layouts speak 0..1; frames speak pixels from the canvas TOPLEFT.
local function place(canvas, region, x, y, w, h)
    local size = canvasSize()
    region:ClearAllPoints()
    region:SetSize(w, h)
    region:SetPoint("CENTER", canvas, "TOPLEFT", x * size, -y * size)
end

local function newToken(canvas, size)
    local token = CreateFrame("Frame", nil, canvas)
    token:SetSize(size, size)

    token.halo = token:CreateTexture(nil, "ARTWORK", nil, 1)
    token.halo:SetTexture(TEX.disc)
    token.halo:SetAllPoints(token)

    token.icon = token:CreateTexture(nil, "ARTWORK", nil, 2)
    token.icon:SetPoint("CENTER")
    token.icon:SetSize(size * 0.74, size * 0.74)

    token.ring = token:CreateTexture(nil, "OVERLAY")
    token.ring:SetTexture(TEX.ring)
    token.ring:SetAllPoints(token)

    return token
end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------

function bc:BuildFrame()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "TankAssistBossCard", UIParent, "BackdropTemplate")
    f:SetSize(DEFAULT_CANVAS + 32, DEFAULT_CANVAS + CHROME_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropColor(unpack(COLOR.panel))
    f:SetBackdropBorderColor(unpack(COLOR.border))

    ------------------------------------------------------------------
    -- Header
    ------------------------------------------------------------------
    local portrait = CreateFrame("Frame", nil, f)
    portrait:SetSize(40, 40)
    portrait:SetPoint("TOPLEFT", 12, -10)

    portrait.icon = portrait:CreateTexture(nil, "ARTWORK")
    portrait.icon:SetAllPoints(portrait)
    portrait.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    portrait.ring = portrait:CreateTexture(nil, "OVERLAY")
    portrait.ring:SetTexture(TEX.ring)
    portrait.ring:SetPoint("CENTER")
    portrait.ring:SetSize(47, 47)
    setColor(portrait.ring, COLOR.boss)
    f.portrait = portrait

    f.bossName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.bossName:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 10, -1)
    f.bossName:SetTextColor(unpack(COLOR.text))

    f.dungeonName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.dungeonName:SetPoint("TOPLEFT", f.bossName, "BOTTOMLEFT", 0, -2)
    f.dungeonName:SetTextColor(unpack(COLOR.dim))

    f.verdictText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.verdictText:SetPoint("TOPLEFT", f.dungeonName, "BOTTOMLEFT", 0, -3)
    f.verdictText:SetTextColor(unpack(COLOR.accent))

    -- Standalone-only chrome. Hidden and disabled once the card is living
    -- inside the Journal, which brings its own frame and close button.
    f.closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.closeButton:SetPoint("TOPRIGHT", 2, 2)
    f.closeButton:SetScript("OnClick", function() bc:Hide() end)

    ------------------------------------------------------------------
    -- Canvas
    ------------------------------------------------------------------
    local canvas = CreateFrame("Frame", nil, f, "BackdropTemplate")
    canvas:SetSize(DEFAULT_CANVAS, DEFAULT_CANVAS)
    canvas:SetPoint("TOP", f, "TOP", 0, -62)
    canvas:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    canvas:SetBackdropColor(unpack(COLOR.canvas))
    canvas:SetBackdropBorderColor(unpack(COLOR.border))
    canvas:SetClipsChildren(true)
    f.canvas = canvas

    -- Dungeon art. This sublevel matters: the backdrop's fill is an opaque
    -- texture in the BACKGROUND layer, so anything below it is painted over
    -- and never seen. Sitting above the fill and below the grid is the only
    -- place this shows up at all.
    canvas.background = canvas:CreateTexture(nil, "BACKGROUND", nil, 2)
    canvas.background:SetAllPoints(canvas)
    canvas.background:SetAlpha(0.30)
    canvas.background:Hide()

    canvas.grid = {}
    for i = 1, 7 do
        for _, orient in ipairs({ "H", "V" }) do
            local line = canvas:CreateLine(nil, "BACKGROUND", nil, 5)
            line:SetThickness(1)
            line:SetColorTexture(unpack(COLOR.grid))
            line.gridFraction = i / 8
            line.gridOrient = orient
            tinsert(canvas.grid, line)
        end
    end

    canvas.walls = {}
    canvas.cone = canvas:CreateTexture(nil, "ARTWORK", nil, -2)

    canvas.boss = newToken(canvas, 44)
    setColor(canvas.boss.halo, COLOR.boss, 0.30)
    setColor(canvas.boss.ring, COLOR.boss)

    -- Which way the boss is looking, so the cone is never the only cue.
    canvas.bossArrow = canvas:CreateTexture(nil, "OVERLAY")
    canvas.bossArrow:SetTexture(TEX.arrow)
    setColor(canvas.bossArrow, COLOR.boss)

    canvas.tank = newToken(canvas, 32)
    setColor(canvas.tank.halo, COLOR.tank, 0.30)
    setColor(canvas.tank.ring, COLOR.tank)

    canvas.busterGlyph = canvas:CreateTexture(nil, "OVERLAY", nil, 2)
    canvas.busterGlyph:SetTexture(BUSTER_ICON)

    canvas.group = {}
    for i = 1, 4 do
        canvas.group[i] = newToken(canvas, 25)
    end

    ------------------------------------------------------------------
    -- Footer
    ------------------------------------------------------------------
    local function makeButton(label, width, onClick)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end

    f.btnAway = makeButton("Turn it away", 100, function() bc:SetLayout("away") end)
    f.btnAway:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 0, -8)

    f.btnSoak = makeButton("Soak together", 104, function() bc:SetLayout("soak") end)
    f.btnSoak:SetPoint("LEFT", f.btnAway, "RIGHT", 4, 0)

    f.btnMap = makeButton("Art", 50, function() bc:ToggleBackground() end)
    f.btnMap:SetPoint("LEFT", f.btnSoak, "RIGHT", 4, 0)

    f.btnDebug = makeButton("Debug", 56, function() bc:Debug() end)
    f.btnDebug:SetPoint("LEFT", f.btnMap, "RIGHT", 4, 0)

    -- The one place words are allowed: the visual language has to be learnable
    -- once before it can be read everywhere.
    f.legend = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.legend:SetPoint("TOPLEFT", f.btnAway, "BOTTOMLEFT", 1, -6)
    f.legend:SetPoint("TOPRIGHT", f.btnDebug, "BOTTOMRIGHT", -1, -6)
    f.legend:SetJustifyH("LEFT")
    f.legend:SetTextColor(unpack(COLOR.dim))
    f.legend:SetText("|cff33b8f0Tank|r  |cff59d973Healer|r  |cffeb9440DPS|r"
        .. "        |cffe63838Red cone|r = stay out"
        .. "        |cff40b3ffBlue cone|r = stand in")

    f:SetScript("OnUpdate", function(_, elapsed) bc:OnUpdate(elapsed) end)
    f:Hide()

    self.frame = f
    self:SetMode("window")
    return f
end

----------------------------------------------------------------------------
-- Placement: inside the Journal, or a window of its own
----------------------------------------------------------------------------

-- The Journal's right-hand info panel is where boss detail already lives, so
-- that is where the card goes. Falls back through progressively less specific
-- frames rather than assuming one layout survives every patch.
local function journalAnchor()
    local ej = _G.EncounterJournal
    if not ej then return nil end
    local encounter = ej.encounter
    if encounter and encounter.info then return encounter.info end
    if encounter then return encounter end
    return ej
end

function bc:SetMode(mode, anchor)
    local f = self.frame
    if not f then return end

    self.mode = mode

    if mode == "journal" and anchor then
        f:SetParent(anchor)
        f:SetFrameStrata(anchor:GetFrameStrata())
        f:SetFrameLevel((anchor:GetFrameLevel() or 1) + 10)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", anchor, "TOPLEFT", 2, -2)
        f:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -2, 2)
        f:SetMovable(false)
        f:EnableMouse(true)
        f:RegisterForDrag()
        f:SetScript("OnDragStart", nil)
        f:SetScript("OnDragStop", nil)
        f.closeButton:Hide()
    else
        f:SetParent(UIParent)
        f:SetFrameStrata("DIALOG")
        f:ClearAllPoints()
        f:SetPoint("CENTER")
        f:SetSize(DEFAULT_CANVAS + 32, DEFAULT_CANVAS + CHROME_HEIGHT)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f.closeButton:Show()
    end

    self:Relayout()
end

-- The canvas is square and takes whatever room is left after the chrome, so
-- the card fits the Journal's panel instead of assuming a fixed size.
function bc:Relayout()
    local f = self.frame
    if not f then return end

    local width = f:GetWidth() or 0
    local height = f:GetHeight() or 0
    if width <= 1 or height <= 1 then
        width, height = DEFAULT_CANVAS + 32, DEFAULT_CANVAS + CHROME_HEIGHT
    end

    local size = math.floor(math.min(width - 24, height - CHROME_HEIGHT))
    if size < MIN_CANVAS then size = MIN_CANVAS end

    self.canvasSize = size
    f.canvas:SetSize(size, size)

    for _, line in ipairs(f.canvas.grid) do
        local t = line.gridFraction
        if line.gridOrient == "H" then
            line:SetStartPoint("TOPLEFT", f.canvas, 0, -t * size)
            line:SetEndPoint("TOPLEFT", f.canvas, size, -t * size)
        else
            line:SetStartPoint("TOPLEFT", f.canvas, t * size, 0)
            line:SetEndPoint("TOPLEFT", f.canvas, t * size, -size)
        end
    end

    if self.layout then
        self:SetLayout(self.layout.key)
    end
end

----------------------------------------------------------------------------
-- Encounter Journal integration
----------------------------------------------------------------------------

function bc:AttachToJournal()
    if self.attached then return true end

    local anchor = journalAnchor()
    if not anchor then
        probe["journal anchor"] = "not found"
        return false
    end
    probe["journal anchor"] = anchor:GetName() or "unnamed frame"

    self:BuildFrame()

    -- Toggle sits on the Journal itself so it is reachable whichever tab is up.
    local button = CreateFrame("Button", "TankAssistBossCardToggle", _G.EncounterJournal,
        "UIPanelButtonTemplate")
    button:SetSize(76, 22)
    button:SetText("Tank")
    button:SetPoint("TOPRIGHT", _G.EncounterJournal, "TOPRIGHT", -60, -28)
    button:SetScript("OnClick", function() bc:Toggle() end)
    button:SetScript("OnEnter", function(self_)
        GameTooltip:SetOwner(self_, "ANCHOR_LEFT")
        GameTooltip:SetText("Tank card")
        GameTooltip:AddLine("Tanking diagram for the selected boss.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.toggleButton = button

    self:SetMode("journal", anchor)

    -- Follow whatever boss the player clicks.
    if EJ_SelectEncounter then
        hooksecurefunc("EJ_SelectEncounter", function()
            if bc.frame and bc.frame:IsShown() then
                bc:SyncToJournal()
            end
        end)
    end

    -- The Journal closing should take the card with it.
    _G.EncounterJournal:HookScript("OnHide", function()
        if bc.frame then bc.frame:Hide() end
    end)

    self.attached = true
    return true
end

function bc:SyncToJournal()
    local selection = self:ReadJournalSelection()
    if selection then
        self.current = selection
    end
    if self.layout then
        self:SetLayout(self.layout.key)
    end
end

-- The Journal is load-on-demand, so attach when it arrives rather than at login.
function bc:EnsureJournalLoaded()
    if _G.EncounterJournal then return true end
    if C_AddOns and C_AddOns.LoadAddOn then
        local ok = pcall(C_AddOns.LoadAddOn, JOURNAL_ADDON)
        if ok and _G.EncounterJournal then return true end
    end
    return _G.EncounterJournal ~= nil
end

----------------------------------------------------------------------------
-- Layout application
----------------------------------------------------------------------------

function bc:CurrentBoss()
    return self.current or self:ResolveDemoBoss()
end

function bc:SetLayout(key)
    local f = self:BuildFrame()
    local layout
    for _, candidate in ipairs(LAYOUTS) do
        if candidate.key == key then layout = candidate break end
    end
    if not layout then return end

    self.layout = layout
    self.elapsed = self.elapsed or 0

    local canvas = f.canvas
    local size = canvasSize()
    local boss = self:CurrentBoss()

    ------------------------------------------------------------------
    -- Header
    ------------------------------------------------------------------
    f.portrait.icon:SetTexture(boss.portrait or FALLBACK_PORTRAIT)
    f.bossName:SetText(boss.bossName or "Boss")
    f.dungeonName:SetText(boss.dungeonName or "")
    f.verdictText:SetText(layout.title .. "  |cff808080" .. layout.subtitle .. "|r")

    if boss.background then
        canvas.background:SetTexture(boss.background)
        if self.backgroundWanted ~= false then
            canvas.background:Show()
        end
    else
        canvas.background:Hide()
    end

    ------------------------------------------------------------------
    -- Walls
    ------------------------------------------------------------------
    for _, line in ipairs(canvas.walls) do line:Hide() end
    for index, wall in ipairs(layout.walls) do
        local line = canvas.walls[index]
        if not line then
            line = canvas:CreateLine(nil, "ARTWORK", nil, -4)
            line:SetThickness(5)
            canvas.walls[index] = line
        end
        line:SetColorTexture(unpack(COLOR.wall))
        line:SetStartPoint("TOPLEFT", canvas, wall[1] * size, -wall[2] * size)
        line:SetEndPoint("TOPLEFT", canvas, wall[3] * size, -wall[4] * size)
        line:Show()
    end

    ------------------------------------------------------------------
    -- Cone. The texture's apex sits at its own centre, so centring it on the
    -- boss and rotating about the middle pivots the cone around the boss.
    ------------------------------------------------------------------
    local reach = layout.cone.reach * size * 2
    canvas.cone:SetTexture(layout.cone.texture)
    canvas.cone:ClearAllPoints()
    canvas.cone:SetSize(reach, reach)
    canvas.cone:SetPoint("CENTER", canvas, "TOPLEFT", layout.boss.x * size, -layout.boss.y * size)

    ------------------------------------------------------------------
    -- Tokens
    ------------------------------------------------------------------
    local tokenScale = size / DEFAULT_CANVAS
    self.tokenScale = tokenScale

    place(canvas, canvas.boss, layout.boss.x, layout.boss.y, 44 * tokenScale, 44 * tokenScale)
    canvas.boss.icon:SetTexture(boss.portrait or FALLBACK_PORTRAIT)
    canvas.boss.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    local l, r, t, b = roleTexCoords("TANK")
    if l then
        canvas.tank.icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
        canvas.tank.icon:SetTexCoord(l, r, t, b)
        canvas.tank.icon:SetVertexColor(1, 1, 1, 1)
    else
        canvas.tank.icon:SetTexture(TEX.disc)
        canvas.tank.icon:SetTexCoord(0, 1, 0, 1)
        setColor(canvas.tank.icon, COLOR.tank)
    end

    for index, member in ipairs(layout.group) do
        local token = canvas.group[index]
        local color = ROLE_COLOR[member.role] or COLOR.dps
        setColor(token.halo, color, 0.30)
        setColor(token.ring, color)

        local ml, mr, mt, mb = roleTexCoords(member.role)
        if ml then
            token.icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
            token.icon:SetTexCoord(ml, mr, mt, mb)
            token.icon:SetVertexColor(1, 1, 1, 1)
        else
            token.icon:SetTexture(TEX.disc)
            token.icon:SetTexCoord(0, 1, 0, 1)
            setColor(token.icon, color)
        end
        token:Show()
    end
    for index = #layout.group + 1, #canvas.group do
        canvas.group[index]:Hide()
    end

    local buster = BUSTER[layout.buster] or BUSTER.NONE
    canvas.busterGlyph:SetSize(buster.size * tokenScale, buster.size * tokenScale)
    canvas.busterGlyph:SetVertexColor(buster.color[1], buster.color[2], buster.color[3], 1)

    f.btnAway:SetEnabled(key ~= "away")
    f.btnSoak:SetEnabled(key ~= "soak")
end

function bc:ToggleBackground()
    local f = self:BuildFrame()
    local bg = f.canvas.background

    if bg:IsShown() then
        self.backgroundWanted = false
        bg:Hide()
        return
    end

    self.backgroundWanted = true
    if bg:GetTexture() then
        bg:Show()
    else
        local addon = TankAssist.Addon
        local message = "No dungeon art resolved for this boss ("
            .. tostring(probe["background source"] or "not probed") .. ")."
        if addon then addon:Print(message) else print(message) end
    end
end

----------------------------------------------------------------------------
-- Animation
--
-- One loop shows the tank doing the thing, which is the part a list of words
-- cannot carry. Nothing here is per-boss: it is driven entirely by the layout's
-- facing and token start/end positions.
----------------------------------------------------------------------------

local function lerp(a, b, t) return a + (b - a) * t end

local function easeInOut(t)
    if t < 0.5 then return 2 * t * t end
    return -1 + (4 - 2 * t) * t
end

function bc:OnUpdate(elapsed)
    local layout = self.layout
    if not layout then return end

    self.elapsed = ((self.elapsed or 0) + elapsed) % CYCLE
    local t = self.elapsed
    local size = canvasSize()
    local scale = self.tokenScale or 1

    -- Beat one holds the mistake, beat two is the tank acting, beat three holds
    -- the result.
    local moveStart, moveEnd = 1.4, 3.4
    local progress = 0
    if t > moveEnd then
        progress = 1
    elseif t > moveStart then
        progress = easeInOut((t - moveStart) / (moveEnd - moveStart))
    end

    local canvas = self.frame.canvas

    -- Facing is degrees clockwise from up; WoW rotates counter-clockwise.
    local facing = lerp(layout.facingFrom, layout.facingTo, progress)
    canvas.cone:SetRotation(-math.rad(facing))

    local coneColor
    if layout.coneSafeAlways then
        coneColor = COLOR.safe
    else
        -- Cross-fade danger to safe as the boss comes around, so the colour
        -- change and the movement read as one event.
        coneColor = {
            lerp(COLOR.danger[1], COLOR.safe[1], progress),
            lerp(COLOR.danger[2], COLOR.safe[2], progress),
            lerp(COLOR.danger[3], COLOR.safe[3], progress),
            lerp(COLOR.danger[4], COLOR.safe[4], progress),
        }
    end
    setColor(canvas.cone, coneColor)

    local radians = math.rad(facing)
    local offset = 32 * scale
    canvas.bossArrow:ClearAllPoints()
    canvas.bossArrow:SetSize(15 * scale, 15 * scale)
    canvas.bossArrow:SetPoint("CENTER", canvas, "TOPLEFT",
        layout.boss.x * size + math.sin(radians) * offset,
        -(layout.boss.y * size) + math.cos(radians) * offset)
    canvas.bossArrow:SetRotation(-radians)

    local tx = lerp(layout.tank.from.x, layout.tank.to.x, progress)
    local ty = lerp(layout.tank.from.y, layout.tank.to.y, progress)
    place(canvas, canvas.tank, tx, ty, 32 * scale, 32 * scale)

    canvas.busterGlyph:ClearAllPoints()
    canvas.busterGlyph:SetPoint("CENTER", canvas.tank, "CENTER", 20 * scale, 15 * scale)
    -- Pulse once the tank is in position, so the eye lands on it last.
    local pulse = 0.55 + 0.45 * math.abs(math.sin(t * 2.2))
    canvas.busterGlyph:SetAlpha(progress >= 1 and pulse or 0.25)

    for index, member in ipairs(layout.group) do
        local token = canvas.group[index]
        local gx = member.toX and lerp(member.x, member.toX, progress) or member.x
        local gy = member.toY and lerp(member.y, member.toY, progress) or member.y
        place(canvas, token, gx, gy, 25 * scale, 25 * scale)

        -- In the "turn it away" loop the group starts standing in the frontal;
        -- flashing them makes the mistake obvious before the fix.
        if layout.flashGroupAtStart then
            token.halo:SetAlpha(lerp(0.25 + 0.55 * math.abs(math.sin(t * 5)), 0.30, progress))
        else
            token.halo:SetAlpha(0.30)
        end
    end
end

----------------------------------------------------------------------------
-- Public
----------------------------------------------------------------------------

function bc:Show()
    self:BuildFrame()

    if self:EnsureJournalLoaded() then
        self:AttachToJournal()
        if _G.EncounterJournal and not _G.EncounterJournal:IsShown() then
            if ToggleEncounterJournal then
                pcall(ToggleEncounterJournal)
            elseif ShowUIPanel then
                pcall(ShowUIPanel, _G.EncounterJournal)
            end
        end
        self:SyncToJournal()
    end

    if not self.layout then self:SetLayout("away") end
    self.frame:Show()
    self:Relayout()
end

function bc:Hide()
    if self.frame then self.frame:Hide() end
end

function bc:Toggle()
    self:BuildFrame()
    if self.frame:IsShown() then self:Hide() else self:Show() end
end

-- Which client APIs actually answered. This is the real output of the first
-- pass: it decides whether the boss skeleton can be built from the Journal or
-- whether every boss has to be entered by hand.
function bc:Debug()
    self.demo = nil
    probe = {}

    self:EnsureJournalLoaded()
    local selection = self:ReadJournalSelection()
    local boss = selection or self:ResolveDemoBoss()
    probe["journal selection"] = selection and "ok" or "nothing selected"

    local addon = TankAssist.Addon
    local function say(line) if addon then addon:Print(line) else print(line) end end

    say("Boss card API probe:")
    local names = {}
    for name in pairs(probe) do tinsert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        local value = tostring(probe[name])
        local color = value:match("^ok") and "|cff40d040" or "|cffe85050"
        print(("  %-42s %s%s|r"):format(name, color, value))
    end
    print(("  %-42s %s"):format("resolved boss", tostring(boss.bossName)))
    print(("  %-42s %s"):format("resolved dungeon", tostring(boss.dungeonName)))
    print(("  %-42s %s"):format("portrait texture", tostring(boss.portrait)))
    print(("  %-42s %s"):format("background texture", tostring(boss.background)))
    print(("  %-42s %s"):format("mode", tostring(self.mode)))
end

----------------------------------------------------------------------------
-- Init
----------------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(_, event, addOnName)
    if event == "ADDON_LOADED" and addOnName == JOURNAL_ADDON then
        -- The Journal builds its frames as it loads, so give it a tick before
        -- reaching into them.
        C_Timer.After(0, function() bc:AttachToJournal() end)
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(0.8, function()
            if TankAssist.Addon then
                TankAssist.Addon.bossCard = bc
            end
        end)
    end
end)
