-- Boss card data -- see https://github.com/fooxytv/TankAssist/issues/38
--
-- One entry per encounter, one card per ability that a tank has to do something
-- about. Abilities a tank can ignore are deliberately absent: the point of this
-- is that it is shorter than a guide, not that it is complete.
--
-- Nothing here is text the player reads. Ability names and icons come from the
-- client and arrive already localised, so a card works in every language
-- without a single translated string. What is stored is geometry and verdicts.
--
-- Authored with the in-game designer rather than by hand:
--
--     /ta bosscard design
--
-- Drag the tokens where they belong, set the verdict, hit Export, paste the
-- block it gives you in here. Hand-editing coordinates without seeing them is
-- how the first pass ended up looking wrong.
--
-- Schema
-- ------
-- [journalEncounterID] = {
--     abilities = {
--         {
--             spellID = 12345,        -- name and icon resolved from the client
--             verdict = "AWAY",       -- AWAY | SOAK | DODGE | STACK | NONE
--             buster  = "MAJOR",      -- MAJOR | PERSONAL | NONE
--             cone    = { width = 90, reach = 0.44 },   -- omit for no frontal
--             boss    = { x = 0.5, y = 0.42, facing = 180 },
--             tank    = { x = 0.5, y = 0.62 },
--             group   = { { role = "HEALER", x = .., y = .. }, ... },
--             walls   = { { x1, y1, x2, y2 }, ... },
--             -- Optional second position. Present means "the tank does this":
--             -- the card animates from the first state to this one on a loop.
--             move    = {
--                 boss  = { facing = 0 },
--                 tank  = { x = 0.5, y = 0.24 },
--                 group = { [1] = { x = .., y = .. } },
--             },
--         },
--     },
-- }
--
-- Coordinates are 0..1 across the diagram with the origin top-left, so a card
-- renders identically at any panel size. Facing is degrees clockwise from up.

local ADDON_NAME, TankAssist = ...

TankAssist.BossCards = {}

-- Verdicts decide the cone's colour and the glyph shown, so that a card is read
-- rather than decoded. Kept here rather than in the renderer because the
-- designer offers them as choices and the data references them by name.
TankAssist.BossCards.VERDICTS = {
    AWAY  = { label = "Turn it away",     tone = "danger", hint = "Group must not be in the frontal" },
    SOAK  = { label = "Soak it together", tone = "safe",   hint = "Frontal splits -- everyone stands in it" },
    DODGE = { label = "Move out",         tone = "danger", hint = "Nobody stands in it, including you" },
    STACK = { label = "Stack up",         tone = "safe",   hint = "Everyone on the tank" },
    NONE  = { label = "Nothing to do",    tone = "neutral", hint = "No tank action required" },
}

TankAssist.BossCards.BUSTERS = {
    MAJOR    = { label = "Major cooldown" },
    PERSONAL = { label = "Personal" },
    NONE     = { label = "No cooldown needed" },
}

-- Authored cards. Empty until somebody sits down with the designer and a
-- dungeon; the card only offers itself on encounters that appear here.
TankAssist.BossCards.data = {
}

-- Two worked examples, used when the designer is open on an encounter that has
-- no card yet. They are starting geometry to drag around, not boss data -- so
-- they live apart from `data` and are never offered as if they were real.
TankAssist.BossCards.TEMPLATES = {
    {
        key     = "away",
        label   = "Turn it away",
        verdict = "AWAY",
        buster  = "MAJOR",
        cone    = { width = 90, reach = 0.44 },
        walls   = { { 0.06, 0.10, 0.94, 0.10 } },
        boss    = { x = 0.50, y = 0.42, facing = 180 },
        tank    = { x = 0.50, y = 0.62 },
        group   = {
            { role = "HEALER",  x = 0.34, y = 0.80 },
            { role = "DAMAGER", x = 0.46, y = 0.84 },
            { role = "DAMAGER", x = 0.58, y = 0.80 },
            { role = "DAMAGER", x = 0.50, y = 0.72 },
        },
        move    = {
            boss = { facing = 0 },
            tank = { x = 0.50, y = 0.24 },
        },
    },
    {
        key     = "soak",
        label   = "Soak it together",
        verdict = "SOAK",
        buster  = "PERSONAL",
        cone    = { width = 90, reach = 0.44 },
        walls   = {},
        boss    = { x = 0.50, y = 0.34, facing = 180 },
        tank    = { x = 0.50, y = 0.58 },
        group   = {
            { role = "HEALER",  x = 0.20, y = 0.86 },
            { role = "DAMAGER", x = 0.44, y = 0.92 },
            { role = "DAMAGER", x = 0.78, y = 0.86 },
            { role = "DAMAGER", x = 0.84, y = 0.62 },
        },
        move    = {
            group = {
                [1] = { x = 0.40, y = 0.66 },
                [2] = { x = 0.50, y = 0.70 },
                [3] = { x = 0.60, y = 0.66 },
                [4] = { x = 0.55, y = 0.62 },
            },
        },
    },
}

function TankAssist.BossCards:Get(encounterID)
    return self.data[encounterID]
end

function TankAssist.BossCards:HasCard(encounterID)
    local entry = self.data[encounterID]
    return entry ~= nil and entry.abilities ~= nil and #entry.abilities > 0
end

function TankAssist.BossCards:GetAbility(encounterID, spellID)
    local entry = self.data[encounterID]
    if not entry or not entry.abilities then return nil end
    for _, ability in ipairs(entry.abilities) do
        if ability.spellID == spellID then return ability end
    end
    return nil
end
