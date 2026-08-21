-- Boss Card Designer -- see https://github.com/fooxytv/TankAssist/issues/38
--
-- Authoring mode for the tank cards. Drag the boss, the tank and the group to
-- where they actually belong, wheel the boss round to set which way it is
-- facing, pick the verdict, then hit Export and paste the block into
-- data/BossCards.lua.
--
-- This exists because hand-writing normalised coordinates without being able to
-- see them produces exactly what you would expect it to. The person who can see
-- the diagram should be the one positioning it, and the addon should be the one
-- turning that into data.
--
-- A card has two states: what it looks like when the ability goes out, and what
-- it should look like after the tank has done their job. The Before/After
-- toggle picks which one you are dragging; the card animates between them.
--
--   /ta bosscard design
--
-- The palette is a floating window rather than another row of buttons inside
-- the card, because the card is already fighting the Journal for room and the
-- palette is only ever on screen for whoever is authoring.

local ADDON_NAME, TankAssist = ...

TankAssist.BossCardDesigner = {}
local designer = TankAssist.BossCardDesigner

designer.active = false
designer.editing = "before"

local VERDICT_ORDER = { "AWAY", "SOAK", "DODGE", "STACK", "NONE" }
local BUSTER_ORDER  = { "MAJOR", "PERSONAL", "NONE" }
local CONE_WIDTHS   = { 60, 90, 120 }
local ROLE_ORDER    = { "DAMAGER", "HEALER" }

