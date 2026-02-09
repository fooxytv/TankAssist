-- Luacheck configuration for TankAssist WoW Addon

std = "lua51"
max_line_length = false

-- Exclude library files
exclude_files = {
    "Libs/**",
    "ci/**",
}

-- WoW global functions and variables
globals = {
    -- WoW API namespaces
    "C_Spell",
    "C_UnitAuras",
    "C_AssistedCombat",
    "C_SpellActivationOverlay",
    "C_Timer",
    "Enum",
    "AuraUtil",
    "EventRegistry",
    "EditModeManagerFrame",

    -- WoW API functions
    "CreateFrame",
    "GetTime",
    "UnitHealth",
    "UnitHealthMax",
    "UnitPower",
    "UnitPowerMax",
    "UnitStagger",
    "UnitExists",
    "UnitIsDead",
    "UnitCanAttack",
    "UnitAffectingCombat",
    "GetSpecialization",
    "GetSpecializationInfo",
    "IsSpellKnown",
    "IsPlayerSpell",
    "GetActionInfo",
    "GetBindingKey",
    "GetMacroSpell",
    "GetRuneCooldown",
    "GetInstanceInfo",
    "CopyTable",
    "hooksecurefunc",
    "issecretvalue",
    "canaccesssecrets",
    "canaccessvalue",

    -- WoW UI globals
    "UIParent",
    "GameTooltip",
    "IsShiftKeyDown",
    "ActionButton_ShowOverlayGlow",
    "ActionButton_HideOverlayGlow",
    "SlashCmdList",
    "SLASH_TANKASSIST1",
    "SLASH_TANKASSIST2",

    -- Libraries
    "LibStub",

    -- Addon global (set by the addon itself)
    "TankAssist",
    "TankAssistDB",
}

-- Read-only globals (accessed but not modified)
read_globals = {
    "print",
    "pairs",
    "ipairs",
    "type",
    "tostring",
    "tonumber",
    "string",
    "table",
    "math",
    "select",
    "unpack",
    "next",
    "setmetatable",
    "getmetatable",
    "rawget",
    "rawset",
    "pcall",
    "xpcall",
    "error",
    "assert",
}
