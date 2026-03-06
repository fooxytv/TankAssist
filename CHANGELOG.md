# Changelog

All notable changes to TankAssist will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.3-alpha.d2b781c] - 2026-03-06

*No changes since previous release.*

## [0.2.2-alpha.8970754] - 2026-03-06

### Changed
- Updated publish script to publish GitHub release packages

### Fixed
- Fixed PR review comments across multiple UI and spec files
- Removed accidentally committed claude-plugins-official submodule reference



## [0.2.1-alpha.56bf278] - 2026-03-06

### Added
- **Player & Target Cast Bars** — fully customisable replacements for Blizzard cast bars
  - Configurable width, height, scale, colours (cast/channel/non-interruptible/background/border)
  - Text options: spell name, cast timer, font face/size, alignment, position (above/inside/below)
  - Spell icon display with left/right positioning
  - Bar texture selection (Solid, Blizzard, Smooth, Flat)
  - Target cast bar shows interrupted state with linger + fade-out
  - Option to hide Blizzard's default player cast bar
- **External Cooldown Tracking** — monitors healer/ally defensives on the player
  - Tracks Pain Suppression, Guardian Spirit, Ironbark, Life Cocoon, Blessing of Sacrifice/Protection/Spellwarding, Rallying Cry
  - Real-time duration display with cooldown sweep animation
  - Handles secret values gracefully (shows "?" when duration is hidden)
- **Cooldown Alerts** — tracks player spell cooldowns with countdown and ready flash
  - Per-spec defaults for all 6 tank specs via `/ta alert defaults`
  - Three alert styles: Ready Only, Countdown Only, Countdown + Ready
  - Shadow tracking via UNIT_SPELLCAST_SUCCEEDED to work around Assisted Combat secret values
- **Display Mode setting** for External Cooldowns and Cooldown Alerts (Icon Only, Icon + Name, Name Only)
- **Timer Position setting** for External Cooldowns and Cooldown Alerts (Inside Icon, Below Icon)
- **Border Color setting** (colour picker) for External Cooldowns and Cooldown Alerts
- Full Edit Mode integration via LibEQOL for all new UI components
- Slash commands for managing tracked cooldown alerts (`/ta alert list|add|remove|defaults|clear`)
- GitHub Actions workflow for packaging and CurseForge upload on tags

### Changed
- Refactored namespace from `TA` to `TankAssist` across all modules
- Reorganised spec modules into class subdirectories (e.g. `specs/Warrior/Protection.lua`)
- Cast bar width/height sliders now use step size of 1 for precise control
- Improved build pipeline: rsync staging, `.gitattributes` exclusion, robust zip packaging
- Stabilised cooldown tracker display order with deterministic sorting

### Fixed
- Stale variable references in ConfigPanel, TankActionsDisplay, and CooldownTracker init
- Cooldown sweep duration calculation in TankActionsDisplay
- Mousewheel keybind formatting order in Utils
- Unlock overlay initial visibility state in MainFrame
- Removed dead variable assignment in CooldownTracker



## [0.2.0-alpha.7f62013] - 2026-03-05

*No changes since previous release.*

## [0.1.5-alpha.1879071] - 2026-02-10

_No user-facing changes. Version bump and CI maintenance only._

## [0.1.4-alpha.b372c9a] - 2026-02-10

### Added
- Fix packaging script to include addon subfolder in zip file

### Changed
- Improved Bone Shield stack tracking for Blood DK using shadow stacks for more accurate readings
- Refactored combat display visibility into centralized `ShouldBeVisible`/`UpdateVisibility` logic
- Fixed packaging script to produce correctly structured zip files with addon subfolder
- Fixed deploy script to extract to the correct addon directory

## [0.1.3-alpha.7b67e00] - 2026-02-10

- Added enable/disable toggle in Edit Mode
- Added support for disabling out of combat, mounted and pet battles
- Added shadow stack tracking for Bone Shield
- Cleaned up naming conventions

## [0.1.2-alpha.ed33179] - 2026-02-10

### Changed
- Bump version to 0.1.2-alpha.ed33179

## [0.1.0] - 2025-02-10

### Added
- Initial release of TankAssist
- Assisted Combat integration for tank specializations
- Primary and secondary spell recommendations
- Support for all tank specs:
  - Blood Death Knight
  - Brewmaster Monk
  - Protection Warrior
  - Protection Paladin
  - Vengeance Demon Hunter
  - Guardian Druid
- Secret Values handling for WoW 12.0 combat restrictions
- Shadow tracking for cooldowns and charge-based spells
- Edit Mode integration via LibEQOL
- Configurable display options
- Keybind display on spell recommendations

### Technical
- PascalCase naming convention for constants
- Centralized spell data registration via `RegisterSpellData()`
- Safe pcall wrapping for secret value comparisons
