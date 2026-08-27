-- Aura display -- the sanctioned way to show an aura the addon is not allowed
-- to read. See https://github.com/fooxytv/TankAssist/issues/38 for context on
-- the secret-values regime generally.
--
-- Since 12.0 some aura data comes back *secret*: it can be passed onwards and
-- rendered, but not read, compared or branched on.
--
-- The exact rule matters, and it is easy to get wrong. From Blizzard's own
-- SecretPredicatesDocumentation.lua, `SecretWhenUnitAuraRestricted` reads:
--
--     "Guarded APIs and events produce secret values when combat, encounter,
--      challenge mode, or PvP match addon restrictions are in effect.
--      Individual spells may be flagged as never or always secret, which takes
--      priority over restrictions."
--
-- Two consequences, both load-bearing:
--
--   * The axis is *combat*, not Mythic+. A target dummy is enough to trigger it.
--   * Per-spell flags override the blanket rule. A spell Blizzard has marked
--     never-secret stays readable in a key, and there is no API to ask which --
--     it is data on the spell, not something the UI source exposes. So whether
--     Ironfur specifically is readable can only be answered by the client.
--
-- That is what `/ta aura` is for. Everything here is written to work either
-- way: if the count is readable it is used directly, and if it is not, the
-- display path below still puts the true number on screen.
--
-- What is still allowed is display and alerting, and 12.1 added more of it:
--
--   * C_UnitAuras.GetAuraApplicationDisplayCount formats the stack count as a
--     *string* for showing. The addon never sees the number.
--   * C_UnitAuras.AddAuraSound (new in 12.1) has the client play a sound when an
--     aura is applied, gains a stack, or falls off -- without the addon reading
--     the aura at all. That is a real "Ironfur just dropped" alert.
--
-- The distinction this module exists to hold: showing a player their own stack
-- count is always allowed and always accurate, whether or not the addon may
-- read it. Deciding from it is only sound when the value is genuinely readable.
-- A caller that cannot tell the difference has to say so rather than quietly
-- substituting a zero, which is what the addon did before and why it
-- recommended Ironfur on every pull regardless of stacks.

local ADDON_NAME, TankAssist = ...

TankAssist.AuraDisplay = {}
local auraDisplay = TankAssist.AuraDisplay

-- spellID -> auraInstanceID for the player, kept current off UNIT_AURA.
auraDisplay.instances = {}
auraDisplay.sounds = {}

----------------------------------------------------------------------------
-- Capability
----------------------------------------------------------------------------

local function has(fn)
    return C_UnitAuras and type(C_UnitAuras[fn]) == "function"
end

function auraDisplay:CanShowCount()
    return has("GetAuraApplicationDisplayCount")
end

function auraDisplay:CanPlaySounds()
    return has("AddAuraSound") and Enum and Enum.UnitAuraSoundTrigger ~= nil
end

----------------------------------------------------------------------------
-- Aura instance tracking
--
-- GetAuraApplicationDisplayCount is keyed on an auraInstanceID rather than a
-- spell, so one has to be found first. UNIT_AURA carries them in its payload,
-- which is cheaper than asking every time and is the only path that stays
-- correct when the same spell is on the unit more than once.
----------------------------------------------------------------------------

-- A secret value must never be compared, only passed on. `canaccessvalue`
-- answers whether this one may be looked at; without it, treat it as readable,
-- which is correct on any client old enough not to have the restriction.
local function readable(value)
    if value == nil then return false end
    if canaccessvalue then return canaccessvalue(value) end
    return true
end

function auraDisplay:NoteAura(auraData)
    if type(auraData) ~= "table" then return end
    if canaccesstable and not canaccesstable(auraData) then return end

    local spellID = auraData.spellId
    local instanceID = auraData.auraInstanceID
    -- The spell is what this is keyed on, so it has to be readable. The
    -- instance ID does not: it is only ever handed back to the client.
    if instanceID == nil or not readable(spellID) then return end

    self.instances[spellID] = instanceID
end

function auraDisplay:ForgetInstance(instanceID)
    for spellID, known in pairs(self.instances) do
        if known == instanceID then
            self.instances[spellID] = nil
            return
        end
    end
end

function auraDisplay:InstanceFor(spellID)
    local known = self.instances[spellID]
    if known then return known end

    -- Nothing cached: ask directly. Under restriction the whole aura table may
    -- be unreadable, in which case there is nothing to be had here either.
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and type(auraData) == "table" then
            self:NoteAura(auraData)
            return self.instances[spellID]
        end
    end

    return nil
end

----------------------------------------------------------------------------
-- Display
----------------------------------------------------------------------------

-- The count as the client formats it. May be a secret string: fine to hand to a
-- FontString, never fine to compare or concatenate.
--
-- minDisplay follows Blizzard's own default of 2, so a single application shows
-- nothing -- one stack of Ironfur is the same as "Ironfur is up", and the icon
-- already says that.
function auraDisplay:GetCountText(spellID, minDisplay, maxDisplay)
    if not self:CanShowCount() then return nil end

    local instanceID = self:InstanceFor(spellID)
    if not instanceID then return nil end

    local ok, text = pcall(C_UnitAuras.GetAuraApplicationDisplayCount,
        "player", instanceID, minDisplay or 2, maxDisplay)
    if not ok then return nil end
    return text
