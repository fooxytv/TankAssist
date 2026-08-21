-- Boss Card -- see https://github.com/fooxytv/TankAssist/issues/38
--
-- A per-boss tanking diagram: where to stand, which way to point the boss, what
-- the frontal wants, what the buster wants. Tank information only.
--
-- This file is the first pass and deliberately has no data layer. It exists to
-- answer one question: does a top-down diagram drawn from primitives actually
-- read clearly at panel size? Everything downstream -- the archetype library,
-- the verdict schema, the Encounter Journal import -- is wasted effort if the
-- answer is no, so the two demo layouts below are hardcoded and the only real
-- data pulled from the client is a boss portrait and a dungeon backdrop.
--
--   /ta bosscard         toggle the card
--   /ta bosscard debug   report which client APIs resolved here
--
-- The visual language is the actual product, so it is defined once at the top
-- and nothing below is allowed to invent a colour.

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
    panel      = { 0.05, 0.06, 0.08, 0.94 },
    canvas     = { 0.08, 0.09, 0.12, 1.00 },
    border     = { 0.20, 0.22, 0.28, 1.00 },
    grid       = { 1.00, 1.00, 1.00, 0.04 },
    wall       = { 0.52, 0.56, 0.64, 0.90 },

    boss       = { 0.90, 0.30, 0.30, 1.00 },
    tank       = { 0.20, 0.72, 0.95, 1.00 },
    healer     = { 0.35, 0.85, 0.45, 1.00 },
    dps        = { 0.92, 0.58, 0.25, 1.00 },

    danger     = { 0.95, 0.22, 0.22, 0.50 },  -- cone that must not touch the group
    safe       = { 0.25, 0.70, 1.00, 0.42 },  -- cone the group is meant to stand in
    accent     = { 0.00, 0.75, 0.95, 1.00 },
    dim        = { 0.62, 0.62, 0.66, 1.00 },
    text       = { 0.92, 0.92, 0.94, 1.00 },
}

local ROLE_COLOR = { TANK = COLOR.tank, HEALER = COLOR.healer, DAMAGER = COLOR.dps }

-- Buster tiers. A glyph, not a sentence: size and colour carry the meaning.
local BUSTER = {
    MAJOR    = { size = 30, color = { 0.95, 0.30, 0.30 }, label = "Major cooldown" },
    PERSONAL = { size = 22, color = { 0.95, 0.78, 0.25 }, label = "Personal" },
    NONE     = { size = 18, color = { 0.45, 0.45, 0.48 }, label = "No cooldown needed" },
}
local BUSTER_ICON = "Interface\\Icons\\Spell_Holy_DefensiveStance"

local CANVAS_SIZE = 356
local CYCLE = 6.0  -- seconds per animation loop

----------------------------------------------------------------------------
-- Layouts
--
-- Coordinates are 0..1 across the canvas with the origin top-left, so a layout
-- is resolution independent and an archetype can later be reused at any panel
-- size. Facing is in degrees clockwise from "up".
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
        -- The loop: cone starts on the group (wrong), tank drags the boss
        -- around, cone ends pointing at the wall (right).
        facingFrom = 180,
        facingTo   = 0,
        groupSafeAtEnd = true,
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
        groupSafeAtEnd = false,  -- the cone is safe here from the start
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

-- Best-effort: find the Encounter Journal instance matching a season dungeon,
-- so the demo shows a boss the player will actually meet rather than a museum
-- piece. Falls back to the first dungeon of the current tier.
local function findJournalDungeon(wantedName)
    if not EJ_GetNumTiers or not EJ_SelectTier or not EJ_GetInstanceByIndex then
        return nil
    end

    if EJ_GetCurrentTier and EJ_SelectTier then
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

