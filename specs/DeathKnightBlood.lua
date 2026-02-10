local ADDON_NAME, TankAssist = ...

TankAssist.Constants.BloodDeathKnight = {
    Spells = {
        Marrowrend = 195182,
        HeartStrike = 206930,
        DeathStrike = 49998,
        BloodBoil = 50842,
        DeathsCaress = 195292,
        DeathAndDecay = 43265,
        Consumption = 274156,
        Bonestorm = 194844,
        DancingRuneWeapon = 49028,
        VampiricBlood = 55233,
        IceboundFortitude = 48792,
        AntiMagicShell = 48707,
        RaiseDead = 46585,
        DeathGrip = 49576,
        GorefiendsGrasp = 108199,
        Tombstone = 219809,
        RuneTap = 194679,
        AbominationLimb = 383269,
        EmpowerRuneWeapon = 47568,
    },

    SpellCosts = {
        [195182] = {
            resource = "RUNES",
            cost = 2,
        },
        [206930] = {
            resource = "RUNES",
            cost = 1,
        },
        [49998] = {
            resource = "RUNIC_POWER",
            cost = 40,
        },
        [50842] = {
            resource = "RUNES",
            cost = 1,
        },
        [195292] = {
            resource = "RUNES",
            cost = 1,
        },
        [43265] = {
            resource = "RUNES",
            cost = 1,
        },
        [274156] = {
            resource = "RUNES",
            cost = 1,
        },
        [194844] = {
            resource = "RUNIC_POWER",
            cost = 10,
        },
        [194679] = {
            resource = "RUNES",
            cost = 1,
        },
    },

    Buffs = {
        BoneShield = 195181,
        BloodShield = 77535,
        DancingRuneWeapon = 81256,
        VampiricBlood = 55233,
        IceboundFortitude = 48792,
        AntiMagicShell = 48707,
        CrimsonScourge = 81141,
        Hemostasis = 273947,
        Ossuary = 219786,
    },

    Thresholds = {
        BoneShieldMin = 5,
        BoneShieldMax = 10,
        DeathStrikeRp = 40,
        LowHealthPercent = 0.5,
    },

    Cooldowns = {
        Major = { 49028, 55233 },
        Defensive = { 48792, 48707, 194679, 219809 },
        Offensive = { 194844, 383269, 47568 },
    },

    CooldownDurations = {
        [195182] = 0,
        [206930] = 0,
        [50842] = 7.5,
        [49998] = 0,
        [43265] = 30,
        [55233] = 90,
        [49028] = 120,
        [48792] = 180,
        [48707] = 60,
        [194679] = 25,
        [194844] = 60,
    },
    ChargeSpells = {
        [194679] = { maxCharges = 2, rechargeTime = 25 },
        [50842] = { maxCharges = 2, rechargeTime = 7.5 },
    },
}

TankAssist.SecretValues:RegisterSpellData(TankAssist.Constants.BloodDeathKnight)

local bloodDK = TankAssist.SpecBase:New(250, "Blood Death Knight")

local spells = TankAssist.Constants.BloodDeathKnight.Spells
local buffs = TankAssist.Constants.BloodDeathKnight.Buffs
local thresholds = TankAssist.Constants.BloodDeathKnight.Thresholds

bloodDK.secondarySpells = {
    {
        spellId = spells.IceboundFortitude,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.25)
        end,
    },
    {
        spellId = spells.VampiricBlood,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.40)
        end,
    },
    {
        spellId = spells.DeathStrike,
        category = "HEAL",
        urgency = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            local rp = self:GetResource("RUNIC_POWER")
            return hp and hp < 0.50 and rp and rp >= 40
        end,
    },
    {
        spellId = spells.DeathStrike,
        category = "SHIELD",
        urgency = "NORMAL",
        condition = function(self)
            local bsInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.BloodShield)
            if bsInfo.exists then
                return false
            end
            local hp = self:GetHealthPercent()
            local rp = self:GetResource("RUNIC_POWER")
            return hp and hp >= 0.50 and rp and rp >= 40
        end,
    },
    {
        spellId = spells.Marrowrend,
        category = "MITIGATION",
        urgency = "HIGH",
        condition = function(self)
            local bsInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.BoneShield)
            if not bsInfo.exists then
                return true
            end
            return bsInfo.stacks and bsInfo.stacks < 5
        end,
    },
    {
        spellId = spells.RuneTap,
        category = "MITIGATION",
        urgency = "NORMAL",
        condition = function(self)
            return self:HealthBelow(0.60)
        end,
    },
    {
        spellId = spells.DeathAndDecay,
        category = "AOE",
        urgency = "HIGH",
        condition = function(self)
            local procInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.CrimsonScourge)
            return procInfo.exists
        end,
    },
    {
        spellId = spells.BloodBoil,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },
    {
        spellId = spells.DeathAndDecay,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget()
        end,
    },
    {
        spellId = spells.DancingRuneWeapon,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.AbominationLimb,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.HeartStrike,
        category = "FILLER",
        urgency = "LOW",
        condition = function(self)
            return self:HasTarget()
        end,
    },
}

bloodDK.buffsToTrack = {
    {
        spellId = buffs.BoneShield,
        name = "Bone Shield",
        refreshSpell = spells.Marrowrend,
        minStacks = thresholds.BoneShieldMin,
        maxStacks = thresholds.BoneShieldMax,
        refreshThreshold = 5,
        priority = "CRITICAL",
    },
    {
        spellId = buffs.BloodShield,
        name = "Blood Shield",
        refreshSpell = spells.DeathStrike,
        refreshThreshold = 0,
        priority = "HIGH",
        isAbsorb = true,
    },
    {
        spellId = buffs.DancingRuneWeapon,
        name = "Dancing Rune Weapon",
        refreshSpell = spells.DancingRuneWeapon,
        refreshThreshold = 0,
        priority = "HIGH",
    },
    {
        spellId = buffs.VampiricBlood,
        name = "Vampiric Blood",
        refreshSpell = spells.VampiricBlood,
        refreshThreshold = 0,
        priority = "HIGH",
    },
}

