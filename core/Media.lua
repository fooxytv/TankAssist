-- TankAssist Font Media
-- One place to turn a user-chosen font name into a path the client will
-- actually load, and to apply it without ever leaving a font string fontless.

local ADDON_NAME, TankAssist = ...

TankAssist.Media = {}
local media = TankAssist.Media

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local LSM_FONT = LSM and LSM.MediaType and LSM.MediaType.FONT or "font"

local DEFAULT_FONT_NAME = "Friz Quadrata"
local DEFAULT_FONT_PATH = "Fonts\\FRIZQT__.TTF"
local DEFAULT_FLAG_NAME = "Outline"
local DEFAULT_FLAG = "OUTLINE"

-- SetFont returns false for a path this client cannot load, and leaves the font
-- string with no font at all -- the error then surfaces on the next SetText,
-- far from the setting that caused it. Probe each path once against a throwaway
-- string so an unavailable face is never offered in a dropdown to begin with.
-- Several of the faces the addon has always listed (2002, Express Way) are
-- missing on some locales, which is exactly how that bug reached players.
local probeString
local probeResults = {}

local function CanLoad(path)
    if type(path) ~= "string" or path == "" then return false end
    if probeResults[path] ~= nil then return probeResults[path] end

    if not probeString then
        local holder = CreateFrame("Frame")
        holder:Hide()
        probeString = holder:CreateFontString(nil, "ARTWORK")
    end

    -- pcall as well as the return value: a malformed path can raise rather
    -- than decline, and either way the answer is "do not offer this font".
    local ok, loaded = pcall(probeString.SetFont, probeString, path, 12, DEFAULT_FLAG)
    -- A stub or an older client returns nothing at all from SetFont; only an
    -- explicit false is a refusal.
    local usable = ok and loaded ~= false
    probeResults[path] = usable
    return usable
end

local function BuiltInPath(name)
    for _, entry in ipairs(TankAssist.Constants.Fonts) do
        if entry.name == name then return entry.path end
    end
    return nil
end

--- Resolve a font name to a path that is known to load.
-- LibSharedMedia first, so faces registered by other addons work, then the
-- built-in list, then the stock font.
function media:GetFontPath(name)
    if type(name) == "string" and name ~= "" then
        local path = BuiltInPath(name)
        if not path and LSM then
            path = LSM:Fetch(LSM_FONT, name, true)
        end
        if path and CanLoad(path) then
            return path
        end
    end
    return DEFAULT_FONT_PATH
end

function media:ResolveFlag(name)
    for _, entry in ipairs(TankAssist.Constants.FontFlags) do
        if entry.name == name then return entry.flag end
    end
    return DEFAULT_FLAG
end

--- Every font name worth offering: the built-in faces this client can actually
-- load, plus anything LibSharedMedia knows about, sorted and de-duplicated.
function media:ListFonts()
    local names, seen = {}, {}

    for _, entry in ipairs(TankAssist.Constants.Fonts) do
        if not seen[entry.name] and CanLoad(entry.path) then
            seen[entry.name] = true
            table.insert(names, entry.name)
        end
    end

    if LSM then
        for _, name in ipairs(LSM:List(LSM_FONT) or {}) do
            if not seen[name] and CanLoad(LSM:Fetch(LSM_FONT, name, true)) then
                seen[name] = true
                table.insert(names, name)
            end
        end
    end

    if #names == 0 then
        names[1] = DEFAULT_FONT_NAME
    end
    table.sort(names)
    return names
end

--- Dropdown values in the shape LibEQOL Edit Mode expects.
function media:GetFontDropdownValues()
    local values = {}
    for _, name in ipairs(self:ListFonts()) do
        table.insert(values, { text = name })
    end
    return values
end

function media:GetFontFlagDropdownValues()
    local values = {}
    for _, entry in ipairs(TankAssist.Constants.FontFlags) do
        table.insert(values, { text = entry.name })
    end
    return values
end

--- Apply a font by name, and never leave the string without one.
-- Returns the path that was actually applied, so a caller (or a test) can tell
-- a fallback from a hit; nil means even the stock font was refused.
function media:SetFont(fontString, name, size, flagName)
    if not fontString or not fontString.SetFont then return nil end

    size = tonumber(size) or 11
    if size < 1 then size = 1 end
    local flag = self:ResolveFlag(flagName)
    local path = self:GetFontPath(name)

    local ok, loaded = pcall(fontString.SetFont, fontString, path, size, flag)
    if ok and loaded ~= false then
        return path
    end

    -- The probe passed and it still failed here. Anything is better than a
    -- font string with no font, which errors on its next SetText.
    probeResults[path] = false
    if path ~= DEFAULT_FONT_PATH then
        local retryOk, retryLoaded = pcall(fontString.SetFont, fontString, DEFAULT_FONT_PATH, size, flag)
        if retryOk and retryLoaded ~= false then
            return DEFAULT_FONT_PATH
        end
    end
    if fontString.SetFontObject then
        pcall(fontString.SetFontObject, fontString, "GameFontNormal")
    end
    return nil
end

function media.DefaultFontName()
    return DEFAULT_FONT_NAME
end

function media.DefaultFlagName()
    return DEFAULT_FLAG_NAME
end
