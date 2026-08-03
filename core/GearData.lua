local ADDON_NAME, TankAssist = ...

TankAssist.GearData = {}
local gd = TankAssist.GearData

-- ============================================================================
-- Stat aliases
-- User-facing words (from the weights: import line) -> internal stat key.
-- Matched against a normalized (lowercased, space-stripped) token.
-- ============================================================================
gd.STAT_ALIASES = {
    stamina = "stamina", stam = "stamina", sta = "stamina",
    strength = "strength", str = "strength",
    agility = "agility", agi = "agility",
    intellect = "intellect", int = "intellect",
    crit = "crit", criticalstrike = "crit", critical = "crit", critstrike = "crit",
    haste = "haste",
    mastery = "mastery", mast = "mastery",
    versatility = "versatility", vers = "versatility", versa = "versatility", vrs = "versatility",
    avoidance = "avoidance", avoid = "avoidance",
    leech = "leech", lifesteal = "leech",
    speed = "speed", movespeed = "speed", movementspeed = "speed",
}

-- ============================================================================
-- Slot aliases (from the bis: import line) -> canonical slot-group key.
-- Paired/duplicated slots collapse to one group (trinket1/trinket2 -> trinket)
-- because BIS membership is about the item, not which of the two slots it sits in.
-- ============================================================================
gd.SLOT_ALIASES = {
    head = "head", helm = "head", helmet = "head",
    neck = "neck", necklace = "neck", amulet = "neck",
    shoulder = "shoulder", shoulders = "shoulder", shoulderpads = "shoulder",
    back = "back", cloak = "back", cape = "back",
    chest = "chest", robe = "chest", chestpiece = "chest",
    waist = "waist", belt = "waist",
    legs = "legs", leg = "legs", pants = "legs",
    feet = "feet", foot = "feet", boots = "feet",
    wrist = "wrist", wrists = "wrist", bracer = "wrist", bracers = "wrist",
    hands = "hands", hand = "hands", gloves = "hands",
    finger = "finger", finger1 = "finger", finger2 = "finger",
    ring = "finger", ring1 = "finger", ring2 = "finger",
    trinket = "trinket", trinket1 = "trinket", trinket2 = "trinket",
    weapon = "weapon", weapon1 = "weapon", mainhand = "weapon", main = "weapon",
    mh = "weapon", ["2h"] = "weapon", twohand = "weapon", twohander = "weapon",
    offhand = "offhand", off = "offhand", oh = "offhand", shield = "offhand", holdable = "offhand",
}

-- ============================================================================
-- Equip location (INVTYPE_*) -> canonical slot-group key (for BIS lookup).
-- ============================================================================
gd.INVTYPE_TO_BISKEY = {
    INVTYPE_HEAD = "head",
    INVTYPE_NECK = "neck",
    INVTYPE_SHOULDER = "shoulder",
    INVTYPE_CLOAK = "back",
    INVTYPE_CHEST = "chest",
    INVTYPE_ROBE = "chest",
    INVTYPE_WAIST = "waist",
    INVTYPE_LEGS = "legs",
    INVTYPE_FEET = "feet",
    INVTYPE_WRIST = "wrist",
    INVTYPE_HAND = "hands",
    INVTYPE_FINGER = "finger",
    INVTYPE_TRINKET = "trinket",
    INVTYPE_WEAPON = "weapon",
    INVTYPE_2HWEAPON = "weapon",
    INVTYPE_WEAPONMAINHAND = "weapon",
    INVTYPE_RANGED = "weapon",
    INVTYPE_RANGEDRIGHT = "weapon",
    INVTYPE_WEAPONOFFHAND = "offhand",
    INVTYPE_SHIELD = "offhand",
    INVTYPE_HOLDABLE = "offhand",
}

-- ============================================================================
-- Equip location (INVTYPE_*) -> equipped inventory slot id(s) for comparison.
-- Two-slot entries (rings/trinkets/one-hands) are compared against the
-- lower-scoring equipped item, since that is the one being replaced.
-- Numeric literals used directly so we don't depend on INVSLOT_* globals.
-- ============================================================================
gd.INVTYPE_TO_SLOTS = {
    INVTYPE_HEAD = { 1 },
    INVTYPE_NECK = { 2 },
    INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16 },
    INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_RANGED = { 16 },
    INVTYPE_RANGEDRIGHT = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 },
}

