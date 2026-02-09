-- TankAssist Guardian Druid Module

local ADDON_NAME, TA = ...

local GuardianDruid = TA.SpecBase:New(104, "Guardian Druid")

local SPELLS = TA.Constants.GUARDIAN_DRUID.SPELLS
local BUFFS = TA.Constants.GUARDIAN_DRUID.BUFFS
local THRESHOLDS = TA.Constants.GUARDIAN_DRUID.THRESHOLDS

-- =============================================================================
-- SECONDARY SPELLS
-- =============================================================================

GuardianDruid.secondarySpells = {
    -- EMERGENCY: Survival Instincts at critical health
    {
        spellId = SPELLS.SURVIVAL_INSTINCTS,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.30)
        end,
    },

    -- HEAL: Frenzied Regeneration when low health
    {
        spellId = SPELLS.FRENZIED_REGENERATION,
        category = "HEAL",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.60)
        end,
    },

    -- MITIGATION: Ironfur maintenance (no cooldown, just rage cost)
    -- Note: Resource check is handled by CanCastSpell/IsSpellUsable before condition runs
    {
        spellId = SPELLS.IRONFUR,
        category = "MITIGATION",
        urgency = "HIGH",
        condition = function(self)
            -- CanCastSpell already verified we have enough rage via IsSpellUsable
            -- Just check if we're in a situation where we'd want to use it
            return self:InCombat() or self:HasTarget()
        end,
    },

    -- DEFENSIVE: Barkskin when taking damage
    {
        spellId = SPELLS.BARKSKIN,
        category = "DEFENSIVE",
        urgency = "HIGH",
        condition = function(self)
            return self:HealthBelow(0.50)
        end,
    },

    -- DEFENSIVE: Rage of the Sleeper (if talented)
    {
        spellId = SPELLS.RAGE_OF_THE_SLEEPER,
        category = "DEFENSIVE",
        urgency = "HIGH",
        condition = function(self)
            return self:HealthBelow(0.40) and self:InCombat()
        end,
    },

    -- OFFENSIVE: Incarnation/Berserk
    {
        spellId = SPELLS.INCARNATION_GUARDIAN,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },

    {
        spellId = SPELLS.BERSERK,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            if not self:HasTarget() or not self:InCombat() then
                return false
            end
            -- If Incarnation is also "known", it means Incarnation replaced Berserk
            -- In that case, don't show Berserk (Incarnation entry will handle it)
            if IsPlayerSpell(SPELLS.INCARNATION_GUARDIAN) then
                return false
            end
            return true
        end,
    },

    -- OFFENSIVE: Convoke the Spirits (if talented)
    {
        spellId = SPELLS.CONVOKE_THE_SPIRITS,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- AOE: Thrash (6s cooldown)
    {
        spellId = SPELLS.THRASH,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },

    -- FILLER: Mangle (6s cooldown)
    {
        spellId = SPELLS.MANGLE,
        category = "FILLER",
        urgency = "LOW",
        condition = function(self)
            return self:HasTarget()
        end,
    },

    -- FILLER: Maul (rage dump, 3s CD)
    -- Note: We can't check exact rage during combat due to secret values
    -- So we just recommend it if castable (has enough rage) and has target
    {
        spellId = SPELLS.MAUL,
        category = "FILLER",
        urgency = "LOW",
        condition = function(self)
            -- CanCastSpell already verified we have enough rage
            return self:HasTarget()
        end,
    },
}

-- Legacy: AoE spells in priority order
GuardianDruid.aoeSpells = {
    {
        spellId = SPELLS.THRASH,
        priority = 1,
        condition = function() return true end,
    },
    {
        spellId = SPELLS.SWIPE,
        priority = 2,
        condition = function() return true end,
    },
}

function GuardianDruid:GetBestAoESpell()
    for _, aoeData in ipairs(self.aoeSpells) do
        local spellId = aoeData.spellId
        if spellId and IsSpellKnown(spellId) then
            local cdInfo = TA.SecretValues:GetCooldownInfo(spellId)
            local isReady = not cdInfo.onCooldown or (cdInfo.charges and cdInfo.charges > 0)
            local conditionMet = not aoeData.condition or aoeData.condition()
            if isReady and conditionMet then
                return spellId
            end
        end
    end
    return nil
end

-- =============================================================================
-- TRACKED BUFFS
-- =============================================================================

GuardianDruid.buffsToTrack = {
    {
        spellId = BUFFS.IRONFUR,
        name = "Ironfur",
        refreshSpell = SPELLS.IRONFUR,
        minStacks = THRESHOLDS.IRONFUR_MIN_STACKS,
        refreshThreshold = THRESHOLDS.IRONFUR_REFRESH,
        priority = "CRITICAL",
    },
    {
        spellId = BUFFS.FRENZIED_REGENERATION,
        name = "Frenzied Regen",
        refreshSpell = SPELLS.FRENZIED_REGENERATION,
        refreshThreshold = 0,
        priority = "HIGH",
    },
    {
        spellId = BUFFS.BARKSKIN,
        name = "Barkskin",
        refreshSpell = SPELLS.BARKSKIN,
        refreshThreshold = 0,
        priority = "HIGH",
    },
}

-- =============================================================================
-- TANK ACTIONS (for TankActionsDisplay)
-- =============================================================================

