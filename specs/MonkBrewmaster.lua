-- TankAssist Brewmaster Monk Module
-- Complete implementation for Brewmaster tanking

local ADDON_NAME, TA = ...

local Brewmaster = TA.SpecBase:New(268, "Brewmaster Monk")

local SPELLS = TA.Constants.BREWMASTER.SPELLS

-- =============================================================================
-- SECONDARY SPELL SYSTEM
-- Ordered by priority (first match wins)
-- Categories: EMERGENCY, MITIGATION, HEAL, SHIELD, AOE, FILLER
-- =============================================================================

Brewmaster.secondarySpells = {
    -- EMERGENCY: Major defensive when very low health
    {
        spellId = SPELLS.FORTIFYING_BREW,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.30)
        end,
    },

    -- HEAL: Self-healing when low health
    {
        spellId = SPELLS.EXPEL_HARM,
        category = "HEAL",
        urgency = "HIGH",
        condition = function(self)
            return self:HealthBelow(0.50)
        end,
    },

    -- MITIGATION: Purifying Brew when there's any stagger
    {
        spellId = SPELLS.PURIFYING_BREW,
        category = "MITIGATION",
        urgency = "HIGH",
        condition = function(self)
            local stagger = self:GetStaggerInfo()
            -- Recommend when there's any stagger (light, moderate, or heavy)
            -- The urgency varies based on level - heavy is more urgent
            if stagger.level == "HEAVY" then
                return true -- Will get URGENT priority from category
            end
            if stagger.level == "MODERATE" or stagger.level == "LIGHT" then
                return true
            end
            return false
        end,
    },

    -- SHIELD: Celestial Brew when health drops
    {
        spellId = SPELLS.CELESTIAL_BREW,
        category = "SHIELD",
        urgency = "HIGH",
        condition = function(self)
            return self:HealthBelow(0.60)
        end,
    },

    -- AOE: Keg Smash (core rotational, high priority AoE)
    {
        spellId = SPELLS.KEG_SMASH,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return true
        end,
    },

    -- AOE: Breath of Fire (maintain debuff)
    {
        spellId = SPELLS.BREATH_OF_FIRE,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return true
        end,
    },

    -- AOE: Rushing Jade Wind (if talented)
    {
        spellId = SPELLS.RUSHING_JADE_WIND,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            -- Only recommend if spell is known (talented)
            if not IsSpellKnown(SPELLS.RUSHING_JADE_WIND) then
                return false
            end
            return true
        end,
    },

    -- FILLER: Spinning Crane Kick (always available as last resort)
    {
        spellId = SPELLS.SPINNING_CRANE_KICK,
        category = "FILLER",
        urgency = "LOW",
        condition = function(self)
            return true
        end,
    },

    -- OFFENSIVE: Invoke Niuzao (major offensive cooldown)
    {
        spellId = SPELLS.INVOKE_NIUZAO,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            -- Only recommend in combat with a target and when we have some stagger
            -- (Niuzao's Stomp damage scales with stagger)
            if not self:HasTarget() or not self:InCombat() then
                return false
            end
            local stagger = self:GetStaggerInfo()
            -- Recommend when we have moderate+ stagger for good damage
            return stagger.level == "HEAVY" or stagger.level == "MODERATE"
        end,
    },

    -- OFFENSIVE: Exploding Keg (if talented, good AoE)
    {
        spellId = SPELLS.EXPLODING_KEG,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            -- Recommend in combat with target
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- OFFENSIVE: Bonedust Brew (if talented, damage amp)
    {
        spellId = SPELLS.BONEDUST_BREW,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            -- Recommend in combat with target
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- OFFENSIVE: Weapons of Order (if talented, big CD)
    {
        spellId = SPELLS.WEAPONS_OF_ORDER,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            -- Only recommend during combat with target
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- DEFENSIVE TALENT: Dampen Harm (if talented, emergency)
    {
        spellId = SPELLS.DAMPEN_HARM,
        category = "EMERGENCY",
        urgency = "HIGH",
        condition = function(self)
            return self:HealthBelow(0.40)
        end,
    },

    -- DEFENSIVE TALENT: Diffuse Magic (if talented, for magic damage)
    {
        spellId = SPELLS.DIFFUSE_MAGIC,
        category = "EMERGENCY",
        urgency = "HIGH",
        condition = function(self)
            return self:HealthBelow(0.40)
        end,
    },
}

-- Note: Old aoeSpells and priorityUtilities replaced by unified secondarySpells system above
local BUFFS = TA.Constants.BREWMASTER.BUFFS
local DEBUFFS = TA.Constants.BREWMASTER.DEBUFFS
local THRESHOLDS = TA.Constants.BREWMASTER.THRESHOLDS
local COOLDOWNS = TA.Constants.BREWMASTER.COOLDOWNS

-- =============================================================================
-- STAGGER TRACKING
-- Brewmaster's unique damage smoothing mechanic
-- STAGGER IS EXPLICITLY WHITELISTED BY BLIZZARD - full access!
-- =============================================================================

-- Get current stagger level using the whitelisted API
function Brewmaster:GetStaggerInfo()
    -- Stagger is declassified - use SecretValues helper that uses UnitPower
    return TA.SecretValues:GetStaggerInfo()
end

-- Should we purify?
function Brewmaster:ShouldPurify()
    local stagger = self:GetStaggerInfo()

    -- Heavy stagger - always purify urgently
    if stagger.level == "HEAVY" then
        return true, "URGENT"
    end

    -- Moderate stagger - high priority
    if stagger.level == "MODERATE" then
        return true, "HIGH"
    end

    -- Light stagger - still recommend, normal priority
    if stagger.level == "LIGHT" then
        return true, "NORMAL"
    end

    return false, "NORMAL"
end

-- =============================================================================
-- TRACKED BUFFS
-- =============================================================================

Brewmaster.buffsToTrack = {
    {
        spellId = BUFFS.SHUFFLE,
        name = "Shuffle",
        refreshSpell = SPELLS.BLACKOUT_KICK,
        refreshThreshold = THRESHOLDS.SHUFFLE_REFRESH,
        priority = "CRITICAL",
    },
    {
        spellId = BUFFS.CELESTIAL_BREW,
        name = "Celestial Brew",
        refreshSpell = SPELLS.CELESTIAL_BREW,
        refreshThreshold = 0,
        priority = "HIGH",
    },
    {
        spellId = BUFFS.FORTIFYING_BREW,
        name = "Fortifying Brew",
        refreshSpell = SPELLS.FORTIFYING_BREW,
        refreshThreshold = 0,
        priority = "HIGH",
    },
    -- Stagger is shown separately via custom UI
}

-- =============================================================================
-- TANK ACTIONS (for TankActionsDisplay)
-- These show in the dedicated tank cooldowns bar
-- =============================================================================

Brewmaster.tankActions = {
    MITIGATION = {
        spellId = SPELLS.PURIFYING_BREW,
        name = "Purifying Brew",
        -- Highlight when stagger is moderate or above
        condition = function()
            local stagger = TA.SecretValues:GetStaggerInfo()
            return stagger.level == "HEAVY" or stagger.level == "MODERATE"
        end,
    },
    SHIELD = {
        spellId = SPELLS.CELESTIAL_BREW,
        name = "Celestial Brew",
        -- Highlight when health is below 70%
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.7
        end,
    },
    DEFENSIVE = {
        spellId = SPELLS.FORTIFYING_BREW,
        name = "Fortifying Brew",
        -- Highlight when health is critical
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.4
        end,
    },
    HEAL = {
        spellId = SPELLS.EXPEL_HARM,
        name = "Expel Harm",
        -- Highlight when health is below 50%
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.5
        end,
    },
}

-- =============================================================================
-- TRACKED COOLDOWNS
-- =============================================================================

Brewmaster.cooldownsToTrack = {
    -- Major
    {
        spellId = SPELLS.INVOKE_NIUZAO,
        name = "Invoke Niuzao",
        category = "MAJOR",
    },
    {
        spellId = SPELLS.WEAPONS_OF_ORDER,
        name = "Weapons of Order",
        category = "MAJOR",
    },
    -- Defensive
    {
        spellId = SPELLS.FORTIFYING_BREW,
        name = "Fortifying Brew",
        category = "DEFENSIVE",
    },
    {
        spellId = SPELLS.ZEN_MEDITATION,
        name = "Zen Meditation",
        category = "DEFENSIVE",
    },
    {
        spellId = SPELLS.DAMPEN_HARM,
        name = "Dampen Harm",
        category = "DEFENSIVE",
    },
    {
        spellId = SPELLS.DIFFUSE_MAGIC,
        name = "Diffuse Magic",
        category = "DEFENSIVE",
    },
    -- Brews (special handling)
    {
        spellId = SPELLS.PURIFYING_BREW,
        name = "Purifying Brew",
        category = "DEFENSIVE",
    },
    {
        spellId = SPELLS.CELESTIAL_BREW,
        name = "Celestial Brew",
        category = "DEFENSIVE",
    },
    -- Offensive
    {
        spellId = SPELLS.EXPLODING_KEG,
        name = "Exploding Keg",
        category = "OFFENSIVE",
    },
    {
        spellId = SPELLS.BONEDUST_BREW,
        name = "Bonedust Brew",
        category = "OFFENSIVE",
    },
}

-- =============================================================================
-- ROTATION PRIORITY
-- =============================================================================

Brewmaster.rotationPriority = {
    -- ==========================================================================
    -- TANK ALERTS (only show when actually needed)
    -- ==========================================================================

    -- 1. Fortifying Brew (EMERGENCY - very low health)
    {
        spellId = SPELLS.FORTIFYING_BREW,
        defaultPriority = "URGENT",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.35 then
                local usable = TA.SecretValues:IsSpellUsable(SPELLS.FORTIFYING_BREW)
                if usable then
                    return true, "URGENT", "EMERGENCY!"
                end
            end
            return false
        end,
    },

    -- 2. Purifying Brew when there's any stagger
    {
        spellId = SPELLS.PURIFYING_BREW,
        defaultPriority = "HIGH",
        condition = function(self)
            local shouldPurify, urgency = self:ShouldPurify()

            if shouldPurify == nil then
                return false -- Can't determine
            end

            if shouldPurify then
                if urgency == "URGENT" then
                    return true, "URGENT", "Heavy Stagger!"
                elseif urgency == "HIGH" then
                    return true, "HIGH", "Purify stagger"
                else
                    return true, "NORMAL", "Clear stagger"
                end
            end

            return false
        end,
    },

    -- 3. Celestial Brew for shield (when health drops)
    {
        spellId = SPELLS.CELESTIAL_BREW,
        defaultPriority = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            -- More aggressive - show at 60% health
            if hp and hp < 0.6 then
                local usable = TA.SecretValues:IsSpellUsable(SPELLS.CELESTIAL_BREW)
                if usable then
                    return true, "HIGH", "Shield up"
                end
            end
            return false
        end,
    },

    -- 4. Expel Harm (self-heal when low)
    {
        spellId = SPELLS.EXPEL_HARM,
        defaultPriority = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.5 then
                local usable = TA.SecretValues:IsSpellUsable(SPELLS.EXPEL_HARM)
                if usable then
                    return true, "HIGH", "Heal yourself!"
                end
            end
            return false
        end,
    },

    -- ==========================================================================
    -- ROTATION PRIORITIES (maintenance and DPS)
    -- ==========================================================================
    
    -- 3. Blackout Kick for Shuffle maintenance
    {
        spellId = SPELLS.BLACKOUT_KICK,
        defaultPriority = "HIGH",
        condition = function(self)
            local needsRefresh, reason = self:BuffNeedsRefresh(
                BUFFS.SHUFFLE,
                THRESHOLDS.SHUFFLE_REFRESH
            )
            
            if needsRefresh == nil then
                return false
            end
            
            if needsRefresh then
                if reason == "DOWN" then
                    return true, "URGENT", "Shuffle DOWN!"
                else
                    return true, "HIGH", "Refresh Shuffle"
                end
            end
            
            return false
        end,
    },
    
    -- 4. Keg Smash (core ability, always use on CD)
    {
        spellId = SPELLS.KEG_SMASH,
        defaultPriority = "HIGH",
        condition = function(self)
            local usable = TA.SecretValues:IsSpellUsable(SPELLS.KEG_SMASH)
            local energy = self:GetResource("ENERGY")
            
            if usable and energy and energy >= THRESHOLDS.KEG_SMASH_ENERGY then
                return true, "HIGH", nil
            end
            
            return false
        end,
    },
    
    -- 5. Breath of Fire (maintain debuff)
    {
        spellId = SPELLS.BREATH_OF_FIRE,
        defaultPriority = "NORMAL",
        condition = function(self)
            -- Only recommend if we have a target to hit
            if not self:HasTarget() then
                return false
            end

            -- Check if Breath of Fire debuff needs refreshing on target
            -- Note: Target debuffs may be secret in 12.0, so we fall back to cooldown-based logic
            local debuffInfo = TA.SecretValues:GetBuffInfo("target", DEBUFFS.BREATH_OF_FIRE_DOT)
            if debuffInfo.isSecret then
                -- Can't check debuff, recommend if off cooldown
                return true, "NORMAL", nil
            end

            -- Recommend if debuff is down or about to expire
            if not debuffInfo.exists then
                return true, "HIGH", "BoF debuff down"
            end

            local remaining = (debuffInfo.expirationTime or 0) - GetTime()
            if remaining < 3 then
                return true, "NORMAL", "Refresh BoF"
            end

            return false
        end,
    },

    -- 6. Rushing Jade Wind (if talented)
    {
        spellId = SPELLS.RUSHING_JADE_WIND,
        defaultPriority = "NORMAL",
        condition = function(self)
            if not IsSpellKnown(SPELLS.RUSHING_JADE_WIND) then
                return false
            end

            -- Check if buff is down or about to expire
            local rjwInfo = TA.SecretValues:GetBuffInfo("player", SPELLS.RUSHING_JADE_WIND)
            if not rjwInfo.exists then
                return true, "HIGH", "RJW down"
            end

            -- Also recommend if about to expire (< 2 seconds remaining)
            local remaining = (rjwInfo.expirationTime or 0) - GetTime()
            if remaining > 0 and remaining < 2 then
                return true, "NORMAL", "RJW expiring"
            end

            return false
        end,
    },
    
    -- 7. Spinning Crane Kick (AoE - 3+ targets)
    {
        spellId = SPELLS.SPINNING_CRANE_KICK,
        defaultPriority = "NORMAL",
        condition = function(self)
            local enemies = self:GetEnemyCount()
            if enemies >= 3 then
                local energy = self:GetResource("ENERGY")
                if energy and energy >= 40 then
                    -- Higher priority with more enemies
                    if enemies >= 5 then
                        return true, "HIGH", "AoE! (5+ mobs)"
                    end
                    return true, "NORMAL", "AoE (3+ mobs)"
                end
            end
            return false
        end,
    },
    
    -- 8. Tiger Palm (filler)
    {
        spellId = SPELLS.TIGER_PALM,
        defaultPriority = "NORMAL",
        condition = function(self)
            -- Use Tiger Palm as filler when nothing else is available
            local energy = self:GetResource("ENERGY")
            if energy and energy >= 50 then -- Keep some energy pooled
                -- Don't use if Keg Smash is about to come up
                local kegCD = TA.SecretValues:GetCooldownInfo(SPELLS.KEG_SMASH)
                if kegCD.remaining and kegCD.remaining > 1 then
                    return true, "NORMAL", nil
                end
            end
            return false
        end,
    },
}

-- =============================================================================
-- CUSTOM UPDATE LOGIC
-- =============================================================================

function Brewmaster:OnUpdate()
    -- Track stagger for custom display
    self.currentStagger = self:GetStaggerInfo()
end

-- =============================================================================
-- CUSTOM UI ADDITION: STAGGER BAR
-- Stagger is whitelisted so we have full access to the data
-- =============================================================================

function Brewmaster:GetStaggerDisplayInfo()
    local stagger = self:GetStaggerInfo()
    
    local colors = {
        NONE = { 0.5, 0.5, 0.5 },
        LIGHT = { 0.2, 0.8, 0.2 },
        MODERATE = { 1, 0.8, 0 },
        HEAVY = { 1, 0.2, 0.2 },
    }
    
    return {
        level = stagger.level,
        percent = stagger.percent,
        amount = stagger.amount,
        color = colors[stagger.level] or colors.NONE,
        shouldPurify = stagger.level == "HEAVY" or stagger.level == "MODERATE",
        -- Stagger is whitelisted - never secret!
        isSecret = false,
    }
end

-- =============================================================================
-- REGISTER MODULE
-- =============================================================================

Brewmaster:Register()

-- Store reference
TA.Brewmaster = Brewmaster
