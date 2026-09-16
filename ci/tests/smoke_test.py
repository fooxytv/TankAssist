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
PACKAGE_SH = ROOT / "ci" / "scripts" / "package.sh"
INSTALLER = ROOT / "ci" / "scripts" / "Install-TankAssist.ps1"

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

-- Six of the seven built-ins, not seven: the stub declines Fonts\\\\2002.TTF the
-- way a locale that does not ship it would, and validation is supposed to drop
-- it rather than offer a face that blanks the text it is applied to.
R.fontCount = #ns.Media:ListFonts()
R.offersUsable = false
R.offersUnusable = false
for _, name in ipairs(ns.Media:ListFonts()) do
    if name == "Friz Quadrata" then R.offersUsable = true end
    if name == "2002" then R.offersUnusable = true end
end

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


# Font selection used to hand SetFont a path straight out of a hardcoded table.
# SetFont returns false rather than raising for a face the client lacks, so the
# font string was left with no font at all and the error surfaced later, on the
# next SetText. These assert the two ways that happens: a face that fails the
# up-front probe, and one that passes the probe but fails on apply anyway.
FONT_SCRIPT = """
local ns = __ns
local R = {}
local FRIZ = "Fonts\\\\FRIZQT__.TTF"

-- A face the client cannot load is not offered, and never resolves to itself.
local offered = {}
for _, name in ipairs(ns.Media:ListFonts()) do offered[name] = true end
R.missingFaceHidden = offered["2002"] == nil
R.friznOffered = offered["Friz Quadrata"] == true
R.missingFaceFallsBack = ns.Media:FetchFont("2002") == FRIZ
R.unknownNameFallsBack = ns.Media:FetchFont("No Such Font") == FRIZ
R.nilNameFallsBack = ns.Media:FetchFont(nil) == FRIZ

local fs = CreateFrame("Frame"):CreateFontString(nil, "OVERLAY")
R.appliedMissing = ns.Media:SetFont(fs, "2002", 12, "Outline") == FRIZ

-- Morpheus probed fine above; break it only now, so SetFont hits the branch
-- where the probe passed and the apply still fails.
R.probedGood = ns.Media:FetchFont("Morpheus") ~= FRIZ
__unloadableFonts["Fonts\\\\MORPHEUS.TTF"] = true
R.brokenOnApply = ns.Media:SetFont(fs, "Morpheus", 12, "Outline") == FRIZ
R.stillHasAFont = fs:GetFontPath() == FRIZ

-- A junk size must not reach SetFont as junk.
R.junkSize = ns.Media:SetFont(fs, "Friz Quadrata", "not a number", "Outline") == FRIZ

R.flagResolved = ns.Media:ResolveFontFlag("Thick Outline")
R.flagFallback = ns.Media:ResolveFontFlag("Nonsense")

return R
"""

# The crop takes the fraction trimmed off each edge, the same quantity action-bar
# skins expose as a percentage -- so 0.055 here has to mean exactly what Icon
# Zoom 5.5 means there, or "set both to the same number" stops being true. The
# aspect correction is the other half: a square trim on a non-square button
# stretches the art rather than cropping it.
CROP_SCRIPT = """
local ns = __ns
local R = {}

-- EllesmereUI's default, the number this is meant to line up with.
local l, r, t, b = ns.Utils:GetIconTexCoords(0.055, 50, 50)
R.skinDefaultLeft = l
R.skinDefaultRight = r

local deep = ns.Utils:GetIconTexCoords(0.2, 50, 50)
R.moreTrimCropsFurther = deep > l

-- A wide button crops vertically, so the visible region is wider than tall by
-- exactly the button's own ratio.
local wl, wr, wt, wb = ns.Utils:GetIconTexCoords(0.055, 100, 50)
R.wideKeepsWidth = wl == l
R.wideAspect = math.floor(((wr - wl) / (wb - wt)) * 100 + 0.5) / 100

local tl, tr, tt, tb = ns.Utils:GetIconTexCoords(0.055, 50, 100)
R.tallAspect = math.floor(((tr - tl) / (tb - tt)) * 100 + 0.5) / 100

-- No trim at all is a legitimate setting (Icon Zoom 0) and must be the whole
-- texture, not silently floored to some minimum.
R.zeroIsUncropped = ns.Utils:GetIconTexCoords(0, 50, 50)

-- Out of range and junk clamp instead of inverting the texcoords.
R.clampsHigh = ns.Utils:GetIconTexCoords(5, 50, 50)
R.clampsLow = ns.Utils:GetIconTexCoords(-3, 50, 50)
-- Junk is not zero: it means "unspecified", which falls back to the stock trim.
R.junkTrim = ns.Utils:GetIconTexCoords("x", 50, 50)

-- No size given: fall back to a square crop rather than dividing by zero.
R.noSizeSquare = ns.Utils:GetIconTexCoords(0.055) == l

return R
"""

