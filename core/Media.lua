-- TankAssist Shared Media
--
-- Fonts and bar textures resolved through LibSharedMedia-3.0, the same way
-- sounds already are in core/Sounds.lua.
--
-- These lists used to be hardcoded to seven Blizzard fonts and four bar
-- textures, so installing a font pack did nothing -- the dropdown never saw it.
-- Routing them through LSM means any media addon the player already has fills
-- the dropdowns for free: SharedMediaAdditionalFonts, SharedMedia_Causese,
-- ElvUI, WeakAuras, DBM, BigWigs. Nothing is shipped, so there are no font
-- licences to redistribute and no megabytes added to the package.
--
-- The addon's own built-ins are registered into LSM under their existing names,
-- which keeps saved settings resolving and hands them to every other LSM-aware
-- addon on the account.

local ADDON_NAME, TankAssist = ...

TankAssist.Media = {}
local media = TankAssist.Media

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local FONT      = "font"
local STATUSBAR = "statusbar"

local FALLBACK_FONT      = "Fonts\\FRIZQT__.TTF"
local FALLBACK_STATUSBAR = "Interface\\TargetingFrame\\UI-StatusBar"

----------------------------------------------------------------------------
-- Font validation
--
-- A font path that does not resolve makes SetFont raise "Invalid font asset"
-- and takes the surrounding frame construction down with it. That is not
-- hypothetical: it is exactly how a missing font in another addon stopped its
-- config window from opening at all.
--
-- We are now offering whatever arbitrary media addons have registered, some of
-- which point at files they no longer ship, so every candidate is proved before
-- it is offered or applied. One hidden FontString does the proving and the
-- answer is cached, because the check is only cheap if it happens once.
----------------------------------------------------------------------------

local fontProbe
local fontUsable = {}

local function isUsableFont(path)
    if type(path) ~= "string" or path == "" then return false end

    local cached = fontUsable[path]
    if cached ~= nil then return cached end

    if not fontProbe then
        local holder = CreateFrame("Frame")
        holder:Hide()
        fontProbe = holder:CreateFontString(nil, "ARTWORK")
    end

    -- pcall because an invalid asset raises rather than returning false, and
    -- the explicit false check because some builds return a status instead.
    local ok, result = pcall(fontProbe.SetFont, fontProbe, path, 12, "")
    local usable = ok and result ~= false

    fontUsable[path] = usable
    return usable
end

function media:IsUsableFont(path)
    return isUsableFont(path)
end

----------------------------------------------------------------------------
-- Registration
----------------------------------------------------------------------------

if LSM then
    for _, entry in ipairs(TankAssist.Constants.Fonts) do
        if isUsableFont(entry.path) then
            LSM:Register(FONT, entry.name, entry.path)
        end
    end
    for _, entry in ipairs(TankAssist.Constants.BarTextures) do
        LSM:Register(STATUSBAR, entry.name, entry.path)
    end
end

----------------------------------------------------------------------------
-- Listing
----------------------------------------------------------------------------

-- Falls back to the built-in table when LSM is missing, so the dropdowns are
-- never empty even on a stripped install.
local function listFrom(mediaType, builtins, validator)
    local function collect(useValidator)
        local names, seen = {}, {}

        if LSM then
            for _, name in ipairs(LSM:List(mediaType) or {}) do
                if not seen[name] then
                    local path = LSM:Fetch(mediaType, name, true)
                    if path and (not useValidator or not validator or validator(path)) then
                        seen[name] = true
                        table.insert(names, name)
                    end
                end
            end
        end

        for _, entry in ipairs(builtins) do
            if not seen[entry.name] and (not useValidator or not validator or validator(entry.path)) then
                seen[entry.name] = true
                table.insert(names, entry.name)
            end
        end

        table.sort(names)
        return names
    end

    local names = collect(true)

    -- An empty dropdown is worse than an unverified one. If validation rejected
    -- everything -- a client where the probe cannot run, say -- fall back to the
    -- raw list rather than offering the player nothing at all.
    if #names == 0 then
        names = collect(false)
    end

    return names
