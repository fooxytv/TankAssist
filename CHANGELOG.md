# Changelog

All notable changes to TankAssist will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]



## [0.2.1-alpha.56bf278] - 2026-03-06

### Changed
- Bump version to 0.2.0-alpha.7f62013



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
