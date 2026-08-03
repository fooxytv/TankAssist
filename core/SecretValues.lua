local ADDON_NAME, TankAssist = ...
TankAssist.SecretValues = {}

local secretValues = TankAssist.SecretValues

function secretValues:IsSecret(value)
    if issecretvalue then
        return issecretvalue(value)
    end
    return false
end

function secretValues:CanAccessSecrets()
    if canaccesssecrets then
        return canaccesssecrets()
    end
    return true
end

function secretValues:CanAccessValue(value)
    if canaccessvalue then
        return canaccessvalue(value)
    end
    return true
end

function secretValues:SafeNumber(value, default)
    if value == nil then
        return default
    end
    if self:IsSecret(value) then
        return default
    end
    return value
end

function secretValues:SafeCompare(value, threshold, operator)
    if self:IsSecret(value) then
        return nil
    end
    if operator == "<" then
        return value < threshold
    elseif operator == "<=" then
        return value <= threshold
    elseif operator == ">" then
        return value > threshold
    elseif operator == ">=" then
        return value >= threshold
    elseif operator == "==" then
        return value == threshold
    end
    return nil
end

secretValues.buffCache = {}
secretValues.lastCacheUpdate = 0
secretValues.CacheDuration = 0.5
secretValues.trackedCooldowns = {}
secretValues.trackedCharges = {}
secretValues.trackedStackingBuffs = {}
secretValues.KnownStackingBuffs = {}

function secretValues:TrackStackingBuff(spellId)
    local buffData = self.KnownStackingBuffs[spellId]
    if not buffData then return end
    local now = GetTime()
    local expirationTime = now + buffData.duration
    if not self.trackedStackingBuffs[spellId] then
        self.trackedStackingBuffs[spellId] = { stacks = {} }
    end
    local tracking = self.trackedStackingBuffs[spellId]
    local validStacks = {}
    for _, stack in ipairs(tracking.stacks) do
        if stack.expirationTime > now then
            table.insert(validStacks, stack)
        end
    end
    tracking.stacks = validStacks
    table.insert(tracking.stacks, {
        castTime = now,
        expirationTime = expirationTime,
    })
end

function secretValues:GetTrackedStackingBuff(spellId)
    local buffData = self.KnownStackingBuffs[spellId]
    if not buffData then return nil end
    local tracking = self.trackedStackingBuffs[spellId]
    if not tracking then
        return { exists = false, stacks = 0, minRemaining = 0, maxRemaining = 0 }
    end
    local now = GetTime()
    local validStacks = {}
    local minRemaining = nil
    local maxRemaining = 0
    for _, stack in ipairs(tracking.stacks) do
        local remaining = stack.expirationTime - now
        if remaining > 0 then
            table.insert(validStacks, stack)
            if minRemaining == nil or remaining < minRemaining then
                minRemaining = remaining
            end
            if remaining > maxRemaining then
                maxRemaining = remaining
            end
        end
    end
    tracking.stacks = validStacks

    local stackCount = #validStacks
    return {
        exists = stackCount > 0,
        stacks = stackCount,
        minRemaining = minRemaining or 0,
        maxRemaining = maxRemaining,
        expirationTime = stackCount > 0 and (now + maxRemaining) or 0,
        duration = buffData.duration,
    }
end

secretValues.KnownChargeSpells = {}
secretValues.KnownCooldowns = {}
secretValues.KnownShadowStackBuffs = {}
secretValues.trackedShadowStacks = {}

