-- TankAssist SecretValues Handler
-- Handles the 12.0 Secret Values system for safe combat data access

local ADDON_NAME, TA = ...
TA.SecretValues = {}

local SV = TA.SecretValues

-- =============================================================================
-- SECRET VALUE DETECTION
-- =============================================================================

-- Check if a value is secret (can't be operated on)
function SV:IsSecret(value)
    if issecretvalue then
        return issecretvalue(value)
    end
    return false
end

-- Check if we can access secrets (execution is not tainted)
function SV:CanAccessSecrets()
    if canaccesssecrets then
        return canaccesssecrets()
    end
    return true -- Assume we can if function doesn't exist
end

-- Check if we can access a specific value
function SV:CanAccessValue(value)
    if canaccessvalue then
        return canaccessvalue(value)
    end
    return true
end

-- =============================================================================
-- SAFE DATA RETRIEVAL
-- These functions attempt to get data and return nil if it's secret/unavailable
-- =============================================================================

-- Safely get a numeric value, returns nil if secret
function SV:SafeNumber(value, default)
    if value == nil then
        return default
    end
    
    if self:IsSecret(value) then
        return default
    end
    
    return value
end

-- Safely perform a comparison - returns nil if we can't compare
function SV:SafeCompare(value, threshold, operator)
    if self:IsSecret(value) then
        return nil -- Can't determine
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

-- =============================================================================
-- AURA/BUFF TRACKING
-- Handles the complexity of buff tracking in 12.0
-- =============================================================================

-- Cache for storing last known buff states (used when values become secret)
SV.buffCache = {}
SV.lastCacheUpdate = 0
SV.CACHE_DURATION = 0.5 -- How long to trust cached values

-- =============================================================================
-- COOLDOWN TRACKING (fallback when API data is secret)
-- We track when spells are cast and estimate when they come off cooldown
-- =============================================================================

SV.trackedCooldowns = {} -- [spellId] = { castTime = X, duration = Y }
SV.trackedCharges = {}   -- [spellId] = { castTimes = {t1, t2, ...}, maxCharges = N, rechargeDuration = X }
SV.trackedStackingBuffs = {} -- [spellId] = { stacks = { {castTime, expirationTime}, ... } }

-- =============================================================================
-- STACKING BUFF SHADOW TRACKING
-- For buffs like Ironfur where each cast adds an independent stack with its own duration
-- =============================================================================

-- Known stacking buffs that need shadow tracking
-- Format: [spellId] = { buffId = X, duration = Y }
-- buffId is the buff applied (often same as spell), duration is base duration in seconds
SV.KNOWN_STACKING_BUFFS = {
    [192081] = { buffId = 192081, duration = 7 },  -- Ironfur (Guardian Druid)
    [132403] = { buffId = 132403, duration = 4.5 }, -- Shield of the Righteous (Prot Paladin)
}

-- Track a stacking buff application
function SV:TrackStackingBuff(spellId)
    local buffData = self.KNOWN_STACKING_BUFFS[spellId]
    if not buffData then return end

    local now = GetTime()
    local expirationTime = now + buffData.duration

    -- Initialize tracking if needed
    if not self.trackedStackingBuffs[spellId] then
        self.trackedStackingBuffs[spellId] = { stacks = {} }
    end

    local tracking = self.trackedStackingBuffs[spellId]

    -- Clean up expired stacks
    local validStacks = {}
    for _, stack in ipairs(tracking.stacks) do
        if stack.expirationTime > now then
            table.insert(validStacks, stack)
        end
    end
    tracking.stacks = validStacks

    -- Add new stack
    table.insert(tracking.stacks, {
        castTime = now,
        expirationTime = expirationTime,
    })
end

-- Get shadow-tracked buff info for stacking buffs
-- Returns: { exists, stacks, minRemaining, maxRemaining } or nil if not tracked
function SV:GetTrackedStackingBuff(spellId)
    local buffData = self.KNOWN_STACKING_BUFFS[spellId]
    if not buffData then return nil end

    local tracking = self.trackedStackingBuffs[spellId]
    if not tracking then
        return { exists = false, stacks = 0, minRemaining = 0, maxRemaining = 0 }
    end

    local now = GetTime()

    -- Clean up expired stacks and calculate remaining times
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
        -- For compatibility, set expirationTime to when the last stack expires
        expirationTime = stackCount > 0 and (now + maxRemaining) or 0,
        duration = buffData.duration,
    }
