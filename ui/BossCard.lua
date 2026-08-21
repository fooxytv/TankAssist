-- Boss Card -- see https://github.com/fooxytv/TankAssist/issues/38
--
-- A tanking diagram per boss ability: where to stand, which way to point the
-- boss, what the frontal wants, what the buster wants. Tank information only.
--
-- It lives inside the Encounter Journal, opened by an info button beside the
-- portrait, and takes over the content area the way the Traveler's Log tab
-- does. The Journal already knows which boss you are looking at and already has
-- its abilities, portraits and dungeon art, so the card augments the page you
-- are on rather than being a second window you have to find.
--
-- The ability list is read from the Journal's own sections, so it is complete,
-- current, and localised without shipping a single translated string. What this
-- addon adds is the tank verdict for the handful of abilities that need one.
--
--   /ta bosscard         open the Journal on the card
--   /ta bosscard design  authoring mode -- drag things, then export
--   /ta bosscard debug   report which client APIs resolved here

local ADDON_NAME, TankAssist = ...

TankAssist.BossCard = {}
local bc = TankAssist.BossCard

local MEDIA = "Interface\\AddOns\\TankAssist\\media\\diagram\\"

bc.TEX = {
    cone60  = MEDIA .. "cone60",
    cone90  = MEDIA .. "cone90",
    cone120 = MEDIA .. "cone120",
    arrow   = MEDIA .. "arrow",
    ring    = MEDIA .. "ring",
    disc    = MEDIA .. "disc",
}
local TEX = bc.TEX

-- The whole point is that these are read, not decoded. Danger is always the
-- same red, safe is always the same blue, and nothing else uses either.
bc.COLOR = {
    panel   = { 0.04, 0.05, 0.07, 0.97 },
    canvas  = { 0.07, 0.08, 0.10, 1.00 },
    border  = { 0.22, 0.24, 0.30, 1.00 },
    grid    = { 1.00, 1.00, 1.00, 0.045 },
    wall    = { 0.58, 0.62, 0.70, 0.95 },

    boss    = { 0.90, 0.30, 0.30, 1.00 },
    tank    = { 0.20, 0.72, 0.95, 1.00 },
    healer  = { 0.35, 0.85, 0.45, 1.00 },
    dps     = { 0.92, 0.58, 0.25, 1.00 },

    danger  = { 0.95, 0.22, 0.22, 0.48 },
    safe    = { 0.25, 0.70, 1.00, 0.42 },
    neutral = { 0.65, 0.65, 0.70, 0.28 },

    accent  = { 0.00, 0.75, 0.95, 1.00 },
    dim     = { 0.60, 0.60, 0.65, 1.00 },
    text    = { 0.93, 0.93, 0.95, 1.00 },
}
local COLOR = bc.COLOR

bc.ROLE_COLOR = { TANK = COLOR.tank, HEALER = COLOR.healer, DAMAGER = COLOR.dps }
local ROLE_COLOR = bc.ROLE_COLOR

local BUSTER_GLYPH = {
    MAJOR    = { size = 30, color = { 0.95, 0.30, 0.30 } },
    PERSONAL = { size = 22, color = { 0.95, 0.78, 0.25 } },
    NONE     = { size = 0,  color = { 0.45, 0.45, 0.48 } },
}
local BUSTER_ICON = "Interface\\Icons\\Spell_Holy_DefensiveStance"
local FALLBACK_PORTRAIT = "Interface\\Icons\\Ability_Creature_Cursed_02"
local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"

-- Blizzard's boss-page tabs sit at frame level 510. Everything the card builds
-- has to stay under that, including the levels it stacks on itself.
local CARD_LEVEL_CAP = 495

local CYCLE = 6.0
local STRIP_HEIGHT = 46
local HEADER_HEIGHT = 52
local FOOTER_HEIGHT = 30
local MIN_CANVAS = 200

local JOURNAL_ADDON = "Blizzard_EncounterJournal"

bc.state = { abilities = {} }
local state = bc.state

----------------------------------------------------------------------------
-- Client lookups
--
-- Each one records what it found so `/ta bosscard debug` can report it. That
-- report is what decides whether the ability list can be built from the Journal
-- for every boss, or whether each one has to be typed in by hand.
----------------------------------------------------------------------------

local probe = {}
bc.probe = probe

local function try(name, fn)
    local ok, a, b, c, d, e = pcall(fn)
    if not ok then
        probe[name] = "error: " .. tostring(a)
        return nil
    end
    probe[name] = (a ~= nil) and "ok" or "nil"
    return a, b, c, d, e
end

local function getSectionInfo(sectionID)
    if C_EncounterJournal and C_EncounterJournal.GetSectionInfo then
        local ok, info = pcall(C_EncounterJournal.GetSectionInfo, sectionID)
        if ok and type(info) == "table" then return info end
    end
    if EJ_GetSectionInfo then
        local ok, title, description, _, abilityIcon = pcall(EJ_GetSectionInfo, sectionID)
        if ok and title then
            return { title = title, description = description, abilityIcon = abilityIcon }
        end
    end
    return nil
end

-- Walk the Journal's section tree for an encounter and keep everything with a
-- spell attached. That is the boss's ability list, straight from the client:
-- complete, patched by Blizzard, and already in the player's language.
local function collectAbilities(rootSectionID)
    local found, seen, visits = {}, {}, 0

    local function walk(sectionID, depth)
        while sectionID and visits < 400 do
            visits = visits + 1
            local info = getSectionInfo(sectionID)
            if not info then return end

            local spellID = info.spellID
            if spellID and spellID ~= 0 and not seen[spellID] then
                seen[spellID] = true
                found[#found + 1] = {
                    spellID = spellID,
                    name = info.title,
                    icon = info.abilityIcon,
                }
            end

            if info.firstChildSectionID and depth < 5 then
                walk(info.firstChildSectionID, depth + 1)
            end
            sectionID = info.siblingSectionID
        end
    end

    walk(rootSectionID, 0)
    return found
end

