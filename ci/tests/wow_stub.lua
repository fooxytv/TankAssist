-- Minimal WoW client stub: enough of the widget and C_* API for the addon's
-- load path, a layout pass and an update tick to run outside the game.

unpack = unpack or table.unpack
loadstring = loadstring or load

-- WoW ships LuaJIT's bit library; Lua 5.4 does not.
bit = bit or {
    band   = function(a, b) return a & b end,
    bor    = function(a, b) return a | b end,
    bxor   = function(a, b) return a ~ b end,
    lshift = function(a, n) return (a << n) & 0xFFFFFFFF end,
    rshift = function(a, n) return (a & 0xFFFFFFFF) >> n end,
    bnot   = function(a) return ~a & 0xFFFFFFFF end,
}

local calls = {}
_G.__calls = calls

local function record(name)
    calls[name] = (calls[name] or 0) + 1
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local Widget = {}
Widget.__index = Widget

local frameLevelSeed = 1

local function newWidget(kind, name, parent)
    local self = setmetatable({}, Widget)
    self.__kind = kind
    self.__name = name
    self.__parent = parent
    self.__shown = true
    self.__points = {}
    self.__width, self.__height = 40, 40
    frameLevelSeed = frameLevelSeed + 1
    self.__level = frameLevelSeed
    self.__min, self.__max, self.__value = 0, 1, 0
    self.__text = ""
    return self
end