end

-- Known charge-based spells with their max charges and recharge time
SV.KNOWN_CHARGE_SPELLS = {
    [119582] = { maxCharges = 2, rechargeTime = 20 },  -- Purifying Brew
    [194679] = { maxCharges = 2, rechargeTime = 25 },  -- Rune Tap
    [2565] = { maxCharges = 2, rechargeTime = 16 },    -- Shield Block
    [203720] = { maxCharges = 1, rechargeTime = 17 },  -- Demon Spikes (base 1 charge, 2 with Demonic Resilience talent)
    [22842] = { maxCharges = 2, rechargeTime = 36 },   -- Frenzied Regeneration
    [61336] = { maxCharges = 2, rechargeTime = 180 },  -- Survival Instincts
    [50842] = { maxCharges = 2, rechargeTime = 7.5 },  -- Blood Boil
}

-- Known spell cooldown durations (in seconds)
-- This is used as fallback when we can't get the info from the API
SV.KNOWN_COOLDOWNS = {
    -- Brewmaster Monk
    [121253] = 8,      -- Keg Smash
    [115181] = 15,     -- Breath of Fire
    [322729] = 0,      -- Spinning Crane Kick (no CD, just energy)
    [100780] = 0,      -- Tiger Palm (no CD, just energy)
    [205523] = 3,      -- Blackout Kick
    [116847] = 6,      -- Rushing Jade Wind (6s CD)
    [322507] = 45,     -- Celestial Brew
    [119582] = 20,     -- Purifying Brew (20s recharge per charge)
    [115203] = 180,    -- Fortifying Brew
    [322101] = 15,     -- Expel Harm
    [115176] = 300,    -- Zen Meditation
    [132578] = 180,    -- Invoke Niuzao
    [325153] = 60,     -- Exploding Keg
    [386276] = 60,     -- Bonedust Brew
    [387184] = 120,    -- Weapons of Order
    [122278] = 120,    -- Dampen Harm
    [122783] = 90,     -- Diffuse Magic

    -- Blood DK
    [195182] = 0,      -- Marrowrend (no CD, just runes)
    [206930] = 0,      -- Heart Strike (no CD, just runes)
    [50842] = 7.5,     -- Blood Boil
    [49998] = 0,       -- Death Strike (no CD, just RP)
    [43265] = 30,      -- Death and Decay
    [55233] = 90,      -- Vampiric Blood
    [49028] = 120,     -- Dancing Rune Weapon
    [48792] = 180,     -- Icebound Fortitude
    [48707] = 60,      -- Anti-Magic Shell
    [194679] = 25,     -- Rune Tap (charge-based)
    [194844] = 60,     -- Bonestorm

    -- Protection Warrior
    [23922] = 9,       -- Shield Slam
    [6343] = 6,        -- Thunder Clap
    [6572] = 0,        -- Revenge (no CD when proc, 3s otherwise)
    [2565] = 16,       -- Shield Block (charge-based)
    [190456] = 0,      -- Ignore Pain (no CD, just rage)
    [871] = 180,       -- Shield Wall
    [12975] = 180,     -- Last Stand
    [1160] = 45,       -- Demoralizing Shout
    [23920] = 25,      -- Spell Reflection
    [401150] = 90,     -- Avatar
    [46968] = 40,      -- Shockwave

    -- Protection Paladin
    [275779] = 6,      -- Judgment
    [31935] = 15,      -- Avenger's Shield
    [53600] = 0,       -- Shield of the Righteous (no CD, just Holy Power)
    [53595] = 0,       -- Hammer of the Righteous (no CD)
    [26573] = 4,       -- Consecration (4s CD)
    [85673] = 0,       -- Word of Glory (no CD, just Holy Power)
    [31850] = 120,     -- Ardent Defender
    [86659] = 300,     -- Guardian of Ancient Kings
    [31884] = 60,      -- Avenging Wrath
    [375576] = 60,     -- Divine Toll
    [387174] = 60,     -- Eye of Tyr
    [633] = 600,       -- Lay on Hands (10 min CD)
    [642] = 300,       -- Divine Shield (5 min CD)
    [389539] = 120,    -- Sentinel (2 min CD)

    -- Vengeance DH
    [203782] = 0,      -- Shear (no CD)
    [263642] = 4.5,    -- Fracture
    [228477] = 0,      -- Soul Cleave (no CD)
    [247454] = 0,      -- Spirit Bomb (no CD, just fury + fragments)
    [258920] = 30,     -- Immolation Aura
    [204596] = 30,     -- Sigil of Flame
    [390163] = 60,     -- Sigil of Spite
    [203720] = 17,     -- Demon Spikes (charge-based)
    [204021] = 60,     -- Fiery Brand
    [187827] = 180,    -- Metamorphosis
    [212084] = 40,     -- Fel Devastation

    -- Guardian Druid
    [33917] = 6,       -- Mangle
    [77758] = 6,       -- Thrash (6s CD)
    [213771] = 0,      -- Swipe (no CD, just GCD)
    [6807] = 3,        -- Maul (3s CD)
    [192081] = 0,      -- Ironfur (no CD, just rage)
    [22842] = 36,      -- Frenzied Regeneration (charge-based)
    [22812] = 60,      -- Barkskin
    [61336] = 180,     -- Survival Instincts (charge-based)
    [102558] = 180,    -- Incarnation: Guardian of Ursoc
    [50334] = 180,     -- Berserk
    [200851] = 60,     -- Rage of the Sleeper
    [155835] = 40,     -- Bristling Fur
    [391528] = 120,    -- Convoke the Spirits
    [8921] = 0,        -- Moonfire (no CD)
}

