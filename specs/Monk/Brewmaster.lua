local ADDON_NAME, TankAssist = ...

TankAssist.Constants.Brewmaster = {
    Spells = {
        TigerPalm = 100780,
        BlackoutKick = 205523,
        KegSmash = 121253,
        BreathOfFire = 115181,
        SpinningCraneKick = 322729,
        RushingJadeWind = 116847,
        PurifyingBrew = 119582,
        CelestialBrew = 322507,
        FortifyingBrew = 115203,
        ZenMeditation = 115176,
        InvokeNiuzao = 132578,
        ExplodingKeg = 325153,
        BonedustBrew = 386276,
        WeaponsOfOrder = 387184,
        DampenHarm = 122278,
        DiffuseMagic = 122783,
        ExpelHarm = 322101,
        Clash = 324312,
        RingOfPeace = 116844,
        SummonWhiteTigerStatue = 388686,
    },

    SpellCosts = {
        [100780] = {
            resource = "ENERGY",
            cost = 50,
        },
        [205523] = {
            resource = "ENERGY",
            cost = 0,
        },
        [121253] = {
            resource = "ENERGY",
            cost = 40,
        },
        [115181] = {
            resource = "ENERGY",
            cost = 0,
        },
        [322729] = {
            resource = "ENERGY",
            cost = 25,
        },
        [116847] = {
            resource = "ENERGY",
            cost = 0,
        },
        [322101] = {
            resource = "ENERGY",
            cost = 15,
        },
    },

    Buffs = {
        Shuffle = 322120,
        CelestialBrew = 322507,
        FortifyingBrew = 115203,
        ZenMeditation = 115176,
        BlackoutCombo = 228563,
        CharredPassions = 386963,
        PretenseOfInstability = 393516,
        ElusiveBrawler = 195630,
        WeaponsOfOrder = 387184,
    },

    Debuffs = {
        LightStagger = 124275,
        ModerateStagger = 124274,
        HeavyStagger = 124273,
        BreathOfFireDot = 123725,
    },

    Thresholds = {
        PurifyStaggerPercent = 0.06,
        HeavyStaggerPercent = 0.10,
        ShuffleRefresh = 3,
        KegSmashEnergy = 40,
    },

    Cooldowns = {
        Major = { 132578, 387184 },
        Defensive = { 115203, 115176, 122278, 122783 },
        Offensive = { 325153, 386276 },
    },

    CooldownDurations = {
        [121253] = 8,
        [115181] = 15,
        [322729] = 0,
        [100780] = 0,
        [205523] = 3,
        [116847] = 6,
        [322507] = 45,
        [119582] = 20,
        [115203] = 180,
        [322101] = 15,
        [115176] = 300,
        [132578] = 180,
        [325153] = 60,
        [386276] = 60,
        [387184] = 120,
        [122278] = 120,
        [122783] = 90,
    },
    ChargeSpells = {
        [119582] = { maxCharges = 2, rechargeTime = 20 },
    },
}

TankAssist.SecretValues:RegisterSpellData(TankAssist.Constants.Brewmaster)

local brewmaster = TankAssist.SpecBase:New(268, "Brewmaster Monk")
local spells = TankAssist.Constants.Brewmaster.Spells