-- Dungeon art for the diagram base. Two sources, because neither is reliably
-- present, and the Journal's own instance art is the better looking of the two.
local function resolveBackground(instanceID, dungeonName)
    if instanceID and EJ_GetInstanceInfo then
        local _, _, bgImage, _, loreImage = try("EJ_GetInstanceInfo", function()
            return EJ_GetInstanceInfo(instanceID)
        end)
        if bgImage or loreImage then
            probe["background source"] = "EJ_GetInstanceInfo"
            return bgImage or loreImage
        end
    end

    if C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapUIInfo then
        local maps = try("C_ChallengeMode.GetMapTable", function()
            return C_ChallengeMode.GetMapTable()
        end)
        if type(maps) == "table" then
            probe["C_ChallengeMode.GetMapTable"] = ("ok (%d dungeons)"):format(#maps)
            for _, mapID in ipairs(maps) do
                local name, _, _, texture, background = try("C_ChallengeMode.GetMapUIInfo", function()
                    return C_ChallengeMode.GetMapUIInfo(mapID)
                end)
                if name and (not dungeonName or name == dungeonName) and (background or texture) then
                    probe["background source"] = "C_ChallengeMode.GetMapUIInfo"
                    return background or texture
                end
            end
        end
    end

    probe["background source"] = "none found"
    return nil
end

-- Everything the card needs about whatever the Journal has selected.
function bc:ReadJournal()
    local ej = _G.EncounterJournal
    local encounterID = ej and ej.encounterID
    if not encounterID or not EJ_GetEncounterInfo then return false end

    if state.encounterID == encounterID and #state.abilities > 0 then
        return true
    end

    local name, _, _, rootSectionID, _, journalInstanceID = try("EJ_GetEncounterInfo", function()
        return EJ_GetEncounterInfo(encounterID)
    end)
    if not name then return false end

    wipe(state.abilities)
    state.encounterID = encounterID
    state.bossName = name
    state.selectedIndex = nil
    state.ability = nil

    if EJ_GetCreatureInfo then
        local _, _, _, _, icon = try("EJ_GetCreatureInfo", function()
            return EJ_GetCreatureInfo(1, encounterID)
        end)
        state.portrait = icon
    end

    local instanceID = journalInstanceID or (EJ_GetCurrentInstance and EJ_GetCurrentInstance())
    state.instanceID = instanceID
    state.dungeonAreaMapID = nil
    if instanceID and EJ_GetInstanceInfo then
        -- name, description, bgImage, _, loreImage, buttonImage, dungeonAreaMapID
        local instanceName, _, _, _, _, _, dungeonAreaMapID = try("EJ_GetInstanceInfo", function()
            return EJ_GetInstanceInfo(instanceID)
        end)
        state.dungeonName = instanceName
        state.dungeonAreaMapID = dungeonAreaMapID
    end

    -- The real floor plan, and where the game says this boss stands on it.
    state.mapID, state.bossMapX, state.bossMapY =
        TankAssist.BossCardMap:FindFloorFor(encounterID, state.dungeonAreaMapID)
    if state.mapID then
        probe["dungeon floor map"] = ("ok (map %d at %.2f, %.2f)"):format(
            state.mapID, state.bossMapX or 0, state.bossMapY or 0)
    else
        probe["dungeon floor map"] = "not found"
    end

    -- Lore art is the fallback for when a floor plan cannot be had.
    state.background = resolveBackground(instanceID, state.dungeonName)

    if rootSectionID then
        local abilities = try("collectAbilities", function() return collectAbilities(rootSectionID) end)
        if abilities then
            probe["collectAbilities"] = ("ok (%d abilities)"):format(#abilities)
            for _, ability in ipairs(abilities) do
                ability.card = TankAssist.BossCards:GetAbility(encounterID, ability.spellID)
                state.abilities[#state.abilities + 1] = ability
            end
        end
    end

    return true
end

function bc:HasCardForSelection()
    return state.encounterID ~= nil and TankAssist.BossCards:HasCard(state.encounterID)
end

local function roleTexCoords(role)
    if GetTexCoordsForRoleSmallCircle then
        local ok, l, r, t, b = pcall(GetTexCoordsForRoleSmallCircle, role)
        if ok and l then return l, r, t, b end
    end
    return nil
end
bc.RoleTexCoords = function(_, role) return roleTexCoords(role) end

----------------------------------------------------------------------------
-- Diagram primitives
----------------------------------------------------------------------------

local function setColor(texture, color, alphaOverride)
    texture:SetVertexColor(color[1], color[2], color[3], alphaOverride or color[4] or 1)
end
bc.SetColor = function(_, texture, color, alpha) setColor(texture, color, alpha) end

function bc:CanvasSize()
    return self.canvasSize or 300
end

-- Settings, when the addon has finished loading them. The card is reachable
-- from the Journal before that on a slow login, so it must not assume a db.
function bc:Settings()
    local addon = TankAssist.Addon
    return addon and addon.db and addon.db.profile and addon.db.profile.bossCard
end

-- The designer always gets the floor plan whether or not the card is showing
-- one: tracing the room into a couple of wall segments is the only reason the
-- map has to exist at all, and you cannot trace what you cannot see.
function bc:MapWanted()
    if TankAssist.BossCardDesigner and TankAssist.BossCardDesigner:IsActive() then
        return true
    end
    local settings = self:Settings()
    return settings and settings.showMap or false
end

function bc:SetMapShown(shown)
    local settings = self:Settings()
    if settings then settings.showMap = shown and true or false end
    self:RefreshMapToggle()
    if state.ability then self:Render(state.ability) end
end

-- With a dungeon map attached, card coordinates are map coordinates, so the
-- tokens stay locked to the room when it is zoomed or panned. Without one they
-- are plain canvas coordinates. Converting here means every call site gets that
-- for free rather than each one remembering to ask.
function bc:ToCanvas(x, y)
    if not self.mapActive then return x, y end
    local card = state.ability
    if not card or not card.map then return x, y end
    return TankAssist.BossCardMap:MapToCanvas(x, y, self:CanvasSize(), card.map)
end

function bc:Place(region, x, y, w, h)
    local size = self:CanvasSize()
    local cx, cy = self:ToCanvas(x, y)
    region:ClearAllPoints()
    region:SetSize(w, h)
    region:SetPoint("CENTER", self.frame.canvas, "TOPLEFT", cx * size, -cy * size)
end

-- Screen position -> 0..1 inside the canvas. The designer drags with this.
function bc:CursorToCanvas()
    local canvas = self.frame and self.frame.canvas
    if not canvas then return 0.5, 0.5 end

    local scale = canvas:GetEffectiveScale()
    if not scale or scale == 0 then return 0.5, 0.5 end

    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale

    local left, top = canvas:GetLeft(), canvas:GetTop()
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    if not left or not top or width == 0 or height == 0 then return 0.5, 0.5 end

    local x = (cx - left) / width
    local y = (top - cy) / height
    x, y = math.max(0, math.min(1, x)), math.max(0, math.min(1, y))

    -- Store in the same space the card reads from, or a drag would land
    -- somewhere else the moment the map moved.
    local card = state.ability
    if self.mapActive and card and card.map then
        return TankAssist.BossCardMap:CanvasToMap(x, y, self:CanvasSize(), card.map)
    end
    return x, y
end

local function newToken(parent, size)
    local token = CreateFrame("Frame", nil, parent)
    token:SetSize(size, size)

    token.halo = token:CreateTexture(nil, "ARTWORK", nil, 1)
    token.halo:SetTexture(TEX.disc)
    token.halo:SetAllPoints(token)

    token.icon = token:CreateTexture(nil, "ARTWORK", nil, 2)
    token.icon:SetPoint("CENTER")
    token.icon:SetSize(size * 0.72, size * 0.72)

    token.ring = token:CreateTexture(nil, "OVERLAY")
    token.ring:SetTexture(TEX.ring)
    token.ring:SetAllPoints(token)

    return token
end
bc.NewToken = function(_, parent, size) return newToken(parent, size) end

local function applyRoleIcon(token, role, color)
    local l, r, t, b = roleTexCoords(role)
    if l then
        token.icon:SetTexture(ROLE_TEXTURE)
        token.icon:SetTexCoord(l, r, t, b)
        token.icon:SetVertexColor(1, 1, 1, 1)
    else
        token.icon:SetTexture(TEX.disc)
        token.icon:SetTexCoord(0, 1, 0, 1)
        setColor(token.icon, color)
    end
end

----------------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------------

-- The card takes over the Journal's content area, so it anchors to whichever of
-- these the client actually has rather than assuming one layout survives every
-- patch.
local function contentAnchor()
    local ej = _G.EncounterJournal
    if not ej then return nil end
    if ej.encounter and ej.encounter.info then return ej.encounter.info end
    if ej.encounter then return ej.encounter end
    if ej.inset then return ej.inset end
    return ej
end

function bc:BuildFrame()
    if self.frame then return self.frame end

    local parent = contentAnchor() or UIParent
    local f = CreateFrame("Frame", "TankAssistBossCard", parent, "BackdropTemplate")
    f:SetFrameStrata(parent:GetFrameStrata())
    -- Above the Journal's content, below its tab column. EncounterTabTemplate
    -- pins itself at frame level 510, so anything at or over that would cover
    -- the tabs and strand the player on the card with no way back. The cap
    -- leaves headroom rather than sitting just under it: the card stacks a
    -- canvas, a map layer, a plate and the tokens on top of itself, and those
    -- would climb over 510 from a tighter ceiling.
    f:SetFrameLevel(math.min((parent:GetFrameLevel() or 1) + 10, CARD_LEVEL_CAP))
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -2)
    f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 2)
    f:EnableMouse(true)
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
    f.abilityIcon = f:CreateTexture(nil, "ARTWORK")
    f.abilityIcon:SetSize(34, 34)
    f.abilityIcon:SetPoint("TOPLEFT", 10, -9)
    f.abilityIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.abilityName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.abilityName:SetPoint("TOPLEFT", f.abilityIcon, "TOPRIGHT", 9, -1)
    f.abilityName:SetTextColor(unpack(COLOR.text))
    f.abilityName:SetJustifyH("LEFT")

    f.verdictText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.verdictText:SetPoint("TOPLEFT", f.abilityName, "BOTTOMLEFT", 0, -3)
    f.verdictText:SetJustifyH("LEFT")
    f.verdictText:SetTextColor(unpack(COLOR.accent))

    f.closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.closeButton:SetPoint("TOPRIGHT", 1, 1)
    f.closeButton:SetScript("OnClick", function() bc:Hide() end)

    -- Floor plan on or off. The ticket asks for the plain background to be
    -- judged first rather than assumed worse, which needs both to be one click
    -- apart on the same boss.
    f.mapToggle = CreateFrame("Button", nil, f)
    f.mapToggle:SetSize(46, 18)
    f.mapToggle:SetPoint("TOPRIGHT", f.closeButton, "TOPLEFT", -2, -6)
    f.mapToggle.label = f.mapToggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.mapToggle.label:SetPoint("CENTER")
    f.mapToggle.label:SetText("Map")
    f.mapToggle:SetScript("OnClick", function() bc:SetMapShown(not bc:MapWanted()) end)
    f.mapToggle:SetScript("OnEnter", function(self_)
        GameTooltip:SetOwner(self_, "ANCHOR_LEFT")
        GameTooltip:SetText("Dungeon floor plan")
        GameTooltip:AddLine("The real room behind the diagram.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.mapToggle:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ------------------------------------------------------------------
    -- Ability strip: one button per ability the Journal knows about.
    -- Dimmed until a card has been authored for it.
    ------------------------------------------------------------------
    local strip = CreateFrame("Frame", nil, f)
    strip:SetHeight(STRIP_HEIGHT)
    strip:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -HEADER_HEIGHT)
    strip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -HEADER_HEIGHT)
    f.strip = strip
    strip.buttons = {}

    ------------------------------------------------------------------
    -- Canvas
    ------------------------------------------------------------------
    local canvas = CreateFrame("Frame", nil, f, "BackdropTemplate")
    canvas:SetPoint("TOP", strip, "BOTTOM", 0, -6)
    canvas:SetSize(260, 260)
    canvas:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    canvas:SetBackdropColor(unpack(COLOR.canvas))
    canvas:SetBackdropBorderColor(unpack(COLOR.border))
    canvas:SetClipsChildren(true)
    f.canvas = canvas

    -- Two child frames, at explicit levels, because draw layers do not order
    -- anything across frames -- only frame level does, and siblings that share
    -- a level fall back to creation order. The dungeon floor plan lives in a
    -- frame, so it can be scaled and panned as one piece; that means every
    -- part of the diagram has to live in a frame above it, or the tiles bury
    -- the lot. Sublevels order things *within* each of these, nothing more.
    local canvasLevel = canvas:GetFrameLevel() or 1

    local mapLayer = CreateFrame("Frame", nil, canvas)
    mapLayer:SetAllPoints(canvas)
    mapLayer:SetFrameLevel(canvasLevel + 1)
    canvas.mapLayer = mapLayer

    local plate = CreateFrame("Frame", nil, canvas)
    plate:SetAllPoints(canvas)
    plate:SetFrameLevel(canvasLevel + 4)
    canvas.plate = plate

    -- Lore art, used only when there is no floor plan to be had. It sits on the
    -- plate rather than the canvas so that it and the tiles never compete.
    canvas.background = plate:CreateTexture(nil, "BACKGROUND", nil, 2)
    canvas.background:SetAllPoints(canvas)
    canvas.background:SetAlpha(0.38)

    canvas.grid = {}
    for i = 1, 7 do
        for _, orient in ipairs({ "H", "V" }) do
            local line = plate:CreateLine(nil, "BACKGROUND", nil, 5)
            line:SetThickness(1)
            line:SetColorTexture(unpack(COLOR.grid))
            line.gridFraction = i / 8
            line.gridOrient = orient
            tinsert(canvas.grid, line)
        end
    end

    canvas.walls = {}
    canvas.cone = plate:CreateTexture(nil, "ARTWORK", nil, -2)

    canvas.boss = newToken(plate, 44)
    setColor(canvas.boss.halo, COLOR.boss, 0.30)
    setColor(canvas.boss.ring, COLOR.boss)

    canvas.bossArrow = plate:CreateTexture(nil, "OVERLAY")
    canvas.bossArrow:SetTexture(TEX.arrow)
    setColor(canvas.bossArrow, COLOR.boss)

    canvas.tank = newToken(plate, 32)
    setColor(canvas.tank.halo, COLOR.tank, 0.30)
    setColor(canvas.tank.ring, COLOR.tank)

    canvas.busterGlyph = plate:CreateTexture(nil, "OVERLAY", nil, 2)
    canvas.busterGlyph:SetTexture(BUSTER_ICON)

    canvas.group = {}
    for i = 1, 4 do
        canvas.group[i] = newToken(plate, 25)
    end

    ------------------------------------------------------------------
    -- Footer
    ------------------------------------------------------------------
    f.legend = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.legend:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 9)
    f.legend:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 9)
    f.legend:SetJustifyH("LEFT")
    f.legend:SetTextColor(unpack(COLOR.dim))
    f.legend:SetText("|cff33b8f0Tank|r  |cff59d973Healer|r  |cffeb9440DPS|r"
        .. "    |cffe63838red|r = stay out of it    |cff40b3ffblue|r = stand in it")

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.empty:SetPoint("CENTER", canvas, "CENTER")
    f.empty:SetWidth(220)
    f.empty:SetTextColor(unpack(COLOR.dim))
    f.empty:Hide()

    f:SetScript("OnUpdate", function(_, elapsed) bc:OnUpdate(elapsed) end)
    f:SetScript("OnSizeChanged", function() bc:Relayout() end)
    f:Hide()

    self.frame = f

    if TankAssist.BossCardDesigner then
        TankAssist.BossCardDesigner:Attach(self)
    end

    return f
