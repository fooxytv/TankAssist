-- TankAssist Constants
-- Spell IDs, buff IDs, and other static data for tank specializations

local ADDON_NAME, TA = ...
TA.Constants = {}

-- =============================================================================
-- SPEC IDENTIFIERS
-- =============================================================================
TA.Constants.SPECS = {
    BLOOD_DK = 250,
    BREWMASTER = 268,
    PROTECTION_WARRIOR = 73,
    PROTECTION_PALADIN = 66,
    VENGEANCE_DH = 581,
    GUARDIAN_DRUID = 104,
}

-- Reverse lookup
TA.Constants.SPEC_NAMES = {
    [250] = "Blood Death Knight",
    [268] = "Brewmaster Monk",
    [73] = "Protection Warrior",
    [66] = "Protection Paladin",
    [581] = "Vengeance Demon Hunter",
    [104] = "Guardian Druid",
}

-- =============================================================================
-- DEATH KNIGHT - BLOOD
-- =============================================================================
TA.Constants.BLOOD_DK = {
    -- Core Abilities
    SPELLS = {
        MARROWREND = 195182,
        HEART_STRIKE = 206930,
        DEATH_STRIKE = 49998,
        BLOOD_BOIL = 50842,
        DEATHS_CARESS = 195292,
        DEATH_AND_DECAY = 43265,
        CONSUMPTION = 274156,
        BONESTORM = 194844,
        DANCING_RUNE_WEAPON = 49028,
        VAMPIRIC_BLOOD = 55233,
        ICEBOUND_FORTITUDE = 48792,
        ANTI_MAGIC_SHELL = 48707,
        RAISE_DEAD = 46585,
        DEATH_GRIP = 49576,
        GOREFIENDS_GRASP = 108199,
        TOMBSTONE = 219809,
        RUNE_TAP = 194679,
        ABOMINATION_LIMB = 383269,
        EMPOWER_RUNE_WEAPON = 47568,
    },

    -- Resource costs for spells (Runic Power and Runes)
    SPELL_COSTS = {
        [195182] = { resource = "RUNES", cost = 2 },        -- Marrowrend
        [206930] = { resource = "RUNES", cost = 1 },        -- Heart Strike
        [49998] = { resource = "RUNIC_POWER", cost = 40 },  -- Death Strike (35 with Ossuary)
        [50842] = { resource = "RUNES", cost = 1 },         -- Blood Boil
        [195292] = { resource = "RUNES", cost = 1 },        -- Death's Caress
        [43265] = { resource = "RUNES", cost = 1 },         -- Death and Decay
        [274156] = { resource = "RUNES", cost = 1 },        -- Consumption
        [194844] = { resource = "RUNIC_POWER", cost = 10 }, -- Bonestorm (per second)
    },

    -- Buffs to track
    BUFFS = {
        BONE_SHIELD = 195181,           -- Main maintenance buff
        BLOOD_SHIELD = 77535,           -- Death Strike absorb (amount is secret, but existence is trackable)
        DANCING_RUNE_WEAPON = 81256,    -- Active mitigation
        VAMPIRIC_BLOOD = 55233,         -- Defensive CD
        ICEBOUND_FORTITUDE = 48792,     -- Defensive CD
        ANTI_MAGIC_SHELL = 48707,       -- Magic defensive
        CRIMSON_SCOURGE = 81141,        -- Free D&D proc
        HEMOSTASIS = 273947,            -- Bonus Death Strike healing
        OSSUARY = 219786,               -- Runic power reduction
    },

    -- Important thresholds
    THRESHOLDS = {
        BONE_SHIELD_MIN = 5,            -- Refresh at this many stacks
        BONE_SHIELD_MAX = 10,           -- Maximum stacks
        DEATH_STRIKE_RP = 40,           -- RP cost (35 with Ossuary)
        LOW_HEALTH_PERCENT = 0.5,       -- Prioritize Death Strike
    },

    -- Cooldown categories
    COOLDOWNS = {
        MAJOR = { 49028, 55233 },                           -- DRW, Vampiric Blood
        DEFENSIVE = { 48792, 48707, 194679, 219809 },       -- IBF, AMS, Rune Tap, Tombstone
        OFFENSIVE = { 194844, 383269, 47568 },              -- Bonestorm, Abom Limb, ERW
    },
}

