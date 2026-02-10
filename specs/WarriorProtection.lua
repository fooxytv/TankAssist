local ADDON_NAME, TankAssist = ...

TankAssist.Constants.ProtectionWarrior = {
    Spells = {
        ShieldSlam = 23922,
        ThunderClap = 6343,
        Revenge = 6572,
        Devastate = 20243,
        ShieldBlock = 2565,
        IgnorePain = 190456,
        ShieldWall = 871,
        LastStand = 12975,
        DemoralizingShout = 1160,
        SpellReflection = 23920,
        Avatar = 401150,
        Ravager = 228920,
        Shockwave = 46968,
        HeroicThrow = 57755,
        Charge = 100,
        Intervene = 3411,
        RallyingCry = 97462,
        ChampionsSpear = 376079,
        ThunderousRoar = 384318,
    },

    SpellCosts = {
        [23922] = {
            resource = "RAGE",
            cost = 0,
        },
        [6343] = {
            resource = "RAGE",
            cost = 0,
        },
        [6572] = {
            resource = "RAGE",
            cost = 20,
        },
        [20243] = {
            resource = "RAGE",
            cost = 0,
        },
        [2565] = {
            resource = "RAGE",
            cost = 30,
        },
        [190456] = {
            resource = "RAGE",
            cost = 40,
        },
        [46968] = {
            resource = "RAGE",
            cost = 0,
        },
    },

    Buffs = {
        ShieldBlock = 132404,
        IgnorePain = 190456,
        ShieldWall = 871,
        LastStand = 12975,
        Avatar = 401150,
        Ravager = 228920,
        RevengeProc = 5302,
        ViolentOutburst = 386478,
        Vanguard = 71,
    },

    Thresholds = {
        ShieldBlockRefresh = 2,
        IgnorePainMaxAbsorb = 0.5,
        LowRageThreshold = 40,
        RevengeRage = 20,
    },

    Cooldowns = {
        Major = { 401150, 228920, 376079 },
        Defensive = { 871, 12975, 23920, 1160 },
        Offensive = { 384318 },
    },

    CooldownDurations = {
        [23922] = 9,
        [6343] = 6,
        [6572] = 0,
        [2565] = 16,
        [190456] = 0,
        [871] = 180,
        [12975] = 180,
        [1160] = 45,
        [23920] = 25,
        [401150] = 90,
        [46968] = 40,
    },
    ChargeSpells = {
        [2565] = { maxCharges = 2, rechargeTime = 16 },
    },
}

TankAssist.SecretValues:RegisterSpellData(TankAssist.Constants.ProtectionWarrior)

local protWarrior = TankAssist.SpecBase:New(73, "Protection Warrior")

local spells = TankAssist.Constants.ProtectionWarrior.Spells
local buffs = TankAssist.Constants.ProtectionWarrior.Buffs
local thresholds = TankAssist.Constants.ProtectionWarrior.Thresholds

protWarrior.secondarySpells = {
    {
        spellId = spells.ShieldWall,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.30)
        end,
    },
    {
        spellId = spells.LastStand,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.35)
        end,
    },
    {
        spellId = spells.ShieldBlock,
        category = "MITIGATION",
        urgency = "HIGH",
        condition = function(self)
            local buffInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.ShieldBlock)
            if not buffInfo.exists then
                return true
            end
            local remaining = buffInfo.expirationTime and (buffInfo.expirationTime - GetTime()) or 0
            return remaining < 2
        end,
    },
    {
        spellId = spells.IgnorePain,
        category = "SHIELD",
        urgency = "HIGH",
        condition = function(self)
            local rage = self:GetResource("RAGE")
            return self:HealthBelow(0.60) and rage and rage >= 40
        end,
    },
    {
        spellId = spells.DemoralizingShout,
        category = "DEFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HealthBelow(0.50) and self:HasTarget()
        end,
    },
    {
        spellId = spells.SpellReflection,
        category = "DEFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },
    {
        spellId = spells.ThunderClap,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },
    {
        spellId = spells.Revenge,
        category = "AOE",
        urgency = "HIGH",
        condition = function(self)
            local procInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.RevengeProc)
            return procInfo.exists
        end,
    },
    {
        spellId = spells.Shockwave,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },
    {
        spellId = spells.Avatar,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.Ravager,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.ThunderousRoar,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.Revenge,
        category = "AOE",
        urgency = "LOW",
        condition = function(self)
            local rage = self:GetResource("RAGE")
            return self:HasTarget() and rage and rage >= 40
        end,
    },
    {
        spellId = spells.ShieldSlam,
        category = "FILLER",
        urgency = "LOW",
        condition = function(self)
            return self:HasTarget()
        end,
    },
}

