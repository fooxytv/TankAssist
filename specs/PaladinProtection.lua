-- TankAssist Protection Paladin Module

local ADDON_NAME, TA = ...

local ProtPaladin = TA.SpecBase:New(66, "Protection Paladin")

local SPELLS = TA.Constants.PROTECTION_PALADIN.SPELLS
local BUFFS = TA.Constants.PROTECTION_PALADIN.BUFFS
local THRESHOLDS = TA.Constants.PROTECTION_PALADIN.THRESHOLDS

-- AoE spells in priority order
ProtPaladin.aoeSpells = {
    {
        spellId = SPELLS.AVENGERS_SHIELD,
        priority = 1,
        condition = function() return true end,
    },
    {
        spellId = SPELLS.CONSECRATION,
        priority = 2,
        -- Use when Consecration buff is down
        condition = function()
            local buffInfo = TA.SecretValues:GetBuffInfo("player", TA.Constants.PROTECTION_PALADIN.BUFFS.CONSECRATION)
            return not buffInfo.exists
        end,
    },
    {
        spellId = SPELLS.HAMMER_OF_THE_RIGHTEOUS,
        priority = 3,
        condition = function() return true end,
    },
}

function ProtPaladin:GetBestAoESpell()
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
    return SPELLS.CONSECRATION
end

-- =============================================================================
-- SECONDARY SPELLS (unified system like Brewmaster)
-- Ordered by priority - first match wins
-- =============================================================================