function bc:ResolveDemoBoss()
    if self.demo then return self.demo end

    local demo = { bossName = "Boss", dungeonName = nil, portrait = nil, background = nil }

    local wantedName
    local maps = self:GetSeasonMaps()
    if maps and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local name, _, _, texture, background = try("C_ChallengeMode.GetMapUIInfo", function()
            return C_ChallengeMode.GetMapUIInfo(maps[1])
        end)
        wantedName = name
        demo.dungeonName = name
        demo.background = background or texture
    end

    local dungeon = try("EJ_GetInstanceByIndex", function() return findJournalDungeon(wantedName) end)
    if dungeon then
        demo.dungeonName = demo.dungeonName or dungeon.name
        probe["journal dungeon"] = tostring(dungeon.name)

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

        if not demo.background and EJ_GetInstanceInfo then
            local _, _, bgImage = try("EJ_GetInstanceInfo", function()
                return EJ_GetInstanceInfo()
            end)
            demo.background = bgImage
        end
    end

    -- Not used yet, but this is the call that would place bosses on a real
    -- dungeon map instead of hand-placed coordinates, so probe it now while
    -- there is someone to read the answer.
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

-- Canvas coordinates: layouts speak 0..1, frames speak pixels from TOPLEFT.
local function place(canvas, region, x, y, w, h)
    region:ClearAllPoints()
    region:SetSize(w, h)
    region:SetPoint("CENTER", canvas, "TOPLEFT", x * CANVAS_SIZE, -y * CANVAS_SIZE)
end

