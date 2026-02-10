# Changelog

All notable changes to TankAssist will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

{"type":"result","subtype":"error_during_execution","duration_ms":0,"duration_api_ms":0,"is_error":true,"num_turns":0,"stop_reason":null,"session_id":"5c0c093f-4216-4caa-9af6-8d527a9caee4","total_cost_usd":0,"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[]},"modelUsage":{},"permission_denials":[],"uuid":"095cdb09-73db-48cf-b378-4d866d98c679","errors":["EROFS: read-only file system, open '/root/.claude/debug/5c0c093f-4216-4caa-9af6-8d527a9caee4.txt'","Error: EROFS: read-only file system, open '/root/.claude/todos/5c0c093f-4216-4caa-9af6-8d527a9caee4-agent-5c0c093f-4216-4caa-9af6-8d527a9caee4.json'
    at writeFileSync (node:fs:2380:20)
    at lU7 (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:1324:11809)
    at $K1 (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:1324:11141)
    at Object.SQA (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:7290:6519)
    at file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:7602:3137
    at process.processTicksAndRejections (node:internal/process/task_queues:95:5)","Error: EROFS: read-only file system, open '/root/.claude/debug/5c0c093f-4216-4caa-9af6-8d527a9caee4.txt'
    at Object.writeFileSync (node:fs:2380:20)
    at Module.appendFileSync (node:fs:2461:6)
    at file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:9:1166
    at tJ (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:8:49854)
    at Object.appendFileSync (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:9:984)
    at writeFn (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:9:5004)
    at $ (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:9:4376)
    at Object.write (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:9:4499)
    at h (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:11:31)
    at US (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:904:23328)","Error: EROFS: read-only file system, open '/root/.claude/debug/5c0c093f-4216-4caa-9af6-8d527a9caee4.txt'
    at Object.writeFileSync (node:fs:2380:20)
    at Module.appendFileSync (node:fs:2461:6)
    at file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:9:1166
    at tJ (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:8:49854)
    at Object.appendFileSync (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:9:984)
    at writeFn (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:9:5004)
    at $ (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:9:4376)
    at Object.write (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:9:4499)
    at h (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:11:31)
    at WIY (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:3103:16379)","Error: EROFS: read-only file system, open '/root/.claude/debug/5c0c093f-4216-4caa-9af6-8d527a9caee4.txt'
    at Object.writeFileSync (node:fs:2380:20)
    at Module.appendFileSync (node:fs:2461:6)
    at file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:9:1166
    at tJ (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:8:49854)
    at Object.appendFileSync (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:9:984)
    at writeFn (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:9:5004)
    at $ (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:9:4376)
    at Object.write (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:9:4499)
    at h (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:11:31)
    at Jn7 (file:///usr/lib/node_modules/@anthropic-ai/claude-code/cli.js:1545:1343)"]}

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
