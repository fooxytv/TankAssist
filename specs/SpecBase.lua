local ADDON_NAME, TankAssist = ...

TankAssist.SpecBase = {}

function TankAssist.SpecBase:New(specId, specName)
    local spec = {
        specId = specId,
        specName = specName,
        buffsToTrack = {},
        cooldownsToTrack = {},
        rotationPriority = {},
        isActive = false,
    }
    setmetatable(spec, { __index = self })
    return spec
end

function TankAssist.SpecBase:OnActivate()
    self.isActive = true
    TankAssist.Utils:Debug(self.specName, "activated")
end

function TankAssist.SpecBase:OnDeactivate()
    self.isActive = false
    TankAssist.Utils:Debug(self.specName, "deactivated")
end

function TankAssist.SpecBase:OnUpdate()
end

function TankAssist.SpecBase:GetRecommendations()
    local recommendations = {}

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

    local priorityOrder = { URGENT = 1, HIGH = 2, NORMAL = 3, LOW = 4 }
    table.sort(recommendations, function(a, b)
        return (priorityOrder[a.priority] or 3) < (priorityOrder[b.priority] or 3)
    end)

    return recommendations
end

function TankAssist.SpecBase:EvaluatePriorityEntry(entry)
    if not IsSpellKnown(entry.spellId) then
        return false
    end

    local canCast, reason = TankAssist.SecretValues:CanCastSpell(entry.spellId)
    if canCast ~= true then
        return false
    end

    if entry.condition then
        local conditionMet, priority, condReason = entry.condition(self)
        if not conditionMet then
            return false
        end
        return true, priority, condReason
    end

    return true, entry.defaultPriority, nil
end

function TankAssist.SpecBase:BuffNeedsRefresh(spellId, threshold, minStacks)
    local info = TankAssist.SecretValues:GetBuffInfo("player", spellId)

    if not info.exists then
        return true, "DOWN"
    end

    if info.isSecret then
        return nil, "UNKNOWN"
    end

    if minStacks and info.stacks and info.stacks < minStacks then
        return true, "LOW_STACKS"
    end

    local remaining = (info.expirationTime or 0) - GetTime()
    if remaining < (threshold or 3) then
        return true, "EXPIRING"
    end

    return false, "ACTIVE"
end

function TankAssist.SpecBase:GetBuffStacks(spellId)
    local info = TankAssist.SecretValues:GetBuffInfo("player", spellId)
    if info.isSecret then
        return nil
    end
    return info.stacks or 0
end

function TankAssist.SpecBase:HasResource(resourceType, amount)
    local current = TankAssist.SecretValues:GetResource(resourceType)
    if current == nil then
        return nil
    end
    return current >= amount
end

function TankAssist.SpecBase:GetResource(resourceType)
    return TankAssist.SecretValues:GetResource(resourceType)
end

function TankAssist.SpecBase:CanAffordSpell(spellId)
    local specConstants = self:GetSpecConstants()
    if not specConstants or not specConstants.SpellCosts then
        return true, nil
    end

    local costData = specConstants.SpellCosts[spellId]
    if not costData then
        return true, nil
    end

    local hasEnough = self:HasResource(costData.resource, costData.cost)
    if hasEnough == nil then
        return nil, costData.resource
    end

    return hasEnough, hasEnough and nil or costData.resource
end

function TankAssist.SpecBase:GetSpecConstants()
    local specConstantsMap = {
        [250] = TankAssist.Constants.BloodDeathKnight,
        [268] = TankAssist.Constants.Brewmaster,
        [73] = TankAssist.Constants.ProtectionWarrior,
        [66] = TankAssist.Constants.ProtectionPaladin,
        [581] = TankAssist.Constants.VengeanceDemonHunter,
        [104] = TankAssist.Constants.GuardianDruid,
    }
    return specConstantsMap[self.specId]
end

function TankAssist.SpecBase:GetHealthPercent()
    return TankAssist.SecretValues:GetHealthPercent("player")
end

function TankAssist.SpecBase:IsBelowHealth(threshold)
    return TankAssist.SecretValues:IsBelowHealthThreshold("player", threshold)
end

function TankAssist.SpecBase:InCombat()
    return TankAssist.SecretValues:InCombat()
end

function TankAssist.SpecBase:HasTarget()
    return TankAssist.SecretValues:HasTarget()
end

function TankAssist.SpecBase:GetEnemyCount()
    local count = 0
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsDead(unit) then
            count = count + 1
        end
    end
    return count
end

TankAssist.SpecBase.debugUtilities = false

function TankAssist.SpecBase:GetPriorityUtility()
    if not self.priorityUtilities then
        return nil
    end

    for _, utility in ipairs(self.priorityUtilities) do
        local spellId = utility.spellId
        local isAvailable = self:IsSpellAvailable(spellId)

        if self.debugUtilities then
            local spellInfo = C_Spell.GetSpellInfo(spellId)
            local spellName = spellInfo and spellInfo.name or "Unknown"
            print("|cFF00CCFF[TA Utility]|r", spellName, "Available:", isAvailable)
        end

        if isAvailable then
            local canCast, reason = TankAssist.SecretValues:CanCastSpell(spellId)
            local isReady = (canCast == true)

            if self.debugUtilities then
                local spellInfo = C_Spell.GetSpellInfo(spellId)
                local spellName = spellInfo and spellInfo.name or "Unknown"
                print("  Ready:", isReady, "CanCast:", canCast, "Reason:", reason or "none")
            end

            if isReady then
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

function TankAssist.SpecBase:SetDebugUtilities(enabled)
    self.debugUtilities = enabled
end

function TankAssist.SpecBase:IsSpellAvailable(spellId)
    if not spellId then return false end

    if IsSpellKnown(spellId) then
        return true
    end

    if IsPlayerSpell and IsPlayerSpell(spellId) then
        return true
    end

    local cdInfo = C_Spell.GetSpellCooldown(spellId)
    if cdInfo and cdInfo.startTime ~= nil and not TankAssist.SecretValues:IsSecret(cdInfo.startTime) then
        return true
    end

    return false
end

function TankAssist.SpecBase:GetSecondarySpell()
    if not self.secondarySpells then
        local utilitySpell, priority = self:GetPriorityUtility()
        if utilitySpell then
            return utilitySpell, "utility", priority
        end
        if self.GetBestAoESpell then
            return self:GetBestAoESpell(), "aoe", "NORMAL"
        end
        return nil
    end

    for _, spellData in ipairs(self.secondarySpells) do
        local spellId = spellData.spellId

        if self:IsSpellAvailable(spellId) then
            local canCast, reason = TankAssist.SecretValues:CanCastSpell(spellId)

            if canCast then
                local conditionMet = true
                if spellData.condition then
                    conditionMet = spellData.condition(self)
                end

                if conditionMet then
                    local priority = spellData.urgency or "NORMAL"
                    local category = spellData.category or "UTILITY"

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

function TankAssist.SpecBase:HealthBelow(threshold)
    local hp = self:GetHealthPercent()
    return hp and hp < threshold
end

function TankAssist.SpecBase:HealthAbove(threshold)
    local hp = self:GetHealthPercent()
    return hp and hp >= threshold
end

function TankAssist.SpecBase:Register()
    if TankAssist.Addon then
        TankAssist.Addon:RegisterSpecModule(self.specId, self)
    end
end
