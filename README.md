# TankAssist

A focused tank assistant addon for World of Warcraft 12.0 (Midnight). Designed around Blizzard's Assisted Combat / One-Button Rotation system, with a small set of supporting tools to cover the things a tank actually wants at a glance — cast bars, externals on the player, cooldown reminders, raid-ready consumable checks, and clean per-event audio cues.

The intent is to feel like a streamlined two-button rotation helper (in the spirit of Ovale / Hekili) without simulating rotations, while bringing the rest of the tanking UI into one minimal, native-feeling package.

## Features

### Assisted Combat Display
- Surfaces Blizzard's built-in rotation recommendation as a **Primary** ability button
- A **Secondary** ability button highlights situational offensive/defensive cooldowns using lightweight addon-side tracking
- Shows keybinds for the recommended abilities
- Works wherever the Assisted Combat system works — no custom rotation engine
- **Proc glow** (opt-in): the recommended/secondary icon glows with the Blizzard proc look when the ability is being overlayed by Blizzard (Revenge!, Grand Crusader, ...) or a curated tank proc is up (e.g. Guardian Gore/Galactic Guardian → Mangle, Blood Crimson Scourge → Death and Decay). Read-and-highlight only; selectable glow style (Action Button / Pixel / Autocast Shine / Proc Glow) in Edit Mode

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

### Consumable Check
- Checks for Food, Flask/Phial, Weapon Oil, and Augment Rune on instance entry (party / raid / scenario)
- Category-level detection (any food gives "Well Fed", any flask buff counts, etc.) so it survives patch-to-patch item changes
- Missing categories pulse with a yellow glow; detected categories show a green tick overlay
- One-click minimize collapses the panel to a small mini-icon with a missing-count badge — handy when you've decided not to consume in this run
- Auto-hides after everything is detected; re-expands on each new instance
- Per-spec recommendations surfaced in the tooltip (Brewmaster populated; other tanks easy to add)

### Sound Alerts
- Optional audio cue when a tracked cooldown becomes ready, or when an external is applied to the player
- Sounds are registered via LibSharedMedia-3.0, so any LSM-aware addon's sounds (BigWigs, DBM, etc.) are selectable
- Six bundled Blizzard SOUNDKIT entries shipped under TankAssist names (Ready Ding, Raid Siren, Alarm, Boss Whisper, Soft Click, Quest Done)
- Per-spell sound overrides — set a unique sound on individual tracked cooldowns, or fall back to a global default

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

The slash surface is intentionally small. Almost all user-facing settings live in the in-game config panel (`/ta`).

```
/ta              - Open the configuration panel
/ta toggle       - Enable / disable the addon
/ta test         - Run diagnostic tests
/ta help         - Print this command list
```

Reposition frames via WoW's **Edit Mode** (Escape > Edit Mode).

### Debug (diagnostics)
```
/ta debug on/off     - Toggle verbose debug logging
/ta debug utility    - Toggle tank utility debug output
/ta debug stagger    - Show stagger diagnostic (Brewmaster)
/ta debug health     - Show health percent
/ta debug rage       - Show rage / resource info
/ta debug secondary  - Show secondary spell selection
/ta debug tracking   - Show tracked cooldowns (internal timers)
/ta debug combat     - Show combat state
/ta debug settings   - Show saved settings
```

### Configuration panel
`/ta` opens the panel. Sidebar pages:
- **General** — enable, scale, show-out-of-combat, show-without-target, Assisted Combat display options
- **Cooldown Alerts** — per-spec tracked spell list (add / remove / load defaults / per-spell sound overrides)
- **External CDs** — list of monitored externals and their display
- **Consumables** — enable, scale, icon size, "also check outside instances", manual "Check Now" button
- **Sounds & Alerts** — global sound channel and per-event default sounds
- **Cast Bars** — player and target cast bar appearance and behaviour

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
1. Open `/ta` → **Cooldown Alerts** and confirm spells are listed for your current spec
2. If empty, click **Load Spec Defaults** to populate the list
3. Check the Alert Style setting (Ready Only / Countdown Only / Countdown + Ready) matches what you expect

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
