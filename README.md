# TankAssist

A tank assistant addon for World of Warcraft 12.0 (Midnight) designed to work within Blizzard's Assisted Combat API restrictions.

## Features

### Assisted Combat Display
- Displays Blizzard's built-in rotation recommendations in a customisable UI
- Shows keybinds for recommended abilities
- Works anywhere the Assisted Combat system works

### Player & Target Cast Bars
- Fully customisable replacements for Blizzard's default cast bars
- Configurable width, height, scale, and colours (cast, channel, non-interruptible, background, border)
- Text options: spell name, cast timer, font face/size, alignment, position (above/inside/below)
- Spell icon display with left/right positioning
- Bar texture selection (Solid, Blizzard, Smooth, Flat)
- Target cast bar shows interrupted state with linger and fade-out
- Option to hide Blizzard's default player cast bar

### External Cooldown Tracking
- Monitors healer and ally defensive cooldowns active on the player
- Supported externals: Pain Suppression, Guardian Spirit, Ironbark, Life Cocoon, Blessing of Sacrifice, Blessing of Protection, Blessing of Spellwarding, Rallying Cry
- Real-time duration display with cooldown sweep animation
- Handles Blizzard's secret values gracefully (shows "?" when duration is hidden)

### Cooldown Alerts
- Tracks your own player cooldowns (interrupts, defensives) and alerts when they come off cooldown
- Countdown timer with ready flash animation
- Per-spec defaults for all 6 tank specs
- Three alert styles: Ready Only, Countdown Only, Countdown + Ready
- Shadow tracking via UNIT_SPELLCAST_SUCCEEDED to work around secret value restrictions

### Cooldown & Buff Tracking
- Tracks major defensive and offensive cooldowns with timers and charge counts
- Colour-coded by category (Major/Defensive/Offensive)
- Tracks tank-specific maintenance buffs (Bone Shield, Shuffle, Ironfur, etc.)
- Alerts when buffs need refreshing

### Shared Display Options
The following settings are available for External Cooldowns and Cooldown Alerts:
- **Display Mode**: Icon Only, Icon + Name, Name Only
- **Timer Position**: Inside Icon or Below Icon
- **Border Color**: Configurable via colour picker
- **Icon Size** and **Scale** sliders

### Edit Mode Integration
All UI components integrate with WoW's Edit Mode via LibEQOL:
- Drag to reposition any frame
- In-place settings via sliders, dropdowns, checkboxes, and colour pickers
- All settings saved per-character and persist across reloads

## Supported Specs

| Spec | Key Mechanics |
|------|---------------|
| **Blood Death Knight** | Bone Shield stacks, Runic Power, Crimson Scourge procs |
| **Brewmaster Monk** | Stagger tracking, Purifying Brew, Shuffle maintenance |
| **Protection Warrior** | Shield Block uptime, Revenge procs, Rage management |
| **Protection Paladin** | Shield of the Righteous, Holy Power, Shining Light procs |
| **Vengeance Demon Hunter** | Soul Fragments, Demon Spikes, Spirit Bomb |
| **Guardian Druid** | Ironfur stacks, Gore/Galactic Guardian procs, Frenzied Regen |

## Installation

1. Download the latest release from [GitHub Releases](https://github.com/fooxytv/TankAssist/releases) or CurseForge
2. Extract to your `World of Warcraft/_retail_/Interface/AddOns/` folder
3. Ensure the folder is named `TankAssist`
4. Restart WoW or `/reload`

## Slash Commands

### General
```
/ta                  - Show help
/ta toggle           - Enable/disable addon
/ta config           - Open configuration panel
/ta reset            - Reset frame position
/ta test             - Run diagnostic tests
```

### Positioning
```
/ta edit             - Instructions for using Edit Mode
/ta lock             - (same as edit)
/ta unlock           - (same as edit)
```
All frames are repositioned via WoW's Edit Mode (Escape > Edit Mode).

### Cooldown Alerts
```
/ta alert            - Show alert command help
/ta alert list       - Show tracked spells
/ta alert add <id>   - Track a spell by ID
/ta alert remove <id>- Stop tracking a spell
/ta alert defaults   - Load default spells for current tank spec
/ta alert clear      - Clear all tracked spells
```

### Debug
```
/ta debug on/off     - Toggle debug mode
/ta debug utility    - Toggle tank utility debug output
/ta debug stagger    - Show stagger diagnostic (Brewmaster)
/ta debug health     - Show health percent
/ta debug rage       - Show rage/resource info
/ta debug secondary  - Show secondary spell selection
/ta debug tracking   - Show tracked cooldowns (internal timers)
/ta debug combat     - Show combat state
/ta debug settings   - Show saved settings
```

## API Restrictions in 12.0

This addon is designed to work within Blizzard's "Secret Values" system.

### What's Accessible
- **Secondary Resources**: Stagger, Holy Power, Soul Fragments, Chi, Combo Points, Runes
- **Your Own Cooldowns**: Accessible through the Cooldown Manager API
- **Your Own Spell Casts**: Cast bar info is accessible
- **Specific Spells**: Maelstrom Weapon, DH Devourer spells, Combat Res, GCD

### What's Restricted (Secret Values)
- **Enemy State**: Health, casts, debuffs (especially in M+)
- **Primary Resources**: Health, Mana, Rage, Energy — can display but not use in logic
- **Complex Logic**: Can't do conditional logic on restricted values in tainted code

### How TankAssist Handles This
- **Shadow Tracking**: Monitors `UNIT_SPELLCAST_SUCCEEDED` events and calculates remaining cooldowns from known durations, avoiding secret value APIs entirely
- **Secret Value Detection**: `SecretValues.lua` wraps API calls with `IsSecret()` checks and graceful fallbacks
- **Assisted Combat**: Hooks into `C_Spell.GetAssistedHighlight()` which Blizzard provides for addon use

## Extending the Addon

### Adding a New Spec

1. Create a new file in `specs/<Class>/`
2. Inherit from `TankAssist.SpecBase`
3. Define `buffsToTrack`, `cooldownsToTrack`, and `rotationPriority`
4. Register with `spec:Register()`

```lua
local MySpec = TankAssist.SpecBase:New(SPEC_ID, "Spec Name")

MySpec.buffsToTrack = {
    {
        spellId = 12345,
        name = "Important Buff",
        refreshThreshold = 3,
        priority = "CRITICAL",
    },
}

MySpec:Register()
```

### Updating Rotation Data

The `data/RotationData.lua` file contains APL-style rotation definitions that can be updated independently of the core addon code.

## Troubleshooting

### Addon not showing
1. Check you're in a tank spec
2. Use WoW's Edit Mode to check if frames are off-screen
3. Run `/ta test` for diagnostics

### Cooldown Alerts not appearing
1. Run `/ta alert list` to check if spells are tracked
2. Run `/ta alert defaults` to load spells for your current spec
3. Ensure the alert style is set to show what you expect (Edit Mode settings)

### Limited functionality in M+
This is expected due to API restrictions. The addon will show what's available.

### Recommendations seem wrong
1. Check if Blizzard's Assisted Combat is enabled in Interface Options
2. The addon prioritises Blizzard's recommendation over its own

## Credits

- SimulationCraft for rotation reference
- Wowhead/Icy Veins for tanking guides
- WoWUIDev Discord for API documentation
- LibEQOL for Edit Mode integration

## License

MIT License - Feel free to modify and distribute.