protWarrior.aoeSpells = {
    {
        spellId = spells.ThunderClap,
        priority = 1,
        condition = function() return true end,
    },
    {
        spellId = spells.Revenge,
        priority = 2,
        condition = function()
            local procInfo = TankAssist.SecretValues:GetBuffInfo("player", TankAssist.Constants.ProtectionWarrior.Buffs.RevengeProc)
            return procInfo.exists
        end,
    },
    {
        spellId = spells.Shockwave,
        priority = 3,
        condition = function()
            return IsSpellKnown(spells.Shockwave)
        end,
    },
}

function protWarrior:GetBestAoESpell()
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
    return spells.ThunderClap
end

protWarrior.buffsToTrack = {
    {
        spellId = buffs.ShieldBlock,
        name = "Shield Block",
        refreshSpell = spells.ShieldBlock,
        refreshThreshold = thresholds.ShieldBlockRefresh,
        priority = "CRITICAL",
    },
    {
        spellId = buffs.IgnorePain,
        name = "Ignore Pain",
        refreshSpell = spells.IgnorePain,
        refreshThreshold = 2,
        priority = "HIGH",
        isAbsorb = true,
    },
    {
        spellId = buffs.ShieldWall,
        name = "Shield Wall",
        refreshSpell = spells.ShieldWall,
        refreshThreshold = 0,
        priority = "HIGH",
    },
}

protWarrior.tankActions = {
    MITIGATION = {
        spellId = spells.ShieldBlock,
        name = "Shield Block",
        condition = function()
            local buffInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.ShieldBlock)
            return not buffInfo.exists
        end,
    },
    SHIELD = {
        spellId = spells.IgnorePain,
        name = "Ignore Pain",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.7
        end,
    },
    DEFENSIVE = {
        spellId = spells.ShieldWall,
        name = "Shield Wall",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.4
        end,
    },
    HEAL = {
        spellId = spells.IgnorePain,
        name = "Ignore Pain",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.5
        end,
    },
}

protWarrior.cooldownsToTrack = protWarrior:BuildCooldownsToTrack()

protWarrior.rotationPriority = {
    {
        spellId = spells.ShieldWall,
        defaultPriority = "URGENT",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.3 then
                local usable = TankAssist.SecretValues:IsSpellUsable(spells.ShieldWall)
                if usable then
                    return true, "URGENT", "EMERGENCY!"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.LastStand,
        defaultPriority = "URGENT",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.35 then
                local usable = TankAssist.SecretValues:IsSpellUsable(spells.LastStand)
                if usable then
                    return true, "URGENT", "EMERGENCY!"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.IgnorePain,
        defaultPriority = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            local rage = self:GetResource("RAGE")
            if hp and hp < 0.6 and rage and rage >= 40 then
                local usable = TankAssist.SecretValues:IsSpellUsable(spells.IgnorePain)
                if usable then
                    return true, "HIGH", "Absorb damage!"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.ShieldBlock,
        defaultPriority = "HIGH",
        condition = function(self)
            local needsRefresh = self:BuffNeedsRefresh(buffs.ShieldBlock, thresholds.ShieldBlockRefresh)
            if needsRefresh then
                local rage = self:GetResource("RAGE")
                if rage and rage >= 30 then
                    return true, "HIGH", "Shield Block"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.ShieldSlam,
        defaultPriority = "HIGH",
        condition = function(self)
            local usable = TankAssist.SecretValues:IsSpellUsable(spells.ShieldSlam)
            return usable == true, "HIGH", nil
        end,
    },
    {
        spellId = spells.ThunderClap,
        defaultPriority = "NORMAL",
        condition = function(self)
            local usable = TankAssist.SecretValues:IsSpellUsable(spells.ThunderClap)
            return usable == true, "NORMAL", nil
        end,
    },
    {
        spellId = spells.Revenge,
        defaultPriority = "NORMAL",
        condition = function(self)
            local procInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.RevengeProc)
            if procInfo.exists then
                return true, "HIGH", "Free Revenge!"
            end
            local rage = self:GetResource("RAGE")
            if rage and rage >= 60 then
                return true, "NORMAL", nil
            end
            return false
        end,
    },
    {
        spellId = spells.IgnorePain,
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

protWarrior:Register()
TankAssist.ProtWarrior = protWarrior
