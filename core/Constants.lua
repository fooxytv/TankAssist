local ADDON_NAME, TankAssist = ...
TankAssist.Constants = {}

TankAssist.Constants.Specs = {
    BloodDeathKnight = 250,
    Brewmaster = 268,
    ProtectionWarrior = 73,
    ProtectionPaladin = 66,
    VengeanceDemonHunter = 581,
    GuardianDruid = 104,
}

TankAssist.Constants.SpecNames = {
    [250] = "Blood Death Knight",
    [268] = "Brewmaster Monk",
    [73] = "Protection Warrior",
    [66] = "Protection Paladin",
    [581] = "Vengeance Demon Hunter",
    [104] = "Guardian Druid",
}

TankAssist.Constants.Display = {
    Colors = {
        Urgent = { 1, 0.2, 0.2, 1 },
        High = { 1, 0.6, 0, 1 },
        Normal = { 1, 1, 1, 1 },
        Ready = { 0.2, 1, 0.2, 1 },
        OnCooldown = { 0.5, 0.5, 0.5, 1 },
        BuffActive = { 0.4, 0.8, 1, 1 },
        BuffExpiring = { 1, 1, 0, 1 },
    },
    IconSizes = {
        Main = 64,
        Queue = 48,
        Cooldown = 40,
        Buff = 32,
    },
    Animations = {
        GlowPulse = 0.5,
        FadeIn = 0.2,
        FadeOut = 0.3,
    },
}

TankAssist.Constants.AssistedCombat = {
    UpdateInterval = 0.1,
    QueueDisplayCount = 5,
}

TankAssist.Constants.Fonts = {
    { name = "Friz Quadrata",   path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow",    path = "Fonts\\ARIALN.TTF" },
    { name = "Morpheus",        path = "Fonts\\MORPHEUS.TTF" },
    { name = "Skurri",          path = "Fonts\\SKURRI.TTF" },
    { name = "2002",            path = "Fonts\\2002.TTF" },
    { name = "2002 Bold",       path = "Fonts\\2002B.TTF" },
    { name = "Express Way",     path = "Fonts\\EXPRESSWAY.TTF" },
}

TankAssist.Constants.FontFlags = {
    { name = "Outline",         flag = "OUTLINE" },
    { name = "Thick Outline",   flag = "THICKOUTLINE" },
    { name = "Monochrome",      flag = "MONOCHROME" },
    { name = "None",            flag = "" },
}

TankAssist.Constants.BarTextures = {
    { name = "Solid",           path = "Interface\\Buttons\\WHITE8x8" },
    { name = "Blizzard",        path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { name = "Blizzard Raid",   path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { name = "Blizzard Rock",   path = "Interface\\BarberShop\\UI-BarberShop-pointed" },
}

TankAssist.Constants.CooldownAlertDefaults = {
    [73]  = { 871, 12975, 6552 },
    [66]  = { 31850, 86659, 96231 },
    [250] = { 48792, 55233, 47528 },
    [268] = { 115203, 122278, 116705 },
    [581] = { 187827, 204021, 183752 },
    [104] = { 22812, 61336, 106839 },
}