brewmaster.secondarySpells = {
    {
        spellId = spells.FortifyingBrew,
        category = "EMERGENCY",
        urgency = "URGENT",
        condition = function(self)
            return self:HealthBelow(0.30)
        end,
    },
    {
        spellId = spells.ExpelHarm,
        category = "HEAL",
        urgency = "HIGH",
        condition = function(self)
            return self:HealthBelow(0.50)
        end,
    },
    {
        spellId = spells.PurifyingBrew,
        category = "MITIGATION",
        urgency = "HIGH",
        condition = function(self)
            local stagger = self:GetStaggerInfo()
            if stagger.level == "HEAVY" then
                return true
            end
            if stagger.level == "MODERATE" or stagger.level == "LIGHT" then
                return true
            end
            return false
        end,
    },
    {
        spellId = spells.CelestialBrew,
        category = "SHIELD",
        urgency = "HIGH",
        condition = function(self)
            return self:HealthBelow(0.60)
        end,
    },
    {
        spellId = spells.KegSmash,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return true
        end,
    },
    {
        spellId = spells.BreathOfFire,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            return true
        end,
    },
    {
        spellId = spells.RushingJadeWind,
        category = "AOE",
        urgency = "NORMAL",
        condition = function(self)
            if not IsSpellKnown(spells.RushingJadeWind) then
                return false
            end
            return true
        end,
    },
    {
        spellId = spells.SpinningCraneKick,
        category = "FILLER",
        urgency = "LOW",
        condition = function(self)
            return true
        end,
    },
    {
        spellId = spells.InvokeNiuzao,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            if not self:HasTarget() or not self:InCombat() then
                return false
            end
            local stagger = self:GetStaggerInfo()
            return stagger.level == "HEAVY" or stagger.level == "MODERATE"
        end,
    },
    {
        spellId = spells.ExplodingKeg,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.BonedustBrew,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.WeaponsOfOrder,
        category = "OFFENSIVE",
        urgency = "NORMAL",
        condition = function(self)
            return self:HasTarget() and self:InCombat()
        end,
    },
    {
        spellId = spells.DampenHarm,
        category = "EMERGENCY",
        urgency = "HIGH",
        condition = function(self)
            return self:HealthBelow(0.40)
        end,
    },
    {
        spellId = spells.DiffuseMagic,
        category = "EMERGENCY",
        urgency = "HIGH",
        condition = function(self)
            return self:HealthBelow(0.40)
        end,
    },
}

local buffs = TankAssist.Constants.Brewmaster.Buffs
local debuffs = TankAssist.Constants.Brewmaster.Debuffs
local thresholds = TankAssist.Constants.Brewmaster.Thresholds

function brewmaster:GetStaggerInfo()
    return TankAssist.SecretValues:GetStaggerInfo()
end

function brewmaster:ShouldPurify()
    local stagger = self:GetStaggerInfo()

    if stagger.level == "HEAVY" then
        return true, "URGENT"
    end

    if stagger.level == "MODERATE" then
        return true, "HIGH"
    end

    if stagger.level == "LIGHT" then
        return true, "NORMAL"
    end

    return false, "NORMAL"
end

brewmaster.buffsToTrack = {
    {
        spellId = buffs.Shuffle,
        name = "Shuffle",
        refreshSpell = spells.BlackoutKick,
        refreshThreshold = thresholds.ShuffleRefresh,
        priority = "CRITICAL",
    },
    {
        spellId = buffs.CelestialBrew,
        name = "Celestial Brew",
        refreshSpell = spells.CelestialBrew,
        refreshThreshold = 0,
        priority = "HIGH",
    },
    {
        spellId = buffs.FortifyingBrew,
        name = "Fortifying Brew",
        refreshSpell = spells.FortifyingBrew,
        refreshThreshold = 0,
        priority = "HIGH",
    },
}

brewmaster.tankActions = {
    MITIGATION = {
        spellId = spells.PurifyingBrew,
        name = "Purifying Brew",
        condition = function()
            local stagger = TankAssist.SecretValues:GetStaggerInfo()
            return stagger.level == "HEAVY" or stagger.level == "MODERATE"
        end,
    },
    SHIELD = {
        spellId = spells.CelestialBrew,
        name = "Celestial Brew",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.7
        end,
    },
    DEFENSIVE = {
        spellId = spells.FortifyingBrew,
        name = "Fortifying Brew",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.4
        end,
    },
    HEAL = {
        spellId = spells.ExpelHarm,
        name = "Expel Harm",
        condition = function()
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            return hp and hp < 0.5
        end,
    },
}

brewmaster.cooldownsToTrack = brewmaster:BuildCooldownsToTrack()