-- =============================================================================
-- MONK - BREWMASTER
-- =============================================================================
TA.Constants.BREWMASTER = {
    SPELLS = {
        TIGER_PALM = 100780,
        BLACKOUT_KICK = 205523,
        KEG_SMASH = 121253,
        BREATH_OF_FIRE = 115181,
        SPINNING_CRANE_KICK = 322729,
        RUSHING_JADE_WIND = 116847,
        PURIFYING_BREW = 119582,
        CELESTIAL_BREW = 322507,
        FORTIFYING_BREW = 115203,
        ZEN_MEDITATION = 115176,
        INVOKE_NIUZAO = 132578,
        EXPLODING_KEG = 325153,
        BONEDUST_BREW = 386276,
        WEAPONS_OF_ORDER = 387184,
        DAMPEN_HARM = 122278,
        DIFFUSE_MAGIC = 122783,
        EXPEL_HARM = 322101,
        CLASH = 324312,
        RING_OF_PEACE = 116844,
        SUMMON_WHITE_TIGER_STATUE = 388686,
    },

    -- Resource costs for spells (energy for Brewmaster)
    SPELL_COSTS = {
        [100780] = { resource = "ENERGY", cost = 50 },   -- Tiger Palm
        [205523] = { resource = "ENERGY", cost = 0 },    -- Blackout Kick (free)
        [121253] = { resource = "ENERGY", cost = 40 },   -- Keg Smash
        [115181] = { resource = "ENERGY", cost = 0 },    -- Breath of Fire (free)
        [322729] = { resource = "ENERGY", cost = 25 },   -- Spinning Crane Kick
        [116847] = { resource = "ENERGY", cost = 0 },    -- Rushing Jade Wind (free, talent)
        [322101] = { resource = "ENERGY", cost = 15 },   -- Expel Harm
    },

    BUFFS = {
        SHUFFLE = 322120,               -- Core mitigation buff
        CELESTIAL_BREW = 322507,        -- Absorb shield
        FORTIFYING_BREW = 115203,       -- Major defensive
        ZEN_MEDITATION = 115176,        -- Channel defensive
        BLACKOUT_COMBO = 228563,        -- Talent buff
        CHARRED_PASSIONS = 386963,      -- Breath of Fire buff
        PRETENSE_OF_INSTABILITY = 393516, -- Dodge buff
        ELUSIVE_BRAWLER = 195630,       -- Stagger mastery stacks
        WEAPONS_OF_ORDER = 387184,      -- Cooldown buff
    },

    DEBUFFS = {
        -- Stagger levels (on player, shown as debuffs)
        LIGHT_STAGGER = 124275,
        MODERATE_STAGGER = 124274,
        HEAVY_STAGGER = 124273,
        BREATH_OF_FIRE_DOT = 123725,    -- On enemies
    },

    THRESHOLDS = {
        PURIFY_STAGGER_PERCENT = 0.06,  -- Purify when stagger > 6% of max HP
        HEAVY_STAGGER_PERCENT = 0.10,   -- Heavy stagger threshold
        SHUFFLE_REFRESH = 3,            -- Refresh when < 3 seconds
        KEG_SMASH_ENERGY = 40,          -- Energy cost (legacy, use SPELL_COSTS instead)
    },

    COOLDOWNS = {
        MAJOR = { 132578, 387184 },                         -- Niuzao, WoO
        DEFENSIVE = { 115203, 115176, 122278, 122783 },     -- Fort Brew, Zen Med, Dampen, Diffuse
        OFFENSIVE = { 325153, 386276 },                     -- Exploding Keg, Bonedust
    },
}

