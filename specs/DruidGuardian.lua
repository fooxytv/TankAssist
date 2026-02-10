local ADDON_NAME, TankAssist = ...

TankAssist.Constants.GuardianDruid = {
    Spells = {
        Mangle = 33917,
        Thrash = 77758,
        Swipe = 213771,
        Maul = 6807,
        Ironfur = 192081,
        FrenziedRegeneration = 22842,
        Barkskin = 22812,
        SurvivalInstincts = 61336,
        IncarnationGuardian = 102558,
        Berserk = 50334,
        RageOfTheSleeper = 200851,
        Pulverize = 80313,
        BristlingFur = 155835,
        SkullBash = 106839,
        IncapacitatingRoar = 99,
        StampedingRoar = 106898,
        Moonfire = 8921,
        ConvokeTheSpirits = 391528,
    },

    SpellCosts = {
        [33917] = {
            resource = "RAGE",
            cost = 0,
        },
        [77758] = {
            resource = "RAGE",
            cost = 0,
        },
        [213771] = {
            resource = "RAGE",
            cost = 0,
        },
        [6807] = {
            resource = "RAGE",
            cost = 40,
        },
        [192081] = {
            resource = "RAGE",
            cost = 40,
        },
        [22842] = {
            resource = "RAGE",
            cost = 10,
        },
        [80313] = {
            resource = "RAGE",
            cost = 0,
        },
        [8921] = {
            resource = "RAGE",
            cost = 0,
        },
    },

    Buffs = {
        Ironfur = 192081,
        FrenziedRegeneration = 22842,
        Barkskin = 22812,
        SurvivalInstincts = 61336,
        Incarnation = 102558,
        Berserk = 50334,
        RageOfTheSleeper = 200851,
        ToothAndClaw = 135286,
        GalacticGuardian = 213708,
        Gore = 93622,
        Earthwarden = 203975,
        DreamOfCenarius = 372152,
    },

    Thresholds = {
        IronfurMinStacks = 2,
        IronfurRefresh = 3,
        FrenziedRegenHp = 0.7,
        RageForIronfur = 40,
        RageForMaul = 40,
    },

    Cooldowns = {
        Major = { 102558, 50334, 391528 },
        Defensive = { 22812, 61336, 200851 },
        Offensive = { 155835 },
    },

    CooldownDurations = {
        [33917] = 6,
        [77758] = 6,
        [213771] = 0,
        [6807] = 3,
        [192081] = 0,
        [22842] = 36,
        [22812] = 60,
        [61336] = 180,
        [102558] = 180,
        [50334] = 180,
        [200851] = 60,
        [155835] = 40,
        [391528] = 120,
        [8921] = 0,
    },
    ChargeSpells = {
        [22842] = { maxCharges = 2, rechargeTime = 36 },
        [61336] = { maxCharges = 2, rechargeTime = 180 },
    },
    StackingBuffs = {
        [192081] = { buffId = 192081, duration = 7 },
    },
}

TankAssist.SecretValues:RegisterSpellData(TankAssist.Constants.GuardianDruid)

local guardianDruid = TankAssist.SpecBase:New(104, "Guardian Druid")
local spells = TankAssist.Constants.GuardianDruid.Spells
local buffs = TankAssist.Constants.GuardianDruid.Buffs
local thresholds = TankAssist.Constants.GuardianDruid.Thresholds

guardianDruid.secondarySpells = {
    {
        spellId = spells.SurvivalInstincts,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.30)
        end,
    },
    {
        spellId = spells.FrenziedRegeneration,
        category = "HEAL",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.60)
        end,
    },
    {
        spellId = spells.Ironfur,
        category = "MITIGATION",
        urgency = "HIGH",
        condition = function(self)
            return self:InCombat() or self:HasTarget()
        end,
    },
    {
        spellId = spells.Barkskin,
        category = "DEFENSIVE",
        urgency = "HIGH",
        condition = function(self)
            return self:HealthBelow(0.50)
        end,
    },
    {
        spellId = spells.RageOfTheSleeper,
        category = "DEFENSIVE",
        urgency = "HIGH",
        condition = function(self)
            return self:HealthBelow(0.40) and self:InCombat()
        end,
    },
    {
        spellId = spells.IncarnationGuardian,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.Berserk,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            if not self:HasTarget() or not self:InCombat() then
                return false
            end
            if IsPlayerSpell(spells.IncarnationGuardian) then
                return false
            end
            return true
        end,
    },
    {
        spellId = spells.ConvokeTheSpirits,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.Thrash,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },
    {
        spellId = spells.Mangle,
        category = "FILLER",
        urgency = "LOW",
        condition = function(self)
            return self:HasTarget()
        end,
    },
    {
        spellId = spells.Maul,
        category = "FILLER",
        urgency = "LOW",
        condition = function(self)
            return self:HasTarget()
        end,
    },
}