function secretValues:OnSpellCast(spellId)
    local now = GetTime()

    local chargeData = self.KnownChargeSpells[spellId]
    if chargeData then
        if not self.trackedCharges[spellId] then
            self.trackedCharges[spellId] = {
                castTimes = {},
                maxCharges = chargeData.maxCharges,
                rechargeTime = chargeData.rechargeTime,
            }
        end

        local tracking = self.trackedCharges[spellId]
        local validCasts = {}
        for _, castTime in ipairs(tracking.castTimes) do
            local elapsed = now - castTime
            if elapsed < tracking.rechargeTime then
                table.insert(validCasts, castTime)
            end
        end
        tracking.castTimes = validCasts
        table.insert(tracking.castTimes, now)

        if self.debugTracking then
            local spellInfo = C_Spell.GetSpellInfo(spellId)
            local spellName = spellInfo and spellInfo.name or "Unknown"
            local chargesRemaining = tracking.maxCharges - #tracking.castTimes
            print("|cFF00FF00[TA Tracking]|r", spellName, "(" .. spellId .. ") - Charges:", chargesRemaining .. "/" .. tracking.maxCharges)
        end
        return
    end

    local cdInfo = C_Spell.GetSpellCooldown(spellId)
    if cdInfo and cdInfo.duration then
        local ok, isReal = pcall(function()
            return cdInfo.duration > 1.5
        end)
        if ok and isReal then
            self.KnownCooldowns[spellId] = cdInfo.duration
        end
    end

    local knownCD = self.KnownCooldowns[spellId]
    if knownCD and knownCD > 0 then
        self.trackedCooldowns[spellId] = {
            castTime = now,
            duration = knownCD,
        }
        if self.debugTracking then
            local spellInfo = C_Spell.GetSpellInfo(spellId)
            local spellName = spellInfo and spellInfo.name or "Unknown"
            print("|cFF00FF00[TA Tracking]|r", spellName, "(" .. spellId .. ") - CD:", knownCD .. "s")
        end
    end

    self:TrackStackingBuff(spellId)
    self:TrackShadowStacks(spellId)
end

function secretValues:TrackShadowStacks(spellId)
    for buffId, buffConfig in pairs(self.KnownShadowStackBuffs) do
        if buffConfig.grantedBy and buffConfig.grantedBy[spellId] then
            local stacksToAdd = buffConfig.grantedBy[spellId]
            if not self.trackedShadowStacks[buffId] then
                self.trackedShadowStacks[buffId] = {
                    stacks = 0,
                    lastUpdate = GetTime(),
                }
            end

            local tracking = self.trackedShadowStacks[buffId]
            tracking.stacks = math.min(tracking.stacks + stacksToAdd, buffConfig.maxStacks or 10)
            tracking.lastUpdate = GetTime()

            if self.debugTracking then
                local buffInfo = C_Spell.GetSpellInfo(buffId)
                local buffName = buffInfo and buffInfo.name or "Unknown"
                local spellInfo = C_Spell.GetSpellInfo(spellId)
                local spellName = spellInfo and spellInfo.name or "Unknown"
                print("|cFF00FF00[TA Shadow Stacks]|r", spellName, "granted", stacksToAdd, "stacks of", buffName, "- Total:", tracking.stacks)
            end
        end
    end
end

function secretValues:GetShadowStackCount(buffId)
    local buffConfig = self.KnownShadowStackBuffs[buffId]
    if not buffConfig then
        return nil
    end

    local auraInfo = C_UnitAuras.GetPlayerAuraBySpellID(buffId)
    if not auraInfo then
        if self.trackedShadowStacks[buffId] then
            self.trackedShadowStacks[buffId].stacks = 0
        end
        return 0
    end

    local tracking = self.trackedShadowStacks[buffId]
    if not tracking then
        return nil
    end

    return tracking.stacks
end

function secretValues:ResetShadowStacks(buffId)
    if self.trackedShadowStacks[buffId] then
        self.trackedShadowStacks[buffId].stacks = 0
        self.trackedShadowStacks[buffId].lastUpdate = GetTime()
    end
end

function secretValues:ConsumeShadowStack(buffId, amount)
    amount = amount or 1
    if self.trackedShadowStacks[buffId] then
        self.trackedShadowStacks[buffId].stacks = math.max(0, self.trackedShadowStacks[buffId].stacks - amount)
        self.trackedShadowStacks[buffId].lastUpdate = GetTime()
    end
end

secretValues.debugTracking = false

function secretValues:SetDebugTracking(enabled)
    self.debugTracking = enabled
    print("|cFF00FF00[TankAssist]|r Spell tracking debug:", enabled and "ON" or "OFF")
end

