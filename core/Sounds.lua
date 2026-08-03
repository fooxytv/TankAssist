-- TankAssist Sound Playback
-- Resolves user-selected sound names via LibSharedMedia-3.0 and plays them.

local ADDON_NAME, TankAssist = ...

TankAssist.Sounds = {}
local sounds = TankAssist.Sounds

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local VALID_CHANNELS = {
    Master = true, SFX = true, Music = true, Dialog = true, Ambience = true,
}

local NONE_VALUE = "None"

local DEFAULT_SOUNDS = {
    { name = "TankAssist: Ready Ding",   key = "READY_CHECK" },
    { name = "TankAssist: Raid Siren",   key = "RAID_WARNING" },
    { name = "TankAssist: Alarm",        key = "ALARM_CLOCK_WARNING_3" },
    { name = "TankAssist: Boss Whisper", key = "UI_RAID_BOSS_WHISPER_WARNING" },
    { name = "TankAssist: Soft Click",   key = "IG_QUEST_LIST_OPEN" },
    { name = "TankAssist: Quest Done",   key = "UI_AUTO_QUEST_COMPLETE" },
}

if LSM and SOUNDKIT then
    for _, entry in ipairs(DEFAULT_SOUNDS) do
        local id = SOUNDKIT[entry.key]
        if id then
            LSM:Register("sound", entry.name, id)
        end
    end
end

function sounds:GetSettings()
    return TankAssist.Addon and TankAssist.Addon.db and TankAssist.Addon.db.profile.sounds
end

function sounds:GetSoundOptions()
    local options = { { value = NONE_VALUE, label = NONE_VALUE } }
    if not LSM then return options end

    local list = LSM:List("sound") or {}
    local seen = { [NONE_VALUE] = true }
    for _, name in ipairs(list) do
        if not seen[name] then
            seen[name] = true
            table.insert(options, { value = name, label = name })
        end
    end
    return options
end

function sounds:ResolveFile(name)
    if not name or name == "" or name == NONE_VALUE then return nil end
    if not LSM then return nil end
    return LSM:Fetch("sound", name, true)
end

function sounds:PlayByName(name)
    local resolved = self:ResolveFile(name)
    if not resolved then return end
    local settings = self:GetSettings()
    local channel = settings and settings.channel or "Master"
    if not VALID_CHANNELS[channel] then channel = "Master" end

    if type(resolved) == "number" then
        -- A numeric value from LibSharedMedia is a SOUNDKIT id, which only
        -- PlaySound understands. Falling back to PlaySoundFile here would hand
        -- it an id where a file path / fileDataID is expected, so if PlaySound
        -- declines there is nothing further to try.
        PlaySound(resolved, channel)
    else
        PlaySoundFile(resolved, channel)
    end
end

function sounds:Play(eventKey)
    local settings = self:GetSettings()
    if not settings or not settings.enabled then return end
    self:PlayByName(settings[eventKey])
end

function sounds:PlayForSpell(spellId, fallbackEventKey)
    local settings = self:GetSettings()
    if not settings or not settings.enabled then return end

    local cdSettings = TankAssist.Addon and TankAssist.Addon.db
        and TankAssist.Addon.db.profile.cooldownAlerts
    local override = cdSettings and cdSettings.spellSounds
        and cdSettings.spellSounds[tostring(spellId)]

    if override == NONE_VALUE then
        return
    end
    if override and override ~= "Default" then
        self:PlayByName(override)
        return
    end
    self:PlayByName(settings[fallbackEventKey])
end