end

function bc:RefreshMapToggle()
    local f = self.frame
    if not f or not f.mapToggle then return end

    local wanted = self:MapWanted()
    local available = state.mapID ~= nil
    f.mapToggle:SetEnabled(available)
    f.mapToggle.label:SetTextColor(unpack(
        (not available) and COLOR.dim or (wanted and COLOR.accent or COLOR.border)))
end

-- The canvas is square and takes whatever room is left, so the card fits the
-- Journal's panel instead of assuming a size it does not have.
function bc:Relayout()
    local f = self.frame
    if not f then return end

    local width, height = f:GetWidth() or 0, f:GetHeight() or 0
    if width <= 1 or height <= 1 then return end

    local available = math.min(width - 24, height - (HEADER_HEIGHT + STRIP_HEIGHT + FOOTER_HEIGHT + 18))
    local size = math.floor(math.max(MIN_CANVAS, available))

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

    if state.ability then self:Render(state.ability) end
end

----------------------------------------------------------------------------
-- Ability strip
----------------------------------------------------------------------------

function bc:RefreshStrip()
    local f = self.frame
    local strip = f.strip

    for _, button in ipairs(strip.buttons) do button:Hide() end

    local size = 36
    local gap = 4
    for index, ability in ipairs(state.abilities) do
        local button = strip.buttons[index]
        if not button then
            button = CreateFrame("Button", nil, strip)
            button:SetSize(size, size)

            button.icon = button:CreateTexture(nil, "ARTWORK")
            button.icon:SetAllPoints(button)
            button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            button.border = button:CreateTexture(nil, "OVERLAY")
            button.border:SetTexture(TEX.ring)
            button.border:SetPoint("CENTER")
            button.border:SetSize(size + 5, size + 5)

            button:SetScript("OnClick", function(self_)
                bc:SelectAbility(self_.abilityIndex)
            end)
            button:SetScript("OnEnter", function(self_)
                GameTooltip:SetOwner(self_, "ANCHOR_BOTTOM")
                if self_.spellID and GameTooltip.SetSpellByID then
                    pcall(GameTooltip.SetSpellByID, GameTooltip, self_.spellID)
                else
                    GameTooltip:SetText(self_.abilityName or "")
                end
                if not self_.hasCard then
                    GameTooltip:AddLine("No tank card yet.", 0.6, 0.6, 0.6)
                end
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)

            strip.buttons[index] = button
        end

        button.abilityIndex = index
        button.spellID = ability.spellID
        button.abilityName = ability.name
        button.hasCard = ability.card ~= nil

        button.icon:SetTexture(ability.icon or FALLBACK_PORTRAIT)
        -- Abilities without a card stay visible but greyed: the gap is
        -- information, and hiding them would make the list look complete.
        button.icon:SetDesaturated(not button.hasCard)
        button.icon:SetAlpha(button.hasCard and 1 or 0.45)

        button:ClearAllPoints()
        button:SetPoint("LEFT", strip, "LEFT", (index - 1) * (size + gap), 0)
        button:Show()

        local selected = (state.selectedIndex == index)
        setColor(button.border, selected and COLOR.accent or COLOR.border,
            selected and 1 or 0.6)
    end