guardianDruid.aoeSpells = {
    {
        spellId = spells.Thrash,
        priority = 1,
        condition = function() return true end,
    },
    {
        spellId = spells.Swipe,
        priority = 2,
        condition = function() return true end,
    },
}

function guardianDruid:GetBestAoESpell()
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

guardianDruid.buffsToTrack = {
    {
        spellId = buffs.Ironfur,
        name = "Ironfur",
        refreshSpell = spells.Ironfur,
        minStacks = thresholds.IronfurMinStacks,
        refreshThreshold = thresholds.IronfurRefresh,
        priority = "CRITICAL",
    },
    {
        spellId = buffs.FrenziedRegeneration,
        name = "Frenzied Regen",
        refreshSpell = spells.FrenziedRegeneration,
        refreshThreshold = 0,
        priority = "HIGH",
    },
    {
        spellId = buffs.Barkskin,
        name = "Barkskin",
        refreshSpell = spells.Barkskin,
        refreshThreshold = 0,
        priority = "HIGH",
    },
}

guardianDruid.tankActions = {
    MITIGATION = {
        spellId = spells.Ironfur,
        name = "Ironfur",
        condition = function()
            local buffInfo = TankAssist.SecretValues:GetBuffInfo("player", TankAssist.Constants.GuardianDruid.Buffs.Ironfur)
            if not buffInfo.exists then return true end
            return buffInfo.stacks and buffInfo.stacks < 2
        end,
    },
    SHIELD = {
        spellId = spells.FrenziedRegeneration,
        name = "Frenzied Regeneration",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.7
        end,
    },
    DEFENSIVE = {
        spellId = spells.SurvivalInstincts,
        name = "Survival Instincts",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.4
        end,
    },
    HEAL = {
        spellId = spells.FrenziedRegeneration,
        name = "Frenzied Regeneration",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.5
        end,
    },
}

guardianDruid.cooldownsToTrack = guardianDruid:BuildCooldownsToTrack()

guardianDruid.rotationPriority = {
    {
        spellId = spells.FrenziedRegeneration,
        defaultPriority = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < thresholds.FrenziedRegenHp then
                local cdInfo = TankAssist.SecretValues:GetCooldownInfo(spells.FrenziedRegeneration)
                if cdInfo.charges and cdInfo.charges >= 1 then
                    return true, "URGENT", "Heal up!"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.Ironfur,
        defaultPriority = "HIGH",
        condition = function(self)
            local needsRefresh, reason = self:BuffNeedsRefresh(
                buffs.Ironfur,
                thresholds.IronfurRefresh,
                thresholds.IronfurMinStacks
            )
            if needsRefresh then
                if reason == "DOWN" then
                    return true, "URGENT", "Ironfur DOWN!"
                else
                    return true, "HIGH", "Stack Ironfur"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.Mangle,
        defaultPriority = "HIGH",
        condition = function(self)
            local goreInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.Gore)
            if goreInfo.exists then
                return true, "HIGH", "Gore proc!"
            end
            local usable = TankAssist.SecretValues:IsSpellUsable(spells.Mangle)
            return usable == true, "NORMAL", nil
        end,
    },
    {
        spellId = spells.Thrash,
        defaultPriority = "NORMAL",
        condition = function(self)
            local usable = TankAssist.SecretValues:IsSpellUsable(spells.Thrash)
            return usable == true, "NORMAL", nil
        end,
    },
    {
        spellId = spells.Moonfire,
        defaultPriority = "NORMAL",
        condition = function(self)
            local procInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.GalacticGuardian)
            if procInfo.exists then
                return true, "HIGH", "Free Moonfire!"
            end
            return false
        end,
    },
    {
        spellId = spells.Maul,
        defaultPriority = "NORMAL",
        condition = function(self)
            local procInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.ToothAndClaw)
            if procInfo.exists then
                return true, "HIGH", "Free Maul!"
            end
            return false
        end,
    },
    {
        spellId = spells.Swipe,
        defaultPriority = "NORMAL",
        condition = function(self)
            local enemies = self:GetEnemyCount()
            if enemies >= 2 then
                return true, "NORMAL", nil
            end
            return false
        end,
    },
}

guardianDruid:Register()
TankAssist.GuardianDruid = guardianDruid
