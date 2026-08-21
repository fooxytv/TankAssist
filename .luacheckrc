-- Luacheck configuration for TankAssist WoW Addon

std = "lua51"
max_line_length = false

-- Exclude library files. Lowercase "libs" matters: the CI runner is
-- case-sensitive, so "Libs/**" silently excluded nothing there.
exclude_files = {
    "libs/**",
    "ci/**",
}

-- Every global the addon touches is enumerated here, which is what lets
-- lint.sh leave the undefined-global diagnostics switched on. A mistyped API
-- name then fails CI instead of surfacing as an in-game error. When a new API
-- is used, add it here rather than restoring the ignores in lint.sh.
globals = {
    -- WoW API namespaces
    "C_AddOns",
    "C_AssistedCombat",
    "C_Item",
    "C_PetBattles",
    "C_Spell",
    "C_SpellActivationOverlay",
    "C_Timer",
    "C_UnitAuras",
    "AuraUtil",
    "EditModeManagerFrame",
    "Enum",
    "EventRegistry",
    "TooltipDataProcessor",

    -- WoW API functions
    "CreateFrame",
    "GetTime",
    "UnitHealth",
    "UnitHealthMax",
    "UnitPower",
    "UnitPowerMax",
    "UnitStagger",
    "UnitExists",
    "UnitName",
    "SetRaidTarget",
    "MenuUtil",
    "UnitIsDead",
    "UnitCanAttack",
    "UnitAffectingCombat",
    "UnitClass",
    "UnitCastingInfo",
    "UnitCastingDuration",
    "UnitChannelInfo",
    "UnitChannelDuration",
    "GetSpecialization",
    "GetSpecializationInfo",
    "GetSpecializationInfoByID",
    "IsSpellKnown",
    "IsPlayerSpell",
    "IsMounted",
    "IsInInstance",
    "InCombatLockdown",
    "GetActionInfo",
    "GetBindingKey",
    "GetMacroSpell",
    "GetRuneCooldown",
    "GetInstanceInfo",
    "GetWeaponEnchantInfo",
    "GetInventoryItemLink",
    "GetLootRollItemLink",
    "CopyTable",
    "hooksecurefunc",
    "issecretvalue",
    "canaccesssecrets",
    "canaccessvalue",

    -- Item API. The C_Item namespace is preferred, but the addon falls back to
    -- these globals when a client does not expose it.
    "GetItemInfoInstant",
    "GetItemStats",
    "GetDetailedItemLevelInfo",

    -- Sound API
    "PlaySound",
    "PlaySoundFile",
    "SOUNDKIT",

    -- WoW UI globals
    "UIParent",
    "GameTooltip",
    "IsShiftKeyDown",
    "ActionButton_ShowOverlayGlow",
    "ActionButton_HideOverlayGlow",
    "PlayerCastingBarFrame",
    "RAID_CLASS_COLORS",
    "NUM_GROUP_LOOT_FRAMES",
    "UISpecialFrames",
    "ScrollingEdit_OnCursorChanged",
    "ScrollingEdit_OnTextChanged",
    "SlashCmdList",
    "SLASH_TANKASSIST1",
    "SLASH_TANKASSIST2",

    -- Libraries
    "LibStub",

    -- Addon global (set by the addon itself)
    "TankAssist",
    "TankAssistDB",

    -- Key binding handler and labels, called by name from Bindings.xml
    "TankAssist_OpenTargetMarkerMenu",
    "BINDING_HEADER_TANKASSIST",
    "BINDING_NAME_TANKASSIST_TARGETMARKER_MENU",
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

    -- Lua aliases WoW exposes as globals
    "format",
    "tinsert",
    "wipe",
    "time",
}