end

function bc:SelectAbility(index)
    local ability = state.abilities[index]
    if not ability then
        -- No abilities at all: the Journal had nothing for this encounter, or
        -- it has not finished populating. Say so rather than leaving the last
        -- boss's diagram on screen looking like this one's.
        state.selectedIndex = nil
        state.ability = nil
        local f = self.frame
        f.abilityIcon:SetTexture(state.portrait or FALLBACK_PORTRAIT)
        f.abilityName:SetText(state.bossName or "")
        f.verdictText:SetText("")
        f.empty:SetText("The Adventure Guide lists no abilities for this boss.")
        f.empty:Show()
        self:ShowDiagram(false)
        self:RefreshStrip()
        return
    end

    state.selectedIndex = index

    local card = ability.card
    if not card and TankAssist.BossCardDesigner and TankAssist.BossCardDesigner:IsActive() then
        card = TankAssist.BossCardDesigner:NewCardFor(ability)
        ability.card = card
    end

    state.ability = card
    self:RefreshStrip()

    local f = self.frame
    f.abilityIcon:SetTexture(ability.icon or FALLBACK_PORTRAIT)
    f.abilityName:SetText(ability.name or "")

    if card then
        local verdict = TankAssist.BossCards.VERDICTS[card.verdict] or TankAssist.BossCards.VERDICTS.NONE
        f.verdictText:SetText(verdict.label .. "  |cff808080" .. verdict.hint .. "|r")
        f.empty:Hide()
        self:Render(card)
        self:ShowDiagram(true)
    else
        f.verdictText:SetText("")
        f.empty:SetText("No tank card for this ability yet.\n\n"
            .. "|cff808080/ta bosscard design|r to author one.")
        f.empty:Show()
        self:ShowDiagram(false)
    end

    if TankAssist.BossCardDesigner then
        TankAssist.BossCardDesigner:OnAbilityChanged(ability, card)
    end