# Keybinds on the buttons come from walking the action bars and asking what each
# slot holds. Macros are where that goes wrong, and it went wrong twice:
#
#  * GetActionInfo's second return is NOT a macro index. For a "smart"
#    single-spell macro it is the spellID; for any other macro it is an opaque
#    id. The old code passed it straight to GetMacroSpell, which then looked up
#    whichever unrelated macro happened to sit at that index -- so a keybind
#    behind a macro simply never appeared.
#  * GetMacroSpell answers only for the branch that would fire right now, so a
#    "/cast [mod:shift] A; B" macro hides B until shift is held.
KEYBIND_SCRIPT = """
local ns = __ns
local R = {}

local BARKSKIN, INSTINCTS = 22812, 61336
local SKULL_BASH, IRONFUR = 106839, 192081

-- ACTIONBUTTON1..12 are slots 1..12; MULTIACTIONBAR1BUTTON1.. are slots 61..
__bindings["ACTIONBUTTON1"] = "Q"
__bindings["ACTIONBUTTON2"] = "SHIFT-E"
__bindings["ACTIONBUTTON3"] = "R"
__bindings["ACTIONBUTTON4"] = "F"

-- Slot 1: a plain spell, the case that always worked.
__actionSlots[1] = { actionType = "spell", id = BARKSKIN }

-- Slot 2: a "smart" single-spell macro. subType is "spell" and id is the
-- spellID itself -- not an index into __macros.
__actionSlots[2] = { actionType = "macro", id = INSTINCTS, subType = "spell",
                     macroName = "SI" }

-- Slot 3: a conditional macro. GetMacroSpell reports only the branch that
-- would fire now (Ironfur); Skull Bash is the other branch and is what we ask
-- for, so only a body scan finds it.
__actionSlots[3] = { actionType = "macro", id = 999, macroName = "Utility" }
__macros[7] = {
    name = "Utility",
    liveSpell = IRONFUR,
    body = "#showtooltip\\n/cast [mod:shift] Skull Bash; Ironfur",
}

-- Slot 4: a macro whose opaque id collides with a real, unrelated macro index.
-- This is the old bug's mirror: resolving by id would report Barkskin's key
-- here and hand out a wrong binding rather than none.
__actionSlots[4] = { actionType = "macro", id = 7, macroName = "Unrelated" }
__macros[11] = { name = "Unrelated", liveSpell = nil,
                 body = "/use Healthstone" }

local function keyFor(spellId)
    ns.Utils:ClearKeybindCache()
    return ns.Utils:GetSpellKeybind(spellId)
end

R.plainSpell = keyFor(BARKSKIN)
R.smartMacro = keyFor(INSTINCTS)
R.conditionalBranch = keyFor(SKULL_BASH)
R.liveMacroSpell = keyFor(IRONFUR)

-- The collision slot must contribute nothing: its macro casts an item, and
-- nothing in it should claim a spell binding.
__actionSlots[1] = nil
__actionSlots[2] = nil
__actionSlots[3] = nil
R.noFalseMatch = keyFor(BARKSKIN) == nil

return R
"""