-- =============================================================================
-- WARRIOR - PROTECTION
-- =============================================================================
TA.Constants.PROTECTION_WARRIOR = {
    SPELLS = {
        SHIELD_SLAM = 23922,
        THUNDER_CLAP = 6343,
        REVENGE = 6572,
        DEVASTATE = 20243,
        SHIELD_BLOCK = 2565,
        IGNORE_PAIN = 190456,
        SHIELD_WALL = 871,
        LAST_STAND = 12975,
        DEMORALIZING_SHOUT = 1160,
        SPELL_REFLECTION = 23920,
        AVATAR = 401150,
        RAVAGER = 228920,
        SHOCKWAVE = 46968,
        HEROIC_THROW = 57755,
        CHARGE = 100,
        INTERVENE = 3411,
        RALLYING_CRY = 97462,
        CHAMPIONS_SPEAR = 376079,
        THUNDEROUS_ROAR = 384318,
    },

    -- Resource costs for spells (Rage)
    SPELL_COSTS = {
        [23922] = { resource = "RAGE", cost = 0 },          -- Shield Slam (generates rage)
        [6343] = { resource = "RAGE", cost = 0 },           -- Thunder Clap (generates rage)
        [6572] = { resource = "RAGE", cost = 20 },          -- Revenge (0 with proc)
        [20243] = { resource = "RAGE", cost = 0 },          -- Devastate (free)
        [2565] = { resource = "RAGE", cost = 30 },          -- Shield Block
        [190456] = { resource = "RAGE", cost = 40 },        -- Ignore Pain
        [46968] = { resource = "RAGE", cost = 0 },          -- Shockwave (free)
    },

    BUFFS = {
        SHIELD_BLOCK = 132404,          -- Core mitigation
        IGNORE_PAIN = 190456,           -- Absorb
        SHIELD_WALL = 871,              -- Major defensive
        LAST_STAND = 12975,             -- Health increase
        AVATAR = 401150,                -- Offensive CD
        RAVAGER = 228920,               -- Parry buff
        REVENGE_PROC = 5302,            -- Free Revenge
        VIOLENT_OUTBURST = 386478,      -- Shield Slam reset
        VANGUARD = 71,                  -- Mastery buff
    },

    THRESHOLDS = {
        SHIELD_BLOCK_REFRESH = 2,       -- Refresh at < 2 seconds
        IGNORE_PAIN_MAX_ABSORB = 0.5,   -- Cap at 50% of max HP
        LOW_RAGE_THRESHOLD = 40,        -- Conserve rage below this
        REVENGE_RAGE = 20,              -- Rage cost (0 if proc)
    },

    COOLDOWNS = {
        MAJOR = { 401150, 228920, 376079 },                 -- Avatar, Ravager, Spear
        DEFENSIVE = { 871, 12975, 23920, 1160 },            -- Wall, Last Stand, Reflect, Demo Shout
        OFFENSIVE = { 384318 },                             -- Thunderous Roar
    },
}

-- =============================================================================
-- PALADIN - PROTECTION
-- =============================================================================
TA.Constants.PROTECTION_PALADIN = {
    SPELLS = {
        JUDGMENT = 275779,
        SHIELD_OF_THE_RIGHTEOUS = 53600,
        AVENGERS_SHIELD = 31935,
        HAMMER_OF_THE_RIGHTEOUS = 53595,
        BLESSED_HAMMER = 204019,
        CONSECRATION = 26573,
        WORD_OF_GLORY = 85673,
        ARDENT_DEFENDER = 31850,
        GUARDIAN_OF_ANCIENT_KINGS = 86659,
        DIVINE_SHIELD = 642,
        LAY_ON_HANDS = 633,
        AVENGING_WRATH = 31884,
        MOMENT_OF_GLORY = 327193,
        SENTINEL = 389539,
        EYE_OF_TYR = 387174,
        HAMMER_OF_WRATH = 24275,
        DIVINE_TOLL = 375576,
        HAND_OF_RECKONING = 62124,
    },

    -- Resource costs for spells (Holy Power)
    SPELL_COSTS = {
        [275779] = { resource = "HOLY_POWER", cost = 0 },   -- Judgment (generates HP)
        [53600] = { resource = "HOLY_POWER", cost = 3 },    -- Shield of the Righteous
        [31935] = { resource = "HOLY_POWER", cost = 0 },    -- Avenger's Shield (generates HP)
        [53595] = { resource = "HOLY_POWER", cost = 0 },    -- Hammer of the Righteous (generates HP)
        [204019] = { resource = "HOLY_POWER", cost = 0 },   -- Blessed Hammer (generates HP)
        [26573] = { resource = "HOLY_POWER", cost = 0 },    -- Consecration (free)
        [85673] = { resource = "HOLY_POWER", cost = 3 },    -- Word of Glory
        [24275] = { resource = "HOLY_POWER", cost = 0 },    -- Hammer of Wrath (generates HP)
    },

    BUFFS = {
        SHIELD_OF_THE_RIGHTEOUS = 132403,   -- Core mitigation
        CONSECRATION = 188370,               -- Ground effect buff
        ARDENT_DEFENDER = 31850,             -- Defensive CD
        GUARDIAN_OF_ANCIENT_KINGS = 86659,   -- Major defensive
        AVENGING_WRATH = 31884,              -- Wings
        SENTINEL = 389539,                   -- Talent defensive
        MOMENT_OF_GLORY = 327193,            -- Avenger's Shield buff
        SHINING_LIGHT = 327510,              -- Free Word of Glory
        BLESSED_ASSURANCE = 433019,          -- Holy power buff
    },

    THRESHOLDS = {
        SOTR_REFRESH = 3,               -- Refresh at < 3 seconds
        CONSECRATION_REFRESH = 1,       -- Keep consecration up
        WORD_OF_GLORY_HP = 0.5,         -- Use WoG below 50% HP
        HOLY_POWER_MAX = 5,             -- Max holy power
    },

    COOLDOWNS = {
        MAJOR = { 31884, 389539, 375576 },                  -- Wings, Sentinel, Divine Toll
        DEFENSIVE = { 31850, 86659, 642, 633 },             -- AD, GoAK, Bubble, LoH
        OFFENSIVE = { 387174 },                             -- Eye of Tyr
    },
}