end

function bc:ShowDiagram(shown)
    local canvas = self.frame.canvas
    local regions = { canvas.cone, canvas.bossArrow, canvas.busterGlyph }
    for _, region in ipairs(regions) do
        if shown then region:Show() else region:Hide() end
    end
    for _, token in ipairs({ canvas.boss, canvas.tank }) do
        if shown then token:Show() else token:Hide() end
    end
    for _, token in ipairs(canvas.group) do
        if shown then token:Show() else token:Hide() end
    end
    for _, line in ipairs(canvas.walls) do
        if not shown then line:Hide() end
    end
end

----------------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------------

local CONE_TEXTURE = { [60] = TEX.cone60, [90] = TEX.cone90, [120] = TEX.cone120 }

function bc:Render(card)
    local f = self.frame
    local canvas = f.canvas
    local size = self:CanvasSize()

    -- The dungeon floor first; the instance's lore art only if there is no
    -- floor plan to be had. A room you recognise beats a mood painting.
    local cardmap = TankAssist.BossCardMap
    self.mapActive = false
    if state.mapID and self:MapWanted() then
        cardmap:Build(canvas.mapLayer)
        if cardmap:SetMap(canvas.mapLayer, state.mapID) then
            card.map = card.map or cardmap:DefaultView(state.bossMapX, state.bossMapY)
            cardmap:Apply(size, card.map)
            self.mapActive = true
        end
    end

    if self.mapActive then
        canvas.background:Hide()
    else
        cardmap:Hide()
        canvas.background:SetTexture(state.background)
        canvas.background:SetShown(state.background ~= nil)
    end

    -- With a floor plan up, the boss belongs where the game says it stands
    -- rather than wherever it was dragged, so the diagram lines up with the room.
    if self.mapActive and state.bossMapX and not card.bossPlaced then
        card.boss.x, card.boss.y = state.bossMapX, state.bossMapY
    end

    ------------------------------------------------------------------
    -- Walls
    ------------------------------------------------------------------
    for _, line in ipairs(canvas.walls) do line:Hide() end
    for index, wall in ipairs(card.walls or {}) do
        local line = canvas.walls[index]
        if not line then
            line = canvas.plate:CreateLine(nil, "ARTWORK", nil, -4)
            line:SetThickness(5)
            canvas.walls[index] = line
        end
        line:SetColorTexture(unpack(COLOR.wall))
        local ax, ay = self:ToCanvas(wall[1], wall[2])
        local bx, by = self:ToCanvas(wall[3], wall[4])
        line:SetStartPoint("TOPLEFT", canvas, ax * size, -ay * size)
        line:SetEndPoint("TOPLEFT", canvas, bx * size, -by * size)
        line:Show()
    end

    ------------------------------------------------------------------
    -- Cone. The texture's apex is at its own centre, so centring it on the
    -- boss and rotating about the middle pivots it around the boss.
    ------------------------------------------------------------------
    if card.cone then
        local width = card.cone.width or 90
        canvas.cone:SetTexture(CONE_TEXTURE[width] or TEX.cone90)
        local reach = (card.cone.reach or 0.44) * size * 2
        canvas.cone:ClearAllPoints()
        canvas.cone:SetSize(reach, reach)
        local coneX, coneY = self:ToCanvas(card.boss.x, card.boss.y)
        canvas.cone:SetPoint("CENTER", canvas, "TOPLEFT", coneX * size, -coneY * size)
        canvas.cone:Show()
    else
        canvas.cone:Hide()
    end

    ------------------------------------------------------------------
    -- Tokens
    ------------------------------------------------------------------
    local scale = size / 320
    self.tokenScale = scale

    self:Place(canvas.boss, card.boss.x, card.boss.y, 44 * scale, 44 * scale)
    canvas.boss.icon:SetVertexColor(1, 1, 1, 1)
    if not cardmap:ApplyBossPortrait(canvas.boss.icon, state.encounterID) then
        canvas.boss.icon:SetTexture(state.portrait or FALLBACK_PORTRAIT)
        canvas.boss.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    end

    applyRoleIcon(canvas.tank, "TANK", COLOR.tank)

    for index, member in ipairs(card.group or {}) do
        local token = canvas.group[index]
        if token then
            local color = ROLE_COLOR[member.role] or COLOR.dps
            setColor(token.halo, color, 0.30)
            setColor(token.ring, color)
            applyRoleIcon(token, member.role, color)
            token:Show()
        end
    end
    for index = #(card.group or {}) + 1, #canvas.group do
        canvas.group[index]:Hide()
    end

    local glyph = BUSTER_GLYPH[card.buster] or BUSTER_GLYPH.NONE
    if glyph.size > 0 then
        canvas.busterGlyph:SetSize(glyph.size * scale, glyph.size * scale)
        canvas.busterGlyph:SetVertexColor(glyph.color[1], glyph.color[2], glyph.color[3], 1)
        canvas.busterGlyph:Show()
    else
        canvas.busterGlyph:Hide()
    end

    if TankAssist.BossCardDesigner then
        TankAssist.BossCardDesigner:SyncHandles(card)
    end
end

----------------------------------------------------------------------------
-- Animation
--
-- A card with a `move` block is showing the tank doing something, so it loops
-- between the two states. Without one it just sits still, which is correct for
-- an ability where the answer is "stand here and press this".
----------------------------------------------------------------------------