local function newToken(canvas, size)
    local token = CreateFrame("Frame", nil, canvas)
    token:SetSize(size, size)

    token.halo = token:CreateTexture(nil, "BACKGROUND")
    token.halo:SetTexture(TEX.disc)
    token.halo:SetAllPoints(token)

    token.icon = token:CreateTexture(nil, "ARTWORK")
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
    f:SetSize(CANVAS_SIZE + 32, CANVAS_SIZE + 150)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropColor(unpack(COLOR.panel))
    f:SetBackdropBorderColor(unpack(COLOR.border))
    tinsert(UISpecialFrames, "TankAssistBossCard")

    ------------------------------------------------------------------
    -- Header: portrait, boss name, dungeon
    ------------------------------------------------------------------
    local portrait = CreateFrame("Frame", nil, f)
    portrait:SetSize(44, 44)
    portrait:SetPoint("TOPLEFT", 12, -12)

    portrait.icon = portrait:CreateTexture(nil, "ARTWORK")
    portrait.icon:SetAllPoints(portrait)
    portrait.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    portrait.ring = portrait:CreateTexture(nil, "OVERLAY")
    portrait.ring:SetTexture(TEX.ring)
    portrait.ring:SetPoint("CENTER")
    portrait.ring:SetSize(52, 52)
    setColor(portrait.ring, COLOR.boss)
    f.portrait = portrait

    f.bossName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.bossName:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 10, -2)
    f.bossName:SetTextColor(unpack(COLOR.text))

    f.dungeonName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.dungeonName:SetPoint("TOPLEFT", f.bossName, "BOTTOMLEFT", 0, -3)
    f.dungeonName:SetTextColor(unpack(COLOR.dim))

    f.verdictText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.verdictText:SetPoint("TOPLEFT", f.dungeonName, "BOTTOMLEFT", 0, -4)
    f.verdictText:SetTextColor(unpack(COLOR.accent))

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() bc:Hide() end)

    ------------------------------------------------------------------
    -- Canvas
    ------------------------------------------------------------------
    local canvas = CreateFrame("Frame", nil, f, "BackdropTemplate")
    canvas:SetSize(CANVAS_SIZE, CANVAS_SIZE)
    canvas:SetPoint("TOP", f, "TOP", 0, -68)
    canvas:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    canvas:SetBackdropColor(unpack(COLOR.canvas))
    canvas:SetBackdropBorderColor(unpack(COLOR.border))
    canvas:SetClipsChildren(true)
    f.canvas = canvas

    -- Dungeon art, sat behind everything and knocked well back so it reads as
    -- "you are here" rather than competing with the diagram. Off by default so
    -- the plain background can be judged first.
    canvas.background = canvas:CreateTexture(nil, "BACKGROUND", nil, -8)
    canvas.background:SetAllPoints(canvas)
    canvas.background:SetAlpha(0.22)
    canvas.background:Hide()

    canvas.grid = {}
    for i = 1, 7 do
        for _, orient in ipairs({ "H", "V" }) do
            local line = canvas:CreateLine(nil, "BACKGROUND", nil, -6)
            line:SetThickness(1)
            line:SetColorTexture(unpack(COLOR.grid))
            local t = i / 8
            if orient == "H" then
                line:SetStartPoint("TOPLEFT", canvas, 0, -t * CANVAS_SIZE)
                line:SetEndPoint("TOPLEFT", canvas, CANVAS_SIZE, -t * CANVAS_SIZE)
            else
                line:SetStartPoint("TOPLEFT", canvas, t * CANVAS_SIZE, 0)
                line:SetEndPoint("TOPLEFT", canvas, t * CANVAS_SIZE, -CANVAS_SIZE)
            end
            tinsert(canvas.grid, line)
        end
    end

    canvas.walls = {}

    canvas.cone = canvas:CreateTexture(nil, "ARTWORK", nil, -2)

    canvas.boss = newToken(canvas, 46)
    setColor(canvas.boss.halo, COLOR.boss, 0.30)
    setColor(canvas.boss.ring, COLOR.boss)

    -- Which way the boss is looking, so the cone is never the only cue.
    canvas.bossArrow = canvas:CreateTexture(nil, "OVERLAY")
    canvas.bossArrow:SetTexture(TEX.arrow)
    setColor(canvas.bossArrow, COLOR.boss)

    canvas.tank = newToken(canvas, 34)
    setColor(canvas.tank.halo, COLOR.tank, 0.30)
    setColor(canvas.tank.ring, COLOR.tank)

    canvas.busterGlyph = canvas:CreateTexture(nil, "OVERLAY")
    canvas.busterGlyph:SetTexture(BUSTER_ICON)
    canvas.busterGlyph:SetSize(30, 30)

    canvas.group = {}
    for i = 1, 4 do
        local token = newToken(canvas, 26)
        canvas.group[i] = token
    end

    ------------------------------------------------------------------
    -- Footer: layout switch, toggles
    ------------------------------------------------------------------
    local function makeButton(label, width, onClick)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end

    f.btnAway = makeButton("Turn it away", 104, function() bc:SetLayout("away") end)
    f.btnAway:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 0, -10)

    f.btnSoak = makeButton("Soak together", 108, function() bc:SetLayout("soak") end)
    f.btnSoak:SetPoint("LEFT", f.btnAway, "RIGHT", 6, 0)

    f.btnMap = makeButton("Map", 60, function() bc:ToggleBackground() end)
    f.btnMap:SetPoint("LEFT", f.btnSoak, "RIGHT", 6, 0)

    f.btnDebug = makeButton("Debug", 62, function() bc:Debug() end)
    f.btnDebug:SetPoint("LEFT", f.btnMap, "RIGHT", 6, 0)

    -- Legend. This is the one place words are allowed, because the visual
    -- language has to be learnable once before it can be read everywhere.
    f.legend = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.legend:SetPoint("TOPLEFT", f.btnAway, "BOTTOMLEFT", 1, -8)
    f.legend:SetPoint("TOPRIGHT", f.btnDebug, "BOTTOMRIGHT", -1, -8)
    f.legend:SetJustifyH("LEFT")
    f.legend:SetTextColor(unpack(COLOR.dim))

    f:SetScript("OnUpdate", function(_, elapsed) bc:OnUpdate(elapsed) end)
    f:Hide()

    self.frame = f
    return f
end

----------------------------------------------------------------------------
-- Layout application
----------------------------------------------------------------------------

