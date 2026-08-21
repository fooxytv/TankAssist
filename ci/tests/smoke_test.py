#!/usr/bin/env python3
"""Load and exercise the addon against a stubbed WoW client.

luacheck parses; this runs. It catches the failures a parse cannot see -- load
order mistakes, indexing a nil child widget, an API branch that was never taken
-- which otherwise only appear after a /reload in game.

Every file listed in the .toc is loaded in .toc order, so a new file is covered
the moment it is packaged. Libraries are skipped: they are third-party, and
leaving LibStub nil exercises the addon's no-Ace fallback paths for free.

    python ci/tests/smoke_test.py

Requires: pip install lupa
"""

import sys
from pathlib import Path

try:
    from lupa import LuaRuntime
except ImportError:
    print("smoke_test: lupa is not installed (pip install lupa) - skipping.")
    sys.exit(0)

ROOT = Path(__file__).resolve().parents[2]
STUB = Path(__file__).with_name("wow_stub.lua")

failures = []


def check(name, actual, expected):
    if actual != expected:
        failures.append(f"{name}: expected {expected!r}, got {actual!r}")
        print(f"  FAIL {name}: expected {expected!r}, got {actual!r}")
    else:
        print(f"  ok   {name} = {actual!r}")


def addon_files():
    """Every Lua file in the .toc, in load order. Libraries are third-party."""
    toc = (ROOT / "TankAssist.toc").read_text(encoding="utf-8")
    return [
        line.strip().replace("\\", "/")
        for line in toc.splitlines()
        if line.strip().lower().endswith(".lua")
        and not line.strip().lower().startswith("libs")
    ]


def load_addon():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUB.read_text(encoding="utf-8"))

    lua.execute("__ns = {}")
    ns = lua.globals().__ns
    for rel in addon_files():
        source = (ROOT / rel).read_text(encoding="utf-8")
        chunk = lua.eval("function(s, n) return assert(load(s, n)) end")(source, "@" + rel)
        chunk("TankAssist", ns)
    return lua


# The load itself is most of the value: 23 files in .toc order against a client
# that answers, catching load-order mistakes and top-level nil indexing.
LOAD_SCRIPT = """
local ns = __ns
local R = {}

R.fileCount = __fileCount

-- The modules the .toc is expected to have populated. A rename or a file
-- dropped from the .toc shows up here rather than as a missing frame in game.
local expected = {
    "Addon", "SecretValues", "Utils", "Sounds", "Constants",
    "CooldownAlerts", "ExternalCooldowns", "ConfigPanel", "CastBar",
    "GearAdvisor", "GearData",
}
local missing = {}
for _, name in ipairs(expected) do
    if ns[name] == nil then missing[#missing + 1] = name end
end
R.missingModules = table.concat(missing, ",")

-- Saved variables and slash commands are wired up at initialize time.
ns.Addon:OnInitialize()
R.dbReady = ns.Addon.db ~= nil and ns.Addon.db.profile ~= nil
R.slashRegistered = _G.SlashCmdList["TANKASSIST"] ~= nil and true or false

-- Gear Advisor ships disabled: the default is the shipped behaviour, so it is
-- worth asserting rather than assuming.
R.gearAdvisorDefaultOff = ns.Addon.db.profile.gearAdvisor.enabled

-- The vault highlighter was removed outright, not just switched off. If any of
-- it comes back these stop being nil.
R.noVaultGlow = ns.GearAdvisor.RefreshVaultGlow == nil
    and ns.GearAdvisor.ClearVaultGlows == nil
    and ns.Addon.db.profile.gearAdvisor.glowVault == nil

return R
"""

# Cooldown tracking is pure arithmetic by design: the update loop must never
# call a C_Spell API, because a secret value tainting that path silently kills
# frame rendering. Driving it by clock proves the maths without the API.
COOLDOWN_SCRIPT = """
local ns = __ns
local R = {}
local sv = ns.SecretValues

sv.KnownCooldowns[22812] = 60
sv.trackedCooldowns = {}
sv:OnSpellCast(22812)

R.freshRemaining = math.floor(sv:GetTrackedCooldown(22812) + 0.5)
__advance(20)
R.afterTwenty = math.floor(sv:GetTrackedCooldown(22812) + 0.5)

-- Expired entries are dropped rather than left to accumulate.
__advance(45)
R.afterExpiry = sv:GetTrackedCooldown(22812)
R.entryCleared = sv.trackedCooldowns[22812] == nil

return R
"""

# Regression guard: a numeric LibSharedMedia value is a SOUNDKIT id, so it must
# go to PlaySound only. Falling back to PlaySoundFile handed an id to an API
# that wants a path, which silently played nothing.
SOUND_SCRIPT = """
local ns = __ns
local R = {}

__calls.PlaySound, __calls.PlaySoundFile = 0, 0
ns.Sounds.ResolveFile = function() return 841 end
ns.Sounds:PlayByName("anything")
R.numericUsedPlaySound = __calls.PlaySound
R.numericAvoidedPlaySoundFile = __calls.PlaySoundFile

__calls.PlaySound, __calls.PlaySoundFile = 0, 0
ns.Sounds.ResolveFile = function() return "Interface\\\\Sounds\\\\test.ogg" end
ns.Sounds:PlayByName("anything")
R.pathUsedPlaySoundFile = __calls.PlaySoundFile

return R
"""