bloodDK.tankActions = {
    MITIGATION = {
        spellId = spells.Marrowrend,
        name = "Marrowrend",
        condition = function()
            local bsInfo = TankAssist.SecretValues:GetBuffInfo("player", TankAssist.Constants.BloodDeathKnight.Buffs.BoneShield)
            if not bsInfo.exists then return true end
            return bsInfo.stacks and bsInfo.stacks < 5
        end,
    },
    SHIELD = {
        spellId = spells.DeathStrike,
        name = "Death Strike",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.6
        end,
    },
    DEFENSIVE = {
        spellId = spells.VampiricBlood,
        name = "Vampiric Blood",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.4
        end,
    },
    HEAL = {
        spellId = spells.DeathStrike,
        name = "Death Strike",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.5
        end,
    },
}

bloodDK.cooldownsToTrack = bloodDK:BuildCooldownsToTrack()

bloodDK.rotationPriority = {
    {
        spellId = spells.IceboundFortitude,
        defaultPriority = "URGENT",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.3 then
                local usable = TankAssist.SecretValues:IsSpellUsable(spells.IceboundFortitude)
                if usable then
                    return true, "URGENT", "EMERGENCY!"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.VampiricBlood,
        defaultPriority = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.5 then
                local usable = TankAssist.SecretValues:IsSpellUsable(spells.VampiricBlood)
                if usable then
                    return true, "HIGH", "Boost healing!"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.DeathStrike,
        defaultPriority = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp == nil then return false end
            if hp < thresholds.LowHealthPercent then
                local hasRP = self:HasResource("RUNIC_POWER", thresholds.DeathStrikeRp)
                if hasRP then
                    return true, "URGENT", "Low HP - heal!"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.Marrowrend,
        defaultPriority = "HIGH",
        condition = function(self)
            local needsRefresh, reason = self:BuffNeedsRefresh(
                buffs.BoneShield,
                5,
                thresholds.BoneShieldMin
            )
            if needsRefresh == nil then
                return false
            end
            if needsRefresh then
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
    {
        spellId = spells.DeathAndDecay,
        defaultPriority = "HIGH",
        condition = function(self)
            local procInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.CrimsonScourge)
            if procInfo.exists and not procInfo.isSecret then
                return true, "HIGH", "Free D&D proc!"
            end
            return false
        end,
    },
    {
        spellId = spells.BloodBoil,
        defaultPriority = "NORMAL",
        condition = function(self)
            local cdInfo = TankAssist.SecretValues:GetCooldownInfo(spells.BloodBoil)
            if cdInfo.charges and cdInfo.charges >= 2 then
                return true, "NORMAL", "Use charges"
            elseif cdInfo.charges and cdInfo.charges >= 1 then
                if self:HasTarget() then
                    return true, "NORMAL", nil
                end
            end
            return false
        end,
    },
    {
        spellId = spells.HeartStrike,
        defaultPriority = "NORMAL",
        condition = function(self)
            local runes = self:GetResource("RUNES")
            if runes and runes >= 3 then
                local needsBoneShield = self:BuffNeedsRefresh(buffs.BoneShield, 5, thresholds.BoneShieldMin)
                if not needsBoneShield then
                    return true, "NORMAL", nil
                end
            end
            return false
        end,
    },
    {
        spellId = spells.DeathStrike,
        defaultPriority = "NORMAL",
        condition = function(self)
            local rp = self:GetResource("RUNIC_POWER")
            if rp == nil then return false end
            if rp >= 80 then
                return true, "NORMAL", "Dump RP"
            end
            local hemoInfo = TankAssist.SecretValues:GetBuffInfo("player", buffs.Hemostasis)
            if hemoInfo.exists and hemoInfo.stacks and hemoInfo.stacks >= 5 then
                if rp >= thresholds.DeathStrikeRp then
                    return true, "HIGH", "Max Hemostasis"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.Consumption,
        defaultPriority = "NORMAL",
        condition = function(self)
            if not IsSpellKnown(spells.Consumption) then
                return false
            end
            local usable = TankAssist.SecretValues:IsSpellUsable(spells.Consumption)
            return usable == true, "NORMAL", nil
        end,
    },
    {
        spellId = spells.Bonestorm,
        defaultPriority = "NORMAL",
        condition = function(self)
            if not IsSpellKnown(spells.Bonestorm) then
                return false
            end
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

function bloodDK:OnUpdate()
end

function bloodDK:ShouldPoolResources()
    local hp = self:GetHealthPercent()
    if hp and hp < 0.6 then
        return true
    end
    return false
end

function bloodDK:GetDefensiveRecommendation()
    local hp = self:GetHealthPercent()
    if hp == nil then
        return nil
    end
    if hp < 0.3 then
        if TankAssist.SecretValues:IsSpellUsable(spells.VampiricBlood) then
            return spells.VampiricBlood, "CRITICAL", "HP Critical!"
        elseif TankAssist.SecretValues:IsSpellUsable(spells.IceboundFortitude) then
            return spells.IceboundFortitude, "CRITICAL", "HP Critical!"
        end
    end
    if hp < 0.5 then
        if TankAssist.SecretValues:IsSpellUsable(spells.RuneTap) then
            return spells.RuneTap, "HIGH", "Incoming damage"
        end
    end
    return nil
end

bloodDK:Register()
TankAssist.BloodDK = bloodDK
