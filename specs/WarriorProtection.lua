-- TankAssist Protection Warrior Module
-- Stub implementation - expand based on Blood DK/Brewmaster patterns

local ADDON_NAME, TA = ...

local ProtWarrior = TA.SpecBase:New(73, "Protection Warrior")

local SPELLS = TA.Constants.PROTECTION_WARRIOR.SPELLS
local BUFFS = TA.Constants.PROTECTION_WARRIOR.BUFFS
local THRESHOLDS = TA.Constants.PROTECTION_WARRIOR.THRESHOLDS

-- =============================================================================
-- SECONDARY SPELLS (unified system - uses CanCastSpell for proper cooldown/charge tracking)
-- =============================================================================

ProtWarrior.secondarySpells = {
    -- EMERGENCY: Shield Wall at critical health
    {
        spellId = SPELLS.SHIELD_WALL,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.30)
        end,
    },

    -- EMERGENCY: Last Stand when very low
    {
        spellId = SPELLS.LAST_STAND,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.35)
        end,
    },

    -- MITIGATION: Shield Block maintenance (charge-based)
    {
        spellId = SPELLS.SHIELD_BLOCK,
        category = "MITIGATION",
        urgency = "HIGH",
        condition = function(self)
            local buffInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.SHIELD_BLOCK)
            if not buffInfo.exists then
                return true
            end
            -- Refresh if expiring soon
            local remaining = buffInfo.expirationTime and (buffInfo.expirationTime - GetTime()) or 0
            return remaining < 2
        end,
    },

    -- SHIELD: Ignore Pain when health drops
    {
        spellId = SPELLS.IGNORE_PAIN,
        category = "SHIELD",
        urgency = "HIGH",
        condition = function(self)
            local rage = self:GetResource("RAGE")
            return self:HealthBelow(0.60) and rage and rage >= 40
        end,
    },

    -- DEFENSIVE: Demoralizing Shout
    {
        spellId = SPELLS.DEMORALIZING_SHOUT,
        category = "DEFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HealthBelow(0.50) and self:HasTarget()
        end,
    },

    -- DEFENSIVE: Spell Reflection
    {
        spellId = SPELLS.SPELL_REFLECTION,
        category = "DEFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            -- Could check for incoming spell casts in the future
            return self:HasTarget()
        end,
    },

    -- AOE: Thunder Clap
    {
        spellId = SPELLS.THUNDER_CLAP,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },

    -- AOE: Revenge with proc (free!)
    {
        spellId = SPELLS.REVENGE,
        category = "AOE",
        urgency = "HIGH",
        condition = function(self)
            local procInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.REVENGE_PROC)
            return procInfo.exists
        end,
    },

    -- AOE: Shockwave (if talented)
    {
        spellId = SPELLS.SHOCKWAVE,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },

    -- OFFENSIVE: Avatar
    {
        spellId = SPELLS.AVATAR,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- OFFENSIVE: Ravager (if talented)
    {
        spellId = SPELLS.RAVAGER,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- OFFENSIVE: Thunderous Roar (if talented)
    {
        spellId = SPELLS.THUNDEROUS_ROAR,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- AOE: Revenge (with rage, no proc)
    {
        spellId = SPELLS.REVENGE,
        category = "AOE",
        urgency = "LOW",
        condition = function(self)
            local rage = self:GetResource("RAGE")
            return self:HasTarget() and rage and rage >= 40
        end,
    },

    -- FILLER: Shield Slam
    {
        spellId = SPELLS.SHIELD_SLAM,
        category = "FILLER",
        urgency = "LOW",
        condition = function(self)
            return self:HasTarget()
        end,
    },
}

-- Legacy: Keep aoeSpells for backwards compatibility but it won't be used
ProtWarrior.aoeSpells = {
    {
        spellId = SPELLS.THUNDER_CLAP,
        priority = 1,
        condition = function() return true end,
    },
    {
        spellId = SPELLS.REVENGE,
        priority = 2,
        -- Prioritize when free Revenge proc is up
        condition = function()
            local procInfo = TA.SecretValues:GetBuffInfo("player", TA.Constants.PROTECTION_WARRIOR.BUFFS.REVENGE_PROC)
            return procInfo.exists
        end,
    },
    {
        spellId = SPELLS.SHOCKWAVE,
        priority = 3,
        condition = function()
            return IsSpellKnown(SPELLS.SHOCKWAVE)
        end,
    },
}

function ProtWarrior:GetBestAoESpell()
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
    return SPELLS.THUNDER_CLAP
end


-- =============================================================================
-- TRACKED BUFFS
-- =============================================================================

ProtWarrior.buffsToTrack = {
    {
        spellId = BUFFS.SHIELD_BLOCK,
        name = "Shield Block",
        refreshSpell = SPELLS.SHIELD_BLOCK,
        refreshThreshold = THRESHOLDS.SHIELD_BLOCK_REFRESH,
        priority = "CRITICAL",
    },
    {
        -- Ignore Pain: absorb shield
        -- Note: Absorb AMOUNT is a secret value and cannot be tracked
        -- We can only track whether the shield EXISTS (up/down)
        spellId = BUFFS.IGNORE_PAIN,
        name = "Ignore Pain",
        refreshSpell = SPELLS.IGNORE_PAIN,
        refreshThreshold = 2,
        priority = "HIGH",
        isAbsorb = true, -- Flag for UI to show as absorb indicator
    },
    {
        spellId = BUFFS.SHIELD_WALL,
        name = "Shield Wall",
        refreshSpell = SPELLS.SHIELD_WALL,
        refreshThreshold = 0,
        priority = "HIGH",
    },
}

-- =============================================================================
-- TANK ACTIONS (for TankActionsDisplay)
-- =============================================================================

ProtWarrior.tankActions = {
    MITIGATION = {
        spellId = SPELLS.SHIELD_BLOCK,
        name = "Shield Block",
        condition = function()
            local buffInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.SHIELD_BLOCK)
            return not buffInfo.exists
        end,
    },
    SHIELD = {
        spellId = SPELLS.IGNORE_PAIN,
        name = "Ignore Pain",
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.7
        end,
    },
    DEFENSIVE = {
        spellId = SPELLS.SHIELD_WALL,
        name = "Shield Wall",
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.4
        end,
    },
    HEAL = {
        spellId = SPELLS.IGNORE_PAIN,
        name = "Ignore Pain",
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.5
        end,
    },
}

-- =============================================================================
-- TRACKED COOLDOWNS
-- =============================================================================

ProtWarrior.cooldownsToTrack = {
    { spellId = SPELLS.AVATAR, name = "Avatar", category = "MAJOR" },
    { spellId = SPELLS.RAVAGER, name = "Ravager", category = "MAJOR" },
    { spellId = SPELLS.CHAMPIONS_SPEAR, name = "Champion's Spear", category = "MAJOR" },
    { spellId = SPELLS.SHIELD_WALL, name = "Shield Wall", category = "DEFENSIVE" },
    { spellId = SPELLS.LAST_STAND, name = "Last Stand", category = "DEFENSIVE" },
    { spellId = SPELLS.SPELL_REFLECTION, name = "Spell Reflection", category = "DEFENSIVE" },
    { spellId = SPELLS.DEMORALIZING_SHOUT, name = "Demoralizing Shout", category = "DEFENSIVE" },
    { spellId = SPELLS.THUNDEROUS_ROAR, name = "Thunderous Roar", category = "OFFENSIVE" },
}

-- =============================================================================
-- ROTATION PRIORITY
-- =============================================================================

ProtWarrior.rotationPriority = {
    -- ==========================================================================
    -- TANK ALERTS (only show when actually needed)
    -- ==========================================================================

    -- 1. Shield Wall (EMERGENCY - very low health)
    {
        spellId = SPELLS.SHIELD_WALL,
        defaultPriority = "URGENT",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.3 then
                local usable = TA.SecretValues:IsSpellUsable(SPELLS.SHIELD_WALL)
                if usable then
                    return true, "URGENT", "EMERGENCY!"
                end
            end
            return false
        end,
    },

    -- 2. Last Stand (EMERGENCY when Shield Wall unavailable)
    {
        spellId = SPELLS.LAST_STAND,
        defaultPriority = "URGENT",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.35 then
                local usable = TA.SecretValues:IsSpellUsable(SPELLS.LAST_STAND)
                if usable then
                    return true, "URGENT", "EMERGENCY!"
                end
            end
            return false
        end,
    },

    -- 3. Ignore Pain (when taking damage and health drops)
    {
        spellId = SPELLS.IGNORE_PAIN,
        defaultPriority = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            local rage = self:GetResource("RAGE")
            if hp and hp < 0.6 and rage and rage >= 40 then
                local usable = TA.SecretValues:IsSpellUsable(SPELLS.IGNORE_PAIN)
                if usable then
                    return true, "HIGH", "Absorb damage!"
                end
            end
            return false
        end,
    },

    -- ==========================================================================
    -- ROTATION PRIORITIES (maintenance and DPS)
    -- ==========================================================================

    -- 4. Shield Block maintenance
    {
        spellId = SPELLS.SHIELD_BLOCK,
        defaultPriority = "HIGH",
        condition = function(self)
            local needsRefresh = self:BuffNeedsRefresh(BUFFS.SHIELD_BLOCK, THRESHOLDS.SHIELD_BLOCK_REFRESH)
            if needsRefresh then
                local rage = self:GetResource("RAGE")
                if rage and rage >= 30 then
                    return true, "HIGH", "Shield Block"
                end
            end
            return false
        end,
    },
    
    -- 2. Shield Slam (main ability)
    {
        spellId = SPELLS.SHIELD_SLAM,
        defaultPriority = "HIGH",
        condition = function(self)
            local usable = TA.SecretValues:IsSpellUsable(SPELLS.SHIELD_SLAM)
            return usable == true, "HIGH", nil
        end,
    },
    
    -- 3. Thunder Clap
    {
        spellId = SPELLS.THUNDER_CLAP,
        defaultPriority = "NORMAL",
        condition = function(self)
            local usable = TA.SecretValues:IsSpellUsable(SPELLS.THUNDER_CLAP)
            return usable == true, "NORMAL", nil
        end,
    },
    
    -- 4. Revenge (proc or high rage)
    {
        spellId = SPELLS.REVENGE,
        defaultPriority = "NORMAL",
        condition = function(self)
            -- Check for free Revenge proc
            local procInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.REVENGE_PROC)
            if procInfo.exists then
                return true, "HIGH", "Free Revenge!"
            end
            
            -- Or use with high rage
            local rage = self:GetResource("RAGE")
            if rage and rage >= 60 then
                return true, "NORMAL", nil
            end
            
            return false
        end,
    },
    
    -- 5. Ignore Pain (absorb management)
    {
        spellId = SPELLS.IGNORE_PAIN,
        defaultPriority = "NORMAL",
        condition = function(self)
            local rage = self:GetResource("RAGE")
            local hp = self:GetHealthPercent()
            
            if rage and rage >= 60 and hp and hp < 0.8 then
                return true, "NORMAL", "Build absorb"
            end
            
            return false
        end,
    },
}

-- =============================================================================
-- REGISTER
-- =============================================================================

ProtWarrior:Register()
TA.ProtWarrior = ProtWarrior
