# TankAssist

A tank rotation assistant addon for World of Warcraft 12.0 (Midnight) that works within Blizzard's new API restrictions.

## Overview

TankAssist provides three tiers of functionality:

### Tier 1: Blizzard Assisted Combat Integration
- Displays Blizzard's built-in rotation recommendations in a customizable UI
- Shows keybinds for recommended abilities
- Works anywhere the Assisted Combat system works

### Tier 2: Cooldown Tracking
- Tracks major defensive and offensive cooldowns
- Shows cooldown timers and charge counts
- Color-coded by category (Major/Defensive/Offensive)

### Tier 3: Buff Maintenance
- Tracks tank-specific maintenance buffs
- Shows buff duration and stack counts
- Alerts when buffs need refreshing (e.g., Bone Shield, Shuffle, Ironfur)

## Supported Specs

- **Blood Death Knight** - Full implementation
  - Bone Shield stack tracking
  - Runic Power management
  - Crimson Scourge proc tracking
  
- **Brewmaster Monk** - Full implementation
  - Stagger level tracking
  - Purifying Brew recommendations
  - Shuffle maintenance
  
- **Protection Warrior** - Implemented
  - Shield Block uptime
  - Revenge proc tracking
  - Rage management
  
- **Protection Paladin** - Implemented
  - Shield of the Righteous uptime
  - Holy Power tracking
  - Shining Light proc tracking
  
- **Vengeance Demon Hunter** - Implemented
  - Soul Fragment tracking
  - Demon Spikes uptime
  - Spirit Bomb recommendations
  
- **Guardian Druid** - Implemented
  - Ironfur stack tracking
  - Gore/Galactic Guardian procs
  - Frenzied Regeneration management

## Installation

1. Download and extract to your `World of Warcraft/_retail_/Interface/AddOns/` folder
2. Ensure the folder is named `TankAssist`
3. Restart WoW or `/reload`

## Slash Commands

```
/ta or /tankassist - Show help
/ta toggle        - Enable/disable addon
/ta lock          - Lock frame position
/ta unlock        - Unlock frame for dragging
/ta config        - Open configuration panel
/ta reset         - Reset frame position
/ta debug on/off  - Toggle debug mode
/ta test          - Run diagnostic tests
```

## API Restrictions in 12.0

This addon is designed to work within Blizzard's new "Secret Values" system. The situation is more nuanced than "everything is restricted":

### What's DECLASSIFIED (Always Accessible)

Blizzard explicitly whitelisted these for addon access:

- **Secondary Resources**: Stagger, Holy Power, Soul Fragments, Chi, Combo Points, Runes, Arcane Charges
- **Specific Spells**: Maelstrom Weapon, DH Devourer spells, Combat Res, GCD, Skyriding abilities
- **Your Own Cooldowns**: Generally accessible through the Cooldown Manager API
- **Your Own Spell Casts**: Castbar info is accessible

### What's RESTRICTED (Secret Values)

- **Enemy State**: Health, casts, debuffs (especially in M+)
- **Enemy Identity**: Names simplified in M+, nameplate restrictions
- **Complex Logic**: Can't do `if health < 30% then X` in tainted code
- **Primary Resources**: Health, Mana, Rage, Energy - can DISPLAY but not do logic

### What This Means for Tanks

**Good news for tanks!** Most tank tracking needs are covered:

| Spec | Key Mechanic | Status |
|------|--------------|--------|
| Brewmaster | Stagger | ✅ **Explicitly whitelisted** |
| Vengeance DH | Soul Fragments | ✅ **Explicitly whitelisted** |
| Protection Paladin | Holy Power | ✅ Secondary resource |
| Blood DK | Bone Shield, Runes | ⚠️ Buff tracking varies, Runes accessible |
| Guardian Druid | Ironfur stacks | ⚠️ Buff tracking may be limited |
| Protection Warrior | Shield Block | ⚠️ Buff tracking may be limited |

### How Centered Cooldown Manager Works

Addons like Centered Cooldown Manager work because:
1. Blizzard provides the Cooldown Manager API
2. Cooldown availability is generally trackable
3. Some spells are explicitly whitelisted

Our addon uses similar techniques - if CDM works, TankAssist should work too.

## Configuration

Access the config panel via `/ta config` or through the interface options.

### Display Options
- **Scale**: Adjust UI size (0.5 - 2.0)
- **Show out of combat**: Display when not in combat
- **Show without target**: Display without an enemy target
- **Hide in M+**: Hide when API is limited in keystones

### Assisted Combat
- **Enable**: Show Blizzard's rotation recommendations
- **Show keybinds**: Display ability keybinds

### Cooldown Tracker
- **Show Major**: Display major cooldowns (DRW, Metamorphosis, etc.)
- **Show Defensive**: Display defensive cooldowns
- **Show Offensive**: Display offensive cooldowns

### Buff Maintenance
- **Warning threshold**: Seconds before buff expires to show warning

## How It Works

### Blizzard's Assisted Combat
The addon hooks into Blizzard's `C_Spell.GetAssistedHighlight()` API (and fallbacks) to display what Blizzard recommends you press next. This is the same system that powers the "Single-Button Assistant" feature.

### Spec Module System
Each tank spec has a dedicated module that defines:
- **Maintenance buffs** to track
- **Cooldowns** to display
- **Rotation priority** for fallback recommendations

### Secret Values Handling
The `SecretValues.lua` module handles checking for and working around API restrictions:
```lua
-- Check if a value is secret
if TA.SecretValues:IsSecret(value) then
    -- Handle gracefully
end

-- Safe buff checking with fallback
local info = TA.SecretValues:GetBuffInfo("player", spellId)
if info.isSecret then
    -- Show "unknown" state
end
```

## Extending the Addon

### Adding a New Spec

1. Create a new file in `Specs/`
2. Inherit from `TA.SpecBase`
3. Define `buffsToTrack`, `cooldownsToTrack`, and `rotationPriority`
4. Register with `spec:Register()`

Example:
```lua
local MySpec = TA.SpecBase:New(SPEC_ID, "Spec Name")

MySpec.buffsToTrack = {
    {
        spellId = 12345,
        name = "Important Buff",
        refreshThreshold = 3,
        priority = "CRITICAL",
    },
}

MySpec.rotationPriority = {
    {
        spellId = 12345,
        condition = function(self)
            -- Return true to recommend, false to skip
            return self:BuffNeedsRefresh(12345, 3)
        end,
    },
}

MySpec:Register()
```

### Updating Rotation Data

The `Data/RotationData.lua` file contains APL-style rotation definitions that can be updated independently of the core addon code.

## Troubleshooting

### Addon not showing
1. Check you're a tank spec
2. Try `/ta unlock` to see if frame is off-screen
3. Run `/ta test` for diagnostics

### Limited functionality in M+
This is expected due to API restrictions. The addon will show what's available.

### Recommendations seem wrong
1. Check if Blizzard's Assisted Combat is enabled in Interface Options
2. The addon prioritizes Blizzard's recommendation over its own

## Credits

- SimulationCraft for rotation reference
- Wowhead/Icy Veins for tanking guides
- WoWUIDev Discord for API documentation

## License

MIT License - Feel free to modify and distribute.

## Changelog

### 1.0.0
- Initial release for WoW 12.0
- Support for all 6 tank specs
- Blizzard Assisted Combat integration
- Cooldown and buff tracking