local function lerp(a, b, t) return a + (b - a) * t end

local function easeInOut(t)
    if t < 0.5 then return 2 * t * t end
    return -1 + (4 - 2 * t) * t
end

local function toneColor(verdict)
    local entry = TankAssist.BossCards.VERDICTS[verdict]
    local tone = entry and entry.tone or "neutral"
    if tone == "safe" then return COLOR.safe end
    if tone == "danger" then return COLOR.danger end
    return COLOR.neutral
end

function bc:OnUpdate(elapsed)
    local card = state.ability
    if not card or not self.frame:IsShown() then return end

    -- The designer drives positions from the mouse, so the loop stands aside.
    local designing = TankAssist.BossCardDesigner and TankAssist.BossCardDesigner:IsActive()

    self.elapsed = ((self.elapsed or 0) + elapsed) % CYCLE
    local t = self.elapsed
    local size = self:CanvasSize()
    local scale = self.tokenScale or 1
    local canvas = self.frame.canvas

    local move = card.move

    -- While designing, the loop stands aside and the diagram is pinned to
    -- whichever end of the animation is being edited. Dragging then lands on
    -- what is actually on screen rather than on the state you cannot see.
    local progress = 0
    if designing then
        progress = TankAssist.BossCardDesigner:Progress()
    elseif move then
        local moveStart, moveEnd = 1.4, 3.4
        if t > moveEnd then
            progress = 1
        elseif t > moveStart then
            progress = easeInOut((t - moveStart) / (moveEnd - moveStart))
        end
    end

    ------------------------------------------------------------------
    -- Boss facing and cone
    ------------------------------------------------------------------
    local facingFrom = card.boss.facing or 180
    local facingTo = (move and move.boss and move.boss.facing) or facingFrom
    local facing = lerp(facingFrom, facingTo, progress)

    if card.cone then
        canvas.cone:SetRotation(-math.rad(facing))

        -- Where the boss ends up is the correct answer, so the cone is coloured
        -- by the verdict at the end of the loop and cross-fades into it. The
        -- colour change and the movement then read as one event.
        local target = toneColor(card.verdict)
        local start = (facingTo ~= facingFrom) and COLOR.danger or target
        setColor(canvas.cone, {
            lerp(start[1], target[1], progress),
            lerp(start[2], target[2], progress),
            lerp(start[3], target[3], progress),
            lerp(start[4], target[4], progress),
        })
    end

    self:Place(canvas.boss, card.boss.x, card.boss.y, 44 * scale, 44 * scale)
    if card.cone then
        local coneX, coneY = self:ToCanvas(card.boss.x, card.boss.y)
        canvas.cone:ClearAllPoints()
        canvas.cone:SetPoint("CENTER", canvas, "TOPLEFT", coneX * size, -coneY * size)
    end

    local radians = math.rad(facing)
    local offset = 32 * scale
    canvas.bossArrow:ClearAllPoints()
    canvas.bossArrow:SetSize(15 * scale, 15 * scale)
    local arrowX, arrowY = self:ToCanvas(card.boss.x, card.boss.y)
    canvas.bossArrow:SetPoint("CENTER", canvas, "TOPLEFT",
        arrowX * size + math.sin(radians) * offset,
        -(arrowY * size) + math.cos(radians) * offset)
    canvas.bossArrow:SetRotation(-radians)

    ------------------------------------------------------------------
    -- Tank and group
    ------------------------------------------------------------------
    local tankTo = (move and move.tank) or card.tank
    local tx = lerp(card.tank.x, tankTo.x or card.tank.x, progress)
    local ty = lerp(card.tank.y, tankTo.y or card.tank.y, progress)
    self:Place(canvas.tank, tx, ty, 32 * scale, 32 * scale)

    if canvas.busterGlyph:IsShown() then
        canvas.busterGlyph:ClearAllPoints()
        canvas.busterGlyph:SetPoint("CENTER", canvas.tank, "CENTER", 20 * scale, 15 * scale)
        local pulse = 0.55 + 0.45 * math.abs(math.sin(t * 2.2))
        canvas.busterGlyph:SetAlpha((progress >= 1 or not move) and pulse or 0.25)
    end

    for index, member in ipairs(card.group or {}) do
        local token = canvas.group[index]
        if token and token:IsShown() then
            local dest = move and move.group and move.group[index]
            local gx = lerp(member.x, (dest and dest.x) or member.x, progress)
            local gy = lerp(member.y, (dest and dest.y) or member.y, progress)
            self:Place(token, gx, gy, 25 * scale, 25 * scale)

            -- If the loop is showing a correction, the group is standing in the
            -- wrong place at the start. Flashing them says so without a word.
            if move and card.verdict == "AWAY" then
                token.halo:SetAlpha(lerp(0.25 + 0.55 * math.abs(math.sin(t * 5)), 0.30, progress))
            else
                token.halo:SetAlpha(0.30)
            end
        end
    end

    if designing then
        TankAssist.BossCardDesigner:SyncHandles(card)
    end
end

----------------------------------------------------------------------------
-- Encounter Journal integration
----------------------------------------------------------------------------

-- The way in is a fifth tab on the Journal's boss page, below Overview, Loot,
-- Abilities and Model.
--
-- The first attempt was an "i" button beside the portrait, and it was invisible
-- in game for a reason worth recording: `EncounterJournal.PortraitContainer` is
-- a 1x1 frame pinned to the very corner of the window at frame level 400 -- the
-- 62x62 portrait is a *texture inside it*, offset (-5, 7). Anchoring to that
-- container's TOPRIGHT put a 24x24 button underneath the portrait art, not
-- beside it. (`EncounterJournalPortrait` is not a global either: the container
-- has no name, so `$parentPortrait` never resolves.)
--
-- A tab is the better answer regardless. It is Blizzard's own template, so it
-- gets the right art, the right frame level and tooltip behaviour for free, and
-- it sits where a player already looks for another view of this boss.
local TANK_TAB_ID = 5

local function journalInfoPanel()
    local ej = _G.EncounterJournal
    return ej and ej.encounter and ej.encounter.info
end

-- Blizzard's four tabs, so ours can deselect them and they can dismiss ours.
local BLIZZARD_TABS = { "overviewTab", "lootTab", "bossTab", "modelTab" }

local function eachBlizzardTab(fn)
    local info = journalInfoPanel()
    if not info then return end
    for _, key in ipairs(BLIZZARD_TABS) do
        local tab = info[key]
        if tab then fn(tab) end
    end
