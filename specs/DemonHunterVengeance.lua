-- TankAssist Vengeance Demon Hunter Module

local ADDON_NAME, TA = ...

local VengeanceDH = TA.SpecBase:New(581, "Vengeance Demon Hunter")

local SPELLS = TA.Constants.VENGEANCE_DH.SPELLS
local BUFFS = TA.Constants.VENGEANCE_DH.BUFFS
local THRESHOLDS = TA.Constants.VENGEANCE_DH.THRESHOLDS

-- =============================================================================
-- SECONDARY SPELLS (unified system - uses CanCastSpell for proper cooldown tracking)
-- =============================================================================

VengeanceDH.secondarySpells = {
    -- EMERGENCY: Metamorphosis at critical health
    {
        spellId = SPELLS.METAMORPHOSIS,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.30)
        end,
    },

    -- HEAL: Soul Cleave when low health
    -- Note: Fury check is handled by CanCastSpell/IsSpellUsable
    {
        spellId = SPELLS.SOUL_CLEAVE,
        category = "HEAL",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.50)
        end,
    },

    -- MITIGATION: Demon Spikes maintenance (charge-based)
    {
        spellId = SPELLS.DEMON_SPIKES,
        category = "MITIGATION",
        urgency = "HIGH",
        condition = function(self)
            local buffInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.DEMON_SPIKES)
            if not buffInfo.exists then
                return true
            end
            -- Refresh if expiring soon
            local remaining = buffInfo.expirationTime and (buffInfo.expirationTime - GetTime()) or 0
            return remaining < 2
        end,
    },

    -- DEFENSIVE: Fiery Brand when taking damage
    {
        spellId = SPELLS.FIERY_BRAND,
        category = "DEFENSIVE",
        urgency = "HIGH",
        condition = function(self)
            return self:HealthBelow(0.50) and self:HasTarget()
        end,
    },

    -- AOE: Spirit Bomb (high priority when we have fragments)
    {
        spellId = SPELLS.SPIRIT_BOMB,
        category = "AOE",
        urgency = "HIGH",
        condition = function(self)
            local fragments = self:GetSoulFragments()
            return self:HasTarget() and fragments and fragments >= 4
        end,
    },

    -- AOE: Sigil of Flame
    {
        spellId = SPELLS.SIGIL_OF_FLAME,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },

    -- AOE: Immolation Aura
    {
        spellId = SPELLS.IMMOLATION_AURA,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            local buffInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.IMMOLATION_AURA)
            return not buffInfo.exists and self:HasTarget()
        end,
    },

    -- AOE: Fel Devastation (if talented)
    {
        spellId = SPELLS.FEL_DEVASTATION,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- OFFENSIVE: The Hunt (if talented)
    {
        spellId = SPELLS.THE_HUNT,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- OFFENSIVE: Sigil of Spite (if talented)
    {
        spellId = SPELLS.SIGIL_OF_SPITE,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- OFFENSIVE: Soul Carver (if talented)
    {
        spellId = SPELLS.SOUL_CARVER,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },

    -- FILLER: Fracture (generate souls)
    {
        spellId = SPELLS.FRACTURE,
        category = "FILLER",
        urgency = "LOW",
        condition = function(self)
            local fragments = self:GetSoulFragments()
            return self:HasTarget() and (not fragments or fragments < 4)
        end,
    },

    -- FILLER: Shear (if Fracture not talented)
    {
        spellId = SPELLS.SHEAR,
        category = "FILLER",
        urgency = "LOW",
        condition = function(self)
            return self:HasTarget() and not IsSpellKnown(SPELLS.FRACTURE)
        end,
    },
}

-- Legacy: Keep aoeSpells for backwards compatibility but it won't be used
VengeanceDH.aoeSpells = {
    {
        spellId = SPELLS.SIGIL_OF_FLAME,
        priority = 1,
        condition = function() return true end,
    },
    {
        spellId = SPELLS.IMMOLATION_AURA,
        priority = 2,
        condition = function() return true end,
    },
}

function VengeanceDH:GetBestAoESpell()
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
    -- Return nil instead of a spell on cooldown
    return nil
end

-- =============================================================================
-- SOUL FRAGMENT TRACKING
-- =============================================================================

-- Soul fragments are tracked via a visual buff
function VengeanceDH:GetSoulFragments()
    local fragmentInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.SOUL_FRAGMENTS)
    if fragmentInfo.isSecret then
        return nil
    end
    return fragmentInfo.stacks or 0
end

-- =============================================================================
-- TRACKED BUFFS
-- =============================================================================

VengeanceDH.buffsToTrack = {
    {
        spellId = BUFFS.DEMON_SPIKES,
        name = "Demon Spikes",
        refreshSpell = SPELLS.DEMON_SPIKES,
        refreshThreshold = THRESHOLDS.DEMON_SPIKES_REFRESH,
        priority = "CRITICAL",
    },
    {
        spellId = BUFFS.FIERY_BRAND,
        name = "Fiery Brand",
        refreshSpell = SPELLS.FIERY_BRAND,
        refreshThreshold = 0,
        priority = "HIGH",
    },
    {
        spellId = BUFFS.METAMORPHOSIS,
        name = "Metamorphosis",
        refreshSpell = SPELLS.METAMORPHOSIS,
        refreshThreshold = 0,
        priority = "HIGH",
    },
}

-- =============================================================================
-- TANK ACTIONS (for TankActionsDisplay)
-- =============================================================================

VengeanceDH.tankActions = {
    MITIGATION = {
        spellId = SPELLS.DEMON_SPIKES,
        name = "Demon Spikes",
        condition = function()
            local buffInfo = TA.SecretValues:GetBuffInfo("player", TA.Constants.VENGEANCE_DH.BUFFS.DEMON_SPIKES)
            return not buffInfo.exists
        end,
    },
    SHIELD = {
        spellId = SPELLS.SOUL_CLEAVE,
        name = "Soul Cleave",
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.7
        end,
    },
    DEFENSIVE = {
        spellId = SPELLS.METAMORPHOSIS,
        name = "Metamorphosis",
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.4
        end,
    },
    HEAL = {
        spellId = SPELLS.SOUL_CLEAVE,
        name = "Soul Cleave",
        condition = function()
            local hp = TA.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.5
        end,
    },
}

-- =============================================================================
-- TRACKED COOLDOWNS
-- =============================================================================

VengeanceDH.cooldownsToTrack = {
    { spellId = SPELLS.METAMORPHOSIS, name = "Metamorphosis", category = "MAJOR" },
    { spellId = SPELLS.THE_HUNT, name = "The Hunt", category = "MAJOR" },
    { spellId = SPELLS.SIGIL_OF_SPITE, name = "Sigil of Spite", category = "MAJOR" },
    { spellId = SPELLS.FIERY_BRAND, name = "Fiery Brand", category = "DEFENSIVE" },
    { spellId = SPELLS.FEL_DEVASTATION, name = "Fel Devastation", category = "DEFENSIVE" },
    { spellId = SPELLS.SOUL_CARVER, name = "Soul Carver", category = "OFFENSIVE" },
}

-- =============================================================================
-- ROTATION PRIORITY
-- =============================================================================

VengeanceDH.rotationPriority = {
    -- 1. Soul Cleave when low HP (emergency)
    -- Note: Fury check is handled by CanCastSpell/IsSpellUsable
    {
        spellId = SPELLS.SOUL_CLEAVE,
        defaultPriority = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < THRESHOLDS.LOW_HEALTH_PERCENT then
                return true, "URGENT", "Low HP - heal!"
            end
            return false
        end,
    },
    
    -- 2. Demon Spikes maintenance
    {
        spellId = SPELLS.DEMON_SPIKES,
        defaultPriority = "HIGH",
        condition = function(self)
            local needsRefresh = self:BuffNeedsRefresh(BUFFS.DEMON_SPIKES, THRESHOLDS.DEMON_SPIKES_REFRESH)
            if needsRefresh then
                local cdInfo = TA.SecretValues:GetCooldownInfo(SPELLS.DEMON_SPIKES)
                if cdInfo.charges and cdInfo.charges >= 1 then
                    return true, "HIGH", "Demon Spikes"
                end
            end
            return false
        end,
    },
    
    -- 3. Spirit Bomb at 4+ souls
    {
        spellId = SPELLS.SPIRIT_BOMB,
        defaultPriority = "HIGH",
        condition = function(self)
            if not IsSpellKnown(SPELLS.SPIRIT_BOMB) then
                return false
            end
            
            local fragments = self:GetSoulFragments()
            if fragments and fragments >= THRESHOLDS.SOUL_FRAGMENTS_SPIRIT_BOMB then
                return true, "HIGH", "Spirit Bomb ready"
            end
            return false
        end,
    },
    
    -- 4. Immolation Aura (maintain)
    {
        spellId = SPELLS.IMMOLATION_AURA,
        defaultPriority = "NORMAL",
        condition = function(self)
            local buffInfo = TA.SecretValues:GetBuffInfo("player", BUFFS.IMMOLATION_AURA)
            if not buffInfo.exists then
                local usable = TA.SecretValues:IsSpellUsable(SPELLS.IMMOLATION_AURA)
                return usable == true, "NORMAL", nil
            end
            return false
        end,
    },
    
    -- 5. Fracture (generate souls and fury)
    {
        spellId = SPELLS.FRACTURE,
        defaultPriority = "NORMAL",
        condition = function(self)
            if not IsSpellKnown(SPELLS.FRACTURE) then
                return false
            end
            
            local fragments = self:GetSoulFragments()
            if fragments and fragments < 4 then
                local usable = TA.SecretValues:IsSpellUsable(SPELLS.FRACTURE)
                return usable == true, "NORMAL", nil
            end
            return false
        end,
    },
    
    -- 6. Sigil of Flame
    {
        spellId = SPELLS.SIGIL_OF_FLAME,
        defaultPriority = "NORMAL",
        condition = function(self)
            local usable = TA.SecretValues:IsSpellUsable(SPELLS.SIGIL_OF_FLAME)
            return usable == true, "NORMAL", nil
        end,
    },
    
    -- 7. Soul Cleave (when castable - has enough fury)
    -- Note: Fury check handled by CanCastSpell, just verify we have target
    {
        spellId = SPELLS.SOUL_CLEAVE,
        defaultPriority = "NORMAL",
        condition = function(self)
            -- CanCastSpell verified we have fury, just need target
            return self:HasTarget()
        end,
    },
    
    -- 8. Shear (filler)
    {
        spellId = SPELLS.SHEAR,
        defaultPriority = "NORMAL",
        condition = function(self)
            -- Only if Fracture isn't known
            if IsSpellKnown(SPELLS.FRACTURE) then
                return false
            end
            return true, "NORMAL", nil
        end,
    },
}

VengeanceDH:Register()
TA.VengeanceDH = VengeanceDH