function secretValues:GetTrackedCharges(spellId)
    local chargeData = self.KnownChargeSpells[spellId]
    if not chargeData then
        return nil, nil
    end

    local tracking = self.trackedCharges[spellId]
    if not tracking then
        return chargeData.maxCharges, chargeData.maxCharges
    end

    local now = GetTime()
    local chargesUsed = 0
    for _, castTime in ipairs(tracking.castTimes) do
        local elapsed = now - castTime
        if elapsed < tracking.rechargeTime then
            chargesUsed = chargesUsed + 1
        end
    end

    local currentCharges = tracking.maxCharges - chargesUsed
    return math.max(0, currentCharges), tracking.maxCharges
end

function secretValues:GetTrackedCooldown(spellId)
    local chargeData = self.KnownChargeSpells[spellId]
    if chargeData then
        local charges, maxCharges = self:GetTrackedCharges(spellId)
        if charges and charges > 0 then
            return 0
        elseif charges == 0 then
            local tracking = self.trackedCharges[spellId]
            if tracking and #tracking.castTimes > 0 then
                local oldestCast = tracking.castTimes[1]
                local elapsed = GetTime() - oldestCast
                return math.max(0, tracking.rechargeTime - elapsed)
            end
        end
        return nil
    end

    local tracked = self.trackedCooldowns[spellId]
    if not tracked then
        return nil
    end

    local elapsed = GetTime() - tracked.castTime
    local remaining = tracked.duration - elapsed

    if remaining <= 0 then
        self.trackedCooldowns[spellId] = nil
        return 0
    end

    return remaining
end

function secretValues:IsFillerSpell(spellId)
    local knownCD = self.KnownCooldowns[spellId]
    return knownCD ~= nil and knownCD <= 1.5
end

secretValues.KnownSpellCosts = {}

function secretValues:RegisterSpellData(specConstants)
    if specConstants.CooldownDurations then
        for spellId, duration in pairs(specConstants.CooldownDurations) do
            self.KnownCooldowns[spellId] = duration
        end
    end
    if specConstants.ChargeSpells then
        for spellId, data in pairs(specConstants.ChargeSpells) do
            self.KnownChargeSpells[spellId] = data
        end
    end
    if specConstants.StackingBuffs then
        for spellId, data in pairs(specConstants.StackingBuffs) do
            self.KnownStackingBuffs[spellId] = data
        end
    end
    if specConstants.SpellCosts then
        for spellId, data in pairs(specConstants.SpellCosts) do
            self.KnownSpellCosts[spellId] = data
        end
    end
    if specConstants.KnownShadowStackBuffs then
        for buffId, data in pairs(specConstants.KnownShadowStackBuffs) do
            self.KnownShadowStackBuffs[buffId] = data
        end
    end
end

function secretValues:HasResourcesForSpell(spellId)
    local costData = self.KnownSpellCosts[spellId]
    if not costData then
        return true
    end
    local currentResource = self:GetResource(costData.resource)
    if currentResource == nil then
        return true
    end
    return currentResource >= costData.cost
end

function secretValues:GetBuffInfo(unit, spellId)
    local result = {
        exists = false,
        stacks = nil,
        duration = nil,
        expirationTime = nil,
        isSecret = false,
    }

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
        if auraData then
            result.exists = true
            result.stacks = self:SafeNumber(auraData.applications, 0)
            result.duration = self:SafeNumber(auraData.duration, 0)
            result.expirationTime = self:SafeNumber(auraData.expirationTime, 0)
            if self:IsSecret(auraData.applications) or
               self:IsSecret(auraData.duration) or
               self:IsSecret(auraData.expirationTime) then
                result.isSecret = true
            end
        end
    else
        local spellInfo = C_Spell.GetSpellInfo(spellId)
        local spellName = spellInfo and spellInfo.name
        local name, icon, count, _, duration, expirationTime = AuraUtil.FindAuraByName(
            spellName, unit, "HELPFUL|PLAYER"
        )
        if name then
            result.exists = true
            result.stacks = self:SafeNumber(count, 0)
            result.duration = self:SafeNumber(duration, 0)
            result.expirationTime = self:SafeNumber(expirationTime, 0)
            if self:IsSecret(count) or self:IsSecret(duration) then
                result.isSecret = true
            end
        end
    end

    local cacheKey = unit .. "_" .. spellId
    if result.exists and not result.isSecret then
        self.buffCache[cacheKey] = {
            data = result,
            time = GetTime(),
        }
    end

    if result.isSecret and self.buffCache[cacheKey] then
        local cached = self.buffCache[cacheKey]
        if GetTime() - cached.time < self.CacheDuration then
            local cachedResult = CopyTable(cached.data)
            cachedResult.isCached = true
            return cachedResult
        end
    end

    if result.isSecret or not result.exists then
        local trackedData = self:GetTrackedStackingBuff(spellId)
        if trackedData and trackedData.exists then
            return {
                exists = true,
                stacks = trackedData.stacks,
                duration = trackedData.duration,
                expirationTime = trackedData.expirationTime,
                minRemaining = trackedData.minRemaining,
                maxRemaining = trackedData.maxRemaining,
                isSecret = false,
                isShadowTracked = true,
            }
        end
    end

    return result