end

local function buildTankTab()
    local info = journalInfoPanel()
    if not info or not info.modelTab then return nil end

    local tab = CreateFrame("Button", "TankAssistBossCardTab", info, "EncounterTabTemplate")
    tab:SetID(TANK_TAB_ID)
    tab:SetPoint("TOP", info.modelTab, "BOTTOM", 0, 2)
    tab.tooltip = "Tank card"

    -- Blizzard builds each tab's selected/unselected glyphs in XML rather than
    -- in the template, so ours are ours to make. A shield on our own ring keeps
    -- it recognisable without depending on an art path that may not survive a
    -- patch.
    tab.unselected = tab:CreateTexture(nil, "OVERLAY")
    tab.unselected:SetTexture(BUSTER_ICON)
    tab.unselected:SetSize(26, 26)
    tab.unselected:SetPoint("RIGHT", -12, 0)
    tab.unselected:SetVertexColor(0.75, 0.75, 0.75, 1)

    tab.selected = tab:CreateTexture(nil, "OVERLAY")
    tab.selected:SetTexture(BUSTER_ICON)
    tab.selected:SetSize(26, 26)
    tab.selected:SetPoint("CENTER", tab.unselected, "CENTER")
    tab.selected:SetVertexColor(unpack(COLOR.accent))
    tab.selected:Hide()

    -- Deliberately not EncounterJournal_SetTab / _SetTabEnabled. `EJ_Tabs` is a
    -- file-local, so a fifth entry cannot be registered in it, and handing it a
    -- tab index it does not know about sets `info.tab = 5` -- which makes the
    -- next boss selection throw inside EncounterJournal_ValidateSelectedTab,
    -- where `EJ_Tabs[info.tab].button` indexes nil. Selection stays ours;
    -- `info.tab` stays on a value Blizzard put there.
    tab:SetScript("OnClick", function()
        if PlaySound and SOUNDKIT then
            pcall(PlaySound, SOUNDKIT.IG_ABILITY_PAGE_TURN)
        end
        bc:Show()
    end)

    eachBlizzardTab(function(blizzardTab)
        blizzardTab:HookScript("OnClick", function() bc:Hide() end)
    end)

    return tab
end

-- Ours selected means Blizzard's are not, and the card is covering their
-- content anyway. Nothing here writes to `info.tab`, so Blizzard's own
-- SetTab restores its highlight the moment one of its tabs is clicked.
function bc:RefreshTabSelection()
    local tab = self.tab
    if not tab then return end

    local shown = self.frame and self.frame:IsShown()
    tab.selected:SetShown(shown)
    tab.unselected:SetShown(not shown)
    if shown then
        tab:LockHighlight()
        eachBlizzardTab(function(blizzardTab)
            if blizzardTab.selected then blizzardTab.selected:Hide() end
            if blizzardTab.unselected then blizzardTab.unselected:Show() end
            blizzardTab:UnlockHighlight()
        end)
    else
        tab:UnlockHighlight()
    end
end

-- The tab is always there for a selected boss, so there is always a way in, but
-- it greys out when nothing has been authored -- which makes it a readout of
-- which bosses have a card rather than a control that lies.
function bc:RefreshTab()
    if not self.tab then return end

    local designing = TankAssist.BossCardDesigner and TankAssist.BossCardDesigner:IsActive()
    local selected = state.encounterID ~= nil
    local authored = self:HasCardForSelection()
    local usable = selected and (authored or designing)

    self.tab:SetShown(selected)
    self.tab:SetEnabled(usable)
    self.tab.unselected:SetDesaturated(not usable)
    self.tab:SetAlpha(usable and 1 or 0.5)

    if not selected and self.frame and self.frame:IsShown() then
        self:Hide()
    end
    self:RefreshMapToggle()
    self:RefreshTabSelection()
end

-- Building the tab needs the Journal's boss page to exist, which it does not
-- on every path into here (a card opened before the player has ever viewed an
-- encounter, for one). Kept separate from the hooks so it can be retried
-- without double-hooking anything.
function bc:EnsureTab()
    if not self.tab then
        self.tab = buildTankTab()
    end
    probe["tank tab"] = self.tab and "ok" or "no boss page yet"
    return self.tab ~= nil
end

function bc:AttachToJournal()
    if self.attached then
        self:EnsureTab()
        return true
    end
    if not _G.EncounterJournal then return false end

    probe["journal anchor"] = (contentAnchor() and (contentAnchor():GetName() or "unnamed")) or "none"

    self:BuildFrame()
    self:EnsureTab()

    if EJ_SelectEncounter then
        hooksecurefunc("EJ_SelectEncounter", function()
            state.encounterID = nil
            bc:ReadJournal()
            bc:RefreshTab()
            if bc.frame and bc.frame:IsShown() then
                bc:RefreshStrip()
                bc:SelectAbility(1)
            end
        end)
    end

    _G.EncounterJournal:HookScript("OnHide", function() bc:Hide() end)
    _G.EncounterJournal:HookScript("OnShow", function()
        bc:ReadJournal()
        bc:RefreshTab()
    end)

    -- The Journal has changed which function selects an encounter more than
    -- once. Watching its own encounterID costs a comparison every quarter
    -- second and does not care how the value got there.
    local watcher = CreateFrame("Frame", nil, _G.EncounterJournal)
    watcher.since = 0
    watcher:SetScript("OnUpdate", function(self_, elapsed)
        self_.since = self_.since + elapsed
        if self_.since < 0.25 then return end
        self_.since = 0

        local current = _G.EncounterJournal.encounterID
        if current == self_.lastSeen then return end
        self_.lastSeen = current

        state.encounterID = nil
        bc:ReadJournal()
        bc:RefreshTab()
        if bc.frame and bc.frame:IsShown() then
            bc:RefreshStrip()
            bc:SelectAbility(1)
        end
    end)

    self:ReadJournal()
    self:RefreshTab()
    self.attached = true
    return true
end

function bc:EnsureJournalLoaded()
    if _G.EncounterJournal then return true end
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, JOURNAL_ADDON)
    end
    return _G.EncounterJournal ~= nil
end

----------------------------------------------------------------------------
-- Public
----------------------------------------------------------------------------

function bc:Say(message)
    local addon = TankAssist.Addon
    if addon then addon:Print(message) else print(message) end
end


