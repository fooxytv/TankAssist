local ADDON_NAME, TankAssist = ...

TankAssist.ClassCooldowns = {}
local classCooldowns = TankAssist.ClassCooldowns

classCooldowns.Data = {
    WARRIOR = {
        {
            spellId = 184364,
            category = "DEFENSIVE",
            urgency = "URGENT",
            condition = function(self)
                return self:HealthBelow(0.40)
            end,
        },
        {
            spellId = 97462,
            category = "DEFENSIVE",
            urgency = "HIGH",
            condition = function(self)
                return self:HealthBelow(0.50)
            end,
        },
        {
            spellId = 1719,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
        {
            spellId = 227847,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
    },

    PALADIN = {
        {
            spellId = 642,
            category = "DEFENSIVE",
            urgency = "URGENT",
            condition = function(self)
                return self:HealthBelow(0.20)
            end,
        },
        {
            spellId = 633,
            category = "DEFENSIVE",
            urgency = "URGENT",
            condition = function(self)
                return self:HealthBelow(0.30)
            end,
        },
        {
            spellId = 31884,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
    },

    HUNTER = {
        {
            spellId = 186265,
            category = "DEFENSIVE",
            urgency = "URGENT",
            condition = function(self)
                return self:HealthBelow(0.30)
            end,
        },
        {
            spellId = 109304,
            category = "DEFENSIVE",
            urgency = "HIGH",
            condition = function(self)
                return self:HealthBelow(0.50)
            end,
        },
        {
            spellId = 288613,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
    },

    ROGUE = {
        {
            spellId = 185311,
            category = "DEFENSIVE",
            urgency = "URGENT",
            condition = function(self)
                return self:HealthBelow(0.30)
            end,
        },
        {
            spellId = 31224,
            category = "DEFENSIVE",
            urgency = "HIGH",
            condition = function(self)
                return self:HealthBelow(0.40)
            end,
        },
        {
            spellId = 1856,
            category = "DEFENSIVE",
            urgency = "HIGH",
            condition = function(self)
                return self:HealthBelow(0.25)
            end,
        },
        {
            spellId = 13750,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
    },

    PRIEST = {
        {
            spellId = 19236,
            category = "DEFENSIVE",
            urgency = "URGENT",
            condition = function(self)
                return self:HealthBelow(0.35)
            end,
        },
        {
            spellId = 586,
            category = "DEFENSIVE",
            urgency = "HIGH",
            condition = function(self)
                return self:HealthBelow(0.50)
            end,
        },
        {
            spellId = 10060,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:InCombat()
            end,
        },
    },

    SHAMAN = {
        {
            spellId = 108271,
            category = "DEFENSIVE",
            urgency = "URGENT",
            condition = function(self)
                return self:HealthBelow(0.35)
            end,
        },
        {
            spellId = 198103,
            category = "DEFENSIVE",
            urgency = "HIGH",
            condition = function(self)
                return self:HealthBelow(0.50)
            end,
        },
        {
            spellId = 114051,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
    },

    MAGE = {
        {
            spellId = 45438,
            category = "DEFENSIVE",
            urgency = "URGENT",
            condition = function(self)
                return self:HealthBelow(0.20)
            end,
        },
        {
            spellId = 55342,
            category = "DEFENSIVE",
            urgency = "HIGH",
            condition = function(self)
                return self:HealthBelow(0.40)
            end,
        },
        {
            spellId = 12472,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
        {
            spellId = 190319,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
        {
            spellId = 365350,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
    },

    WARLOCK = {
        {
            spellId = 104773,
            category = "DEFENSIVE",
            urgency = "URGENT",
            condition = function(self)
                return self:HealthBelow(0.30)
            end,
        },
        {
            spellId = 108416,
            category = "DEFENSIVE",
            urgency = "HIGH",
            condition = function(self)
                return self:HealthBelow(0.50)
            end,
        },
        {
            spellId = 205180,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
    },

    DRUID = {
        {
            spellId = 22812,
            category = "DEFENSIVE",
            urgency = "URGENT",
            condition = function(self)
                return self:HealthBelow(0.40)
            end,
        },
        {
            spellId = 108238,
            category = "DEFENSIVE",
            urgency = "HIGH",
            condition = function(self)
                return self:HealthBelow(0.50)
            end,
        },
        {
            spellId = 194223,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
        {
            spellId = 102560,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
    },

    DEATHKNIGHT = {
        {
            spellId = 48792,
            category = "DEFENSIVE",
            urgency = "URGENT",
            condition = function(self)
                return self:HealthBelow(0.35)
            end,
        },
        {
            spellId = 48707,
            category = "DEFENSIVE",
            urgency = "HIGH",
            condition = function(self)
                return self:HealthBelow(0.50)
            end,
        },
        {
            spellId = 47568,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
    },

    MONK = {
        {
            spellId = 122783,
            category = "DEFENSIVE",
            urgency = "HIGH",
            condition = function(self)
                return self:HealthBelow(0.50)
            end,
        },
        {
            spellId = 122278,
            category = "DEFENSIVE",
            urgency = "HIGH",
            condition = function(self)
                return self:HealthBelow(0.40)
            end,
        },
        {
            spellId = 137639,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
        {
            spellId = 152173,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
    },

    DEMONHUNTER = {
        {
            spellId = 198589,
            category = "DEFENSIVE",
            urgency = "URGENT",
            condition = function(self)
                return self:HealthBelow(0.35)
            end,
        },
        {
            spellId = 196555,
            category = "DEFENSIVE",
            urgency = "HIGH",
            condition = function(self)
                return self:HealthBelow(0.50)
            end,
        },
        {
            spellId = 191427,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
        {
            spellId = 258925,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
    },

    EVOKER = {
        {
            spellId = 363916,
            category = "DEFENSIVE",
            urgency = "URGENT",
            condition = function(self)
                return self:HealthBelow(0.30)
            end,
        },
        {
            spellId = 374348,
            category = "DEFENSIVE",
            urgency = "HIGH",
            condition = function(self)
                return self:HealthBelow(0.50)
            end,
        },
        {
            spellId = 375087,
            category = "OFFENSIVE",
            urgency = "NORMAL",
            condition = function(self)
                return self:HasTarget() and self:InCombat()
            end,
        },
    },
}

function classCooldowns:GetForClass(classFile)
    return self.Data[classFile] or {}
end