function bc:SetLayout(key)
    local f = self:BuildFrame()
    local layout
    for _, candidate in ipairs(LAYOUTS) do
        if candidate.key == key then layout = candidate break end
    end
    if not layout then return end

    self.layout = layout
    self.elapsed = 0

    local canvas = f.canvas
    local demo = self:ResolveDemoBoss()

    ------------------------------------------------------------------
    -- Header
    ------------------------------------------------------------------
    f.portrait.icon:SetTexture(demo.portrait or "Interface\\Icons\\Ability_Creature_Cursed_02")
    f.bossName:SetText(demo.bossName or "Boss")
    f.dungeonName:SetText(demo.dungeonName or "")
    f.verdictText:SetText(layout.title .. "  |cff808080" .. layout.subtitle .. "|r")

    if demo.background then
        canvas.background:SetTexture(demo.background)
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
        line:SetStartPoint("TOPLEFT", canvas, wall[1] * CANVAS_SIZE, -wall[2] * CANVAS_SIZE)
        line:SetEndPoint("TOPLEFT", canvas, wall[3] * CANVAS_SIZE, -wall[4] * CANVAS_SIZE)
        line:Show()
    end

    ------------------------------------------------------------------
    -- Cone. The texture's apex sits at its own centre, so centring it on the
    -- boss and rotating about the middle pivots the cone around the boss.
    ------------------------------------------------------------------
    local reach = layout.cone.reach * CANVAS_SIZE * 2
    canvas.cone:SetTexture(layout.cone.texture)
    canvas.cone:ClearAllPoints()
    canvas.cone:SetSize(reach, reach)
    canvas.cone:SetPoint("CENTER", canvas, "TOPLEFT",
        layout.boss.x * CANVAS_SIZE, -layout.boss.y * CANVAS_SIZE)

    ------------------------------------------------------------------
    -- Tokens
    ------------------------------------------------------------------
    place(canvas, canvas.boss, layout.boss.x, layout.boss.y, 46, 46)
    canvas.boss.icon:SetTexture(demo.portrait or "Interface\\Icons\\Ability_Creature_Cursed_02")
    canvas.boss.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    local tankCoordL, tankCoordR, tankCoordT, tankCoordB = roleTexCoords("TANK")
    canvas.tank.icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
    if tankCoordL then
        canvas.tank.icon:SetTexCoord(tankCoordL, tankCoordR, tankCoordT, tankCoordB)
    else
        canvas.tank.icon:SetTexture(TEX.disc)
        setColor(canvas.tank.icon, COLOR.tank)
    end

    for index, member in ipairs(layout.group) do
        local token = canvas.group[index]
        local color = ROLE_COLOR[member.role] or COLOR.dps
        setColor(token.halo, color, 0.30)
        setColor(token.ring, color)

        local l, r, t, b = roleTexCoords(member.role)
        if l then
            token.icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
            token.icon:SetTexCoord(l, r, t, b)
            token.icon:SetVertexColor(1, 1, 1, 1)
        else
            token.icon:SetTexture(TEX.disc)
            setColor(token.icon, color)
        end
        token:Show()
    end
    for index = #layout.group + 1, #canvas.group do
        canvas.group[index]:Hide()
    end

    ------------------------------------------------------------------
    -- Buster glyph
    ------------------------------------------------------------------
    local buster = BUSTER[layout.buster] or BUSTER.NONE
    canvas.busterGlyph:SetSize(buster.size, buster.size)
    canvas.busterGlyph:SetVertexColor(buster.color[1], buster.color[2], buster.color[3], 1)

    f.legend:SetText(
        ("|cff33b8f0Tank|r  |cff59d973Healer|r  |cffeb9440DPS|r        %s        %s"):format(
            "|cffe63838Red cone|r = stay out",
            "|cff40b3ffBlue cone|r = stand in"))

    f.btnAway:SetEnabled(key ~= "away")
    f.btnSoak:SetEnabled(key ~= "soak")
end

function bc:ToggleBackground()
    local f = self:BuildFrame()
    local bg = f.canvas.background
    if bg:IsShown() then
        bg:Hide()
    elseif bg:GetTexture() then
        bg:Show()
    else
        TankAssist.Addon:Print("No dungeon art available for the current season on this client.")
    end
end