-- Record when a spell is cast (call this from spell cast events)
function SV:OnSpellCast(spellId)
    local now = GetTime()

    -- Check if this is a charge-based spell
    local chargeData = self.KNOWN_CHARGE_SPELLS[spellId]
    if chargeData then
        -- Initialize tracking if needed
        if not self.trackedCharges[spellId] then
            self.trackedCharges[spellId] = {
                castTimes = {},
                maxCharges = chargeData.maxCharges,
                rechargeTime = chargeData.rechargeTime,
            }
        end

        local tracking = self.trackedCharges[spellId]

        -- Clean up old cast times that have fully recharged
        local validCasts = {}
        for _, castTime in ipairs(tracking.castTimes) do
            local elapsed = now - castTime
            if elapsed < tracking.rechargeTime then
                table.insert(validCasts, castTime)
            end
        end
        tracking.castTimes = validCasts

        -- Record this cast
        table.insert(tracking.castTimes, now)

        -- Debug output for charge spells
        if self.debugTracking then
            local spellInfo = C_Spell.GetSpellInfo(spellId)
            local spellName = spellInfo and spellInfo.name or "Unknown"
            local chargesRemaining = tracking.maxCharges - #tracking.castTimes
            print("|cFF00FF00[TA Tracking]|r", spellName, "(" .. spellId .. ") - Charges:", chargesRemaining .. "/" .. tracking.maxCharges)
        end
        return
    end

    -- Regular cooldown tracking
    local knownCD = self.KNOWN_COOLDOWNS[spellId]
    if knownCD and knownCD > 0 then
        self.trackedCooldowns[spellId] = {
            castTime = now,
            duration = knownCD,
        }
        -- Debug output
        if self.debugTracking then
            local spellInfo = C_Spell.GetSpellInfo(spellId)
            local spellName = spellInfo and spellInfo.name or "Unknown"
            print("|cFF00FF00[TA Tracking]|r", spellName, "(" .. spellId .. ") - CD:", knownCD .. "s")
        end
    end

    -- Track stacking buffs (like Ironfur)
    self:TrackStackingBuff(spellId)