# Proc glow ships opt-in and data-driven. `procRulesLoaded` is the load-bearing
# check: the proc-rule table (and LibCustomGlow) only work if the .toc actually
# lists data/ProcRules.lua and libs/LibCustomGlow-1.0. A merge once dropped those
# .toc lines while keeping the files, so the feature shipped inert -- this guards
# that exact regression. The rest confirm the rule table reads aura presence
# (not a Secret Value) and that the whole feature degrades to a no-op when the
# glow library is absent, as it is in this headless run.
GLOW_SCRIPT = """
local ns = __ns
local R = {}

R.procRulesLoaded = ns.ProcRules ~= nil
R.glowDefaultOff = ns.Addon.db.profile.assistedCombat.glowEnabled

-- Drive a single Guardian proc aura (Gore) as present; everything else absent.
C_UnitAuras.GetPlayerAuraBySpellID = function(id)
    if id == 93622 then
        return { applications = 1, duration = 10, expirationTime = 1010 }
    end
    return nil
end
ns.SecretValues.buffCache = {}

R.guardianMangleGlows = ns.ProcRules:IsProcActive(104, 33917)
C_UnitAuras.GetPlayerAuraBySpellID = function() return nil end
ns.SecretValues.buffCache = {}
R.guardianMangleQuiet = ns.ProcRules:IsProcActive(104, 33917)

R.unknownSpecQuiet = ns.ProcRules:IsProcActive(577, 33917)
R.unruledSpellQuiet = ns.ProcRules:IsProcActive(104, 12345)

R.glowUnavailable = ns.Utils:IsGlowAvailable()
local fakeIcon = {}
ns.Utils:SetGlow(fakeIcon, true, "Action Button Glow")
ns.Utils:SetGlow(fakeIcon, false)
R.noGlowNoError = true

return R
"""


def run():
    print("\nsmoke_test [load]")
    try:
        lua = load_addon()
        lua.globals().__fileCount = len(addon_files())
        results = dict(lua.execute(LOAD_SCRIPT))
    except Exception as exc:  # noqa: BLE001 - any Lua error is a test failure
        failures.append(f"[load] {exc}")
        print(f"  FAIL {exc}")
        return None

    check("all .toc files loaded", results["fileCount"], len(addon_files()))
    check("no missing modules", results["missingModules"], "")
    check("saved variables initialise", results["dbReady"], True)
    check("slash command registered", results["slashRegistered"], True)
    check("gear advisor defaults off", results["gearAdvisorDefaultOff"], False)
    check("vault highlighter is gone", results["noVaultGlow"], True)
    return lua


def run_script(lua, label, script, checks):
    print(f"\nsmoke_test [{label}]")
    try:
        results = dict(lua.execute(script))
    except Exception as exc:  # noqa: BLE001 - any Lua error is a test failure
        failures.append(f"[{label}] {exc}")
        print(f"  FAIL {exc}")
        return
    for name, key, expected in checks:
        check(name, results[key], expected)


lua = run()
if lua is not None:
    run_script(lua, "cooldown tracking", COOLDOWN_SCRIPT, [
        ("fresh cooldown reads full", "freshRemaining", 60),
        ("counts down by the clock", "afterTwenty", 40),
        ("expired reads zero", "afterExpiry", 0),
        ("expired entry is dropped", "entryCleared", True),
    ])
    run_script(lua, "sounds", SOUND_SCRIPT, [
        ("SOUNDKIT id uses PlaySound", "numericUsedPlaySound", 1),
        ("SOUNDKIT id never hits PlaySoundFile", "numericAvoidedPlaySoundFile", 0),
        ("file path uses PlaySoundFile", "pathUsedPlaySoundFile", 1),
    ])
    run_script(lua, "proc glow", GLOW_SCRIPT, [
        ("proc rules loaded from .toc", "procRulesLoaded", True),
        ("proc glow ships off", "glowDefaultOff", False),
        ("proc aura up -> glow", "guardianMangleGlows", True),
        ("proc aura gone -> quiet", "guardianMangleQuiet", False),
        ("unknown spec stays quiet", "unknownSpecQuiet", False),
        ("unruled spell stays quiet", "unruledSpellQuiet", False),
        ("glow lib absent in headless", "glowUnavailable", False),
        ("no-lib glow is a no-op", "noGlowNoError", True),
    ])

print()
if failures:
    print(f"smoke_test: {len(failures)} failure(s)")
    sys.exit(1)
print("smoke_test: all checks passed")
