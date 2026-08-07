local ADDON_NAME, TankAssist = ...

-- Proc glow rules.
--
-- A curated, data-driven table of tank procs that read cleanly under Secret
-- Values. Each rule says: glow the recommended ability `spell` while any of the
-- listed `procs` auras is present on the player. Aura *presence* is not a Secret
-- Value (only its stacks/duration/expiration can be), so `GetBuffInfo().exists`
-- is a reliable signal even when the rest of the aura is hidden.
--
-- Blizzard's own activation overlays (Revenge!, Grand Crusader, Sudden Death,
-- ...) are handled generically by the display via C_SpellActivationOverlay, so
-- this table only needs to cover procs worth highlighting that the display shows
-- as a recommendation. A class/spec with no entry simply glows nothing.
--
-- Keyed by specialization id. Spell/aura ids are reused from the spec Constants
-- so there is a single source of truth for each number.

TankAssist.ProcRules = {}
local ProcRules = TankAssist.ProcRules

-- specId -> { { spell = <recommended spellId>, procs = { <auraId>, ... } }, ... }
ProcRules.data = {
    -- Blood Death Knight: Crimson Scourge -> free Death and Decay.
    [250] = {
        { spell = 43265, procs = { 81141 } },
    },
    -- Protection Warrior: Revenge! -> free Revenge.
    [73] = {
        { spell = 6572, procs = { 5302 } },
    },
    -- Protection Paladin: Grand Crusader -> Avenger's Shield reset.
    [66] = {
        { spell = 31935, procs = { 85416 } },
    },
    -- Guardian Druid: Gore / Galactic Guardian -> free Mangle.
    [104] = {
        { spell = 33917, procs = { 93622, 213708 } },
    },
}

-- True when a rule for this spec/spell has one of its proc auras active.
function ProcRules:IsProcActive(specId, spellId)
    if not specId or not spellId then
        return false
    end
    local rules = self.data[specId]
    if not rules then
        return false
    end
    local sv = TankAssist.SecretValues
    if not sv then
        return false
    end
    for _, rule in ipairs(rules) do
        if rule.spell == spellId then
            for _, buffId in ipairs(rule.procs) do
                local info = sv:GetBuffInfo("player", buffId)
                if info and info.exists then
                    return true
                end
            end
        end
    end
    return false
end