brewmaster.rotationPriority = {
    {
        spellId = spells.FortifyingBrew,
        defaultPriority = "URGENT",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.35 then
                local usable = TankAssist.SecretValues:IsSpellUsable(spells.FortifyingBrew)
                if usable then
                    return true, "URGENT", "EMERGENCY!"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.PurifyingBrew,
        defaultPriority = "HIGH",
        condition = function(self)
            local shouldPurify, urgency = self:ShouldPurify()
            if shouldPurify == nil then
                return false
            end
            if shouldPurify then
                if urgency == "URGENT" then
                    return true, "URGENT", "Heavy Stagger!"
                elseif urgency == "HIGH" then
                    return true, "HIGH", "Purify stagger"
                else
                    return true, "NORMAL", "Clear stagger"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.CelestialBrew,
        defaultPriority = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.6 then
                local usable = TankAssist.SecretValues:IsSpellUsable(spells.CelestialBrew)
                if usable then
                    return true, "HIGH", "Shield up"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.ExpelHarm,
        defaultPriority = "HIGH",
        condition = function(self)
            local hp = self:GetHealthPercent()
            if hp and hp < 0.5 then
                local usable = TankAssist.SecretValues:IsSpellUsable(spells.ExpelHarm)
                if usable then
                    return true, "HIGH", "Heal yourself!"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.BlackoutKick,
        defaultPriority = "HIGH",
        condition = function(self)
            local needsRefresh, reason = self:BuffNeedsRefresh(
                buffs.Shuffle,
                thresholds.ShuffleRefresh
            )
            if needsRefresh == nil then
                return false
            end
            if needsRefresh then
                if reason == "DOWN" then
                    return true, "URGENT", "Shuffle DOWN!"
                else
                    return true, "HIGH", "Refresh Shuffle"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.KegSmash,
        defaultPriority = "HIGH",
        condition = function(self)
            local usable = TankAssist.SecretValues:IsSpellUsable(spells.KegSmash)
            local energy = self:GetResource("ENERGY")
            if usable and energy and energy >= thresholds.KegSmashEnergy then
                return true, "HIGH", nil
            end
            return false
        end,
    },
    {
        spellId = spells.BreathOfFire,
        defaultPriority = "NORMAL",
        condition = function(self)
            if not self:HasTarget() then
                return false
            end
            local debuffInfo = TankAssist.SecretValues:GetBuffInfo("target", debuffs.BreathOfFireDot)
            if debuffInfo.isSecret then
                return true, "NORMAL", nil
            end
            if not debuffInfo.exists then
                return true, "HIGH", "BoF debuff down"
            end
            local remaining = (debuffInfo.expirationTime or 0) - GetTime()
            if remaining < 3 then
                return true, "NORMAL", "Refresh BoF"
            end
            return false
        end,
    },
    {
        spellId = spells.RushingJadeWind,
        defaultPriority = "NORMAL",
        condition = function(self)
            if not IsSpellKnown(spells.RushingJadeWind) then
                return false
            end
            local rjwInfo = TankAssist.SecretValues:GetBuffInfo("player", spells.RushingJadeWind)
            if not rjwInfo.exists then
                return true, "HIGH", "RJW down"
            end
            local remaining = (rjwInfo.expirationTime or 0) - GetTime()
            if remaining > 0 and remaining < 2 then
                return true, "NORMAL", "RJW expiring"
            end
            return false
        end,
    },
    {
        spellId = spells.SpinningCraneKick,
        defaultPriority = "NORMAL",
        condition = function(self)
            local enemies = self:GetEnemyCount()
            if enemies >= 3 then
                local energy = self:GetResource("ENERGY")
                if energy and energy >= 40 then
                    if enemies >= 5 then
                        return true, "HIGH", "AoE! (5+ mobs)"
                    end
                    return true, "NORMAL", "AoE (3+ mobs)"
                end
            end
            return false
        end,
    },
    {
        spellId = spells.TigerPalm,
        defaultPriority = "NORMAL",
        condition = function(self)
            local energy = self:GetResource("ENERGY")
            if energy and energy >= 50 then
                local kegCD = TankAssist.SecretValues:GetCooldownInfo(spells.KegSmash)
                if kegCD.remaining and kegCD.remaining > 1 then
                    return true, "NORMAL", nil
                end
            end
            return false
        end,
    },
}

function brewmaster:OnUpdate()
    self.currentStagger = self:GetStaggerInfo()
end

function brewmaster:GetStaggerDisplayInfo()
    local stagger = self:GetStaggerInfo()

    local colors = {
        NONE = { 0.5, 0.5, 0.5 },
        LIGHT = { 0.2, 0.8, 0.2 },
        MODERATE = { 1, 0.8, 0 },
        HEAVY = { 1, 0.2, 0.2 },
    }

    return {
        level = stagger.level,
        percent = stagger.percent,
        amount = stagger.amount,
        color = colors[stagger.level] or colors.NONE,
        shouldPurify = stagger.level == "HEAVY" or stagger.level == "MODERATE",
        isSecret = false,
    }
end

brewmaster:Register()
TankAssist.Brewmaster = brewmaster