end

function secretValues:GetBuffRemaining(unit, spellId)
    local info = self:GetBuffInfo(unit, spellId)
    if not info.exists then
        return 0
    end
    if info.isSecret and not info.expirationTime then
        return nil
    end
    local remaining = (info.expirationTime or 0) - GetTime()
    return math.max(0, remaining)
end

function secretValues:BuffNeedsRefresh(unit, spellId, threshold)
    local remaining = self:GetBuffRemaining(unit, spellId)
    if remaining == nil then
        return nil
    end
    return remaining < threshold
end

secretValues.SecondaryResources = {
    "RAGE",
    "ENERGY",
    "FURY",
    "RUNIC_POWER",
    "HOLY_POWER",
    "COMBO_POINTS",
    "CHI",
    "SOUL_SHARDS",
    "ARCANE_CHARGES",
    "RUNES",
    "SOUL_FRAGMENTS",
    "STAGGER",
    "MAELSTROM_WEAPON",
}

function secretValues:IsResourceWhitelisted(resourceType)
    for _, res in ipairs(self.SecondaryResources) do
        if res == resourceType then
            return true
        end
    end
    return false
end

function secretValues:GetResource(resourceType)
    local value
    local powerType

    if resourceType == "RUNIC_POWER" then
        powerType = Enum.PowerType.RunicPower
    elseif resourceType == "RUNES" then
        return self:GetAvailableRunes()
    elseif resourceType == "ENERGY" then
        powerType = Enum.PowerType.Energy
    elseif resourceType == "RAGE" then
        powerType = Enum.PowerType.Rage
    elseif resourceType == "FURY" then
        powerType = Enum.PowerType.Fury
    elseif resourceType == "HOLY_POWER" then
        powerType = Enum.PowerType.HolyPower
    elseif resourceType == "COMBO_POINTS" then
        powerType = Enum.PowerType.ComboPoints
    elseif resourceType == "CHI" then
        powerType = Enum.PowerType.Chi
    elseif resourceType == "STAGGER" then
        powerType = Enum.PowerType.Stagger
    elseif resourceType == "SOUL_FRAGMENTS" then
        return self:GetSoulFragments()
    else
        powerType = nil
    end

    if powerType then
        value = UnitPower("player", powerType)
    else
        value = UnitPower("player")
    end

    if value ~= nil and type(value) == "number" then
        local canUse = pcall(function() return value >= 0 end)
        if canUse then
            return value
        end
    end

    if self:IsSecret(value) then
        return nil
    end

    return value
end

function secretValues:GetSoulFragments()
    local SOUL_FRAGMENTS_BUFF = 203981
    local info = self:GetBuffInfo("player", SOUL_FRAGMENTS_BUFF)
    return info.stacks or 0
end