end

-- Put the real count on a FontString. Separate from GetCountText because the
-- caller must not be tempted to look at the value on the way past -- the whole
-- point is that it goes from the client to the screen without being read.
--
-- Returns true when the client answered, so a caller can fall back to its own
-- estimate rather than showing an empty box and calling it zero.
function auraDisplay:SetCountOn(fontString, spellID, minDisplay, maxDisplay)
    if not fontString then return false end

    local text = self:GetCountText(spellID, minDisplay, maxDisplay)
    if text == nil then return false end

    local ok = pcall(fontString.SetText, fontString, text)
    return ok
end

----------------------------------------------------------------------------
-- Sounds
--
-- The client owns the trigger, so this keeps working in restricted content
-- where reading the aura to notice the same thing would not.
----------------------------------------------------------------------------

local TRIGGER_NAMES = { "Added", "ApplicationsIncreased", "Removed" }

function auraDisplay:AddSound(triggerName, spellID, soundFile, channel)
    if not self:CanPlaySounds() then return nil end

    local trigger = Enum.UnitAuraSoundTrigger[triggerName]
    if trigger == nil then return nil end
    if not soundFile then return nil end

    local info = {
        unitToken = "player",
        spellID = spellID,
        outputChannel = channel or "Master",
    }
    -- The client takes either a path or a file ID, and picks by which field is
    -- set rather than by inspecting the value.
    if type(soundFile) == "number" then
        info.soundFileID = soundFile
    else
        info.soundFileName = soundFile
    end

    local ok, soundID = pcall(C_UnitAuras.AddAuraSound, trigger, info)
    if not ok or soundID == nil then return nil end

    self.sounds[#self.sounds + 1] = soundID
    return soundID
end

function auraDisplay:RemoveAllSounds()
    if not (C_UnitAuras and C_UnitAuras.RemoveAuraSound) then
        self.sounds = {}
        return
    end
    for _, soundID in ipairs(self.sounds) do
        pcall(C_UnitAuras.RemoveAuraSound, soundID)
    end
    self.sounds = {}
end

----------------------------------------------------------------------------
-- Probe
--
-- Which of the above actually answers cannot be settled by reading Blizzard's
-- source -- it depends on taint and on whether the player is in restricted
-- content right now. So report it from the client instead of guessing, the same
-- way `/ta bosscard scan` settles the Journal question.
----------------------------------------------------------------------------

function auraDisplay:Probe(spellID)
    local report = {
        spellID = spellID,
        canShowCount = self:CanShowCount(),
        canPlaySounds = self:CanPlaySounds(),
        -- The restriction keys off combat, so a probe run standing still in a
        -- city proves nothing. Report it rather than let it be assumed.
        inCombat = (UnitAffectingCombat and UnitAffectingCombat("player")) or false,
        restrictedApi = (C_CombatLog and C_CombatLog.IsCombatLogRestricted
            and select(2, pcall(C_CombatLog.IsCombatLogRestricted))) or "unknown",
    }

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        report.auraFound = ok and type(auraData) == "table"
        if report.auraFound then
            report.tableReadable = (not canaccesstable) or canaccesstable(auraData)
            if report.tableReadable then
                report.spellIdReadable = readable(auraData.spellId)
                report.applicationsSecret = issecretvalue
                    and issecretvalue(auraData.applications) or false
                report.applicationsReadable = readable(auraData.applications)
                report.instanceID = auraData.auraInstanceID ~= nil
            end
        end
    else
        report.auraFound = false
    end

    report.resolvedInstance = self:InstanceFor(spellID) ~= nil

    local text = self:GetCountText(spellID, 1)
    report.countReturned = text ~= nil
    report.countSecret = (text ~= nil and issecretvalue and issecretvalue(text)) or false
    -- Only shown when the client says it is safe to look at. Under restriction
    -- the string renders correctly on a FontString while still being unreadable
    -- here, and that is the expected outcome rather than a failure.
    report.countText = (text ~= nil and readable(text)) and tostring(text) or nil

    return report
end

----------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------

local watcher = CreateFrame("Frame")
watcher:RegisterUnitEvent("UNIT_AURA", "player")
watcher:SetScript("OnEvent", function(_, _, _, updateInfo)
    if type(updateInfo) ~= "table" then
        wipe(auraDisplay.instances)
        return
    end

    if updateInfo.isFullUpdate then
        wipe(auraDisplay.instances)
        return
    end

    if updateInfo.addedAuras then
        for _, auraData in ipairs(updateInfo.addedAuras) do
            auraDisplay:NoteAura(auraData)
        end
    end

    if updateInfo.removedAuraInstanceIDs then
        for _, instanceID in ipairs(updateInfo.removedAuraInstanceIDs) do
            auraDisplay:ForgetInstance(instanceID)
        end
    end
end)

auraDisplay.TRIGGER_NAMES = TRIGGER_NAMES

----------------------------------------------------------------------------
-- Report
--
--   /ta aura              probe Ironfur
--   /ta aura 12345        probe another spell
--   /ta aura sound        register applied / stack / dropped sounds on Ironfur
--   /ta aura off          remove them again
----------------------------------------------------------------------------

local IRONFUR = 192081

-- Deliberately Blizzard's own sound kit rather than a media file: a spike
-- should not need the player to have configured anything to hear whether the
-- client is firing the trigger at all.
local PROBE_SOUNDS = {
    Added                 = 567478,
    ApplicationsIncreased = 567478,
    Removed               = 567399,
}

function auraDisplay:Report(addon, arg, extra)
    local function say(line) if addon then addon:Print(line) else print(line) end end

    if arg == "all" then
        self:ReportAll(addon)
        return
    end

    if arg == "off" then
        self:RemoveAllSounds()
        say("Aura sounds removed.")
        return
    end

    local spellID = tonumber(arg) or tonumber(extra) or IRONFUR
    local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    local spellName = (spellInfo and spellInfo.name) or tostring(spellID)

    if arg == "sound" then
        if not self:CanPlaySounds() then
            say("C_UnitAuras.AddAuraSound is not available on this client.")
            return
        end
        self:RemoveAllSounds()
        local registered = 0
        for _, trigger in ipairs(TRIGGER_NAMES) do
            if self:AddSound(trigger, spellID, PROBE_SOUNDS[trigger]) then
                registered = registered + 1
            end
        end
        say(("Registered %d/%d aura sounds on %s. Cast it and let it drop.")
            :format(registered, #TRIGGER_NAMES, spellName))
        say("|cff808080/ta aura off|r to remove them.")
        return
    end

    local report = self:Probe(spellID)

    say(("Aura probe -- %s (%d)"):format(spellName, spellID))
    local function line(label, value)
        local text = tostring(value)
        local colour = (value == true) and "|cff40d040"
            or (value == false) and "|cffe85050"
            or "|cffcccccc"
        print(("  %-26s %s%s|r"):format(label, colour, text))
    end

    line("in combat", report.inCombat)
    line("GetAuraApplicationDisplayCount", report.canShowCount)
    line("AddAuraSound (12.1)", report.canPlaySounds)
    line("combat log restricted", report.restrictedApi)
    line("aura found", report.auraFound)
    line("aura table readable", report.tableReadable)
    line("spellId readable", report.spellIdReadable)
    line("applications secret", report.applicationsSecret)
    line("applications readable", report.applicationsReadable)
    line("aura instance resolved", report.resolvedInstance)
    line("display count returned", report.countReturned)
    line("display count is secret", report.countSecret)
    line("display count value", report.countText or "(secret -- shows on screen)")

    -- The two answers worth having, stated rather than left to be inferred from
    -- the rows above.
    if report.countReturned then
        say("|cff40d040Real stack count can be shown|r, whether or not it can be read.")
    else
        say("|cffe85050No display count|r -- the icon falls back to the estimate.")
    end
    -- Readable out of combat proves nothing: the restriction only applies in
    -- combat, so an unrestricted answer there is the expected result either way.
    if report.applicationsReadable and report.inCombat then
        say("|cff40d040Stacks are readable in combat|r -- this spell is flagged "
            .. "never-secret, so decisions on it are sound.")
    elseif report.applicationsReadable then
        say("|cffe8b040Stacks readable, but out of combat|r -- inconclusive. "
            .. "Re-run at a target dummy while attacking it.")
    else
        say("|cffe85050Stacks are not readable here|r -- anything branching on "
            .. "them is guessing, and the display path above is the honest answer.")
    end
end

-- Every buff the active spec tracks, so the per-spell flags are visible side by
-- side. One spell being readable and another not is the expected shape, and it
-- is the only way to tell a whitelisted spell from an unrestricted client.
function auraDisplay:ReportAll(addon)
    local function say(line) if addon then addon:Print(line) else print(line) end end

    local module = addon and addon.activeSpecModule
    local tracked = module and module.buffsToTrack
    if not tracked then
        say("No active spec module with tracked buffs.")
        return
    end

    say(("Aura probe -- %s, %s combat"):format(
        tostring(module.name or "active spec"),
        (UnitAffectingCombat and UnitAffectingCombat("player")) and "in" or "out of"))
    print(("  %-24s %-10s %-10s %s"):format("buff", "readable", "secret", "display count"))

    for _, buffData in ipairs(tracked) do
        local report = self:Probe(buffData.spellId)
        print(("  %-24s %-10s %-10s %s"):format(
            tostring(buffData.name):sub(1, 24),
            tostring(report.applicationsReadable),
            tostring(report.applicationsSecret),
            report.countReturned and (report.countText or "(secret)") or "-"))
    end
end
