-- TankAssist Blood Death Knight Module
-- Complete implementation for Blood DK tanking

local ADDON_NAME, TA = ...

local BloodDK = TA.SpecBase:New(250, "Blood Death Knight")

local SPELLS = TA.Constants.BLOOD_DK.SPELLS
local BUFFS = TA.Constants.BLOOD_DK.BUFFS
local THRESHOLDS = TA.Constants.BLOOD_DK.THRESHOLDS
local COOLDOWNS = TA.Constants.BLOOD_DK.COOLDOWNS

-- =============================================================================
-- SECONDARY SPELLS (unified system - replaces aoeSpells and priorityUtilities)
-- Uses CanCastSpell() which properly handles charge-based spells
-- =============================================================================

BloodDK.secondarySpells = {
    -- EMERGENCY: Icebound Fortitude at critical health
    {
        spellId = SPELLS.ICEBOUND_FORTITUDE,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.25)
        end,
    },

    -- EMERGENCY: Vampiric Blood when health is low
    {
        spellId = SPELLS.VAMPIRIC_BLOOD,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.40)
        end,
    },

    -- HEAL: Death Strike when low health and have RP
    {
        spellId = SPELLS.DEATH_STRIKE,
        category = "HEAL",
        urgency = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            local rp = self:GetResource("RUNIC_POWER")
            return hp and hp < 0.50 and rp and rp >= 40
        end,
    },

    -- SHIELD: Death Strike to rebuild Blood Shield when it's down
    -- Lower priority than emergency heal - only suggest if health is okay
    {
        spellId = SPELLS.DEATH_STRIKE,
        category = "SHIELD",
        urgency = "NORMAL",
        condition = function(self)
            local bsInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.BLOOD_SHIELD)
            if bsInfo.exists then
                return false -- Blood Shield is still up
            end
            -- Blood Shield is down - suggest Death Strike if we have RP and aren't in emergency
            local hp = self:GetHealthPercent()
            local rp = self:GetResource("RUNIC_POWER")
            -- Only suggest if health is above 50% (not emergency) and we have enough RP
            return hp and hp >= 0.50 and rp and rp >= 40
        end,
    },

    -- MITIGATION: Marrowrend when Bone Shield is down or low
    {
        spellId = SPELLS.MARROWREND,
        category = "MITIGATION",
        urgency = "HIGH",
        condition = function(self)
            local bsInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.BONE_SHIELD)
            if not bsInfo.exists then
                return true
            end
            return bsInfo.stacks and bsInfo.stacks < 5
        end,
    },

    -- MITIGATION: Rune Tap for damage reduction
    {
        spellId = SPELLS.RUNE_TAP,
        category = "MITIGATION",
        urgency = "NORMAL",
        condition = function(self)
            return self:HealthBelow(0.60)
        end,
    },

    -- AOE: Death and Decay with Crimson Scourge proc (free cast!)
    {
        spellId = SPELLS.DEATH_AND_DECAY,
        category = "AOE",
        urgency = "HIGH",
        condition = function(self)
            local procInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.CRIMSON_SCOURGE)
            return procInfo.exists
        end,
    },

    -- AOE: Blood Boil (charge-based - CanCastSpell handles this)
    {
        spellId = SPELLS.BLOOD_BOIL,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },

    -- AOE: Death and Decay (without proc)
    {
        spellId = SPELLS.DEATH_AND_DECAY,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },

    -- OFFENSIVE: Dancing Rune Weapon
    {
        spellId = SPELLS.DANCING_RUNE_WEAPON,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- OFFENSIVE: Abomination Limb (if talented)
    {
        spellId = SPELLS.ABOMINATION_LIMB,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- FILLER: Heart Strike
    {
        spellId = SPELLS.HEART_STRIKE,
        category = "FILLER",
        urgency = "LOW",
        condition = function(self)
            return self:HasTarget()
        end,
    },
}

-- =============================================================================
-- TRACKED BUFFS (for Buff Maintenance display)
-- =============================================================================

BloodDK.buffsToTrack = {
    {
        spellId = BUFFS.BONE_SHIELD,
        name = "Bone Shield",
        refreshSpell = SPELLS.MARROWREND,
        minStacks = THRESHOLDS.BONE_SHIELD_MIN,
        maxStacks = THRESHOLDS.BONE_SHIELD_MAX,
        refreshThreshold = 5, -- More aggressive for DK since it's crucial
        priority = "CRITICAL",
    },
    {
        -- Blood Shield: absorb from Death Strike
        -- Note: Absorb AMOUNT is a secret value and cannot be tracked
        -- We can only track whether the shield EXISTS (up/down)
        spellId = BUFFS.BLOOD_SHIELD,
        name = "Blood Shield",
        refreshSpell = SPELLS.DEATH_STRIKE,
        refreshThreshold = 0, -- Don't "refresh", just track existence
        priority = "HIGH",
        isAbsorb = true, -- Flag for UI to show as absorb indicator
    },
    {
        spellId = BUFFS.DANCING_RUNE_WEAPON,
        name = "Dancing Rune Weapon",
        refreshSpell = SPELLS.DANCING_RUNE_WEAPON,
        refreshThreshold = 0, -- Don't "refresh", just track
        priority = "HIGH",
    },
    {
        spellId = BUFFS.VAMPIRIC_BLOOD,
        name = "Vampiric Blood",
        refreshSpell = SPELLS.VAMPIRIC_BLOOD,
        refreshThreshold = 0,
        priority = "HIGH",
    },
}

-- =============================================================================
-- TANK ACTIONS (for TankActionsDisplay)
-- =============================================================================

BloodDK.tankActions = {
    MITIGATION = {
        spellId = SPELLS.MARROWREND,
        name = "Marrowrend",
        -- Highlight when Bone Shield is low
        condition = function()
            local bsInfo = TA.SecretValues:GetBuffInfo("player", TA.Constants.BLOOD_DK.BUFFS.BONE_SHIELD)
            if not bsInfo.exists then return true end
            return bsInfo.stacks and bsInfo.stacks < 5
        end,
    },
    SHIELD = {
        spellId = SPELLS.DEATH_STRIKE,
        name = "Death Strike",
        -- Highlight when health is below 60%
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.6
        end,
    },
    DEFENSIVE = {
        spellId = SPELLS.VAMPIRIC_BLOOD,
        name = "Vampiric Blood",
        -- Highlight when health is critical
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.4
        end,
    },
    HEAL = {
        spellId = SPELLS.DEATH_STRIKE,
        name = "Death Strike",
        -- Same as SHIELD for Blood DK (Death Strike is their heal)
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.5
        end,
    },
}

-- =============================================================================
-- TRACKED COOLDOWNS
-- =============================================================================

BloodDK.cooldownsToTrack = {
    -- Major
    {
        spellId = SPELLS.DANCING_RUNE_WEAPON,
        name = "Dancing Rune Weapon",
        category = "MAJOR",
    },
    {
        spellId = SPELLS.VAMPIRIC_BLOOD,
        name = "Vampiric Blood",
        category = "MAJOR",
    },
    -- Defensive
    {
        spellId = SPELLS.ICEBOUND_FORTITUDE,
        name = "Icebound Fortitude",
        category = "DEFENSIVE",
    },
    {
        spellId = SPELLS.ANTI_MAGIC_SHELL,
        name = "Anti-Magic Shell",
        category = "DEFENSIVE",
    },
    {
        spellId = SPELLS.RUNE_TAP,
        name = "Rune Tap",
        category = "DEFENSIVE",
    },
    {
        spellId = SPELLS.TOMBSTONE,
        name = "Tombstone",
        category = "DEFENSIVE",
    },
    -- Offensive
    {
        spellId = SPELLS.ABOMINATION_LIMB,
        name = "Abomination Limb",
        category = "OFFENSIVE",
    },
    {
        spellId = SPELLS.EMPOWER_RUNE_WEAPON,
        name = "Empower Rune Weapon",
        category = "OFFENSIVE",
    },
}

-- =============================================================================
-- ROTATION PRIORITY
-- This defines what to recommend when Blizzard's assisted combat is unavailable
-- =============================================================================

BloodDK.rotationPriority = {
    -- ==========================================================================
    -- TANK ALERTS (only show when actually needed)
    -- ==========================================================================

    -- 1. Icebound Fortitude (EMERGENCY - very low health)
    {
        spellId = SPELLS.ICEBOUND_FORTITUDE,
        defaultPriority = "URGENT",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.3 then
                local usable = TA.SecretValues:IsSpellUsable(SPELLS.ICEBOUND_FORTITUDE)
                if usable then
                    return true, "URGENT", "EMERGENCY!"
                end
            end
            return false
        end,
    },

    -- 2. Vampiric Blood (defensive when health is low)
    {
        spellId = SPELLS.VAMPIRIC_BLOOD,
        defaultPriority = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.5 then
                local usable = TA.SecretValues:IsSpellUsable(SPELLS.VAMPIRIC_BLOOD)
                if usable then
                    return true, "HIGH", "Boost healing!"
                end
            end
            return false
        end,
    },

    -- 3. Death Strike when low HP (emergency heal)
    {
        spellId = SPELLS.DEATH_STRIKE,
        defaultPriority = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp == nil then return false end

            if hp < THRESHOLDS.LOW_HEALTH_PERCENT then
                local hasRP = self:HasResource("RUNIC_POWER", THRESHOLDS.DEATH_STRIKE_RP)
                if hasRP then
                    return true, "URGENT", "Low HP - heal!"
                end
            end
            return false
        end,
    },

    -- ==========================================================================
    -- ROTATION PRIORITIES (maintenance and DPS)
    -- ==========================================================================
    
    -- 2. Marrowrend for Bone Shield maintenance
    {
        spellId = SPELLS.MARROWREND,
        defaultPriority = "HIGH",
        condition = function(self)
            local needsRefresh, reason = self:BuffNeedsRefresh(
                BUFFS.BONE_SHIELD, 
                5, -- Time threshold 
                THRESHOLDS.BONE_SHIELD_MIN -- Stack threshold
            )
            
            if needsRefresh == nil then
                return false -- Can't determine
            end
            
            if needsRefresh then
                -- Check if we have runes
                local runes = self:GetResource("RUNES")
                if runes and runes >= 2 then
                    if reason == "DOWN" then
                        return true, "URGENT", "Bone Shield DOWN!"
                    else
                        return true, "HIGH", "Bone Shield low"
                    end
                end
            end
            return false
        end,
    },
    
    -- 3. Death and Decay (with Crimson Scourge proc)
    {
        spellId = SPELLS.DEATH_AND_DECAY,
        defaultPriority = "HIGH",
        condition = function(self)
            -- Check for Crimson Scourge proc (free D&D)
            local procInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.CRIMSON_SCOURGE)
            if procInfo.exists and not procInfo.isSecret then
                return true, "HIGH", "Free D&D proc!"
            end
            return false
        end,
    },
    
    -- 4. Blood Boil (maintain diseases, generate RP)
    {
        spellId = SPELLS.BLOOD_BOIL,
        defaultPriority = "NORMAL",
        condition = function(self)
            -- Check charges
            local cdInfo = TA.SecretValues:GetCooldownInfo(SPELLS.BLOOD_BOIL)
            if cdInfo.charges and cdInfo.charges >= 2 then
                return true, "NORMAL", "Use charges"
            elseif cdInfo.charges and cdInfo.charges >= 1 then
                -- Check if we have targets
                if self:HasTarget() then
                    return true, "NORMAL", nil
                end
            end
            return false
        end,
    },
    
    -- 5. Heart Strike (filler, generates RP)
    {
        spellId = SPELLS.HEART_STRIKE,
        defaultPriority = "NORMAL",
        condition = function(self)
            -- Only use if we have runes and Bone Shield is okay
            local runes = self:GetResource("RUNES")
            if runes and runes >= 3 then
                -- Don't use if we need runes for Marrowrend
                local needsBoneShield = self:BuffNeedsRefresh(BUFFS.BONE_SHIELD, 5, THRESHOLDS.BONE_SHIELD_MIN)
                if not needsBoneShield then
                    return true, "NORMAL", nil
                end
            end
            return false
        end,
    },
    
    -- 6. Death Strike (dump RP when not needed for emergency)
    {
        spellId = SPELLS.DEATH_STRIKE,
        defaultPriority = "NORMAL",
        condition = function(self)
            local rp = self:GetResource("RUNIC_POWER")
            if rp == nil then return false end
            
            -- Use Death Strike at high RP to avoid capping
            if rp >= 80 then
                return true, "NORMAL", "Dump RP"
            end
            
            -- Or if we have Hemostasis stacks (bonus healing)
            local hemoInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.HEMOSTASIS)
            if hemoInfo.exists and hemoInfo.stacks and hemoInfo.stacks >= 5 then
                if rp >= THRESHOLDS.DEATH_STRIKE_RP then
                    return true, "HIGH", "Max Hemostasis"
                end
            end
            
            return false
        end,
    },
    
    -- 7. Consumption (if talented and available)
    {
        spellId = SPELLS.CONSUMPTION,
        defaultPriority = "NORMAL",
        condition = function(self)
            if not IsSpellKnown(SPELLS.CONSUMPTION) then
                return false
            end
            
            -- Use on cooldown for healing and damage
            local usable = TA.SecretValues:IsSpellUsable(SPELLS.CONSUMPTION)
            return usable == true, "NORMAL", nil
        end,
    },
    
    -- 8. Bonestorm (AoE situations)
    {
        spellId = SPELLS.BONESTORM,
        defaultPriority = "NORMAL",
        condition = function(self)
            if not IsSpellKnown(SPELLS.BONESTORM) then
                return false
            end
            
            -- Need high RP and multiple targets
            local rp = self:GetResource("RUNIC_POWER")
            if rp and rp >= 100 then
                local enemies = self:GetEnemyCount()
                if enemies >= 3 then
                    return true, "HIGH", "AoE burst"
                end
            end
            
            return false
        end,
    },
}