GuardianDruid.tankActions = {
    MITIGATION = {
        spellId = SPELLS.IRONFUR,
        name = "Ironfur",
        condition = function()
            local buffInfo = TA.SecretValues:GetBuffInfo("player", TA.Constants.GUARDIAN_DRUID.BUFFS.IRONFUR)
            if not buffInfo.exists then return true end
            return buffInfo.stacks and buffInfo.stacks < 2
        end,
    },
    SHIELD = {
        spellId = SPELLS.FRENZIED_REGENERATION,
        name = "Frenzied Regeneration",
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.7
        end,
    },
    DEFENSIVE = {
        spellId = SPELLS.SURVIVAL_INSTINCTS,
        name = "Survival Instincts",
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.4
        end,
    },
    HEAL = {
        spellId = SPELLS.FRENZIED_REGENERATION,
        name = "Frenzied Regeneration",
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.5
        end,
    },
}

-- =============================================================================
-- TRACKED COOLDOWNS
-- =============================================================================

GuardianDruid.cooldownsToTrack = {
    { spellId = SPELLS.INCARNATION_GUARDIAN, name = "Incarnation", category = "MAJOR" },
    { spellId = SPELLS.BERSERK, name = "Berserk", category = "MAJOR" },
    { spellId = SPELLS.CONVOKE_THE_SPIRITS, name = "Convoke", category = "MAJOR" },
    { spellId = SPELLS.BARKSKIN, name = "Barkskin", category = "DEFENSIVE" },
    { spellId = SPELLS.SURVIVAL_INSTINCTS, name = "Survival Instincts", category = "DEFENSIVE" },
    { spellId = SPELLS.RAGE_OF_THE_SLEEPER, name = "Rage of the Sleeper", category = "DEFENSIVE" },
    { spellId = SPELLS.BRISTLING_FUR, name = "Bristling Fur", category = "OFFENSIVE" },
}

-- =============================================================================
-- ROTATION PRIORITY
-- =============================================================================

GuardianDruid.rotationPriority = {
    -- 1. Frenzied Regeneration when low HP
    {
        spellId = SPELLS.FRENZIED_REGENERATION,
        defaultPriority = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < THRESHOLDS.FRENZIED_REGEN_HP then
                local cdInfo = TA.SecretValues:GetCooldownInfo(SPELLS.FRENZIED_REGENERATION)
                if cdInfo.charges and cdInfo.charges >= 1 then
                    return true, "URGENT", "Heal up!"
                end
            end
            return false
        end,
    },

    -- 2. Ironfur maintenance
    -- Note: Resource check is handled by EvaluatePriorityEntry/CanCastSpell
    {
        spellId = SPELLS.IRONFUR,
        defaultPriority = "HIGH",
        condition = function(self)
            local needsRefresh, reason = self:BuffNeedsRefresh(
                BUFFS.IRONFUR,
                THRESHOLDS.IRONFUR_REFRESH,
                THRESHOLDS.IRONFUR_MIN_STACKS
            )

            if needsRefresh then
                -- CanCastSpell already verified we have enough rage
                if reason == "DOWN" then
                    return true, "URGENT", "Ironfur DOWN!"
                else
                    return true, "HIGH", "Stack Ironfur"
                end
            end
            return false
        end,
    },

    -- 3. Mangle (with Gore proc or on CD)
    {
        spellId = SPELLS.MANGLE,
        defaultPriority = "HIGH",
        condition = function(self)
            -- Check for Gore proc (instant reset)
            local goreInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.GORE)
            if goreInfo.exists then
                return true, "HIGH", "Gore proc!"
            end

            local usable = TA.SecretValues:IsSpellUsable(SPELLS.MANGLE)
            return usable == true, "NORMAL", nil
        end,
    },

    -- 4. Thrash (maintain DoT)
    {
        spellId = SPELLS.THRASH,
        defaultPriority = "NORMAL",
        condition = function(self)
            local usable = TA.SecretValues:IsSpellUsable(SPELLS.THRASH)
            return usable == true, "NORMAL", nil
        end,
    },

    -- 5. Moonfire (Galactic Guardian proc)
    {
        spellId = SPELLS.MOONFIRE,
        defaultPriority = "NORMAL",
        condition = function(self)
            local procInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.GALACTIC_GUARDIAN)
            if procInfo.exists then
                return true, "HIGH", "Free Moonfire!"
            end
            return false
        end,
    },

    -- 6. Maul (with Tooth and Claw proc)
    -- Note: Can't reliably check "excess rage" during combat due to secret values
    {
        spellId = SPELLS.MAUL,
        defaultPriority = "NORMAL",
        condition = function(self)
            local procInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.TOOTH_AND_CLAW)
            if procInfo.exists then
                return true, "HIGH", "Free Maul!"
            end
            -- Without the proc, don't recommend (Ironfur is better use of rage)
            return false
        end,
    },

    -- 7. Swipe (filler)
    {
        spellId = SPELLS.SWIPE,
        defaultPriority = "NORMAL",
        condition = function(self)
            local enemies = self:GetEnemyCount()
            if enemies >= 2 then
                return true, "NORMAL", nil
            end
            return false
        end,
    },
}

-- =============================================================================
-- REGISTER MODULE
-- =============================================================================

GuardianDruid:Register()
TA.GuardianDruid = GuardianDruid