end

-- Enable/disable tracking debug output
SV.debugTracking = false
function SV:SetDebugTracking(enabled)
    self.debugTracking = enabled
    print("|cFF00FF00[TankAssist]|r Spell tracking debug:", enabled and "ON" or "OFF")
end

-- Get tracked charges for a charge-based spell
-- Returns: currentCharges, maxCharges, or nil if not tracked
function SV:GetTrackedCharges(spellId)
    local chargeData = self.KNOWN_CHARGE_SPELLS[spellId]
    if not chargeData then
        return nil, nil -- Not a charge spell
    end

    local tracking = self.trackedCharges[spellId]
    if not tracking then
        -- Not tracked yet, assume full charges
        return chargeData.maxCharges, chargeData.maxCharges
    end

    local now = GetTime()
    local chargesUsed = 0

    -- Count how many charges are still on cooldown
    for _, castTime in ipairs(tracking.castTimes) do
        local elapsed = now - castTime
        if elapsed < tracking.rechargeTime then
            chargesUsed = chargesUsed + 1
        end
    end

    local currentCharges = tracking.maxCharges - chargesUsed
    return math.max(0, currentCharges), tracking.maxCharges
end

-- Check our tracked cooldown for a spell
function SV:GetTrackedCooldown(spellId)
    -- Check charge-based spells first
    local chargeData = self.KNOWN_CHARGE_SPELLS[spellId]
    if chargeData then
        local charges, maxCharges = self:GetTrackedCharges(spellId)
        if charges and charges > 0 then
            return 0 -- Has charges available, no cooldown
        elseif charges == 0 then
            -- All charges used, find the oldest one to calculate remaining
            local tracking = self.trackedCharges[spellId]
            if tracking and #tracking.castTimes > 0 then
                local oldestCast = tracking.castTimes[1]
                local elapsed = GetTime() - oldestCast
                return math.max(0, tracking.rechargeTime - elapsed)
            end
        end
        return nil
    end

    -- Regular cooldown tracking
    local tracked = self.trackedCooldowns[spellId]
    if not tracked then
        return nil -- Not tracked
    end

    local elapsed = GetTime() - tracked.castTime
    local remaining = tracked.duration - elapsed

    if remaining <= 0 then
        -- Cooldown finished, clear tracking
        self.trackedCooldowns[spellId] = nil
        return 0
    end

    return remaining
end

-- Check if spell has no significant cooldown (filler spell)
function SV:IsFillerSpell(spellId)
    local knownCD = self.KNOWN_COOLDOWNS[spellId]
    return knownCD ~= nil and knownCD <= 1.5
end

-- =============================================================================
-- KNOWN RESOURCE COSTS (fallback when API is restricted)
-- =============================================================================

SV.KNOWN_SPELL_COSTS = {
    -- Brewmaster Monk (Energy)
    [322729] = { resource = "ENERGY", cost = 25 },   -- Spinning Crane Kick
    [100780] = { resource = "ENERGY", cost = 50 },   -- Tiger Palm
    [121253] = { resource = "ENERGY", cost = 40 },   -- Keg Smash
    [322101] = { resource = "ENERGY", cost = 15 },   -- Expel Harm

    -- Blood DK (Runic Power / Runes)
    [49998] = { resource = "RUNIC_POWER", cost = 40 }, -- Death Strike

    -- Protection Warrior (Rage)
    [2565] = { resource = "RAGE", cost = 30 },       -- Shield Block
    [190456] = { resource = "RAGE", cost = 40 },     -- Ignore Pain
    [6572] = { resource = "RAGE", cost = 20 },       -- Revenge

    -- Vengeance DH (Fury)
    [228477] = { resource = "FURY", cost = 30 },     -- Soul Cleave
    [263642] = { resource = "FURY", cost = 25 },     -- Fracture
    [247454] = { resource = "FURY", cost = 40 },     -- Spirit Bomb

    -- Guardian Druid (Rage)
    [192081] = { resource = "RAGE", cost = 40 },     -- Ironfur
    [6807] = { resource = "RAGE", cost = 40 },       -- Maul
    [22842] = { resource = "RAGE", cost = 10 },      -- Frenzied Regeneration
}

