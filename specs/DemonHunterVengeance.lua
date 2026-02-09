local ADDON_NAME, TankAssist = ...

TankAssist.Constants.VengeanceDemonHunter = {
    Spells = {
        Shear = 203782,
        Fracture = 263642,
        SoulCleave = 228477,
        SpiritBomb = 247454,
        ImmolationAura = 258920,
        SigilOfFlame = 204596,
        SigilOfSilence = 202137,
        SigilOfMisery = 207684,
        SigilOfChains = 202138,
        SigilOfSpite = 390163,
        DemonSpikes = 203720,
        FieryBrand = 204021,
        Metamorphosis = 187827,
        FelDevastation = 212084,
        InfernalStrike = 189110,
        TheHunt = 370965,
        SoulCarver = 207407,
    },

    SpellCosts = {
        [203782] = {
            resource = "FURY",
            cost = 0,
        },
        [263642] = {
            resource = "FURY",
            cost = 25,
        },
        [228477] = {
            resource = "FURY",
            cost = 30,
        },
        [247454] = {
            resource = "FURY",
            cost = 40,
        },
        [258920] = {
            resource = "FURY",
            cost = 0,
        },
        [204596] = {
            resource = "FURY",
            cost = 0,
        },
        [212084] = {
            resource = "FURY",
            cost = 50,
        },
    },

    Buffs = {
        DemonSpikes = 203819,
        Metamorphosis = 187827,
        SoulFragments = 203981,
        FieryBrand = 207744,
        ImmolationAura = 258920,
        CalcifiedSpikes = 391171,
        Painbringer = 207387,
    },

    Thresholds = {
        DemonSpikesRefresh = 2,
        SoulFragmentsSpiritBomb = 4,
        FuryForSoulCleave = 30,
        LowHealthPercent = 0.4,
    },

    Cooldowns = {
        Major = { 187827, 370965, 390163 },
        Defensive = { 204021, 212084 },
        Offensive = { 207407 },
    },

    CooldownDurations = {
        [203782] = 0,
        [263642] = 4.5,
        [228477] = 0,
        [247454] = 0,
        [258920] = 30,
        [204596] = 30,
        [390163] = 60,
        [203720] = 17,
        [204021] = 60,
        [187827] = 180,
        [212084] = 40,
    },
    ChargeSpells = {
        [203720] = { maxCharges = 1, rechargeTime = 17 },
    },
}

TankAssist.SecretValues:RegisterSpellData(TankAssist.Constants.VengeanceDemonHunter)

local vengeanceDH = TankAssist.SpecBase:New(581, "Vengeance Demon Hunter")

local spells = TankAssist.Constants.VengeanceDemonHunter.Spells
local buffs = TankAssist.Constants.VengeanceDemonHunter.Buffs
local thresholds = TankAssist.Constants.VengeanceDemonHunter.Thresholds

vengeanceDH.secondarySpells = {
    {
        spellId = spells.Metamorphosis,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.30)
        end,
    },
    {
        spellId = spells.SoulCleave,
        category = "HEAL",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.50)
        end,
    },
    {
        spellId = spells.DemonSpikes,
        category = "MITIGATION",
        urgency = "HIGH",
        condition = function(self)
            local buffInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.DemonSpikes)
            if not buffInfo.exists then
                return true
            end
            local remaining = buffInfo.expirationTime and (buffInfo.expirationTime - GetTime()) or 0
            return remaining < 2
        end,
    },
    {
        spellId = spells.FieryBrand,
        category = "DEFENSIVE",
        urgency = "HIGH",
        condition = function(self)
            return self:HealthBelow(0.50) and self:HasTarget()
        end,
    },
    {
        spellId = spells.SpiritBomb,
        category = "AOE",
        urgency = "HIGH",
        condition = function(self)
            local fragments = self:GetSoulFragments()
            return self:HasTarget() and fragments and fragments >= 4
        end,
    },
    {
        spellId = spells.SigilOfFlame,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },
    {
        spellId = spells.ImmolationAura,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            local buffInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.ImmolationAura)
            return not buffInfo.exists and self:HasTarget()
        end,
    },
    {
        spellId = spells.FelDevastation,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.TheHunt,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.SigilOfSpite,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.SoulCarver,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.Fracture,
        category = "FILLER",
        urgency = "LOW",
        condition = function(self)
            local fragments = self:GetSoulFragments()
            return self:HasTarget() and (not fragments or fragments < 4)
        end,
    },
    {
        spellId = spells.Shear,
        category = "FILLER",
        urgency = "LOW",
        condition = function(self)
            return self:HasTarget() and not IsSpellKnown(spells.Fracture)
        end,
    },
}

vengeanceDH.aoeSpells = {
    {
        spellId = spells.SigilOfFlame,
        priority = 1,
        condition = function() return true end,
    },
    {
        spellId = spells.ImmolationAura,
        priority = 2,
        condition = function() return true end,
    },
}

function vengeanceDH:GetBestAoESpell()
    for _, aoeData in ipairs(self.aoeSpells) do
        local spellId = aoeData.spellId
        if spellId and IsSpellKnown(spellId) then
            local cdInfo = TankAssist.SecretValues:GetCooldownInfo(spellId)
            local isReady = not cdInfo.onCooldown or (cdInfo.charges and cdInfo.charges > 0)
            local conditionMet = not aoeData.condition or aoeData.condition()
            if isReady and conditionMet then
                return spellId
            end
        end
    end
    return nil
