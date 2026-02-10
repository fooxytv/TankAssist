local ADDON_NAME, TankAssist = ...
TankAssist.Utils = {}

local utils = TankAssist.Utils

function utils:DeepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[self:DeepCopy(orig_key)] = self:DeepCopy(orig_value)
        end
        setmetatable(copy, self:DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

function utils:Contains(table, value)
    for _, v in pairs(table) do
        if v == value then
            return true
        end
    end
    return false
end

function utils:TableLength(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

function utils:MergeTables(t1, t2)
    local result = self:DeepCopy(t1)
    for k, v in pairs(t2) do
        if type(v) == "table" and type(result[k]) == "table" then
            result[k] = self:MergeTables(result[k], v)
        else
            result[k] = v
        end
    end
    return result
end

function utils:FormatDuration(seconds)
    if not seconds or seconds <= 0 then
        return "0"
    end
    if seconds < 60 then
        return string.format("%.1f", seconds)
    elseif seconds < 3600 then
        return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
    else
        return string.format("%d:%02d:%02d",
            math.floor(seconds / 3600),
            math.floor((seconds % 3600) / 60),
            seconds % 60
        )
    end
end

function utils:FormatPercent(value)
    if not value then
        return "?"
    end
    return string.format("%.0f%%", value * 100)
end

function utils:Truncate(str, maxLen)
    if #str <= maxLen then
        return str
    end
    return string.sub(str, 1, maxLen - 3) .. "..."
end

utils.spellCache = {}
utils.keybindCache = {}
utils.keybindCacheTime = 0
utils.keybindCacheDuration = 5

function utils:GetSpellInfo(spellId)
    if self.spellCache[spellId] then
        return unpack(self.spellCache[spellId])
    end

    local spellInfo = C_Spell.GetSpellInfo(spellId)
    if spellInfo then
        self.spellCache[spellId] = { spellInfo.name, spellInfo.iconID }
        return spellInfo.name, spellInfo.iconID
    end

    return nil, nil
end

function utils:GetSpellKeybind(spellId)
    local now = GetTime()
    if now - self.keybindCacheTime < self.keybindCacheDuration then
        local cached = self.keybindCache[spellId]
        if cached ~= nil then
            return cached ~= false and cached or nil
        end
    else
        self.keybindCache = {}
        self.keybindCacheTime = now
    end

    local spellInfo = C_Spell.GetSpellInfo(spellId)
    local name = spellInfo and spellInfo.name
    if not name then
        self.keybindCache[spellId] = false
        return nil
    end

    local barMappings = {
        { start = 1, prefix = "ACTIONBUTTON" },
        { start = 61, prefix = "MULTIACTIONBAR1BUTTON" },
        { start = 49, prefix = "MULTIACTIONBAR2BUTTON" },
        { start = 25, prefix = "MULTIACTIONBAR3BUTTON" },
        { start = 37, prefix = "MULTIACTIONBAR4BUTTON" },
        { start = 145, prefix = "MULTIACTIONBAR5BUTTON" },
        { start = 157, prefix = "MULTIACTIONBAR6BUTTON" },
        { start = 169, prefix = "MULTIACTIONBAR7BUTTON" },
        { start = 13, prefix = "ACTIONBUTTON" },
        { start = 25, prefix = "ACTIONBUTTON" },
        { start = 37, prefix = "ACTIONBUTTON" },
        { start = 49, prefix = "ACTIONBUTTON" },
        { start = 61, prefix = "ACTIONBUTTON" },
        { start = 73, prefix = "ACTIONBUTTON" },
        { start = 85, prefix = "ACTIONBUTTON" },
        { start = 97, prefix = "ACTIONBUTTON" },
        { start = 109, prefix = "ACTIONBUTTON" },
        { start = 121, prefix = "ACTIONBUTTON" },
        { start = 133, prefix = "ACTIONBUTTON" },
    }

    local function checkSpellMatch(actionType, id)
        if actionType == "spell" then
            if id == spellId then
                return true
            end
            local slotSpellInfo = id and C_Spell.GetSpellInfo(id)
            if slotSpellInfo and slotSpellInfo.name == name then
                return true
            end
        elseif actionType == "macro" then
            local macroSpell, _ = GetMacroSpell(id)
            if macroSpell then
                if macroSpell == spellId or macroSpell == name then
                    return true
                end
                if type(macroSpell) == "number" then
                    local macroSpellInfo = C_Spell.GetSpellInfo(macroSpell)
                    if macroSpellInfo and macroSpellInfo.name == name then
                        return true
                    end
                end
            end
        end
        return false
    end

    for slot = 1, 180 do
        local actionType, id = GetActionInfo(slot)
        if checkSpellMatch(actionType, id) then
            for _, bar in ipairs(barMappings) do
                if slot >= bar.start and slot < bar.start + 12 then
                    local buttonNum = slot - bar.start + 1
                    local key = GetBindingKey(bar.prefix .. buttonNum)
                    if key then
                        self.keybindCache[spellId] = key
                        return key
                    end
                end
            end
        end
    end

    local key = GetBindingKey("SPELL " .. name)
    if key then
        self.keybindCache[spellId] = key
        return key
    end

    key = GetBindingKey("SPELL " .. spellId)
    if key then
        self.keybindCache[spellId] = key
        return key
    end

    self.keybindCache[spellId] = false
    return nil
end

function utils:ClearKeybindCache()
    self.keybindCache = {}
    self.keybindCacheTime = 0
end

function utils:FormatKeybind(key)
    if not key then return "" end
    key = key:gsub("SHIFT%-", "S-")
    key = key:gsub("CTRL%-", "C-")
    key = key:gsub("ALT%-", "A-")
    key = key:gsub("BUTTON", "M")
    key = key:gsub("MOUSEWHEELUP", "WU")
    key = key:gsub("MOUSEWHEELDOWN", "WD")
    return key
end

function utils:GetCurrentSpec()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    local specId = GetSpecializationInfo(specIndex)
    return specId
end

function utils:IsTankSpec(specId)
    specId = specId or self:GetCurrentSpec()
    if not specId then return false end
    local tankSpecs = {
        [250] = true,
        [268] = true,
        [73] = true,
        [66] = true,
        [581] = true,
        [104] = true,
    }
    return tankSpecs[specId] == true
end

function utils:GetSpecName(specId)
    if TankAssist.Constants and TankAssist.Constants.SpecNames then
        return TankAssist.Constants.SpecNames[specId] or "Unknown"
    end
    return "Unknown"
end

function utils:CreateIcon(parent, size, template)
    local frame = CreateFrame("Frame", nil, parent, template)
    frame:SetSize(size, size)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints()
    frame.cooldown:SetDrawSwipe(true)
    frame.cooldown:SetDrawEdge(false)

    frame.border = frame:CreateTexture(nil, "OVERLAY")
    frame.border:SetPoint("TOPLEFT", -2, 2)
    frame.border:SetPoint("BOTTOMRIGHT", 2, -2)
    frame.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.border:SetBlendMode("ADD")
    frame.border:SetVertexColor(1, 1, 1, 0.8)

    frame.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    frame.count:SetPoint("BOTTOMRIGHT", -2, 2)

    frame.keybind = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    frame.keybind:SetPoint("TOPLEFT", 2, -2)

    return frame
end

function utils:ApplyGlow(frame, color, intensity)
    if not frame.glowFrame then
        frame.glowFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.glowFrame:SetPoint("TOPLEFT", -4, 4)
        frame.glowFrame:SetPoint("BOTTOMRIGHT", 4, -4)
        frame.glowFrame:SetFrameLevel(frame:GetFrameLevel() - 1)
    end

    color = color or { 1, 1, 0 }
    intensity = intensity or 0.8

    if ActionButton_ShowOverlayGlow then
        ActionButton_ShowOverlayGlow(frame)
    else
        frame.glowFrame:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
        })
        frame.glowFrame:SetBackdropBorderColor(color[1], color[2], color[3], intensity)
    end
