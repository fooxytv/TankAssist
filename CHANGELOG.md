# Changelog

All notable changes to TankAssist will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- The proc/activation-overlay glow feature was inert in 0.4.4-alpha: `TankAssist.toc` did not load `libs/LibCustomGlow-1.0` or `data/ProcRules.lua` (the load lines were lost in a merge), so the glow library never registered and no glow could appear. Both are now loaded. A smoke-test guard asserts the proc-rules table loads so this cannot silently regress.

## [0.4.4-alpha.2a7596f] - 2026-08-13

### Added
- Proc and activation-overlay glow on the Assisted Combat display: the recommended ability now glows when a relevant proc is active (e.g. Crimson Scourge, Revenge!, Grand Crusader, Gore/Galactic Guardian), with a new data-driven proc-rules table covering Blood DK, Protection Warrior, Protection Paladin, and Guardian Druid.
- Glow settings with an on/off toggle (off by default) and a selectable glow style — Action Button Glow, Pixel Glow, Autocast Shine, or Proc Glow — backed by the bundled LibCustomGlow-1.0 library.

### Changed
- Consolidated version stamping and changelog generation into shared `ci/scripts` used by the main, beta, and release publish workflows, so the `.toc` stamping loop and changelog format each live in a single place.

### Added
- Proc / activation-overlay glow on the Assisted Combat display. When enabled, the recommended and secondary icons glow with the Blizzard proc look while Blizzard is overlaying that spell (Revenge!, Grand Crusader, ...) or a curated tank proc rule for the active spec is active (Blood Crimson Scourge → Death and Decay, Prot Warrior Revenge! → Revenge, Prot Paladin Grand Crusader → Avenger's Shield, Guardian Gore/Galactic Guardian → Mangle). Opt-in per the Assisted Combat Edit Mode options, with a selectable glow style (Action Button / Pixel / Autocast Shine / Proc Glow), defaulting off. Read-and-highlight only — never queues or casts. Bundles LibCustomGlow-1.0 and drives the glow from it; proc rules read aura *presence*, which is not a Secret Value, so they keep working when stacks/duration are hidden. A spec with no matching rule glows nothing.

## [0.4.3-alpha.fddb0c8] - 2026-08-13

### Added
- Continuous integration that lints and smoke-tests every push, running the addon's load path through a minimal WoW client stub to catch load-order mistakes, nil child widgets, and untaken API branches before they surface in-game.
- Beta release channel that publishes to CurseForge as a pre-release when develop is merged into a release branch, alongside the existing alpha and stable paths.

### Changed
- Linting is now strict: undefined-global warnings fail the build, so any mistyped API name is caught in CI rather than in-game, and all warnings (including shadowed upvalues and unused loop variables) are surfaced.
- Stable releases are now gated behind a `release/*` branch merge, preventing an accidental develop-to-main merge from cutting a stable build.

### Fixed
- Action titles no longer include the run name, keeping them consistent with companion addons.

The previous release tag `v0.4.0-alpha.c36e001` points to the exact same commit as `8eccc46` (HEAD). There are no commits and no code diff between them, so there are no changes to report.

## [0.4.1-alpha.8eccc46] - 2026-08-03

_No user-facing changes; release cut from the same commit as the previous version._

## [0.4.0-alpha.c36e001] - 2026-08-03

### Added
- Gear Advisor (opt-in, disabled by default): evaluates gear against per-spec stat weights and best-in-slot lists, annotates item tooltips with an upgrade verdict, and glows loot that's an upgrade. Supports importing custom stat weights and BIS item lists via a paste-in text format (with stat/slot aliases, comments, and versioning), plus a configurable glow colour and optional tier-set consideration.
- `/ta gear` slash command to show Gear Advisor status and sample verdicts.
- Class colour option for cast bars — cast bars can now be tinted by the unit's class colour.

### Changed
- CI publish script now scopes the GitHub token credential helper to the local repo instead of global git config, so the token isn't leaked to other repositories on the build machine.

### Fixed
- Cast bars now cancel correctly when a cast is interrupted or stops.

## [0.3.0-alpha.6ae3945] - 2026-05-18

### Added
- Configurable sound alerts for cooldown-ready and external cooldown applied events, with per-spell sound overrides
- LibSharedMedia-3.0 integration providing a selectable sound library, including six built-in TankAssist sound presets (Ready Ding, Raid Siren, Alarm, Boss Whisper, Soft Click, Quest Done)
- Sound channel selection (Master, SFX, Music, Dialog, Ambience) for alert playback

### Changed
- Replaced hardcoded `.ogg` file paths for buff/cooldown sounds with named sounds resolved through LibSharedMedia
- GitHub release titles now use "TankAssist <version>" instead of "Release <version>"
- Release notes fall back to a filtered commit log when no AI-generated changelog is available

## [0.2.6-alpha.2790150] - 2026-03-06

### Fixed
- Removed accidentally committed claude-plugins-official submodule reference

## [0.2.5-alpha.4435388] - 2026-03-06

### Changed
- Version bump to 0.2.5-alpha.4435388

## [0.2.4-alpha.f5c4e27] - 2026-03-06

### Changed
- Updated CI/CD pipeline and release workflow

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
