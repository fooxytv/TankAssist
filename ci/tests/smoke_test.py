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

import re
import sys
from pathlib import Path

try:
    from lupa import LuaRuntime
except ImportError:
    print("smoke_test: lupa is not installed (pip install lupa) - skipping.")
    sys.exit(0)

ROOT = Path(__file__).resolve().parents[2]
STUB = Path(__file__).with_name("wow_stub.lua")
BINDINGS_XML = ROOT / "Bindings.xml"

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
    "Addon", "SecretValues", "Utils", "Sounds", "Media", "Constants",
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

# Fonts and bar textures come from LibSharedMedia so that any font pack the
# player already has fills the dropdowns. Two things have to hold: a pack
# registered by another addon must appear, and the list must never come back
# empty -- an empty font dropdown is worse than an unverified one, and the
# validation that keeps a broken font out could otherwise reject everything.
MEDIA_SCRIPT = """
local ns = __ns
local R = {}

R.fontCount = #ns.Media:ListFonts()
R.barCount  = #ns.Media:ListStatusBars()

-- Headless has no LibSharedMedia, so this exercises the built-in fallback.
R.noLSM = not ns.Media:HasLibSharedMedia()

-- A name that was saved before any of this existed still has to resolve.
R.knownFont = ns.Media:FetchFont("Friz Quadrata")

-- And one that does not exist has to land on the Blizzard default rather than
-- returning nil into SetFont.
R.unknownFont = ns.Media:FetchFont("No Such Font At All")
R.nilFont = ns.Media:FetchFont(nil)

R.knownBar = ns.Media:FetchStatusBar("Solid")
R.unknownBar = ns.Media:FetchStatusBar("No Such Texture")

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



def check_bindings(lua):
    """Bindings.xml is loaded by the client straight out of the addon folder and
    is never listed in the .toc, so nothing else in CI would notice it going
    missing or its handler being renamed out from under it. It was absent from
    the repo entirely until 0.4.6, and the stray copy that existed on one
    machine bound a function that had never been written.
    """
    print("\nsmoke_test [key bindings]")

    if not BINDINGS_XML.exists():
        failures.append("[key bindings] Bindings.xml is missing from the addon root")
        print("  FAIL Bindings.xml is missing from the addon root")
        return

    text = BINDINGS_XML.read_text(encoding="utf-8")
    bindings = re.findall(r'<Binding\s+name="([^"]+)"[^>]*>(.*?)</Binding>', text, re.S)
    if not bindings:
        failures.append("[key bindings] Bindings.xml declares no bindings")
        print("  FAIL Bindings.xml declares no bindings")
        return

    script = ["local R = {}"]
    expectations = []
    for name, body in bindings:
        called = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*\(", body)
        if not called:
            failures.append(f"[key bindings] {name} calls nothing")
            print(f"  FAIL {name} calls nothing")
            continue
        fn = called.group(1)
        script.append(f'R["{fn}"] = type(_G["{fn}"]) == "function"')
        script.append(f'R["{name}"] = type(_G["BINDING_NAME_{name}"]) == "string"')
        expectations.append((f"{fn} is defined", fn))
        expectations.append((f"{name} has a label", name))
    script.append('R["header"] = type(_G["BINDING_HEADER_TANKASSIST"]) == "string"')
    script.append("return R")

    results = dict(lua.execute("\n".join(script)))
    for label, key in expectations:
        check(label, results.get(key), True)
    check("binding header has a label", results.get("header"), True)


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
    run_script(lua, "shared media", MEDIA_SCRIPT, [
        ("built-in fonts still offered", "fontCount", 7),
        ("built-in bar textures still offered", "barCount", 4),
        ("headless has no LibSharedMedia", "noLSM", True),
        ("saved font name resolves", "knownFont", "Fonts" + chr(92) + "FRIZQT__.TTF"),
        ("unknown font falls back", "unknownFont", "Fonts" + chr(92) + "FRIZQT__.TTF"),
        ("nil font falls back", "nilFont", "Fonts" + chr(92) + "FRIZQT__.TTF"),
        ("saved bar name resolves", "knownBar", "Interface" + chr(92) + "Buttons" + chr(92) + "WHITE8x8"),
        ("unknown bar falls back", "unknownBar", "Interface" + chr(92) + "TargetingFrame" + chr(92) + "UI-StatusBar"),
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
    check_bindings(lua)

print()
if failures:
    print(f"smoke_test: {len(failures)} failure(s)")
    sys.exit(1)
print("smoke_test: all checks passed")