-- Check if player has enough resources to cast a spell
function SV:HasResourcesForSpell(spellId)
    local costData = self.KNOWN_SPELL_COSTS[spellId]
    if not costData then
        return true -- No known cost, assume castable
    end

    local currentResource = self:GetResource(costData.resource)
    if currentResource == nil then
        return true -- Can't determine, assume castable
    end

    return currentResource >= costData.cost
end

-- Attempt to get buff info safely
function SV:GetBuffInfo(unit, spellId)
    local result = {
        exists = false,
        stacks = nil,
        duration = nil,
        expirationTime = nil,
        isSecret = false,
    }
    
    -- Try C_UnitAuras first (newer API)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
        if auraData then
            result.exists = true
            result.stacks = self:SafeNumber(auraData.applications, 0)
            result.duration = self:SafeNumber(auraData.duration, 0)
            result.expirationTime = self:SafeNumber(auraData.expirationTime, 0)
            
            -- Check if key values are secret
            if self:IsSecret(auraData.applications) or 
               self:IsSecret(auraData.duration) or
               self:IsSecret(auraData.expirationTime) then
                result.isSecret = true
            end
        end
    else
        -- Fallback to AuraUtil
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
    
    -- Update cache
    local cacheKey = unit .. "_" .. spellId
    if result.exists and not result.isSecret then
        self.buffCache[cacheKey] = {
            data = result,
            time = GetTime(),
        }
    end
    
    -- If current data is secret, try to use cached data
    if result.isSecret and self.buffCache[cacheKey] then
        local cached = self.buffCache[cacheKey]
        if GetTime() - cached.time < self.CACHE_DURATION then
            -- Return cached data but mark as potentially stale
            local cachedResult = CopyTable(cached.data)
            cachedResult.isCached = true
            return cachedResult
        end
    end

    -- If API data is secret or unavailable, try shadow tracking for known stacking buffs
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

-- Get remaining time on a buff
function SV:GetBuffRemaining(unit, spellId)
    local info = self:GetBuffInfo(unit, spellId)
    
    if not info.exists then
        return 0
    end
    
    if info.isSecret and not info.expirationTime then
        return nil -- Can't determine
    end
    
    local remaining = (info.expirationTime or 0) - GetTime()
    return math.max(0, remaining)
end

-- Check if a buff needs refreshing
function SV:BuffNeedsRefresh(unit, spellId, threshold)
    local remaining = self:GetBuffRemaining(unit, spellId)
    
    if remaining == nil then
        -- Can't determine, return uncertain state
        return nil
    end
    
    return remaining < threshold
end

-- =============================================================================
-- RESOURCE TRACKING
-- =============================================================================

-- Resource classification based on Blizzard's 12.0 whitelisting
-- Secondary resources are NOT secret (declassified)
-- Primary resources MAY be secret but can be displayed via Duration objects
SV.SECONDARY_RESOURCES = {
    -- Primary combat resources (typically accessible for player)
    "RAGE",            -- Warrior, Druid
    "ENERGY",          -- Rogue, Monk, Druid
    "FURY",            -- Demon Hunter
    "RUNIC_POWER",     -- Death Knight
    -- Secondary/combo resources
    "HOLY_POWER",
    "COMBO_POINTS",
    "CHI",
    "SOUL_SHARDS",
    "ARCANE_CHARGES",
    "RUNES",
    "SOUL_FRAGMENTS",  -- Explicitly whitelisted for DH
    "STAGGER",         -- Explicitly whitelisted for Brewmaster
    "MAELSTROM_WEAPON", -- Explicitly whitelisted for Enhancement
}