-- Any widget method not spelled out below is a no-op returning nil. Every call
-- is counted, so a test can assert that something was actually invoked.
-- Widget methods are PascalCase; the fields this addon hangs off a frame
-- (frame.overlay, frame.bar, frame.timeText, ...) are not. So an unknown
-- PascalCase key is treated as a method the stub has not bothered to
-- implement, and anything else stays nil -- which is what an absent child
-- widget looks like in the real client, and what the addon's `if frame.overlay
-- then` guards are testing for.
setmetatable(Widget, {
    __index = function(_, key)
        if type(key) ~= "string" then return nil end
        local first = key:sub(1, 1)
        if first ~= first:upper() or first == "_" then return nil end
        return function(...)
            record(key)
            return nil
        end
    end,
})

function Widget:SetPoint(point, ...) record("SetPoint") self.__points[#self.__points + 1] = { point, ... } end
function Widget:ClearAllPoints() record("ClearAllPoints") self.__points = {} end
function Widget:SetAllPoints() record("SetAllPoints") end
function Widget:GetPoint() return self.__points[1] and self.__points[1][1] or "CENTER", nil, "CENTER", 0, 0 end
function Widget:GetNumPoints() return #self.__points end

function Widget:SetSize(w, h) self.__width, self.__height = w, h end
function Widget:SetWidth(w) self.__width = w end
function Widget:SetHeight(h) self.__height = h end
function Widget:GetSize() return self.__width, self.__height end
function Widget:GetWidth() return self.__width end
function Widget:GetHeight() return self.__height end
function Widget:GetCenter() return 400, 300 end
function Widget:GetEffectiveScale() return 1 end

function Widget:Show() self.__shown = true end
function Widget:Hide() self.__shown = false end
function Widget:SetShown(shown) self.__shown = shown and true or false end
function Widget:IsShown() return self.__shown end
function Widget:IsVisible() return self.__shown end

function Widget:SetFrameLevel(level) self.__level = level end
function Widget:GetFrameLevel() return self.__level end

function Widget:SetScript(script, handler) self.__scripts = self.__scripts or {}; self.__scripts[script] = handler end
function Widget:GetScript(script) return self.__scripts and self.__scripts[script] end
function Widget:HookScript(script, handler) self:SetScript(script, handler) end
function Widget:RegisterEvent() end
function Widget:UnregisterEvent() end
function Widget:SetParent(parent) self.__parent = parent end
function Widget:GetParent() return self.__parent end
function Widget:GetName() return self.__name end

function Widget:CreateTexture(name, layer)
    record("CreateTexture")
    return newWidget("Texture", name, self)
end

function Widget:CreateMaskTexture(name)
    record("CreateMaskTexture")
    return newWidget("MaskTexture", name, self)
end

function Widget:CreateFontString(name, layer, inherits)
    record("CreateFontString")
    local fs = newWidget("FontString", name, self)
    fs.__font = inherits or "GameFontNormal"
    return fs
end

-- FontString
function Widget:SetText(text) self.__text = text end
function Widget:GetText() return self.__text end
function Widget:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function Widget:SetFont(file, size, flags) self.__fontSize = size end
function Widget:SetFontObject(object) self.__font = object end

-- StatusBar
function Widget:SetMinMaxValues(min, max) self.__min, self.__max = min, max end
function Widget:GetMinMaxValues() return self.__min, self.__max end
function Widget:SetValue(value) self.__value = value end
function Widget:GetValue() return self.__value end
function Widget:SetStatusBarTexture(texture) self.__barTexture = texture end
function Widget:GetStatusBarTexture()
    self.__barTexture = self.__barTexture or newWidget("Texture", nil, self)
    return self.__barTexture
end
function Widget:SetStatusBarColor(r, g, b, a) self.__barColor = { r, g, b, a } end

-- Texture
function Widget:SetAtlas(atlas, useSize) record("SetAtlas") self.__atlas = atlas end
function Widget:SetTexture(file) self.__texture = file end
function Widget:GetTexture() return self.__texture end
function Widget:SetColorTexture(r, g, b, a) self.__color = { r, g, b, a } end
function Widget:SetVertexColor(r, g, b, a) self.__vertex = { r, g, b, a } end
function Widget:SetDesaturated(value) self.__desaturated = value end
function Widget:AddMaskTexture(mask) self.__mask = mask end

-- Cooldown
function Widget:SetCooldown(start, duration, modRate) self.__cooldown = { start, duration, modRate } end
function Widget:Clear() self.__cooldown = nil end
function Widget:SetSwipeColor(r, g, b, a) self.__swipeColor = { r, g, b, a } end

function Widget:SetMouseClickEnabled(enabled) self.__mouseClick = enabled end
function Widget:SetMouseMotionEnabled(enabled) self.__mouseMotion = enabled end
function Widget:EnableMouse(enabled) self.__mouse = enabled end

_G.CreateFrame = function(kind, name, parent, template)
    record("CreateFrame")
    local frame = newWidget(kind, name, parent)
    if name then _G[name] = frame end
    -- Templates the addon leans on for named children.
    if template and template:find("OptionsSliderTemplate") and name then
        _G[name .. "Text"] = newWidget("FontString", name .. "Text", frame)
        _G[name .. "Low"] = newWidget("FontString", name .. "Low", frame)
        _G[name .. "High"] = newWidget("FontString", name .. "High", frame)
    end
    if template and template:find("UICheckButtonTemplate") and name then
        _G[name .. "Text"] = newWidget("FontString", name .. "Text", frame)
    end
    if template and template:find("ButtonFrameTemplate") then
        frame.Inset = newWidget("Frame", nil, frame)
        frame.TitleContainer = { TitleText = newWidget("FontString", nil, frame) }
        frame.PortraitContainer = { portrait = newWidget("Texture", nil, frame) }
        frame.SetTitle = function(_, title) frame.__title = title end
    end
    return frame
end

_G.UIParent = newWidget("Frame", "UIParent")
_G.GameTooltip = newWidget("GameTooltip", "GameTooltip")
_G.DEFAULT_CHAT_FRAME = newWidget("Frame", "DEFAULT_CHAT_FRAME")

--------------------------------------------------------------------------------
-- Globals the addon reads
--------------------------------------------------------------------------------

for _, font in ipairs({
    "GameFontNormal", "GameFontNormalSmall", "GameFontHighlight",
    "GameFontHighlightSmall", "NumberFontNormal", "NumberFontNormalSmall",
}) do
    _G[font] = { __fontObject = font }
end

local now = 1000
_G.GetTime = function() return now end
_G.__advance = function(seconds) now = now + seconds end

_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.tinsert = table.insert
_G.tremove = table.remove
_G.format = string.format
_G.time = function() return 1735689600 end
_G.CopyTable = function(t)
    local copy = {}
    for k, v in pairs(t) do copy[k] = type(v) == "table" and _G.CopyTable(v) or v end
    return copy
end
_G.hooksecurefunc = function() end
_G.strsplit = function(sep, str) return str end

_G.UnitName = function() return "Tester" end
_G.UnitClass = function() return "Druid", "DRUID", 11 end
_G.UnitExists = function() return true end
_G.UnitIsDead = function() return false end
_G.UnitCanAttack = function() return true end
_G.UnitAffectingCombat = function() return false end
_G.UnitHealth = function() return 100 end
_G.UnitHealthMax = function() return 100 end
_G.UnitPower = function() return 50 end
_G.UnitPowerMax = function() return 100 end
_G.UnitStagger = function() return 0 end
_G.UnitCastingInfo = function() return nil end
_G.UnitChannelInfo = function() return nil end
_G.UnitCastingDuration = function() return nil end
_G.UnitChannelDuration = function() return nil end
_G.InCombatLockdown = function() return false end
_G.IsMounted = function() return false end
_G.IsInInstance = function() return false, "none" end
_G.IsShiftKeyDown = function() return false end
_G.IsSpellKnown = function() return true end
_G.IsPlayerSpell = function() return true end
_G.GetInstanceInfo = function() return "Test", "none" end
_G.GetWeaponEnchantInfo = function() return false end
_G.GetInventoryItemLink = function() return nil end
_G.GetLootRollItemLink = function() return nil end
_G.GetActionInfo = function() return nil end
_G.GetBindingKey = function() return nil end
_G.GetMacroSpell = function() return nil end
_G.GetRuneCooldown = function() return 0, 10, true end

-- Guardian Druid: the spec the addon is primarily developed against.
_G.GetSpecialization = function() return 3 end
_G.GetSpecializationInfo = function() return 104, "Guardian", nil, nil, "TANK" end
_G.GetSpecializationInfoByID = function(id) return id, "Guardian", nil, nil, "TANK" end

_G.PlaySound = function()
    _G.__calls.PlaySound = (_G.__calls.PlaySound or 0) + 1
    return true
end
_G.PlaySoundFile = function()
    _G.__calls.PlaySoundFile = (_G.__calls.PlaySoundFile or 0) + 1
end
_G.SOUNDKIT = { IG_CHARACTER_INFO_TAB = 841 }

_G.UISpecialFrames = {}
_G.SlashCmdList = {}
_G.NUM_GROUP_LOOT_FRAMES = 4
_G.ScrollingEdit_OnCursorChanged = function() end
_G.ScrollingEdit_OnTextChanged = function() end
_G.ActionButton_ShowOverlayGlow = function() end
_G.ActionButton_HideOverlayGlow = function() end

_G.RAID_CLASS_COLORS = setmetatable({}, {
    __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end,
})

-- 12.0 secret values. Nothing in the stub is secret, so the probes say so and
-- the addon takes its normal path.
_G.issecretvalue = function() return false end
_G.canaccesssecrets = function() return true end
_G.canaccessvalue = function() return true end

--------------------------------------------------------------------------------
-- Namespaced APIs
--------------------------------------------------------------------------------

_G.C_Timer = {
    After = function(_, fn)
        _G.__pendingTimers = _G.__pendingTimers or {}
        table.insert(_G.__pendingTimers, fn)
    end,
    NewTicker = function(_, fn)
        _G.__ticker = fn
        return { Cancel = function() end }
    end,
}

_G.C_AddOns = {
    GetAddOnMetadata = function(_, key) return key == "Version" and "0.0.0-test" or nil end,
    IsAddOnLoaded = function() return false end,
    LoadAddOn = function() return true end,
}

local SPELLS = {
    [22812]  = { name = "Barkskin",           icon = 136097,  cd = 60 },
    [61336]  = { name = "Survival Instincts", icon = 236169,  cd = 180 },
    [106839] = { name = "Skull Bash",         icon = 236946,  cd = 15 },
    [192081] = { name = "Ironfur",            icon = 1378702, cd = 0.5 },
}

_G.C_Spell = {
    GetSpellInfo = function(id)
        local spell = SPELLS[id]
        if not spell then return nil end
        return { name = spell.name, iconID = spell.icon, spellID = id }
    end,
    GetSpellTexture = function(id) return SPELLS[id] and SPELLS[id].icon end,
    GetSpellName = function(id) return SPELLS[id] and SPELLS[id].name end,
    -- Driveable: __cd = { start =, duration = }. Empty means ready.
    GetSpellCooldown = function(id)
        local cd = _G.__cd or {}
        if cd.duration then return { startTime = cd.start or 0, duration = cd.duration, isEnabled = true, modRate = 1 } end
        local spell = SPELLS[id]
        return { startTime = 0, duration = spell and spell.cd or 0, isEnabled = true, modRate = 1 }
    end,
    GetSpellCharges = function() return nil end,
    IsSpellUsable = function() return true, false end,
    DoesSpellExist = function(id) return SPELLS[id] ~= nil end,
    IsSpellDataCached = function() return true end,
    RequestLoadSpellData = function() end,
}

_G.C_UnitAuras = {
    GetAuraDataByIndex = function() return nil end,
    GetPlayerAuraBySpellID = function() return nil end,
    GetAuraDataBySpellName = function() return nil end,
    ForEachAura = function() end,
}

_G.AuraUtil = { ForEachAura = function() end }

_G.C_AssistedCombat = {
    GetNextCastSpell = function() return 192081 end,
    GetRotationSpells = function() return { 192081, 22812 } end,
    SetAssistedCombatEnabled = function() end,
}

_G.C_SpellActivationOverlay = { IsSpellOverlayed = function() return false end }

_G.C_PetBattles = { IsInBattle = function() return false end }

_G.C_Item = {
    GetItemInfoInstant = function() return nil end,
    GetItemStats = function() return nil end,
    GetDetailedItemLevelInfo = function() return nil end,
}
_G.GetItemInfoInstant = function() return nil end
_G.GetItemStats = function() return nil end
_G.GetDetailedItemLevelInfo = function() return nil end

_G.TooltipDataProcessor = { AddTooltipPostCall = function() end }

_G.Enum = {
    TooltipDataType = { Item = 0 },
    PowerType = { Mana = 0, Rage = 1, Energy = 3 },
}

_G.EventRegistry = {
    RegisterCallback = function() end,
    UnregisterCallback = function() end,
    TriggerEvent = function() end,
}

-- Absent in the stub, as on a client without Edit Mode and with no libraries
-- loaded. The addon guards for both, and those guards are worth exercising:
-- the .toc loads libs/ in game, but the smoke test deliberately does not.
_G.EditModeManagerFrame = nil
_G.LibStub = nil