end

function utils:RemoveGlow(frame)
    if ActionButton_HideOverlayGlow then
        ActionButton_HideOverlayGlow(frame)
    elseif frame.glowFrame then
        frame.glowFrame:SetBackdrop(nil)
    end
end

function utils:FadeIn(frame, duration)
    duration = duration or 0.2
    if frame.fadeAnim then
        frame.fadeAnim:Stop()
    end
    frame:Show()
    frame:SetAlpha(0)

    local group = frame:CreateAnimationGroup()
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(duration)
    fade:SetSmoothing("OUT")

    group:SetScript("OnFinished", function()
        frame:SetAlpha(1)
    end)

    frame.fadeAnim = group
    group:Play()
end

function utils:FadeOut(frame, duration)
    duration = duration or 0.3
    if frame.fadeAnim then
        frame.fadeAnim:Stop()
    end

    local group = frame:CreateAnimationGroup()
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(frame:GetAlpha())
    fade:SetToAlpha(0)
    fade:SetDuration(duration)
    fade:SetSmoothing("OUT")

    group:SetScript("OnFinished", function()
        frame:Hide()
        frame:SetAlpha(1)
    end)

    frame.fadeAnim = group
    group:Play()
end

utils.debugMode = false

function utils:Debug(...)
    if self.debugMode then
        print("|cFF00FF00[TankAssist]|r", ...)
    end
end

function utils:SetDebug(enabled)
    self.debugMode = enabled
end

function utils:PrintTable(t, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)
    for k, v in pairs(t) do
        if type(v) == "table" then
            print(prefix .. tostring(k) .. ":")
            self:PrintTable(v, indent + 1)
        else
            print(prefix .. tostring(k) .. " = " .. tostring(v))
        end
    end
end