# The external cooldown icons take the same crop/shape/border/font settings as
# the Assisted Combat buttons, out of the same IconStyle module. The point of
# sharing it is that the two agree, so this asserts against the same numbers --
# and against the one place they deliberately differ, the border default.
EXTERNALS_SCRIPT = """
local ns = __ns
local R = {}
local FRIZ = "Fonts\\\\FRIZQT__.TTF"
local ec = ns.ExternalCooldowns

local profile = ns.Addon.db.profile.externalCooldowns
R.shipsAtSkinDefault = profile.iconZoomPercent

-- The border is signal here, not chrome: it says an external is on you. It is
-- the one setting that ships differently from the Assisted Combat buttons.
R.shipsWithBorder = ec:ShowBorder()
R.buttonsShipWithout = ns.AssistedCombatDisplay:GetAppearanceSettings().showBorder

ec:Create()
local icon = ec:GetIcon(1)
R.built = icon ~= nil and icon.icon ~= nil

-- Art fills the icon frame rather than sitting inset inside the background.
R.artFillsIcon = icon.icon.texture:IsFillingParent()
R.shippedTrim = icon.icon.texture:GetTexCoord()[1]
R.borderShown = icon.icon.border.top:IsShown()

-- Same shape maths as the buttons: 36 wide stays 36, height goes to 80%.
profile.iconShape = "Cropped"
profile.iconZoomPercent = 20
profile.showBorder = false
ec:ApplyIconAppearance()

local w, h = ec:GetIconDimensions()
R.croppedWidth = w
R.croppedHeight = h
local c = icon.icon.texture:GetTexCoord()
R.croppedTrim = c[1]
R.croppedArtAspect = math.floor(((c[2] - c[1]) / (c[4] - c[3])) * 1000 + 0.5) / 1000
R.croppedButtonAspect = math.floor((w / h) * 1000 + 0.5) / 1000
R.borderHides = icon.icon.border.top:IsShown() ~= true

-- An unloadable face falls back rather than blanking the timer text.
profile.fontFace = "2002"
profile.fontSizeOffset = 2
ec:ApplyIconAppearance()
R.fontFellBack = icon.timerInside:GetFontPath() == FRIZ
R.timerSize = icon.timerInside.__fontSize
R.nameSize = icon.spellName.__fontSize

-- Back to shipped.
profile.iconShape = "Square"
profile.iconZoomPercent = 5.5
profile.showBorder = true
profile.fontFace = "Friz Quadrata"
profile.fontSizeOffset = 0
ec:ApplyIconAppearance()
R.squareAgain = select(2, ec:GetIconDimensions())

return R
"""