function secretValues:GetStaggerInfo()
    local result = {
        amount = 0,
        percent = 0,
        level = "NONE",
        isSecret = false,
    }

    local staggerAmountRaw = nil
    if UnitStagger then
        staggerAmountRaw = UnitStagger("player")
    end

    if staggerAmountRaw ~= nil and self:IsSecret(staggerAmountRaw) then
        result.isSecret = true
        return result
    end

    if (staggerAmountRaw == nil or staggerAmountRaw == 0) and Enum and Enum.PowerType then
        if Enum.PowerType.Stagger then
            local powerStagger = UnitPower("player", Enum.PowerType.Stagger)
            if powerStagger ~= nil and self:IsSecret(powerStagger) then
                result.isSecret = true
                return result
            end
            if powerStagger and powerStagger > 0 then
                staggerAmountRaw = powerStagger
            end
        end
    end

    if staggerAmountRaw == nil or staggerAmountRaw == 0 then
        local indexStagger = UnitPower("player", 13)
        if indexStagger ~= nil and self:IsSecret(indexStagger) then
            result.isSecret = true
            return result
        end
        if indexStagger and indexStagger > 0 then
            staggerAmountRaw = indexStagger
        end
    end
    staggerAmountRaw = staggerAmountRaw or 0
    local maxHealthRaw = UnitHealthMax("player")
    if self:IsSecret(maxHealthRaw) then
        result.isSecret = true
        return result
    end

    local staggerAmount = self:SafeNumber(staggerAmountRaw, 0)
    local maxHealth = self:SafeNumber(maxHealthRaw, 1)

    if staggerAmount and maxHealth and maxHealth > 0 then
        result.amount = staggerAmount
        result.percent = staggerAmount / maxHealth
        if result.percent >= 0.08 then
            result.level = "HEAVY"
        elseif result.percent >= 0.04 then
            result.level = "MODERATE"
        elseif result.percent > 0 then
            result.level = "LIGHT"
        end
    end

    return result
end

function secretValues:GetAvailableRunes()
    local available = 0
    for i = 1, 6 do
        local start, duration, runeReady = GetRuneCooldown(i)
        if not self:IsSecret(runeReady) and runeReady then
            available = available + 1
        end
    end
    return available
end

function secretValues:GetHealthPercent(unit)
    local health = UnitHealth(unit)
    local maxHealth = UnitHealthMax(unit)
    if self:IsSecret(health) or self:IsSecret(maxHealth) then
        return nil
    end
    if maxHealth == 0 then
        return 1
    end
    return health / maxHealth
end

function secretValues:IsBelowHealthThreshold(unit, threshold)
    local percent = self:GetHealthPercent(unit)
    if percent == nil then
        return nil
    end
    return percent < threshold
end

secretValues.WhitelistedCooldowns = {
    [20484] = true,
    [61999] = true,
    [20707] = true,
    [61304] = true,
    [187880] = true,
}

function secretValues:GetCooldownInfo(spellId)
    local result = {
        onCooldown = false,
        remaining = 0,
        charges = nil,
        maxCharges = nil,
        isSecret = false,
        isWhitelisted = self.WhitelistedCooldowns[spellId] or false,
    }

    local chargeInfo = C_Spell.GetSpellCharges(spellId)
    local chargesRaw = chargeInfo and chargeInfo.currentCharges
    local maxChargesRaw = chargeInfo and chargeInfo.maxCharges
    local chargeStartRaw = chargeInfo and chargeInfo.cooldownStartTime
    local chargeDurationRaw = chargeInfo and chargeInfo.cooldownDuration

    if chargesRaw ~= nil then
        if self:IsSecret(chargesRaw) and not result.isWhitelisted then
            result.isSecret = true
            result.onCooldown = true
            return result
        end

        result.charges = self:SafeNumber(chargesRaw)
        result.maxCharges = self:SafeNumber(maxChargesRaw)

        if result.charges and result.charges > 0 then
            result.onCooldown = false
            result.remaining = 0
        else
            result.onCooldown = true
            local start = self:SafeNumber(chargeStartRaw, 0)
            local duration = self:SafeNumber(chargeDurationRaw, 0)
            result.remaining = math.max(0, (start + duration) - GetTime())
        end
    else
        local cooldownInfo = C_Spell.GetSpellCooldown(spellId)
        local startRaw = cooldownInfo and cooldownInfo.startTime
        local durationRaw = cooldownInfo and cooldownInfo.duration
        if (self:IsSecret(startRaw) or self:IsSecret(durationRaw)) and not result.isWhitelisted then
            result.isSecret = true
            result.onCooldown = true
            return result
        end

        local start = self:SafeNumber(startRaw, 0)
        local duration = self:SafeNumber(durationRaw, 0)
        local remaining = 0
        if start and start > 0 and duration and duration > 0 then
            remaining = (start + duration) - GetTime()
        end

        if remaining > 0 and duration > 1.5 then
            result.onCooldown = true
            result.remaining = remaining
        else
            result.onCooldown = false
            result.remaining = 0
        end
    end

    return result
