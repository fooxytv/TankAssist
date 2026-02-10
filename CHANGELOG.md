# Changelog

All notable changes to TankAssist will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.2-alpha.ed33179] - 2026-02-10

### Changed
- Bump version to 0.1.1-alpha.c88c94c

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