end

function media:ListFonts()
    return listFrom(FONT, TankAssist.Constants.Fonts, isUsableFont)
end

function media:ListStatusBars()
    return listFrom(STATUSBAR, TankAssist.Constants.BarTextures)
end

-- LEM dropdowns want { { text = name }, ... }.
local function asDropdownValues(names)
    local values = {}
    for _, name in ipairs(names) do
        table.insert(values, { text = name })
    end
    return values
end

function media:FontDropdownValues()
    return asDropdownValues(self:ListFonts())
end

function media:StatusBarDropdownValues()
    return asDropdownValues(self:ListStatusBars())
end

----------------------------------------------------------------------------
-- Fetching
----------------------------------------------------------------------------

local function fetchFrom(mediaType, name, builtins, fallback, validator)
    if LSM and type(name) == "string" and name ~= "" then
        local path = LSM:Fetch(mediaType, name, true)
        if path and (not validator or validator(path)) then
            return path
        end
    end

    -- A setting saved before this went through LSM, or LSM absent entirely.
    for _, entry in ipairs(builtins) do
        if entry.name == name then
            if not validator or validator(entry.path) then
                return entry.path
            end
            break
        end
    end

    return fallback
end

function media:FetchFont(name)
    return fetchFrom(FONT, name, TankAssist.Constants.Fonts, FALLBACK_FONT, isUsableFont)
end

function media:FetchStatusBar(name)
    return fetchFrom(STATUSBAR, name, TankAssist.Constants.BarTextures, FALLBACK_STATUSBAR)
end

function media:HasLibSharedMedia()
    return LSM ~= nil
end

----------------------------------------------------------------------------
-- Applying
--
-- Validation above proves a path loads; this proves it still loads at the
-- moment it is applied. The two are not the same -- a pack can be disabled
-- between the probe and the apply, and the probe's answer is cached -- and the
-- consequence of getting it wrong is nasty: SetFont declines rather than
-- raising, leaving the FontString with no font at all, and the error surfaces
-- later on an unrelated SetText.
--
-- Every caller goes through here so none of them has to remember that.
----------------------------------------------------------------------------

function media:ResolveFontFlag(name)
    for _, entry in ipairs(TankAssist.Constants.FontFlags) do
        if entry.name == name then return entry.flag end
    end
    return "OUTLINE"
end

function media:FontFlagDropdownValues()
    return asDropdownValues((function()
        local names = {}
        for _, entry in ipairs(TankAssist.Constants.FontFlags) do
            table.insert(names, entry.name)
        end
        return names
    end)())
end

--- Apply a font by name. Returns the path that was actually applied, so a
-- caller (or a test) can tell a fallback from a hit; nil means even the
-- Blizzard default was refused.
function media:SetFont(fontString, name, size, flagName)
    if not fontString or not fontString.SetFont then return nil end

    size = tonumber(size) or 11
    if size < 1 then size = 1 end

    local flag = self:ResolveFontFlag(flagName)
    local path = self:FetchFont(name)

    local ok, applied = pcall(fontString.SetFont, fontString, path, size, flag)
    if ok and applied ~= false then
        return path
    end

    -- Proved usable and still refused. Drop the cached verdict so the next
    -- listing stops offering it, and fall back rather than leave the string
    -- with nothing.
    fontUsable[path] = false
    if path ~= FALLBACK_FONT then
        local retryOk, retryApplied = pcall(fontString.SetFont, fontString, FALLBACK_FONT, size, flag)
        if retryOk and retryApplied ~= false then
            return FALLBACK_FONT
        end
    end
    if fontString.SetFontObject then
        pcall(fontString.SetFontObject, fontString, "GameFontNormal")
    end
    return nil
end

function media.DefaultFontName()
    return "Friz Quadrata"
end

function media.DefaultFontFlagName()
    return "Outline"
end

