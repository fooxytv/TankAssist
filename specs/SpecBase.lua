-- TankAssist Spec Base
-- Base class for all tank spec modules

local ADDON_NAME, TA = ...

TA.SpecBase = {}

-- =============================================================================
-- SPEC MODULE TEMPLATE
-- =============================================================================

function TA.SpecBase:New(specId, specName)
    local spec = {
        specId = specId,
        specName = specName,
        
        -- Override these in subclasses
        buffsToTrack = {},      -- Maintenance buffs to display
        cooldownsToTrack = {},  -- Cooldowns to track
        rotationPriority = {},  -- Priority list for recommendations
        
        -- State tracking
        isActive = false,
    }
    
    setmetatable(spec, { __index = self })
    return spec
end

-- =============================================================================
-- LIFECYCLE METHODS
-- =============================================================================

-- Called when this spec becomes active
function TA.SpecBase:OnActivate()
    self.isActive = true
    TA.Utils:Debug(self.specName, "activated")
end

-- Called when switching away from this spec
function TA.SpecBase:OnDeactivate()
    self.isActive = false
    TA.Utils:Debug(self.specName, "deactivated")
end

-- Called every update tick
function TA.SpecBase:OnUpdate()
    -- Override in subclass for custom update logic
end

-- =============================================================================
-- RECOMMENDATION SYSTEM
-- =============================================================================

-- Get list of recommended abilities based on current state
-- Returns: { { spellId = X, priority = "HIGH/NORMAL/LOW", reason = "..." }, ... }
function TA.SpecBase:GetRecommendations()
    local recommendations = {}

    -- Process rotation priority list
    for _, entry in ipairs(self.rotationPriority) do
        local shouldRecommend, priority, reason = self:EvaluatePriorityEntry(entry)

        if shouldRecommend then
            table.insert(recommendations, {
                spellId = entry.spellId,
                priority = priority or entry.defaultPriority or "NORMAL",
                reason = reason,
            })
        end
    end

    -- Sort by priority (URGENT > HIGH > NORMAL > LOW)
    local priorityOrder = { URGENT = 1, HIGH = 2, NORMAL = 3, LOW = 4 }
    table.sort(recommendations, function(a, b)
        return (priorityOrder[a.priority] or 3) < (priorityOrder[b.priority] or 3)
    end)

    return recommendations
end

-- Evaluate a single priority entry
function TA.SpecBase:EvaluatePriorityEntry(entry)
    -- Check if spell is known
    if not IsSpellKnown(entry.spellId) then
        return false
    end

    -- Check if spell can be cast (cooldown AND resources) using unified API check
    local canCast, reason = TA.SecretValues:CanCastSpell(entry.spellId)

    -- If we can't determine (secret values), skip to be safe
    -- If definitely can't cast, skip
    if canCast ~= true then
        return false
    end

    -- Check custom condition if provided
    if entry.condition then
        local conditionMet, priority, condReason = entry.condition(self)
        if not conditionMet then
            return false
        end
        return true, priority, condReason
    end

    -- Default: recommend if castable
    return true, entry.defaultPriority, nil
end

-- =============================================================================
-- BUFF TRACKING HELPERS
-- =============================================================================

-- Check if a maintenance buff needs refreshing
function TA.SpecBase:BuffNeedsRefresh(spellId, threshold, minStacks)
    local info = TA.SecretValues:GetBuffInfo("player", spellId)
    
    if not info.exists then
        return true, "DOWN"
    end
    
    if info.isSecret then
        return nil, "UNKNOWN"
    end
    
    -- Check stacks
    if minStacks and info.stacks and info.stacks < minStacks then
        return true, "LOW_STACKS"
    end
    
    -- Check duration
    local remaining = (info.expirationTime or 0) - GetTime()
    if remaining < (threshold or 3) then
        return true, "EXPIRING"
    end
    
    return false, "ACTIVE"
end

-- Get current stacks of a buff
function TA.SpecBase:GetBuffStacks(spellId)
    local info = TA.SecretValues:GetBuffInfo("player", spellId)
    
    if info.isSecret then
        return nil
    end
    
    return info.stacks or 0
