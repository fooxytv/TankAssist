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
