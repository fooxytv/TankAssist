local ADDON_NAME, TankAssist = ...

TankAssist.Constants.ProtectionPaladin = {
    Spells = {
        Judgment = 275779,
        ShieldOfTheRighteous = 53600,
        AvengersShield = 31935,
        HammerOfTheRighteous = 53595,
        BlessedHammer = 204019,
        Consecration = 26573,
        WordOfGlory = 85673,
        ArdentDefender = 31850,
        GuardianOfAncientKings = 86659,
        DivineShield = 642,
        LayOnHands = 633,
        AvengingWrath = 31884,
        MomentOfGlory = 327193,
        Sentinel = 389539,
        EyeOfTyr = 387174,
        HammerOfWrath = 24275,
        DivineToll = 375576,
        HandOfReckoning = 62124,
    },

    SpellCosts = {
        [275779] = {
            resource = "HOLY_POWER",
            cost = 0,
        },
        [53600] = {
            resource = "HOLY_POWER",
            cost = 3,
        },
        [31935] = {
            resource = "HOLY_POWER",
            cost = 0,
        },
        [53595] = {
            resource = "HOLY_POWER",
            cost = 0,
        },
        [204019] = {
            resource = "HOLY_POWER",
            cost = 0,
        },
        [26573] = {
            resource = "HOLY_POWER",
            cost = 0,
        },
        [85673] = {
            resource = "HOLY_POWER",
            cost = 3,
        },
        [24275] = {
            resource = "HOLY_POWER",
            cost = 0,
        },
    },

    Buffs = {
        ShieldOfTheRighteous = 132403,
        Consecration = 188370,
        ArdentDefender = 31850,
        GuardianOfAncientKings = 86659,
        AvengingWrath = 31884,
        Sentinel = 389539,
        MomentOfGlory = 327193,
        ShiningLight = 327510,
        BlessedAssurance = 433019,
    },

    Thresholds = {
        SotrRefresh = 3,
        ConsecrationRefresh = 1,
        WordOfGloryHp = 0.5,
        HolyPowerMax = 5,
    },

    Cooldowns = {
        Major = { 31884, 389539, 375576 },
        Defensive = { 31850, 86659, 642, 633 },
        Offensive = { 387174 },
    },

    CooldownDurations = {
        [275779] = 6,
        [31935] = 15,
        [53600] = 0,
        [53595] = 0,
        [26573] = 4,
        [85673] = 0,
        [31850] = 120,
        [86659] = 300,
        [31884] = 60,
        [375576] = 60,
        [387174] = 60,
        [633] = 600,
        [642] = 300,
        [389539] = 120,
    },
    StackingBuffs = {
        [132403] = { buffId = 132403, duration = 4.5 },
    },
}

TankAssist.SecretValues:RegisterSpellData(TankAssist.Constants.ProtectionPaladin)

local protPaladin = TankAssist.SpecBase:New(66, "Protection Paladin")

local spells = TankAssist.Constants.ProtectionPaladin.Spells
local buffs = TankAssist.Constants.ProtectionPaladin.Buffs
local thresholds = TankAssist.Constants.ProtectionPaladin.Thresholds

protPaladin.aoeSpells = {
    {
        spellId = spells.AvengersShield,
        priority = 1,
        condition = function() return true end,
    },
    {
        spellId = spells.Consecration,
        priority = 2,
        condition = function()
            local buffInfo = TankAssist.SecretValues:GetBuffInfo("player", TankAssist.Constants.ProtectionPaladin.Buffs.Consecration)
            return not buffInfo.exists
        end,
    },
    {
        spellId = spells.HammerOfTheRighteous,
        priority = 3,
        condition = function() return true end,
    },
}

function protPaladin:GetBestAoESpell()
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
    return spells.Consecration
end

protPaladin.secondarySpells = {
    {
        spellId = spells.LayOnHands,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.20)
        end,
    },
    {
        spellId = spells.GuardianOfAncientKings,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.30)
        end,
    },
    {
        spellId = spells.ArdentDefender,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.35)
        end,
    },
    {
        spellId = spells.WordOfGlory,
        category = "HEAL",
        urgency = "HIGH",
        condition = function(self)
            local procInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.ShiningLight)
            if procInfo.exists then
                return self:HealthBelow(0.80)
            end
            if self:HealthBelow(0.50) then
                local holyPower = self:GetResource("HOLY_POWER")
                return holyPower and holyPower >= 3
            end
            return false
        end,
    },
    {
        spellId = spells.ShieldOfTheRighteous,
        category = "MITIGATION",
        urgency = "HIGH",
        condition = function(self)
            local holyPower = self:GetResource("HOLY_POWER")
            if not holyPower or holyPower < 3 then
                return false
            end
            local buffInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.ShieldOfTheRighteous)
            if not buffInfo.exists then
                return true
            end
            local remaining = (buffInfo.expirationTime or 0) - GetTime()
            return remaining < 3
        end,
    },
    {
        spellId = spells.AvengingWrath,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.DivineToll,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.EyeOfTyr,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.Sentinel,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.AvengersShield,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },
    {
        spellId = spells.Judgment,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },
    {
        spellId = spells.Consecration,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            if not self:HasTarget() then
                return false
            end
            local buffInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.Consecration)
            return not buffInfo.exists
        end,
    },
    {
        spellId = spells.HammerOfTheRighteous,
        category = "FILLER",
        urgency = "LOW",
        condition = function(self)
            return self:HasTarget()
        end,
    },
}