ProtPaladin.secondarySpells = {
    -- EMERGENCY: Lay on Hands (full heal, use at very low health)
    {
        spellId = SPELLS.LAY_ON_HANDS,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.20)
        end,
    },

    -- EMERGENCY: Guardian of Ancient Kings
    {
        spellId = SPELLS.GUARDIAN_OF_ANCIENT_KINGS,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.30)
        end,
    },

    -- EMERGENCY: Ardent Defender
    {
        spellId = SPELLS.ARDENT_DEFENDER,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.35)
        end,
    },

    -- HEAL: Word of Glory with Shining Light proc (free heal)
    {
        spellId = SPELLS.WORD_OF_GLORY,
        category = "HEAL",
        urgency = "HIGH",
        condition = function(self)
            local procInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.SHINING_LIGHT)
            if procInfo.exists then
                return self:HealthBelow(0.80)
            end
            -- Or emergency heal at low health with Holy Power
            if self:HealthBelow(0.50) then
                local holyPower = self:GetResource("HOLY_POWER")
                return holyPower and holyPower >= 3
            end
            return false
        end,
    },

    -- MITIGATION: Shield of the Righteous (maintain buff)
    {
        spellId = SPELLS.SHIELD_OF_THE_RIGHTEOUS,
        category = "MITIGATION",
        urgency = "HIGH",
        condition = function(self)
            local holyPower = self:GetResource("HOLY_POWER")
            if not holyPower or holyPower < 3 then
                return false
            end
            -- Check if buff is down or expiring
            local buffInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.SHIELD_OF_THE_RIGHTEOUS)
            if not buffInfo.exists then
                return true
            end
            -- Refresh if less than 3 seconds remaining
            local remaining = (buffInfo.expirationTime or 0) - GetTime()
            return remaining < 3
        end,
    },

    -- OFFENSIVE: Avenging Wrath (major CD)
    {
        spellId = SPELLS.AVENGING_WRATH,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- OFFENSIVE: Divine Toll (big AoE damage + Holy Power)
    {
        spellId = SPELLS.DIVINE_TOLL,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- OFFENSIVE: Eye of Tyr (if talented)
    {
        spellId = SPELLS.EYE_OF_TYR,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- OFFENSIVE: Sentinel (if talented)
    {
        spellId = SPELLS.SENTINEL,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- AOE: Avenger's Shield (15s CD, high priority)
    {
        spellId = SPELLS.AVENGERS_SHIELD,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },

    -- AOE: Judgment (6s CD, generates Holy Power)
    {
        spellId = SPELLS.JUDGMENT,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },

    -- AOE: Consecration (maintain buff)
    {
        spellId = SPELLS.CONSECRATION,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            if not self:HasTarget() then
                return false
            end
            local buffInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.CONSECRATION)
            return not buffInfo.exists
        end,
    },

    -- FILLER: Hammer of the Righteous
    {
        spellId = SPELLS.HAMMER_OF_THE_RIGHTEOUS,
        category = "FILLER",
        urgency = "LOW",
        condition = function(self)
            return self:HasTarget()
        end,
    },
}

ProtPaladin.buffsToTrack = {
    {
        spellId = BUFFS.SHIELD_OF_THE_RIGHTEOUS,
        name = "Shield of the Righteous",
        refreshSpell = SPELLS.SHIELD_OF_THE_RIGHTEOUS,
        refreshThreshold = THRESHOLDS.SOTR_REFRESH,
        priority = "CRITICAL",
    },
    {
        spellId = BUFFS.CONSECRATION,
        name = "Consecration",
        refreshSpell = SPELLS.CONSECRATION,
        refreshThreshold = THRESHOLDS.CONSECRATION_REFRESH,
        priority = "HIGH",
    },
    {
        spellId = BUFFS.ARDENT_DEFENDER,
        name = "Ardent Defender",
        refreshThreshold = 0,
        priority = "HIGH",
    },
}

-- =============================================================================
-- TANK ACTIONS (for TankActionsDisplay)
-- =============================================================================

ProtPaladin.tankActions = {
    MITIGATION = {
        spellId = SPELLS.SHIELD_OF_THE_RIGHTEOUS,
        name = "Shield of the Righteous",
        condition = function()
            local buffInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.SHIELD_OF_THE_RIGHTEOUS)
            return not buffInfo.exists
        end,
    },
    SHIELD = {
        spellId = SPELLS.WORD_OF_GLORY,
        name = "Word of Glory",
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.6
        end,
    },
    DEFENSIVE = {
        spellId = SPELLS.ARDENT_DEFENDER,
        name = "Ardent Defender",
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.4
        end,
    },
    HEAL = {
        spellId = SPELLS.WORD_OF_GLORY,
        name = "Word of Glory",
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.5
        end,
    },
}

ProtPaladin.cooldownsToTrack = {
    { spellId = SPELLS.AVENGING_WRATH, name = "Avenging Wrath", category = "MAJOR" },
    { spellId = SPELLS.SENTINEL, name = "Sentinel", category = "MAJOR" },
    { spellId = SPELLS.DIVINE_TOLL, name = "Divine Toll", category = "MAJOR" },
    { spellId = SPELLS.ARDENT_DEFENDER, name = "Ardent Defender", category = "DEFENSIVE" },
    { spellId = SPELLS.GUARDIAN_OF_ANCIENT_KINGS, name = "Guardian of Ancient Kings", category = "DEFENSIVE" },
    { spellId = SPELLS.DIVINE_SHIELD, name = "Divine Shield", category = "DEFENSIVE" },
    { spellId = SPELLS.LAY_ON_HANDS, name = "Lay on Hands", category = "DEFENSIVE" },
    { spellId = SPELLS.EYE_OF_TYR, name = "Eye of Tyr", category = "OFFENSIVE" },
}

ProtPaladin.rotationPriority = {
    -- ==========================================================================
    -- TANK ALERTS (only show when actually needed)
    -- ==========================================================================

    -- 1. Ardent Defender (EMERGENCY - very low health)
    {
        spellId = SPELLS.ARDENT_DEFENDER,
        defaultPriority = "URGENT",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.3 then
                local usable = TA.SecretValues:IsSpellUsable(SPELLS.ARDENT_DEFENDER)
                if usable then
                    return true, "URGENT", "EMERGENCY!"
                end
            end
            return false
        end,
    },

    -- 2. Guardian of Ancient Kings (EMERGENCY)
    {
        spellId = SPELLS.GUARDIAN_OF_ANCIENT_KINGS,
        defaultPriority = "URGENT",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.35 then
                local usable = TA.SecretValues:IsSpellUsable(SPELLS.GUARDIAN_OF_ANCIENT_KINGS)
                if usable then
                    return true, "URGENT", "EMERGENCY!"
                end
            end
            return false
        end,
    },

    -- 3. Word of Glory (self-heal when low HP)
    {
        spellId = SPELLS.WORD_OF_GLORY,
        defaultPriority = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.5 then
                -- Check for free proc first
                local procInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.SHINING_LIGHT)
                if procInfo.exists then
                    return true, "URGENT", "Free heal!"
                end
                -- Or if we have Holy Power and really low
                if hp < 0.4 then
                    local holyPower = self:GetResource("HOLY_POWER")
                    if holyPower and holyPower >= 3 then
                        return true, "HIGH", "Heal yourself!"
                    end
                end
            end
            return false
        end,
    },

    -- ==========================================================================
    -- ROTATION PRIORITIES (maintenance and DPS)
    -- ==========================================================================

    -- 4. Shield of the Righteous maintenance
    {
        spellId = SPELLS.SHIELD_OF_THE_RIGHTEOUS,
        defaultPriority = "HIGH",
        condition = function(self)
            local needsRefresh = self:BuffNeedsRefresh(BUFFS.SHIELD_OF_THE_RIGHTEOUS, THRESHOLDS.SOTR_REFRESH)
            if needsRefresh then
                local hp = self:GetResource("HOLY_POWER")
                if hp and hp >= 3 then
                    return true, "HIGH", "Maintain SotR"
                end
            end
            return false
        end,
    },
    
    -- 3. Judgment (generates HP, reduces SotR cooldown)
    {
        spellId = SPELLS.JUDGMENT,
        defaultPriority = "HIGH",
        condition = function(self)
            local usable = TA.SecretValues:IsSpellUsable(SPELLS.JUDGMENT)
            return usable == true, "HIGH", nil
        end,
    },
    
    -- 4. Avenger's Shield
    {
        spellId = SPELLS.AVENGERS_SHIELD,
        defaultPriority = "NORMAL",
        condition = function(self)
            local usable = TA.SecretValues:IsSpellUsable(SPELLS.AVENGERS_SHIELD)
            return usable == true, "NORMAL", nil
        end,
    },
    
    -- 5. Hammer of the Righteous/Blessed Hammer
    {
        spellId = SPELLS.HAMMER_OF_THE_RIGHTEOUS,
        defaultPriority = "NORMAL",
        condition = function(self)
            local usable = TA.SecretValues:IsSpellUsable(SPELLS.HAMMER_OF_THE_RIGHTEOUS)
            return usable == true, "NORMAL", nil
        end,
    },
    
    -- 6. Consecration (keep active)
    {
        spellId = SPELLS.CONSECRATION,
        defaultPriority = "NORMAL",
        condition = function(self)
            local buffInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.CONSECRATION)
            if not buffInfo.exists or buffInfo.isSecret then
                local usable = TA.SecretValues:IsSpellUsable(SPELLS.CONSECRATION)
                return usable == true, "NORMAL", "Consecration down"
            end
            return false
        end,
    },
}

ProtPaladin:Register()
TA.ProtPaladin = ProtPaladin