end

-- =============================================================================
-- RESOURCE HELPERS
-- =============================================================================

-- Check if we have enough of a resource
function TA.SpecBase:HasResource(resourceType, amount)
    local current = TA.SecretValues:GetResource(resourceType)

    if current == nil then
        return nil -- Can't determine
    end

    return current >= amount
end

-- Get current resource amount
function TA.SpecBase:GetResource(resourceType)
    return TA.SecretValues:GetResource(resourceType)
end

-- Check if a spell can be cast based on its resource cost
-- Uses SPELL_COSTS from the spec's Constants entry
-- Returns: canCast (bool/nil), missingResource (string or nil)
function TA.SpecBase:CanAffordSpell(spellId)
    -- Get the spec's constants (e.g., TA.Constants.BREWMASTER)
    local specConstants = self:GetSpecConstants()
    if not specConstants or not specConstants.SPELL_COSTS then
        return true, nil -- No cost data defined, assume castable
    end

    local costData = specConstants.SPELL_COSTS[spellId]
    if not costData then
        return true, nil -- No cost defined for this spell, assume castable
    end

    local hasEnough = self:HasResource(costData.resource, costData.cost)
    if hasEnough == nil then
        return nil, costData.resource -- Can't determine (secret value)
    end

    return hasEnough, hasEnough and nil or costData.resource
end

-- Get the Constants entry for this spec (override in subclass if needed)
function TA.SpecBase:GetSpecConstants()
    -- Map spec IDs to their Constants entries
    local specConstantsMap = {
        [250] = TA.Constants.BLOOD_DK,
        [268] = TA.Constants.BREWMASTER,
        [73] = TA.Constants.PROTECTION_WARRIOR,
        [66] = TA.Constants.PROTECTION_PALADIN,
        [581] = TA.Constants.VENGEANCE_DH,
        [104] = TA.Constants.GUARDIAN_DRUID,
    }
    return specConstantsMap[self.specId]
end

-- =============================================================================
-- HEALTH HELPERS
-- =============================================================================

-- Check player health percentage
function TA.SpecBase:GetHealthPercent()
    return TA.SecretValues:GetHealthPercent("player")
end

-- Check if below health threshold
function TA.SpecBase:IsBelowHealth(threshold)
    return TA.SecretValues:IsBelowHealthThreshold("player", threshold)
end

-- =============================================================================
-- COMBAT STATE HELPERS
-- =============================================================================

function TA.SpecBase:InCombat()
    return TA.SecretValues:InCombat()
end

function TA.SpecBase:HasTarget()
    return TA.SecretValues:HasTarget()
end

-- Get number of enemies in range (if trackable)
function TA.SpecBase:GetEnemyCount()
    -- This is tricky with 12.0 restrictions
    -- Could try nameplate count as approximation
    local count = 0
    
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsDead(unit) then
            count = count + 1
        end
    end
    
    return count
end

-- =============================================================================
-- PRIORITY UTILITY SYSTEM
-- Checks if a tank utility ability should be used urgently
-- Returns spellId if something needs attention, nil otherwise
-- =============================================================================

-- Define priority utilities in subclass like:
-- self.priorityUtilities = {
--     { spellId = X, condition = function(self) return shouldUse, priority end },
-- }

-- Debug flag for priority utilities
TA.SpecBase.debugUtilities = false