----------------------------------------------------------------------------
-- Animation
--
-- One loop shows the tank doing the thing, which is the part a list of words
-- cannot carry. Nothing here is per-boss: it is driven entirely by the layout's
-- facingFrom/facingTo and token start/end positions.
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

    -- Beat 1 hold wrong, beat 2 the tank acts, beat 3 hold right.
    local moveStart, moveEnd = 1.4, 3.4
    local progress = 0
    if t > moveEnd then
        progress = 1
    elseif t > moveStart then
        progress = easeInOut((t - moveStart) / (moveEnd - moveStart))
    end

    local canvas = self.frame.canvas

    -- Facing: degrees clockwise from up, and WoW rotates counter-clockwise.
    local facing = lerp(layout.facingFrom, layout.facingTo, progress)
    canvas.cone:SetRotation(-math.rad(facing))

    local coneColor = COLOR.danger
    if layout.coneSafeAlways then
        coneColor = COLOR.safe
    elseif layout.groupSafeAtEnd then
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

    -- Boss facing arrow, just outside the token.
    local radians = math.rad(facing)
    local offset = 34
    canvas.bossArrow:ClearAllPoints()
    canvas.bossArrow:SetSize(16, 16)
    canvas.bossArrow:SetPoint("CENTER", canvas, "TOPLEFT",
        layout.boss.x * CANVAS_SIZE + math.sin(radians) * offset,
        -(layout.boss.y * CANVAS_SIZE) + math.cos(radians) * offset)
    canvas.bossArrow:SetRotation(-radians)

    -- Tank walks the boss round.
    local tx = lerp(layout.tank.from.x, layout.tank.to.x, progress)
    local ty = lerp(layout.tank.from.y, layout.tank.to.y, progress)
    place(canvas, canvas.tank, tx, ty, 34, 34)

    canvas.busterGlyph:ClearAllPoints()
    canvas.busterGlyph:SetPoint("CENTER", canvas.tank, "CENTER", 22, 16)
    -- Pulse once the tank is in position, so the eye lands on it last.
    local pulse = 0.55 + 0.45 * math.abs(math.sin(t * 2.2))
    canvas.busterGlyph:SetAlpha(progress >= 1 and pulse or 0.25)

    for index, member in ipairs(layout.group) do
        local token = canvas.group[index]
        local gx = member.toX and lerp(member.x, member.toX, progress) or member.x
        local gy = member.toY and lerp(member.y, member.toY, progress) or member.y
        place(canvas, token, gx, gy, 26, 26)

        -- In the "turn it away" loop the group is standing in the frontal at
        -- the start; flashing them makes the mistake obvious before the fix.
        if layout.groupSafeAtEnd then
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
    local f = self:BuildFrame()
    if not self.layout then self:SetLayout("away") end
    f:Show()
end

function bc:Hide()
    if self.frame then self.frame:Hide() end
end

function bc:Toggle()
    local f = self:BuildFrame()
    if f:IsShown() then self:Hide() else self:Show() end
end

-- Which client APIs actually answered. This is the real output of the first
-- pass: it decides whether the boss skeleton can be built from the Journal or
-- whether every boss has to be entered by hand.
function bc:Debug()
    self.demo = nil
    probe = {}
    local demo = self:ResolveDemoBoss()

    local addon = TankAssist.Addon
    local function say(line) if addon then addon:Print(line) else print(line) end end

    say("Boss card API probe:")
    local names = {}
    for name in pairs(probe) do tinsert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        local value = probe[name]
        local color = value:match("^ok") and "|cff40d040" or "|cffe85050"
        print(("  %-42s %s%s|r"):format(name, color, value))
    end
    print(("  %-42s %s"):format("resolved boss", tostring(demo.bossName)))
    print(("  %-42s %s"):format("resolved dungeon", tostring(demo.dungeonName)))
    print(("  %-42s %s"):format("portrait texture", tostring(demo.portrait)))
    print(("  %-42s %s"):format("background texture", tostring(demo.background)))
end

local function Initialize()
    if TankAssist.Addon then
        TankAssist.Addon.bossCard = bc
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.8, Initialize)
end)