-- ============================================================================
-- Per-spec primary stat + default weights.
-- These let the stat layer produce a verdict even before the user imports
-- anything. Real theorycraft weights override these via the import string.
-- ============================================================================
local PRIMARY_BY_SPEC = {
    [250] = "strength",  -- Blood Death Knight
    [268] = "agility",   -- Brewmaster Monk
    [73]  = "strength",  -- Protection Warrior
    [66]  = "strength",  -- Protection Paladin
    [581] = "agility",   -- Vengeance Demon Hunter
    [104] = "agility",   -- Guardian Druid
}

function gd:GetDefaultWeights(specId)
    local primary = PRIMARY_BY_SPEC[specId] or "strength"
    local weights = {
        stamina = 0.6,
        crit = 0.4,
        haste = 0.4,
        mastery = 0.4,
        versatility = 0.4,
        avoidance = 0.1,
        leech = 0.1,
        speed = 0.05,
    }
    weights[primary] = 1.0
    return weights
end

-- Internal stat key for a stat key returned by C_Item.GetItemStats.
-- Substring matching avoids depending on the exact ITEM_MOD_* spelling
-- (the _RATING / _SHORT suffixes have varied across game versions).
function gd:CanonicalStat(itemModKey)
    if not itemModKey then return nil end
    local k = tostring(itemModKey):upper()
    if k:find("STAMINA") then return "stamina"
    elseif k:find("VERSATIL") then return "versatility"
    elseif k:find("MASTERY") then return "mastery"
    elseif k:find("HASTE") then return "haste"
    elseif k:find("CRIT") then return "crit"
    elseif k:find("AVOIDANCE") then return "avoidance"
    elseif k:find("LIFESTEAL") or k:find("LEECH") then return "leech"
    elseif k:find("SPEED") and not k:find("ATTACK") then return "speed"
    elseif k:find("AGILITY") then return "agility"
    elseif k:find("STRENGTH") then return "strength"
    elseif k:find("INTELLECT") then return "intellect"
    end
    return nil
end

function gd:StatAlias(word)
    if not word then return nil end
    local norm = tostring(word):lower():gsub("%s+", "")
    return self.STAT_ALIASES[norm]
end

function gd:SlotAlias(word)
    if not word then return nil end
    local norm = tostring(word):lower():gsub("%s+", "")
    return self.SLOT_ALIASES[norm]
end

function gd:BisKeyForEquipLoc(equipLoc)
    return equipLoc and self.INVTYPE_TO_BISKEY[equipLoc] or nil
end

