local ADDON_NAME, TankAssist = ...

TankAssist.RotationData = {}
local rotationData = TankAssist.RotationData

rotationData.version = "12.0.0"
rotationData.lastUpdated = "2026-01-26"
rotationData.dataSource = "SimC APL / Wowhead Guides"

rotationData.Profiles = {
    BloodDeathKnight = {
        DEFAULT = {
            name = "Standard",
            description = "Balanced survivability and damage",
            priority = {
                "death_strike,if=health.pct<50",
                "marrowrend,if=buff.bone_shield.stack<5",
                "death_and_decay,if=buff.crimson_scourge.up",
                "blood_boil,if=charges>=2",
                "heart_strike,if=rune>=3&buff.bone_shield.stack>=5",
                "death_strike,if=runic_power>=80",
                "consumption",
                "blood_boil",
            },
        },
        HIGH_DAMAGE = {
            name = "High Damage",
            description = "Prioritize damage, less defensive",
            priority = {
                "marrowrend,if=buff.bone_shield.stack<3",
                "death_and_decay,if=buff.crimson_scourge.up",
                "heart_strike",
                "blood_boil,if=charges>=2",
                "death_strike,if=runic_power>=60|health.pct<40",
                "consumption",
            },
        },
        SURVIVAL = {
            name = "Survival",
            description = "Maximum survivability",
            priority = {
                "death_strike,if=health.pct<60",
                "marrowrend,if=buff.bone_shield.stack<7",
                "death_and_decay,if=buff.crimson_scourge.up",
                "death_strike,if=runic_power>=60",
                "blood_boil",
                "heart_strike",
            },
        },
    },
    
    Brewmaster = {
        DEFAULT = {
            name = "Standard",
            description = "Balanced brew usage",
            priority = {
                "purifying_brew,if=stagger.heavy",
                "celestial_brew,if=health.pct<70",
                "blackout_kick,if=buff.shuffle.remains<3",
                "keg_smash",
                "breath_of_fire",
                "purifying_brew,if=stagger.moderate&brew.charges>=2",
                "rushing_jade_wind,if=buff.rushing_jade_wind.down",
                "spinning_crane_kick,if=enemies>=3",
                "tiger_palm,if=energy>=50",
            },
        },
    },
    
    ProtectionWarrior = {
        DEFAULT = {
            name = "Standard",
            description = "Balanced block and damage",
            priority = {
                "shield_block,if=buff.shield_block.remains<2",
                "shield_slam",
                "thunder_clap",
                "revenge,if=buff.revenge.up",
                "ignore_pain,if=rage>=60&health.pct<80",
                "revenge,if=rage>=60",
                "devastate",
            },
        },
    },
    
    ProtectionPaladin = {
        DEFAULT = {
            name = "Standard",
            description = "Balanced holy power usage",
            priority = {
                "shield_of_the_righteous,if=buff.shield_of_the_righteous.remains<3&holy_power>=3",
                "word_of_glory,if=buff.shining_light.up&health.pct<50",
                "judgment",
                "avengers_shield",
                "hammer_of_the_righteous",
                "consecration,if=buff.consecration.down",
                "shield_of_the_righteous,if=holy_power>=5",
            },
        },
    },
    
    VengeanceDemonHunter = {
        DEFAULT = {
            name = "Standard",
            description = "Balanced fragment usage",
            priority = {
                "soul_cleave,if=health.pct<40",
                "demon_spikes,if=buff.demon_spikes.remains<2&charges>=1",
                "spirit_bomb,if=soul_fragments>=4",
                "immolation_aura,if=buff.immolation_aura.down",
                "fracture,if=soul_fragments<4",
                "sigil_of_flame",
                "soul_cleave,if=fury>=60",
                "shear",
            },
        },
    },
    
    GuardianDruid = {
        DEFAULT = {
            name = "Standard", 
            description = "Balanced rage usage",
            priority = {
                "frenzied_regeneration,if=health.pct<70&charges>=1",
                "ironfur,if=buff.ironfur.stack<2|buff.ironfur.remains<3",
                "mangle,if=buff.gore.up",
                "thrash",
                "mangle",
                "moonfire,if=buff.galactic_guardian.up",
                "maul,if=buff.tooth_and_claw.up|rage>=80",
                "swipe",
            },
        },
    },
}

function rotationData:ParseCondition(conditionStr, specModule)
    local conditions = {}
    for condition in conditionStr:gmatch("[^,]+") do
        condition = condition:match("^%s*(.-)%s*$")
        local healthOp, healthVal = condition:match("health%.pct([<>=]+)(%d+)")
        if healthOp and healthVal then
            table.insert(conditions, function()
                local hp = specModule:GetHealthPercent()
                if not hp then return nil end
                return self:Compare(hp * 100, tonumber(healthVal), healthOp)
            end)
        end
        
        local buffName, buffOp, buffVal = condition:match("buff%.([%w_]+)%.(%w+)([<>=]*)(%d*)")
        if buffName then
        end
        
        local resource, resOp, resVal = condition:match("(%w+)([<>=]+)(%d+)")
        if resource and resOp and resVal then
            local resourceMap = {
                runic_power = "RUNIC_POWER",
                rage = "RAGE",
                energy = "ENERGY",
                fury = "FURY",
                holy_power = "HOLY_POWER",
                rune = "RUNES",
            }
            
            if resourceMap[resource:lower()] then
                table.insert(conditions, function()
                    local val = specModule:GetResource(resourceMap[resource:lower()])
                    if not val then return nil end
                    return self:Compare(val, tonumber(resVal), resOp)
                end)
            end
        end
    end
    
    return function()
        for _, check in ipairs(conditions) do
            local result = check()
            if result == false then return false end
            if result == nil then return nil end -- Can't determine
        end
        return true
    end
end

function rotationData:Compare(a, b, op)
    if op == "<" then return a < b
    elseif op == "<=" then return a <= b
    elseif op == ">" then return a > b
    elseif op == ">=" then return a >= b
    elseif op == "=" or op == "==" then return a == b
    end
    return nil
end

function rotationData:GetProfiles(specId)
    local specMap = {
        [250] = "BloodDeathKnight",
        [268] = "Brewmaster",
        [73] = "ProtectionWarrior",
        [66] = "ProtectionPaladin",
        [581] = "VengeanceDemonHunter",
        [104] = "GuardianDruid",
    }
    local specKey = specMap[specId]
    if not specKey then return nil end
    return self.Profiles[specKey]
end

function rotationData:GetDefaultProfile(specId)
    local profiles = self:GetProfiles(specId)
    if profiles then
        return profiles.DEFAULT
    end
    return nil
end

function rotationData:LoadExternalData(source, data)
    TankAssist.Utils:Debug("External data loading not yet implemented")
end