local function nextIn(list, current)
    for index, value in ipairs(list) do
        if value == current then
            return list[index % #list + 1]
        end
    end
    return list[1]
end

local function copyPoint(point)
    return { x = point.x, y = point.y, facing = point.facing, role = point.role }
end

----------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------

function designer:IsActive()
    return self.active
end

-- Which end of the animation is being edited, as the 0..1 the renderer wants.
function designer:Progress()
    return (self.editing == "after") and 1 or 0
end

-- A blank card to start dragging, cloned from a template so there is something
-- on screen rather than four tokens stacked in a corner.
function designer:NewCardFor(ability)
    local template = TankAssist.BossCards.TEMPLATES[1]
    local card = {
        spellID = ability.spellID,
        verdict = template.verdict,
        buster  = template.buster,
        cone    = { width = template.cone.width, reach = template.cone.reach },
        boss    = copyPoint(template.boss),
        tank    = copyPoint(template.tank),
        group   = {},
        walls   = {},
    }
    for _, member in ipairs(template.group) do
        card.group[#card.group + 1] = copyPoint(member)
    end
    for _, wall in ipairs(template.walls) do
        card.walls[#card.walls + 1] = { wall[1], wall[2], wall[3], wall[4] }
    end
    return card
end

----------------------------------------------------------------------------
-- Dragging
--
-- The tokens themselves are the handles. Nothing extra is drawn, so what is
-- being positioned is exactly what will be seen.
----------------------------------------------------------------------------

local function currentCard()
    return TankAssist.BossCard.state.ability
end

-- Where a drag writes depends on which state is being edited: the "after"
-- positions live under card.move, and only exist once something has been moved
-- there, so they are created on demand.
function designer:TargetFor(kind, index)
    local card = currentCard()
    if not card then return nil end

    if self.editing == "before" then
        if kind == "boss" then return card.boss end
        if kind == "tank" then return card.tank end
        return card.group and card.group[index]
    end

    card.move = card.move or {}
    if kind == "boss" then
        -- Boss position is shared between the two states: an ability turns the
        -- boss, it does not usually relocate it, and keeping one position keeps
        -- the cone anchored.
        return card.boss
    end
    if kind == "tank" then
        card.move.tank = card.move.tank or copyPoint(card.tank)
        return card.move.tank
    end
    card.move.group = card.move.group or {}
    if not card.move.group[index] and card.group and card.group[index] then
        card.move.group[index] = copyPoint(card.group[index])
    end
    return card.move.group[index]
end

function designer:MakeDraggable(token, kind, index)
    if token.designerWired then
        token.designerKind, token.designerIndex = kind, index
        return
    end
    token.designerWired = true
    token.designerKind, token.designerIndex = kind, index

    token:SetScript("OnMouseDown", function(self_)
        if not designer:IsActive() then return end
        self_.dragging = true
    end)
    token:SetScript("OnMouseUp", function(self_)
        self_.dragging = false
        designer:RefreshReadout()
    end)
    token:SetScript("OnUpdate", function(self_)
        if not self_.dragging or not designer:IsActive() then return end
        local target = designer:TargetFor(self_.designerKind, self_.designerIndex)
        if not target then return end
        local x, y = TankAssist.BossCard:CursorToCanvas()
        target.x, target.y = x, y
    end)

    -- Wheeling the boss turns it. Five degree steps are fine enough to line a
    -- cone up on a wall and coarse enough to hit a cardinal direction.
    token:SetScript("OnMouseWheel", function(self_, delta)
        if not designer:IsActive() or self_.designerKind ~= "boss" then return end
        local card = currentCard()
        if not card then return end

        if designer.editing == "after" then
            card.move = card.move or {}
            card.move.boss = card.move.boss or { facing = card.boss.facing or 180 }
            card.move.boss.facing = (card.move.boss.facing + delta * 5) % 360
        else
            card.boss.facing = ((card.boss.facing or 180) + delta * 5) % 360
        end
        designer:RefreshReadout()
    end)
end

-- Called every frame while the card is up, so tokens become handles the moment
-- designer mode is switched on and stop being them the moment it is off.
function designer:SyncHandles(card)
    local bcard = TankAssist.BossCard
    local canvas = bcard.frame and bcard.frame.canvas
    if not canvas then return end

    local active = self:IsActive()

    self:MakeDraggable(canvas.boss, "boss")
    self:MakeDraggable(canvas.tank, "tank")
    for index, token in ipairs(canvas.group) do
        self:MakeDraggable(token, "group", index)
    end

    for _, token in ipairs({ canvas.boss, canvas.tank }) do
        token:EnableMouse(active)
        token:EnableMouseWheel(active)
    end
    for _, token in ipairs(canvas.group) do
        token:EnableMouse(active)
    end
end

----------------------------------------------------------------------------
-- Serialisation
--
-- Emits a Lua literal to paste straight into data/BossCards.lua. A copyable
-- block beats a saved-variable blob here: the cards belong in the repo where
-- they can be reviewed and diffed, not in someone's WTF folder.
----------------------------------------------------------------------------

local function num(value)
    return string.format("%.3f", value or 0)
end

local function serialisePoint(point, indent)
    return string.format("%s{ x = %s, y = %s }", indent, num(point.x), num(point.y))
end

function designer:Serialise()
    local bcard = TankAssist.BossCard
    local state = bcard.state
    local card = currentCard()
    if not card then return "-- nothing selected" end

    local ability
    for _, entry in ipairs(state.abilities) do
        if entry.spellID == card.spellID then ability = entry break end
    end

    local out = {}
    local function add(line) out[#out + 1] = line end

    add(string.format("[%d] = {   -- %s", state.encounterID or 0, tostring(state.bossName)))
    add("    abilities = {")
    add("        {")
    add(string.format("            spellID = %d,   -- %s",
        card.spellID or 0, tostring(ability and ability.name or "?")))
    add(string.format("            verdict = %q,", card.verdict or "NONE"))
    add(string.format("            buster  = %q,", card.buster or "NONE"))

    if card.cone then
        add(string.format("            cone    = { width = %d, reach = %s },",
            card.cone.width or 90, num(card.cone.reach or 0.44)))
    end

    add(string.format("            boss    = { x = %s, y = %s, facing = %d },",
        num(card.boss.x), num(card.boss.y), math.floor((card.boss.facing or 180) + 0.5)))
    add(string.format("            tank    = %s,", serialisePoint(card.tank, ""):gsub("^%s+", "")))

    if card.group and #card.group > 0 then
        add("            group   = {")
        for _, member in ipairs(card.group) do
            add(string.format("                { role = %q, x = %s, y = %s },",
                member.role or "DAMAGER", num(member.x), num(member.y)))
        end
        add("            },")
    end

    if card.walls and #card.walls > 0 then
        add("            walls   = {")
        for _, wall in ipairs(card.walls) do
            add(string.format("                { %s, %s, %s, %s },",
                num(wall[1]), num(wall[2]), num(wall[3]), num(wall[4])))
        end
        add("            },")
    end

    if card.move then
        add("            move    = {")
        if card.move.boss and card.move.boss.facing then
            add(string.format("                boss  = { facing = %d },",
                math.floor(card.move.boss.facing + 0.5)))
        end
        if card.move.tank then
            add(string.format("                tank  = { x = %s, y = %s },",
                num(card.move.tank.x), num(card.move.tank.y)))
        end
        if card.move.group then
            add("                group = {")
            for index, member in pairs(card.move.group) do
                add(string.format("                    [%d] = { x = %s, y = %s },",
                    index, num(member.x), num(member.y)))
            end
            add("                },")
        end
        add("            },")
    end

    add("        },")
    add("    },")
    add("},")

    return table.concat(out, "\n")
end

----------------------------------------------------------------------------
-- Palette
----------------------------------------------------------------------------

local function makeButton(parent, label, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 20)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    return button
end

function designer:BuildPalette()
    if self.panel then return self.panel end

    local COLOR = TankAssist.BossCard.COLOR

    local panel = CreateFrame("Frame", "TankAssistBossCardDesigner", UIParent, "BackdropTemplate")
    panel:SetSize(228, 330)
    panel:SetPoint("CENTER", UIParent, "CENTER", 420, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(0.04, 0.05, 0.07, 0.97)
    panel:SetBackdropBorderColor(unpack(COLOR.accent))

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetText("Tank card designer")
    title:SetTextColor(unpack(COLOR.accent))

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 1, 1)
    close:SetScript("OnClick", function() designer:SetActive(false) end)

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetWidth(206)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(unpack(COLOR.dim))
    hint:SetText("Drag the tokens. Wheel the boss to turn it.")

    -- Before/After decides which end of the animation the drags land on.
    panel.stateButton = makeButton(panel, "Editing: Before", 206, function()
        designer.editing = (designer.editing == "before") and "after" or "before"
        designer:RefreshReadout()
    end)
    panel.stateButton:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)

    panel.verdictButton = makeButton(panel, "Verdict", 206, function()
        local card = currentCard()
        if not card then return end
        card.verdict = nextIn(VERDICT_ORDER, card.verdict)
        designer:RefreshReadout()
        TankAssist.BossCard:SelectAbility(TankAssist.BossCard.state.selectedIndex)
    end)
    panel.verdictButton:SetPoint("TOPLEFT", panel.stateButton, "BOTTOMLEFT", 0, -4)

    panel.busterButton = makeButton(panel, "Buster", 206, function()
        local card = currentCard()
        if not card then return end
        card.buster = nextIn(BUSTER_ORDER, card.buster)
        designer:RefreshReadout()
        TankAssist.BossCard:Render(card)
    end)
    panel.busterButton:SetPoint("TOPLEFT", panel.verdictButton, "BOTTOMLEFT", 0, -4)

    panel.coneButton = makeButton(panel, "Cone", 100, function()
        local card = currentCard()
        if not card then return end
        if not card.cone then
            card.cone = { width = 90, reach = 0.44 }
        else
            card.cone.width = nextIn(CONE_WIDTHS, card.cone.width)
        end
        designer:RefreshReadout()
        TankAssist.BossCard:Render(card)
    end)
    panel.coneButton:SetPoint("TOPLEFT", panel.busterButton, "BOTTOMLEFT", 0, -4)

    panel.coneOffButton = makeButton(panel, "No cone", 100, function()
        local card = currentCard()
        if not card then return end
        card.cone = nil
        designer:RefreshReadout()
        TankAssist.BossCard:Render(card)
    end)
    panel.coneOffButton:SetPoint("LEFT", panel.coneButton, "RIGHT", 6, 0)

    panel.addButton = makeButton(panel, "Add member", 100, function()
        local card = currentCard()
        if not card then return end
        card.group = card.group or {}
        if #card.group >= 4 then return end
        card.group[#card.group + 1] = { role = "DAMAGER", x = 0.5, y = 0.85 }
        TankAssist.BossCard:Render(card)
        designer:RefreshReadout()
    end)
    panel.addButton:SetPoint("TOPLEFT", panel.coneButton, "BOTTOMLEFT", 0, -4)

    panel.removeButton = makeButton(panel, "Remove", 100, function()
        local card = currentCard()
        if not card or not card.group or #card.group == 0 then return end
        card.group[#card.group] = nil
        if card.move and card.move.group then card.move.group[#card.group + 1] = nil end
        TankAssist.BossCard:Render(card)
        designer:RefreshReadout()
    end)
    panel.removeButton:SetPoint("LEFT", panel.addButton, "RIGHT", 6, 0)

    panel.roleButton = makeButton(panel, "Last member role", 206, function()
        local card = currentCard()
        if not card or not card.group or #card.group == 0 then return end
        local member = card.group[#card.group]
        member.role = nextIn(ROLE_ORDER, member.role)
        TankAssist.BossCard:Render(card)
        designer:RefreshReadout()
    end)
    panel.roleButton:SetPoint("TOPLEFT", panel.addButton, "BOTTOMLEFT", 0, -4)

    panel.wallButton = makeButton(panel, "Add wall", 100, function()
        local card = currentCard()
        if not card then return end
        card.walls = card.walls or {}
        card.walls[#card.walls + 1] = { 0.08, 0.12, 0.92, 0.12 }
        TankAssist.BossCard:Render(card)
    end)
    panel.wallButton:SetPoint("TOPLEFT", panel.roleButton, "BOTTOMLEFT", 0, -4)

    panel.clearWallsButton = makeButton(panel, "Clear walls", 100, function()
        local card = currentCard()
        if not card then return end
        card.walls = {}
        TankAssist.BossCard:Render(card)
    end)
    panel.clearWallsButton:SetPoint("LEFT", panel.wallButton, "RIGHT", 6, 0)

    panel.clearMoveButton = makeButton(panel, "Clear 'after' state", 206, function()
        local card = currentCard()
        if not card then return end
        card.move = nil
        designer.editing = "before"
        designer:RefreshReadout()
    end)
    panel.clearMoveButton:SetPoint("TOPLEFT", panel.wallButton, "BOTTOMLEFT", 0, -4)

    panel.exportButton = makeButton(panel, "Export", 206, function()
        designer:ShowExport()
    end)
    panel.exportButton:SetPoint("TOPLEFT", panel.clearMoveButton, "BOTTOMLEFT", 0, -8)

    panel.readout = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.readout:SetPoint("TOPLEFT", panel.exportButton, "BOTTOMLEFT", 0, -8)
    panel.readout:SetWidth(206)
    panel.readout:SetJustifyH("LEFT")
    panel.readout:SetTextColor(unpack(COLOR.dim))

    panel:Hide()
    self.panel = panel
    return panel
end

function designer:RefreshReadout()
    local panel = self.panel
    if not panel then return end

    local card = currentCard()
    panel.stateButton:SetText(self.editing == "after" and "Editing: After" or "Editing: Before")

    if not card then
        panel.verdictButton:SetText("Verdict: -")
        panel.busterButton:SetText("Buster: -")
        panel.coneButton:SetText("Cone: -")
        panel.readout:SetText("Pick a boss ability in the card.")
        return
    end

    panel.verdictButton:SetText("Verdict: " .. tostring(card.verdict))
    panel.busterButton:SetText("Buster: " .. tostring(card.buster))
    panel.coneButton:SetText(card.cone and ("Cone: " .. tostring(card.cone.width)) or "Cone: off")
    panel.roleButton:SetText(card.group and #card.group > 0
        and ("Last role: " .. tostring(card.group[#card.group].role))
        or "Last role: -")

    panel.readout:SetText(string.format(
        "boss %.2f, %.2f  facing %d\ntank %.2f, %.2f\n%d in group%s",
        card.boss.x or 0, card.boss.y or 0, card.boss.facing or 0,
        card.tank.x or 0, card.tank.y or 0,
        card.group and #card.group or 0,
        card.move and "\nhas an 'after' state" or ""))
end

function designer:ShowExport()
    if not self.exportFrame then
        local frame = CreateFrame("Frame", "TankAssistBossCardExport", UIParent, "BackdropTemplate")
        frame:SetSize(460, 380)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        frame:SetBackdropColor(0.04, 0.05, 0.07, 0.98)
        frame:SetBackdropBorderColor(unpack(TankAssist.BossCard.COLOR.accent))

        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("Paste this into data/BossCards.lua")

        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 1, 1)

        local scroll = CreateFrame("ScrollFrame", "TankAssistBossCardExportScroll", frame,
            "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -34)
        scroll:SetPoint("BOTTOMRIGHT", -30, 12)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(400)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function(self_) self_:ClearFocus() end)
        scroll:SetScrollChild(edit)

        frame.edit = edit
        self.exportFrame = frame
    end

    self.exportFrame.edit:SetText(self:Serialise())
    self.exportFrame.edit:HighlightText()
    self.exportFrame.edit:SetFocus()
    self.exportFrame:Show()
end

----------------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------------

function designer:Attach(bcard)
    self.card = bcard
end

function designer:OnAbilityChanged()
    self:RefreshReadout()
end

function designer:SetActive(active)
    self.active = active and true or false

    local bcard = TankAssist.BossCard
    if self.active then
        self:BuildPalette()
        self.panel:Show()
        self:RefreshReadout()
        bcard:RefreshInfoButton()
        -- Designer mode is for authoring the card that does not exist yet, so
        -- an ability with no card gets a template rather than the empty state.
        if bcard.state.selectedIndex then
            bcard:SelectAbility(bcard.state.selectedIndex)
        end
    else
        if self.panel then self.panel:Hide() end
        if self.exportFrame then self.exportFrame:Hide() end
        if bcard.frame and bcard.frame.canvas then
            self:SyncHandles(bcard.state.ability)
        end
        bcard:RefreshInfoButton()
    end

    local addon = TankAssist.Addon
    local message = "Tank card designer " .. (self.active and "on" or "off") .. "."
    if addon then addon:Print(message) else print(message) end
end

function designer:Toggle()
    self:SetActive(not self.active)
end