-- =============================================================================
-- CUSTOM UPDATE LOGIC
-- =============================================================================

function BloodDK:OnUpdate()
    -- Track any custom state here
    -- For example, track runic power trends for pooling advice
end

-- =============================================================================
-- CUSTOM HELPERS
-- =============================================================================

-- Check if we should save resources for incoming damage
function BloodDK:ShouldPoolResources()
    -- This could check boss timers, health trends, etc.
    -- For now, simple health check
    local hp = self:GetHealthPercent()
    if hp and hp < 0.6 then
        return true
    end
    return false
end

-- Get recommended defensive for current situation
function BloodDK:GetDefensiveRecommendation()
    local hp = self:GetHealthPercent()
    
    if hp == nil then
        return nil
    end
    
    -- Critical - use major defensive
    if hp < 0.3 then
        if TA.SecretValues:IsSpellUsable(SPELLS.VAMPIRIC_BLOOD) then
            return SPELLS.VAMPIRIC_BLOOD, "CRITICAL", "HP Critical!"
        elseif TA.SecretValues:IsSpellUsable(SPELLS.ICEBOUND_FORTITUDE) then
            return SPELLS.ICEBOUND_FORTITUDE, "CRITICAL", "HP Critical!"
        end
    end
    
    -- Moderate damage - use minor defensive
    if hp < 0.5 then
        if TA.SecretValues:IsSpellUsable(SPELLS.RUNE_TAP) then
            return SPELLS.RUNE_TAP, "HIGH", "Incoming damage"
        end
    end
    
    return nil
end

-- =============================================================================
-- REGISTER MODULE
-- =============================================================================

BloodDK:Register()

-- Store reference for external access
TA.BloodDK = BloodDK