protPaladin.buffsToTrack = {
    {
        spellId = buffs.ShieldOfTheRighteous,
        name = "Shield of the Righteous",
        refreshSpell = spells.ShieldOfTheRighteous,
        refreshThreshold = thresholds.SotrRefresh,
        priority = "CRITICAL",
    },
    {
        spellId = buffs.Consecration,
        name = "Consecration",
        refreshSpell = spells.Consecration,
        refreshThreshold = thresholds.ConsecrationRefresh,
        priority = "HIGH",
    },
    {
        spellId = buffs.ArdentDefender,
        name = "Ardent Defender",
        refreshThreshold = 0,
        priority = "HIGH",
    },
}

protPaladin.tankActions = {
    MITIGATION = {
        spellId = spells.ShieldOfTheRighteous,
        name = "Shield of the Righteous",
        condition = function()
            local buffInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.ShieldOfTheRighteous)
            return not buffInfo.exists
        end,
    },
    SHIELD = {
        spellId = spells.WordOfGlory,
        name = "Word of Glory",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.6
        end,
    },
    DEFENSIVE = {
        spellId = spells.ArdentDefender,
        name = "Ardent Defender",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.4
        end,
    },
    HEAL = {
        spellId = spells.WordOfGlory,
        name = "Word of Glory",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.5
        end,
    },
}

protPaladin.cooldownsToTrack = {
    {
        spellId = spells.AvengingWrath,
        name = "Avenging Wrath",
        category = "MAJOR",
    },
    {
        spellId = spells.Sentinel,
        name = "Sentinel",
        category = "MAJOR",
    },
    {
        spellId = spells.DivineToll,
        name = "Divine Toll",
        category = "MAJOR",
    },
    {
        spellId = spells.ArdentDefender,
        name = "Ardent Defender",
        category = "DEFENSIVE",
    },
    {
        spellId = spells.GuardianOfAncientKings,
        name = "Guardian of Ancient Kings",
        category = "DEFENSIVE",
    },
    {
        spellId = spells.DivineShield,
        name = "Divine Shield",
        category = "DEFENSIVE",
    },
    {
        spellId = spells.LayOnHands,
        name = "Lay on Hands",
        category = "DEFENSIVE",
    },
    {
        spellId = spells.EyeOfTyr,
        name = "Eye of Tyr",
        category = "OFFENSIVE",
    },
}

protPaladin.rotationPriority = {
    {
        spellId = spells.ArdentDefender,
        defaultPriority = "URGENT",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.3 then
                local usable = TankAssist.SecretValues:IsSpellUsable(spells.ArdentDefender)
                if usable then
                    return true, "URGENT", "EMERGENCY!"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.GuardianOfAncientKings,
        defaultPriority = "URGENT",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.35 then
                local usable = TankAssist.SecretValues:IsSpellUsable(spells.GuardianOfAncientKings)
                if usable then
                    return true, "URGENT", "EMERGENCY!"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.WordOfGlory,
        defaultPriority = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.5 then
                local procInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.ShiningLight)
                if procInfo.exists then
                    return true, "URGENT", "Free heal!"
                end
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
    {
        spellId = spells.ShieldOfTheRighteous,
        defaultPriority = "HIGH",
        condition = function(self)
            local needsRefresh = self:BuffNeedsRefresh(buffs.ShieldOfTheRighteous, thresholds.SotrRefresh)
            if needsRefresh then
                local hp = self:GetResource("HOLY_POWER")
                if hp and hp >= 3 then
                    return true, "HIGH", "Maintain SotR"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.Judgment,
        defaultPriority = "HIGH",
        condition = function(self)
            local usable = TankAssist.SecretValues:IsSpellUsable(spells.Judgment)
            return usable == true, "HIGH", nil
        end,
    },
    {
        spellId = spells.AvengersShield,
        defaultPriority = "NORMAL",
        condition = function(self)
            local usable = TankAssist.SecretValues:IsSpellUsable(spells.AvengersShield)
            return usable == true, "NORMAL", nil
        end,
    },
    {
        spellId = spells.HammerOfTheRighteous,
        defaultPriority = "NORMAL",
        condition = function(self)
            local usable = TankAssist.SecretValues:IsSpellUsable(spells.HammerOfTheRighteous)
            return usable == true, "NORMAL", nil
        end,
    },
    {
        spellId = spells.Consecration,
        defaultPriority = "NORMAL",
        condition = function(self)
            local buffInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.Consecration)
            if not buffInfo.exists or buffInfo.isSecret then
                local usable = TankAssist.SecretValues:IsSpellUsable(spells.Consecration)
                return usable == true, "NORMAL", "Consecration down"
            end
            return false
        end,
    },
}

protPaladin:Register()
TankAssist.ProtPaladin = protPaladin