-- ============================================================================
-- Parser
-- ============================================================================

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function splitLines(text)
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = {}
    local start = 1
    while true do
        local nl = text:find("\n", start, true)
        if not nl then
            lines[#lines + 1] = text:sub(start)
            break
        end
        lines[#lines + 1] = text:sub(start, nl - 1)
        start = nl + 1
    end
    return lines
end

local function stripComment(line)
    local hash = line:find("#", 1, true)
    if hash then
        return line:sub(1, hash - 1)
    end
    return line
end

-- token form: key=value or key:value, separated by spaces and/or commas
local function tokenize(rest)
    local tokens = {}
    for tok in rest:gmatch("[^%s,]+") do
        tokens[#tokens + 1] = tok
    end
    return tokens
end

local function splitPair(token)
    local key, val = token:match("^(.-)[=:](.+)$")
    if not key or key == "" then return nil end
    return trim(key), trim(val)
end

function gd:ParsePairsInto(rest, out, errors, lineNo)
    for _, token in ipairs(tokenize(rest)) do
        local key, val = splitPair(token)
        if not key then
            errors[#errors + 1] = { line = lineNo, level = "warn", msg = "expected key=value, got '" .. token .. "'" }
        else
            local internal = self:StatAlias(key)
            local num = tonumber(val)
            if not internal then
                errors[#errors + 1] = { line = lineNo, level = "warn", msg = "unknown stat '" .. key .. "'" }
            elseif not num then
                errors[#errors + 1] = { line = lineNo, level = "warn", msg = "bad weight for '" .. key .. "': '" .. val .. "'" }
            else
                out[internal] = num
            end
        end
    end
end

function gd:ParseBisInto(rest, out, errors, lineNo)
    for _, token in ipairs(tokenize(rest)) do
        local key, val = splitPair(token)
        if not key then
            errors[#errors + 1] = { line = lineNo, level = "warn", msg = "expected slot=itemID, got '" .. token .. "'" }
        else
            local slotKey = self:SlotAlias(key)
            local id = tonumber(val)
            if not slotKey then
                errors[#errors + 1] = { line = lineNo, level = "warn", msg = "unknown slot '" .. key .. "'" }
            elseif not id then
                errors[#errors + 1] = { line = lineNo, level = "warn", msg = "bad item id for '" .. key .. "': '" .. val .. "'" }
            else
                out[slotKey] = out[slotKey] or {}
                out[slotKey][id] = true
            end
        end
    end
end

local KNOWN_VERSION = 1

-- Parse(text) -> profile { weights=table|nil, bis=table|nil, raw=string, declaredSpec=string|nil }, errors[]
-- errors entries: { line=number|nil, level="error"|"warn", msg=string }
function gd:Parse(text)
    local profile = { raw = text, weights = nil, bis = nil }
    local errors = {}

    if type(text) ~= "string" or trim(text) == "" then
        errors[#errors + 1] = { level = "error", msg = "import text is empty" }
        return profile, errors
    end

    local pending = nil -- "weights" | "bis" | nil
    local lineNo = 0

    for _, raw in ipairs(splitLines(text)) do
        lineNo = lineNo + 1
        local line = stripComment(raw)
        if trim(line) ~= "" then
            local lower = line:lower()
            if lower:match("^%s*tankassist%s*:") then
                local v = tonumber(line:match("[vV]?(%d+)%s*$"))
                if v and v > KNOWN_VERSION then
                    errors[#errors + 1] = { line = lineNo, level = "warn", msg = "newer format version v" .. v .. " (this addon knows v" .. KNOWN_VERSION .. ")" }
                end
                pending = nil
            elseif lower:match("^%s*spec%s*=") then
                profile.declaredSpec = trim(line:sub((line:find("=", 1, true)) + 1))
                pending = nil
            elseif lower:match("^%s*weights?%s*:") then
                profile.weights = profile.weights or {}
                self:ParsePairsInto(line:sub((line:find(":", 1, true)) + 1), profile.weights, errors, lineNo)
                pending = "weights"
            elseif lower:match("^%s*bis%s*:") then
                profile.bis = profile.bis or {}
                self:ParseBisInto(line:sub((line:find(":", 1, true)) + 1), profile.bis, errors, lineNo)
                pending = "bis"
            elseif pending == "weights" then
                self:ParsePairsInto(line, profile.weights, errors, lineNo)
            elseif pending == "bis" then
                self:ParseBisInto(line, profile.bis, errors, lineNo)
            else
                errors[#errors + 1] = { line = lineNo, level = "warn", msg = "ignored: '" .. trim(line) .. "'" }
            end
        end
    end

    -- normalize / validate
    if profile.weights and next(profile.weights) == nil then profile.weights = nil end
    if profile.bis and next(profile.bis) == nil then profile.bis = nil end

    if profile.weights then
        for stat, v in pairs(profile.weights) do
            if v < 0 or v > 100 then
                errors[#errors + 1] = { level = "warn", msg = "weight out of range (0-100) for '" .. stat .. "': " .. v }
            end
        end
    end

    if not profile.weights and not profile.bis then
        errors[#errors + 1] = { level = "error", msg = "no usable weights or bis entries found" }
    end

    return profile, errors
end

-- Count helpers used by the config status line / debug dump.
function gd:CountWeights(profile)
    local n = 0
    if profile and profile.weights then
        for _ in pairs(profile.weights) do n = n + 1 end
    end
    return n
end

function gd:CountBis(profile)
    local n = 0
    if profile and profile.bis then
        for _, ids in pairs(profile.bis) do
            for _ in pairs(ids) do n = n + 1 end
        end
    end
    return n
end