# The buttons themselves: one path (ApplyIconAppearance) now owns crop and font
# for both icons, and it is the path every setting change goes through, so drive
# it against a real display rather than trusting the helpers in isolation.
BUTTON_SCRIPT = """
local ns = __ns
local R = {}
local FRIZ = "Fonts\\\\FRIZQT__.TTF"
local acd = ns.AssistedCombatDisplay

acd:Create()
R.created = acd.frame ~= nil and acd.mainIcon ~= nil and acd.aoeIcon ~= nil

local profile = ns.Addon.db.profile.assistedCombat
R.shipsAtSkinDefault = profile.iconZoomPercent
R.shipsBorderless = profile.showBorder
R.shipsStockFont = profile.fontFace

-- The art fills the button. This is the one that made these read as "not an
-- action bar": a 2px inset let the background show as a frame around every icon.
R.iconFillsButton = acd.mainIcon.icon:IsFillingParent()
R.borderHidden = acd.mainIcon.border.top:IsShown() ~= true

-- The shipped crop has to be the skin's number, not near it.
R.shippedTrim = acd.mainIcon.icon:GetTexCoord()[1]

-- A deeper crop, an unloadable font face and a text-size bump, all at once.
profile.iconZoomPercent = 20
profile.showBorder = true
profile.fontFace = "2002"
profile.fontSizeOffset = 3
acd:SetIconSize(60)

local main = acd.mainIcon.icon:GetTexCoord()
local aoe = acd.aoeIcon.icon:GetTexCoord()
R.mainCropped = main ~= nil and main[1] == 0.2
R.bothIconsMatch = aoe ~= nil and aoe[1] == main[1]
R.stillSquare = main ~= nil and main[1] == main[3]
R.borderTurnsOn = acd.mainIcon.border.top:IsShown() == true

R.keybindFellBack = acd.mainIcon.keybind:GetFontPath() == FRIZ
R.keybindSize = acd.mainIcon.keybind.__fontSize
R.countSize = acd.mainIcon.count.__fontSize

-- Cropped: the squat action-bar button. Full width, 80% height, and the art
-- cropped to suit rather than squashed into it -- the visible region has to end
-- up at the button's own aspect, or every icon is subtly stretched.
profile.iconZoomPercent = 5.5
profile.showBorder = false
profile.iconShape = "Cropped"
acd:SetIconSize(50)
R.croppedWidth = acd.mainIcon.__width
R.croppedHeight = acd.mainIcon.__height
local c = acd.mainIcon.icon:GetTexCoord()
R.croppedArtAspect = math.floor(((c[2] - c[1]) / (c[4] - c[3])) * 1000 + 0.5) / 1000
R.croppedButtonAspect = math.floor((acd.mainIcon.__width / acd.mainIcon.__height) * 1000 + 0.5) / 1000
-- Width is untouched by the shape; only the vertical crop deepens.
R.croppedKeepsWidthTrim = c[1] == 0.055
R.croppedTrimsMoreVertically = c[3] > c[1]
-- The frame follows the shorter button rather than leaving a gap.
R.frameHeight = acd.frame.__height

-- Back to the shipped look.
profile.iconShape = "Square"
profile.fontFace = "Friz Quadrata"
profile.fontSizeOffset = 0
acd:SetIconSize(50)
R.squareAgain = acd.mainIcon.__height
R.backToDefault = acd.mainIcon.icon:GetTexCoord()[1]
R.defaultKeybindSize = acd.mainIcon.keybind.__fontSize

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


def check_packaging():
    """The installer copies a branch into AddOns; package.sh builds the zip that
    ships. Both work by excluding the same development files, in two languages
    that cannot share a list. Let them drift and you get the worst kind of
    report -- works from the repo, broken from CurseForge, or the reverse.
    """
    print("\nsmoke_test [packaging]")

    # The path is load-bearing, not incidental: it is what the documented
    # one-liner fetches, so moving the file breaks every copy of that command
    # already pasted into a notes file.
    if not INSTALLER.exists():
        where = INSTALLER.relative_to(ROOT).as_posix()
        failures.append(f"[packaging] the installer is not at {where}")
        print(f"  FAIL the installer is not at {where}")
        return

    sh = PACKAGE_SH.read_text(encoding="utf-8")
    # rsync's --exclude='.env*' is a glob; the installer matches literal names,
    # so it spells out the files that glob covers instead.
    shipped = {e.rstrip("*") for e in re.findall(r"--exclude='([^']+)'", sh)}

    ps = INSTALLER.read_text(encoding="utf-8")
    block = re.search(r"\$ExcludeFromInstall = @\((.*?)\)", ps, re.S)
    if not block:
        failures.append("[packaging] the installer has no $ExcludeFromInstall list")
        print("  FAIL the installer has no $ExcludeFromInstall list")
        return
    installed = {e.rstrip("*") for e in re.findall(r"'([^']+)'", block.group(1))}

    missing = sorted(n for n in shipped if not any(i == n or i.startswith(n) for i in installed))
    extra = sorted(n for n in installed if not any(n == s or n.startswith(s) for s in shipped))

    check("installer excludes everything the zip does", ", ".join(missing), "")
    check("installer excludes nothing extra", ", ".join(extra), "")

    # The installer lives under ci/, which package.sh excludes wholesale, so it
    # cannot reach a player by name or by accident.
    check("the installer is kept out of the shipped zip",
          INSTALLER.relative_to(ROOT).parts[0] in shipped, True)


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
        # .get, not [key]: a nil in Lua leaves the key out of the table
        # entirely, and returning nil is exactly what a broken lookup does. That
        # deserves a FAIL naming the check, not a KeyError traceback that buries
        # which assertion died.
        check(name, results.get(key), expected)


lua = run()
if lua is not None:
    run_script(lua, "cooldown tracking", COOLDOWN_SCRIPT, [
        ("fresh cooldown reads full", "freshRemaining", 60),
        ("counts down by the clock", "afterTwenty", 40),
        ("expired reads zero", "afterExpiry", 0),
        ("expired entry is dropped", "entryCleared", True),
    ])
    run_script(lua, "shared media", MEDIA_SCRIPT, [
        ("built-in fonts still offered", "fontCount", 6),
        ("a usable built-in is offered", "offersUsable", True),
        ("an unusable built-in is filtered out", "offersUnusable", False),
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
    run_script(lua, "fonts", FONT_SCRIPT, [
        ("unloadable face is not offered", "missingFaceHidden", True),
        ("stock face is offered", "friznOffered", True),
        ("unloadable face resolves to stock", "missingFaceFallsBack", True),
        ("unknown name resolves to stock", "unknownNameFallsBack", True),
        ("nil name resolves to stock", "nilNameFallsBack", True),
        ("applying an unloadable face falls back", "appliedMissing", True),
        ("a good face is not forced to stock", "probedGood", True),
        ("failure after a good probe falls back", "brokenOnApply", True),
        ("font string is never left fontless", "stillHasAFont", True),
        ("a junk size still applies a font", "junkSize", True),
        ("flag name resolves", "flagResolved", "THICKOUTLINE"),
        ("unknown flag falls back", "flagFallback", "OUTLINE"),
    ])
    run_script(lua, "icon crop", CROP_SCRIPT, [
        ("5.5% trims exactly 0.055 a side", "skinDefaultLeft", 0.055),
        ("5.5% trims exactly 0.055 a side", "skinDefaultRight", 0.945),
        ("a bigger trim crops further in", "moreTrimCropsFurther", True),
        ("wide button keeps its width", "wideKeepsWidth", True),
        ("wide button crops to 2:1", "wideAspect", 2.0),
        ("tall button crops to 1:2", "tallAspect", 0.5),
        ("zero trim is the whole texture", "zeroIsUncropped", 0.0),
        ("trim clamps at the top", "clampsHigh", 0.45),
        ("trim clamps at zero", "clampsLow", 0.0),
        ("junk falls back to the stock trim", "junkTrim", 0.08),
        ("no size given stays square", "noSizeSquare", True),
    ])
    run_script(lua, "keybinds", KEYBIND_SCRIPT, [
        ("a plain spell slot resolves", "plainSpell", "Q"),
        ("a smart single-spell macro resolves", "smartMacro", "SHIFT-E"),
        ("a conditional branch is found in the body", "conditionalBranch", "R"),
        ("the live macro spell resolves", "liveMacroSpell", "R"),
        ("an id collision does not invent a binding", "noFalseMatch", True),
    ])
    run_script(lua, "external cooldowns", EXTERNALS_SCRIPT, [
        ("ships at the same 5.5% crop", "shipsAtSkinDefault", 5.5),
        ("border ships on, unlike the buttons", "shipsWithBorder", True),
        ("the buttons still ship without one", "buttonsShipWithout", False),
        ("the display builds an icon", "built", True),
        ("the art fills the icon", "artFillsIcon", True),
        ("the shipped crop matches the buttons", "shippedTrim", 0.055),
        ("the border is drawn by default", "borderShown", True),
        ("cropped keeps the full width", "croppedWidth", 36),
        ("cropped takes 80% of the height", "croppedHeight", 29),
        ("the crop setting reaches the art", "croppedTrim", 0.2),
        ("cropped art is not stretched", "croppedArtAspect", 1.241),
        ("cropped art matches the icon aspect", "croppedButtonAspect", 1.241),
        ("the border can be turned off", "borderHides", True),
        ("an unloadable face falls back", "fontFellBack", True),
        ("the size offset reaches the timer", "timerSize", 18),
        ("the size offset reaches the name", "nameSize", 12),
        ("square restores the full height", "squareAgain", 36),
    ])
    run_script(lua, "button appearance", BUTTON_SCRIPT, [
        ("display builds both buttons", "created", True),
        ("ships at the skin's 5.5% crop", "shipsAtSkinDefault", 5.5),
        ("ships with no border", "shipsBorderless", False),
        ("font ships as the stock face", "shipsStockFont", "Friz Quadrata"),
        ("the art fills the button", "iconFillsButton", True),
        ("the border is hidden by default", "borderHidden", True),
        ("the shipped crop is the skin's number", "shippedTrim", 0.055),
        ("crop reaches the primary button", "mainCropped", True),
        ("both buttons crop alike", "bothIconsMatch", True),
        ("a square button crops square", "stillSquare", True),
        ("the border can be turned on", "borderTurnsOn", True),
        ("an unloadable face falls back on the button", "keybindFellBack", True),
        ("text size offset applies", "keybindSize", 15),
        ("count text scales with the icon", "countSize", 17),
        ("cropped keeps the full width", "croppedWidth", 50),
        ("cropped takes 80% of the height", "croppedHeight", 40),
        ("cropped art is not stretched", "croppedArtAspect", 1.25),
        ("cropped art matches the button aspect", "croppedButtonAspect", 1.25),
        ("cropped leaves the side trim alone", "croppedKeepsWidthTrim", True),
        ("cropped trims more off top and bottom", "croppedTrimsMoreVertically", True),
        ("the frame follows the shorter button", "frameHeight", 42),
        ("square restores the full height", "squareAgain", 50),
        ("restoring the default restores the crop", "backToDefault", 0.055),
        ("clearing the offset restores the size", "defaultKeybindSize", 11),
    ])
    check_bindings(lua)

check_packaging()

print()
if failures:
    print(f"smoke_test: {len(failures)} failure(s)")
    sys.exit(1)
print("smoke_test: all checks passed")