-- =============================================================================
-- DEMON HUNTER - VENGEANCE
-- =============================================================================
TA.Constants.VENGEANCE_DH = {
    SPELLS = {
        SHEAR = 203782,
        FRACTURE = 263642,
        SOUL_CLEAVE = 228477,
        SPIRIT_BOMB = 247454,
        IMMOLATION_AURA = 258920,
        SIGIL_OF_FLAME = 204596,
        SIGIL_OF_SILENCE = 202137,
        SIGIL_OF_MISERY = 207684,
        SIGIL_OF_CHAINS = 202138,
        SIGIL_OF_SPITE = 390163,
        DEMON_SPIKES = 203720,
        FIERY_BRAND = 204021,
        METAMORPHOSIS = 187827,
        FEL_DEVASTATION = 212084,
        INFERNAL_STRIKE = 189110,
        THE_HUNT = 370965,
        -- ELYSIAN_DECREE removed - replaced by Sigil of Spite (390163)
        SOUL_CARVER = 207407,
    },

    -- Resource costs for spells (Fury)
    SPELL_COSTS = {
        [203782] = { resource = "FURY", cost = 0 },         -- Shear (generates fury)
        [263642] = { resource = "FURY", cost = 25 },        -- Fracture
        [228477] = { resource = "FURY", cost = 30 },        -- Soul Cleave
        [247454] = { resource = "FURY", cost = 40 },        -- Spirit Bomb
        [258920] = { resource = "FURY", cost = 0 },         -- Immolation Aura (free)
        [204596] = { resource = "FURY", cost = 0 },         -- Sigil of Flame (free)
        [212084] = { resource = "FURY", cost = 50 },        -- Fel Devastation
    },

    BUFFS = {
        DEMON_SPIKES = 203819,          -- Core mitigation
        METAMORPHOSIS = 187827,         -- Major defensive
        SOUL_FRAGMENTS = 203981,        -- Resource tracking (visual)
        FIERY_BRAND = 207744,           -- Damage reduction on target
        IMMOLATION_AURA = 258920,       -- DoT aura
        CALCIFIED_SPIKES = 391171,      -- Talent buff
        PAINBRINGER = 207387,           -- Soul Cleave buff
    },

    THRESHOLDS = {
        DEMON_SPIKES_REFRESH = 2,       -- Refresh at < 2 seconds
        SOUL_FRAGMENTS_SPIRIT_BOMB = 4, -- Use Spirit Bomb at 4+ fragments
        FURY_FOR_SOUL_CLEAVE = 30,      -- Fury cost
        LOW_HEALTH_PERCENT = 0.4,       -- Prioritize Soul Cleave
    },

    COOLDOWNS = {
        MAJOR = { 187827, 370965, 390163 },                 -- Meta, Hunt, Sigil of Spite
        DEFENSIVE = { 204021, 212084 },                     -- Fiery Brand, Fel Dev
        OFFENSIVE = { 207407 },                             -- Soul Carver
    },
}