function bc:Show()
    if not self:EnsureJournalLoaded() then
        self:Say("The Encounter Journal could not be loaded.")
        return
    end

    self:AttachToJournal()

    local ej = _G.EncounterJournal
    if ej and not ej:IsShown() then
        if ToggleEncounterJournal then
            pcall(ToggleEncounterJournal)
        elseif ShowUIPanel then
            pcall(ShowUIPanel, ej)
        end
    end

    if not self:ReadJournal() then
        self:Say("Open a dungeon in the Adventure Guide and click a boss, then use the "
            .. "|cff00bfffTank|r tab under the Model tab.")
        return
    end

    if #state.abilities == 0 then
        self:Say("The Adventure Guide lists no abilities for " .. tostring(state.bossName) .. ".")
    end

    self.frame:Show()
    self:Relayout()
    self:RefreshMapToggle()
    self:RefreshStrip()
    self:SelectAbility(state.selectedIndex or 1)
    self:RefreshTabSelection()
end

function bc:Hide()
    if self.frame then self.frame:Hide() end
    self:RefreshTabSelection()
end

function bc:Toggle()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end

-- The season in one command.
--
-- The ticket has been blocked on "which of these APIs actually answer on a real
-- client" since it was opened, and answering it a boss at a time -- click, run
-- debug, paste -- is why it stayed blocked. This walks every dungeon in the
-- current tier and reports what came back, so the decision it gates (can the
-- boss skeleton be built from the Journal, or does every boss get typed in by
-- hand) can be made from one paste.
--
-- Enumeration follows Blizzard's own: EJ_GetInstanceByIndex over the tier, then
-- EJ_GetEncounterInfoByIndex over the selected instance. The player's selection
-- is captured and put back, and no display function is called, so an open
-- Journal does not move.
function bc:Scan()
    if not self:EnsureJournalLoaded() then
        self:Say("The Encounter Journal could not be loaded.")
        return
    end

    local addon = TankAssist.Addon
    local function say(line) if addon then addon:Print(line) else print(line) end end

    if not EJ_GetInstanceByIndex or not EJ_GetEncounterInfoByIndex or not EJ_SelectInstance then
        say("This client does not expose the Journal enumeration API.")
        return
    end

    local ej = _G.EncounterJournal
    local restoreInstance = ej and ej.instanceID
    local restoreEncounter = ej and ej.encounterID

    local tier = EJ_GetCurrentTier and EJ_GetCurrentTier() or nil
    local tierName = (tier and EJ_GetTierInfo) and EJ_GetTierInfo(tier) or "current tier"

    say(("Journal scan -- %s"):format(tostring(tierName)))
    print(("  %-30s %5s %5s %5s %6s"):format("dungeon", "boss", "abil", "map", "floor"))

    local totals = { instances = 0, bosses = 0, abilities = 0, portraits = 0, floors = 0 }

    local index = 1
    while true do
        local instanceID, instanceName, _, _, _, _, _, _, _, _, _ = EJ_GetInstanceByIndex(index, false)
        if not instanceID then break end
        index = index + 1
        totals.instances = totals.instances + 1

        pcall(EJ_SelectInstance, instanceID)

        local dungeonAreaMapID = select(7, EJ_GetInstanceInfo(instanceID))

        local bosses, abilities, portraits, floors = 0, 0, 0, 0
        local bossIndex = 1
        while true do
            local _, _, encounterID, rootSectionID = EJ_GetEncounterInfoByIndex(bossIndex, instanceID)
            if not encounterID or encounterID <= 0 then break end
            bossIndex = bossIndex + 1
            bosses = bosses + 1

            if rootSectionID and rootSectionID > 0 then
                local ok, found = pcall(collectAbilities, rootSectionID)
                if ok and found then abilities = abilities + #found end
            end

            if EJ_GetCreatureInfo then
                local ok, _, _, _, displayInfo = pcall(EJ_GetCreatureInfo, 1, encounterID)
                if ok and displayInfo then portraits = portraits + 1 end
            end

            if TankAssist.BossCardMap:FindFloorFor(encounterID, dungeonAreaMapID) then
                floors = floors + 1
            end
        end

        totals.bosses = totals.bosses + bosses
        totals.abilities = totals.abilities + abilities
        totals.portraits = totals.portraits + portraits
        totals.floors = totals.floors + floors

        print(("  %-30s %5d %5d %5s %6d"):format(
            tostring(instanceName):sub(1, 30), bosses, abilities,
            dungeonAreaMapID and tostring(dungeonAreaMapID) or "-", floors))
    end

    if restoreInstance then pcall(EJ_SelectInstance, restoreInstance) end
    if restoreEncounter and EJ_SelectEncounter then pcall(EJ_SelectEncounter, restoreEncounter) end

    say(("%d dungeons, %d bosses, %d abilities, %d portraits, %d with a floor plan.")
        :format(totals.instances, totals.bosses, totals.abilities, totals.portraits, totals.floors))

    -- The verdict this scan exists to produce.
    if totals.bosses > 0 and totals.abilities >= totals.bosses then
        say("|cff40d040Skeleton can be auto-built|r -- only the verdicts need authoring.")
    else
        say("|cffe85050The Journal did not answer|r -- bosses would have to be entered by hand.")
    end
end

function bc:Debug()
    wipe(probe)
    self:EnsureJournalLoaded()
    self:AttachToJournal()
    state.encounterID = nil
    local ok = self:ReadJournal()

    local addon = TankAssist.Addon
    local function say(line) if addon then addon:Print(line) else print(line) end end

    say("Boss card API probe:")
    local names = {}
    for name in pairs(probe) do tinsert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        local value = tostring(probe[name])
        local color = value:match("^ok") and "|cff40d040" or "|cffe85050"
        print(("  %-40s %s%s|r"):format(name, color, value))
    end
    print(("  %-40s %s"):format("journal readable", tostring(ok)))
    print(("  %-40s %s"):format("boss", tostring(state.bossName)))
    print(("  %-40s %s"):format("dungeon", tostring(state.dungeonName)))
    print(("  %-40s %s"):format("abilities found", tostring(#state.abilities)))
    print(("  %-40s %s"):format("portrait", tostring(state.portrait)))
    print(("  %-40s %s"):format("background", tostring(state.background)))

    for index, ability in ipairs(state.abilities) do
        if index > 12 then
            print(("  ... and %d more"):format(#state.abilities - 12))
            break
        end
        print(("    %-34s spell %s"):format(tostring(ability.name), tostring(ability.spellID)))
    end
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
            if TankAssist.Addon then TankAssist.Addon.bossCard = bc end
        end)
    end
end)