-- Check if a resource type is whitelisted (secondary/declassified)
function SV:IsResourceWhitelisted(resourceType)
    for _, res in ipairs(self.SECONDARY_RESOURCES) do
        if res == resourceType then
            return true
        end
    end
    return false
end

-- Get player resource safely
-- NOTE: During combat, resource values are often "secret" and cannot be compared
-- Use C_Spell.IsSpellUsable() instead for checking if spells are castable
function SV:GetResource(resourceType)
    local value
    local powerType

    if resourceType == "RUNIC_POWER" then
        powerType = Enum.PowerType.RunicPower
    elseif resourceType == "RUNES" then
        return self:GetAvailableRunes() -- Runes are secondary, always accessible
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
        -- Stagger is explicitly whitelisted! Use the Stagger power type
        powerType = Enum.PowerType.Stagger
    elseif resourceType == "SOUL_FRAGMENTS" then
        -- Soul Fragments - check via buff or power depending on spec
        return self:GetSoulFragments()
    else
        powerType = nil
    end
    
    if powerType then
        value = UnitPower("player", powerType)
    else
        value = UnitPower("player")
    end

    -- During combat, values may be "secret" - they print but can't be compared
    -- Try to use the value if it's a usable number
    if value ~= nil and type(value) == "number" then
        -- Try to verify we can actually use this value (comparison won't error)
        local canUse = pcall(function() return value >= 0 end)
        if canUse then
            return value
        end
    end

    -- Value is secret or unusable during combat
    if self:IsSecret(value) then
        return nil
    end

    return value
end

-- Get Soul Fragments for Vengeance DH (explicitly whitelisted)
function SV:GetSoulFragments()
    -- Soul Fragments are tracked as a buff with stacks
    -- Spell ID 203981 is the Soul Fragments buff
    local SOUL_FRAGMENTS_BUFF = 203981
    local info = self:GetBuffInfo("player", SOUL_FRAGMENTS_BUFF)
    return info.stacks or 0
end

-- Get Stagger amount for Brewmaster (explicitly whitelisted)
function SV:GetStaggerInfo()
    local result = {
        amount = 0,
        percent = 0,
        level = "NONE",
        isSecret = false,
    }

    -- Try multiple methods to get stagger amount
    local staggerAmountRaw = nil

    -- Method 1: UnitStagger (primary API)
    if UnitStagger then
        staggerAmountRaw = UnitStagger("player")
    end

    -- Check if the value is secret before comparing
    if staggerAmountRaw ~= nil and self:IsSecret(staggerAmountRaw) then
        result.isSecret = true
        return result
    end

    -- Method 2: Fallback to power type if UnitStagger returns 0 or nil
    if (staggerAmountRaw == nil or staggerAmountRaw == 0) and Enum and Enum.PowerType then
        -- Try Stagger power type (index 13 in some versions)
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

    -- Method 3: Try by power index directly (Stagger is typically 13)
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

    -- Default to 0 if still nil
    staggerAmountRaw = staggerAmountRaw or 0

    local maxHealthRaw = UnitHealthMax("player")

    -- Check if max health is secret
    if self:IsSecret(maxHealthRaw) then
        result.isSecret = true
        return result
    end

    local staggerAmount = self:SafeNumber(staggerAmountRaw, 0)
    local maxHealth = self:SafeNumber(maxHealthRaw, 1)

    if staggerAmount and maxHealth and maxHealth > 0 then
        result.amount = staggerAmount
        result.percent = staggerAmount / maxHealth

        -- Determine stagger level based on % of max health in stagger pool
        -- These thresholds are tuned to be useful in actual gameplay:
        -- Heavy (red): >= 8% - purify urgently
        -- Moderate (yellow): >= 4% - consider purifying
        -- Light (green): > 0% - manageable
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

-- DK-specific: Get available runes
function SV:GetAvailableRunes()
    local available = 0
    for i = 1, 6 do
        local start, duration, runeReady = GetRuneCooldown(i)
        -- Check if runeReady is secret before using it
        if not self:IsSecret(runeReady) and runeReady then
            available = available + 1
        end
    end
    return available
end

-- =============================================================================
-- HEALTH TRACKING
-- =============================================================================

-- Get health percentage safely
function SV:GetHealthPercent(unit)
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

-- Check if unit is below health threshold
function SV:IsBelowHealthThreshold(unit, threshold)
    local percent = self:GetHealthPercent(unit)
    
    if percent == nil then
        return nil -- Can't determine
    end
    
    return percent < threshold
end

-- =============================================================================
-- COOLDOWN TRACKING
-- Blizzard is whitelisting specific spell cooldowns as non-secret
-- =============================================================================

-- Known whitelisted cooldowns (Blizzard adding more over time)
-- These can be tracked without secret value restrictions
SV.WHITELISTED_COOLDOWNS = {
    -- Combat Res spells (whitelisted)
    [20484] = true,  -- Rebirth
    [61999] = true,  -- Raise Ally
    [20707] = true,  -- Soulstone
    
    -- GCD spell (whitelisted)
    [61304] = true,  -- Global Cooldown
    
    -- Maelstrom Weapon (whitelisted)
    [187880] = true, -- Maelstrom Weapon
    
    -- Skyriding spells (whitelisted)
    -- Add more as Blizzard confirms them
    
    -- Note: Many tank cooldowns may be accessible through the
    -- Cooldown Manager API even if not explicitly whitelisted
}

-- Get cooldown info for a spell
function SV:GetCooldownInfo(spellId)
    local result = {
        onCooldown = false,
        remaining = 0,
        charges = nil,
        maxCharges = nil,
        isSecret = false,
        isWhitelisted = self.WHITELISTED_COOLDOWNS[spellId] or false,
    }

    -- Check for charges first
    local chargeInfo = C_Spell.GetSpellCharges(spellId)
    local chargesRaw = chargeInfo and chargeInfo.currentCharges
    local maxChargesRaw = chargeInfo and chargeInfo.maxCharges
    local chargeStartRaw = chargeInfo and chargeInfo.cooldownStartTime
    local chargeDurationRaw = chargeInfo and chargeInfo.cooldownDuration

    if chargesRaw ~= nil then
        -- Check for secret values BEFORE converting
        if self:IsSecret(chargesRaw) and not result.isWhitelisted then
            result.isSecret = true
            result.onCooldown = true -- Conservative: assume on CD if secret
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
        -- Regular cooldown
        local cooldownInfo = C_Spell.GetSpellCooldown(spellId)
        local startRaw = cooldownInfo and cooldownInfo.startTime
        local durationRaw = cooldownInfo and cooldownInfo.duration

        -- Check for secret values BEFORE converting
        if (self:IsSecret(startRaw) or self:IsSecret(durationRaw)) and not result.isWhitelisted then
            result.isSecret = true
            result.onCooldown = true -- Conservative: assume on CD if secret
            return result
        end

        local start = self:SafeNumber(startRaw, 0)
        local duration = self:SafeNumber(durationRaw, 0)

        -- Calculate remaining time
        local remaining = 0
        if start and start > 0 and duration and duration > 0 then
            remaining = (start + duration) - GetTime()
        end

        -- On cooldown if remaining time > 0 (and not just GCD)
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

-- Check if spell is usable (has resources, correct form, etc.)
-- NOTE: This does NOT check cooldowns - use CanCastSpell for full check
function SV:IsSpellUsable(spellId)
    local usable, insufficientPower = C_Spell.IsSpellUsable(spellId)

    if self:IsSecret(usable) then
        return nil
    end

    return usable == true
end

-- =============================================================================
-- UNIFIED SPELL CASTABILITY CHECK
-- Checks BOTH resources AND cooldown using WoW APIs
-- Returns: canCast (boolean), reason (string or nil)
-- =============================================================================

function SV:CanCastSpell(spellId)
    if not spellId then
        return false, "NO_SPELL"
    end

    -- Step 1: Check if spell is usable via API (resources, form, etc.)
    local usable, insufficientPower = C_Spell.IsSpellUsable(spellId)

    -- If API gives us a clear "false" (not secret), trust it
    if usable == false and not self:IsSecret(usable) then
        if insufficientPower then
            return false, "NO_RESOURCES"
        end
        return false, "NOT_USABLE"
    end

    -- Step 1b: If API is secret/unavailable, check resources ourselves
    if usable == nil or self:IsSecret(usable) then
        if not self:HasResourcesForSpell(spellId) then
            return false, "NO_RESOURCES_TRACKED"
        end
    end

    -- Step 2: Check charges (for spells like Purifying Brew, Demon Spikes)
    local chargeInfo = C_Spell.GetSpellCharges(spellId)
    if chargeInfo then
        local maxCharges = chargeInfo.maxCharges
        local charges = chargeInfo.currentCharges

        -- Check if charge data is secret or if comparisons fail
        local chargesUsable = false
        local hasCharges = false
        local noCharges = false

        -- Try to use the charge values - they might be secret even if IsSecret returns false
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
            -- Charges are secret or comparison failed - use our tracking instead
            local trackedCharges, trackedMax = self:GetTrackedCharges(spellId)
            if trackedCharges ~= nil then
                if trackedCharges > 0 then
                    return true, nil -- Has tracked charges
                else
                    return false, "NO_CHARGES_TRACKED"
                end
            end
            -- No tracking data, fall through to cooldown check
        elseif chargesUsable then
            if noCharges then
                return false, "NO_CHARGES"
            elseif hasCharges then
                return true, nil
            end
        end
    else
        -- No chargeInfo from API - check if this is a known charge spell
        local trackedCharges, trackedMax = self:GetTrackedCharges(spellId)
        if trackedCharges ~= nil then
            if trackedCharges > 0 then
                return true, nil -- Has tracked charges
            else
                return false, "NO_CHARGES_TRACKED"
            end
        end
    end

    -- Step 3: Check cooldown via API
    local cooldownInfo = C_Spell.GetSpellCooldown(spellId)
    local apiCooldownAvailable = false
    local isOnCooldown = false

    if cooldownInfo then
        local startTime = cooldownInfo.startTime
        local duration = cooldownInfo.duration

        -- Try to use cooldown values - wrap in pcall in case they're secretly restricted
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

        -- If comparison failed or values are secret, mark as unavailable
        if not success or self:IsSecret(startTime) or self:IsSecret(duration) then
            apiCooldownAvailable = false
        end
    end

    -- If API says on cooldown, trust it
    if apiCooldownAvailable and isOnCooldown then
        return false, "ON_COOLDOWN"
    end

    -- If API says ready, trust it
    if apiCooldownAvailable and not isOnCooldown then
        return true, nil
    end

    -- Step 4: API data unavailable - use our tracked cooldowns as fallback
    local trackedRemaining = self:GetTrackedCooldown(spellId)

    if trackedRemaining ~= nil then
        -- We have tracking data for this spell
        if trackedRemaining > 0.5 then
            return false, "TRACKED_CD"
        else
            -- Tracked cooldown has expired, spell is ready
            return true, nil
        end
    end

    -- Step 5: No tracking data yet (spell hasn't been cast this session)
    -- Assume it's ready - it will start being tracked after first cast
    return true, "NOT_TRACKED_YET"
end

-- =============================================================================
-- COMBAT STATE
-- =============================================================================

function SV:InCombat()
    return UnitAffectingCombat("player")
end

function SV:HasTarget()
    return UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target")
end

function SV:InMythicPlus()
    -- Check if we're in an M+ keystone
    local _, _, difficultyID = GetInstanceInfo()
    -- M+ difficulty IDs: 8 (M+ Dungeon), 23 (Mythic), etc.
    return difficultyID == 8
end

-- =============================================================================
-- DEBUG/LOGGING
-- =============================================================================

SV.debugMode = false

function SV:Debug(...)
    if self.debugMode then
        print("|cFF00FF00[TankAssist Secret]|r", ...)
    end
end

function SV:SetDebug(enabled)
    self.debugMode = enabled
end