end

function vengeanceDH:GetSoulFragments()
    local fragmentInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.SoulFragments)
    if fragmentInfo.isSecret then
        return nil
    end
    return fragmentInfo.stacks or 0
end

vengeanceDH.buffsToTrack = {
    {
        spellId = buffs.DemonSpikes,
        name = "Demon Spikes",
        refreshSpell = spells.DemonSpikes,
        refreshThreshold = thresholds.DemonSpikesRefresh,
        priority = "CRITICAL",
    },
    {
        spellId = buffs.FieryBrand,
        name = "Fiery Brand",
        refreshSpell = spells.FieryBrand,
        refreshThreshold = 0,
        priority = "HIGH",
    },
    {
        spellId = buffs.Metamorphosis,
        name = "Metamorphosis",
        refreshSpell = spells.Metamorphosis,
        refreshThreshold = 0,
        priority = "HIGH",
    },
}

vengeanceDH.tankActions = {
    MITIGATION = {
        spellId = spells.DemonSpikes,
        name = "Demon Spikes",
        condition = function()
            local buffInfo = TankAssist.SecretValues:GetBuffInfo("player", TankAssist.Constants.VengeanceDemonHunter.Buffs.DemonSpikes)
            return not buffInfo.exists
        end,
    },
    SHIELD = {
        spellId = spells.SoulCleave,
        name = "Soul Cleave",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.7
        end,
    },
    DEFENSIVE = {
        spellId = spells.Metamorphosis,
        name = "Metamorphosis",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.4
        end,
    },
    HEAL = {
        spellId = spells.SoulCleave,
        name = "Soul Cleave",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.5
        end,
    },
}

vengeanceDH.cooldownsToTrack = {
    {
        spellId = spells.Metamorphosis,
        name = "Metamorphosis",
        category = "MAJOR",
    },
    {
        spellId = spells.TheHunt,
        name = "The Hunt",
        category = "MAJOR",
    },
    {
        spellId = spells.SigilOfSpite,
        name = "Sigil of Spite",
        category = "MAJOR",
    },
    {
        spellId = spells.FieryBrand,
        name = "Fiery Brand",
        category = "DEFENSIVE",
    },
    {
        spellId = spells.FelDevastation,
        name = "Fel Devastation",
        category = "DEFENSIVE",
    },
    {
        spellId = spells.SoulCarver,
        name = "Soul Carver",
        category = "OFFENSIVE",
    },
}

vengeanceDH.rotationPriority = {
    {
        spellId = spells.SoulCleave,
        defaultPriority = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < thresholds.LowHealthPercent then
                return true, "URGENT", "Low HP - heal!"
            end
            return false
        end,
    },
    {
        spellId = spells.DemonSpikes,
        defaultPriority = "HIGH",
        condition = function(self)
            local needsRefresh = self:BuffNeedsRefresh(buffs.DemonSpikes, thresholds.DemonSpikesRefresh)
            if needsRefresh then
                local cdInfo = TankAssist.SecretValues:GetCooldownInfo(spells.DemonSpikes)
                if cdInfo.charges and cdInfo.charges >= 1 then
                    return true, "HIGH", "Demon Spikes"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.SpiritBomb,
        defaultPriority = "HIGH",
        condition = function(self)
            if not IsSpellKnown(spells.SpiritBomb) then
                return false
            end
            local fragments = self:GetSoulFragments()
            if fragments and fragments >= thresholds.SoulFragmentsSpiritBomb then
                return true, "HIGH", "Spirit Bomb ready"
            end
            return false
        end,
    },
    {
        spellId = spells.ImmolationAura,
        defaultPriority = "NORMAL",
        condition = function(self)
            local buffInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.ImmolationAura)
            if not buffInfo.exists then
                local usable = TankAssist.SecretValues:IsSpellUsable(spells.ImmolationAura)
                return usable == true, "NORMAL", nil
            end
            return false
        end,
    },
    {
        spellId = spells.Fracture,
        defaultPriority = "NORMAL",
        condition = function(self)
            if not IsSpellKnown(spells.Fracture) then
                return false
            end
            local fragments = self:GetSoulFragments()
            if fragments and fragments < 4 then
                local usable = TankAssist.SecretValues:IsSpellUsable(spells.Fracture)
                return usable == true, "NORMAL", nil
            end
            return false
        end,
    },
    {
        spellId = spells.SigilOfFlame,
        defaultPriority = "NORMAL",
        condition = function(self)
            local usable = TankAssist.SecretValues:IsSpellUsable(spells.SigilOfFlame)
            return usable == true, "NORMAL", nil
        end,
    },
    {
        spellId = spells.SoulCleave,
        defaultPriority = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },
    {
        spellId = spells.Shear,
        defaultPriority = "NORMAL",
        condition = function(self)
            if IsSpellKnown(spells.Fracture) then
                return false
            end
            return true, "NORMAL", nil
        end,
    },
}

vengeanceDH:Register()
TankAssist.VengeanceDH = vengeanceDH