-- =============================================================================
-- DRUID - GUARDIAN
-- =============================================================================
TA.Constants.GUARDIAN_DRUID = {
    SPELLS = {
        MANGLE = 33917,
        THRASH = 77758,
        SWIPE = 213771,
        MAUL = 6807,
        IRONFUR = 192081,
        FRENZIED_REGENERATION = 22842,
        BARKSKIN = 22812,
        SURVIVAL_INSTINCTS = 61336,
        INCARNATION_GUARDIAN = 102558,
        BERSERK = 50334,
        RAGE_OF_THE_SLEEPER = 200851,
        PULVERIZE = 80313,
        BRISTLING_FUR = 155835,
        SKULL_BASH = 106839,
        INCAPACITATING_ROAR = 99,
        STAMPEDING_ROAR = 106898,
        MOONFIRE = 8921,
        CONVOKE_THE_SPIRITS = 391528,
    },

    -- Resource costs for spells (Rage)
    SPELL_COSTS = {
        [33917] = { resource = "RAGE", cost = 0 },          -- Mangle (generates rage)
        [77758] = { resource = "RAGE", cost = 0 },          -- Thrash (generates rage)
        [213771] = { resource = "RAGE", cost = 0 },         -- Swipe (generates rage)
        [6807] = { resource = "RAGE", cost = 40 },          -- Maul
        [192081] = { resource = "RAGE", cost = 40 },        -- Ironfur
        [22842] = { resource = "RAGE", cost = 10 },         -- Frenzied Regeneration
        [80313] = { resource = "RAGE", cost = 0 },          -- Pulverize (free, requires Thrash stacks)
        [8921] = { resource = "RAGE", cost = 0 },           -- Moonfire (free)
    },

    BUFFS = {
        IRONFUR = 192081,               -- Core mitigation (stacks)
        FRENZIED_REGENERATION = 22842,  -- HoT defensive
        BARKSKIN = 22812,               -- Defensive CD
        SURVIVAL_INSTINCTS = 61336,     -- Major defensive
        INCARNATION = 102558,           -- Major cooldown
        BERSERK = 50334,                -- Offensive CD
        RAGE_OF_THE_SLEEPER = 200851,   -- Defensive cooldown
        TOOTH_AND_CLAW = 135286,        -- Maul proc
        GALACTIC_GUARDIAN = 213708,     -- Moonfire proc
        GORE = 93622,                   -- Mangle reset
        EARTHWARDEN = 203975,           -- Thrash buff
        DREAM_OF_CENARIUS = 372152,     -- Healing buff
    },

    THRESHOLDS = {
        IRONFUR_MIN_STACKS = 2,         -- Maintain at least 2 stacks
        IRONFUR_REFRESH = 3,            -- Refresh at < 3 seconds
        FRENZIED_REGEN_HP = 0.7,        -- Use below 70% HP
        RAGE_FOR_IRONFUR = 40,          -- Rage cost
        RAGE_FOR_MAUL = 40,             -- Rage cost
    },

    COOLDOWNS = {
        MAJOR = { 102558, 50334, 391528 },                  -- Incarn, Berserk, Convoke
        DEFENSIVE = { 22812, 61336, 200851 },               -- Barkskin, SI, Rage of Sleeper
        OFFENSIVE = { 155835 },                             -- Bristling Fur
    },
}

-- =============================================================================
-- DISPLAY SETTINGS
-- =============================================================================
TA.Constants.DISPLAY = {
    -- Priority indicator colors
    COLORS = {
        URGENT = { 1, 0.2, 0.2, 1 },        -- Red - use immediately
        HIGH = { 1, 0.6, 0, 1 },            -- Orange - use soon
        NORMAL = { 1, 1, 1, 1 },            -- White - available
        READY = { 0.2, 1, 0.2, 1 },         -- Green - ready to use
        ON_COOLDOWN = { 0.5, 0.5, 0.5, 1 }, -- Gray - on cooldown
        BUFF_ACTIVE = { 0.4, 0.8, 1, 1 },   -- Blue - buff is up
        BUFF_EXPIRING = { 1, 1, 0, 1 },     -- Yellow - buff expiring soon
    },
    
    -- Icon sizes
    ICON_SIZES = {
        MAIN = 64,
        QUEUE = 48,
        COOLDOWN = 40,
        BUFF = 32,
    },
    
    -- Animation durations
    ANIMATIONS = {
        GLOW_PULSE = 0.5,
        FADE_IN = 0.2,
        FADE_OUT = 0.3,
    },
}

-- =============================================================================
-- ASSISTED COMBAT INTEGRATION
-- =============================================================================
TA.Constants.ASSISTED_COMBAT = {
    -- These are the APIs we'll attempt to use for Blizzard's assisted combat system
    -- Note: Actual API names may vary, these are placeholder based on research
    UPDATE_INTERVAL = 0.1,              -- How often to poll for updates
    QUEUE_DISPLAY_COUNT = 5,            -- Number of abilities to show in queue
}