function TA.SpecBase:GetPriorityUtility()
    if not self.priorityUtilities then
        return nil
    end

    for _, utility in ipairs(self.priorityUtilities) do
        local spellId = utility.spellId

        -- Check if spell is available (using the method version)
        local isAvailable = self:IsSpellAvailable(spellId)

        if self.debugUtilities then
            local spellInfo = C_Spell.GetSpellInfo(spellId)
            local spellName = spellInfo and spellInfo.name or "Unknown"
            print("|cFF00CCFF[TA Utility]|r", spellName, "Available:", isAvailable)
        end

        if isAvailable then
            -- Check if spell can be cast (cooldown AND resources)
            local canCast, reason = TA.SecretValues:CanCastSpell(spellId)

            -- If we can't determine (secret), skip this spell to be safe
            local isReady = (canCast == true)

            if self.debugUtilities then
                local spellInfo = C_Spell.GetSpellInfo(spellId)
                local spellName = spellInfo and spellInfo.name or "Unknown"
                print("  Ready:", isReady, "CanCast:", canCast, "Reason:", reason or "none")
            end

            if isReady then
                -- Check custom condition
                if utility.condition then
                    local shouldUse, priority = utility.condition(self)

                    if self.debugUtilities then
                        local spellInfo = C_Spell.GetSpellInfo(spellId)
                        local spellName = spellInfo and spellInfo.name or "Unknown"
                        print("  Condition:", shouldUse, "Priority:", priority)
                    end

                    if shouldUse then
                        return spellId, priority or "HIGH"
                    end
                end
            end
        end
    end

    return nil
end

-- Toggle debug mode for utilities
function TA.SpecBase:SetDebugUtilities(enabled)
    self.debugUtilities = enabled
end

-- =============================================================================
-- UNIFIED SECONDARY SPELL SYSTEM
-- Define spells with categories and conditions for the secondary button
-- Categories: EMERGENCY, MITIGATION, HEAL, SHIELD, AOE, FILLER
-- =============================================================================

-- Check if a spell is available (known/talented)
function TA.SpecBase:IsSpellAvailable(spellId)
    if not spellId then return false end

    -- Method 1: IsSpellKnown
    if IsSpellKnown(spellId) then
        return true
    end

    -- Method 2: IsPlayerSpell (catches some talents)
    if IsPlayerSpell and IsPlayerSpell(spellId) then
        return true
    end

    -- Method 3: Check if spell has cooldown info (means we have it)
    local cdInfo = C_Spell.GetSpellCooldown(spellId)
    if cdInfo and cdInfo.startTime ~= nil and not TA.SecretValues:IsSecret(cdInfo.startTime) then
        return true
    end

    return false
end

-- Get the best secondary spell based on priority and conditions
function TA.SpecBase:GetSecondarySpell()
    if not self.secondarySpells then
        -- Fallback to old system if secondarySpells not defined
        local utilitySpell, priority = self:GetPriorityUtility()
        if utilitySpell then
            return utilitySpell, "utility", priority
        end
        if self.GetBestAoESpell then
            return self:GetBestAoESpell(), "aoe", "NORMAL"
        end
        return nil
    end

    -- Iterate through secondary spells (should be sorted by priority)
    for _, spellData in ipairs(self.secondarySpells) do
        local spellId = spellData.spellId

        -- Step 1: Check if spell is available (known/talented)
        if self:IsSpellAvailable(spellId) then
            -- Step 2: Check if spell can be cast (cooldown + resources)
            local canCast, reason = TA.SecretValues:CanCastSpell(spellId)

            if canCast then
                -- Step 3: Check custom condition
                local conditionMet = true
                if spellData.condition then
                    conditionMet = spellData.condition(self)
                end

                if conditionMet then
                    local priority = spellData.urgency or "NORMAL"
                    local category = spellData.category or "UTILITY"

                    -- Map category to display type
                    local displayType = "utility"
                    if category == "AOE" or category == "FILLER" then
                        displayType = "aoe"
                    elseif category == "OFFENSIVE" then
                        displayType = "offensive"
                    elseif category == "EMERGENCY" then
                        displayType = "utility"
                        priority = "URGENT"
                    end

                    return spellId, displayType, priority
                end
            end
        end
    end

    return nil
end

-- Helper to check health threshold
function TA.SpecBase:HealthBelow(threshold)
    local hp = self:GetHealthPercent()
    return hp and hp < threshold
end

-- Helper to check health threshold (above)
function TA.SpecBase:HealthAbove(threshold)
    local hp = self:GetHealthPercent()
    return hp and hp >= threshold
end

-- =============================================================================
-- UTILITY
-- =============================================================================

-- Register this spec module with the addon
function TA.SpecBase:Register()
    if TA.Addon then
        TA.Addon:RegisterSpecModule(self.specId, self)
    end
end