end

function secretValues:IsSpellUsable(spellId)
    local usable, insufficientPower = C_Spell.IsSpellUsable(spellId)
    if self:IsSecret(usable) then
        return nil
    end
    return usable == true
end

function secretValues:CanCastSpell(spellId)
    if not spellId then
        return false, "NO_SPELL"
    end

    local usable, insufficientPower = C_Spell.IsSpellUsable(spellId)
    if usable == false and not self:IsSecret(usable) then
        if insufficientPower then
            return false, "NO_RESOURCES"
        end
        return false, "NOT_USABLE"
    end

    if usable == nil or self:IsSecret(usable) then
        if not self:HasResourcesForSpell(spellId) then
            return false, "NO_RESOURCES_TRACKED"
        end
    end

    local chargeInfo = C_Spell.GetSpellCharges(spellId)
    if chargeInfo then
        local maxCharges = chargeInfo.maxCharges
        local charges = chargeInfo.currentCharges
        local chargesUsable = false
        local hasCharges = false
        local noCharges = false
        local success = pcall(function()
            if maxCharges and type(maxCharges) == "number" and maxCharges > 0 then
                chargesUsable = true
                if charges and type(charges) == "number" then
                    if charges <= 0 then
                        noCharges = true
                    elseif charges > 0 then
                        hasCharges = true
                    end
                end
            end
        end)

        if not success or self:IsSecret(maxCharges) or self:IsSecret(charges) then
            local trackedCharges, trackedMax = self:GetTrackedCharges(spellId)
            if trackedCharges ~= nil then
                if trackedCharges > 0 then
                    return true, nil
                else
                    return false, "NO_CHARGES_TRACKED"
                end
            end
        elseif chargesUsable then
            if noCharges then
                return false, "NO_CHARGES"
            elseif hasCharges then
                return true, nil
            end
        end
    else
        local trackedCharges, trackedMax = self:GetTrackedCharges(spellId)
        if trackedCharges ~= nil then
            if trackedCharges > 0 then
                return true, nil
            else
                return false, "NO_CHARGES_TRACKED"
            end
        end
    end

    local cooldownInfo = C_Spell.GetSpellCooldown(spellId)
    local apiCooldownAvailable = false
    local isOnCooldown = false

    if cooldownInfo then
        local startTime = cooldownInfo.startTime
        local duration = cooldownInfo.duration
        local success = pcall(function()
            if startTime ~= nil and duration ~= nil and
               type(startTime) == "number" and type(duration) == "number" then
                apiCooldownAvailable = true
                if startTime > 0 and duration > 1.5 then
                    local remaining = (startTime + duration) - GetTime()
                    if remaining > 0.3 then
                        isOnCooldown = true
                    end
                end
            end
        end)
        if not success or self:IsSecret(startTime) or self:IsSecret(duration) then
            apiCooldownAvailable = false
        end
    end
    if apiCooldownAvailable and isOnCooldown then
        return false, "ON_COOLDOWN"
    end
    if apiCooldownAvailable and not isOnCooldown then
        return true, nil
    end
    local trackedRemaining = self:GetTrackedCooldown(spellId)

    if trackedRemaining ~= nil then
        if trackedRemaining > 0.5 then
            return false, "TRACKED_CD"
        else
            return true, nil
        end
    end
    return true, "NOT_TRACKED_YET"
end

function secretValues:InCombat()
    return UnitAffectingCombat("player")
end

function secretValues:HasTarget()
    return UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target")
end

function secretValues:InMythicPlus()
    local _, _, difficultyID = GetInstanceInfo()
    return difficultyID == 8
end

secretValues.debugMode = false

function secretValues:Debug(...)
    if self.debugMode then
        print("|cFF00FF00[TankAssist Secret]|r", ...)
    end
end

function secretValues:SetDebug(enabled)
    self.debugMode = enabled
end
