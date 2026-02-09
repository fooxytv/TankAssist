-- TankAssist Utilities
-- Helper functions used throughout the addon

local ADDON_NAME, TA = ...
TA.Utils = {}

local Utils = TA.Utils

-- =============================================================================
-- TABLE UTILITIES
-- =============================================================================

-- Deep copy a table
function Utils:DeepCopy(orig)
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

-- Check if table contains value
function Utils:Contains(table, value)
    for _, v in pairs(table) do
        if v == value then
            return true
        end
    end
    return false
end

-- Get table length (for non-sequential tables)
function Utils:TableLength(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

-- Merge tables (second overwrites first)
function Utils:MergeTables(t1, t2)
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

-- =============================================================================
-- STRING UTILITIES
-- =============================================================================

-- Format time duration
function Utils:FormatDuration(seconds)
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

-- Format percentage
function Utils:FormatPercent(value)
    if not value then
        return "?"
    end
    return string.format("%.0f%%", value * 100)
end

-- Truncate string with ellipsis
function Utils:Truncate(str, maxLen)
    if #str <= maxLen then
        return str
    end
    return string.sub(str, 1, maxLen - 3) .. "..."
end

-- =============================================================================
-- SPELL UTILITIES
-- =============================================================================

-- Get spell info with caching
Utils.spellCache = {}
Utils.keybindCache = {}
Utils.keybindCacheTime = 0
Utils.KEYBIND_CACHE_DURATION = 5 -- Refresh keybind cache every 5 seconds

function Utils:GetSpellInfo(spellId)
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

-- Get keybind for spell (with caching)
function Utils:GetSpellKeybind(spellId)
    -- Check cache first
    local now = GetTime()
    if now - self.keybindCacheTime < self.KEYBIND_CACHE_DURATION then
        local cached = self.keybindCache[spellId]
        if cached ~= nil then
            -- Return cached value (false means "no keybind found")
            return cached ~= false and cached or nil
        end
    else
        -- Cache expired, clear it
        self.keybindCache = {}
        self.keybindCacheTime = now
    end

    local spellInfo = C_Spell.GetSpellInfo(spellId)
    local name = spellInfo and spellInfo.name
    if not name then
        self.keybindCache[spellId] = false
        return nil
    end

    -- Action bar slot ranges and their binding prefixes
    -- Main Action Bar pages use ACTIONBUTTON1-12 bindings
    -- Other bars use MULTIACTIONBAR bindings
    -- Note: The main bar can have multiple "pages" based on stance/form,
    -- but the bindings always refer to ACTIONBUTTON1-12 for the visible bar
    --
    -- IMPORTANT: MULTIACTIONBAR entries must come BEFORE ACTIONBUTTON entries
    -- for shared slot ranges (25-72), because those slots are more commonly
    -- used as visible multi-action bars rather than hidden bonus bar pages.
    local barMappings = {
        -- Main Action Bar Page 1 (default bar, always check first)
        { start = 1, prefix = "ACTIONBUTTON" },      -- Page 1 (default)

        -- Multi Action Bars (check BEFORE bonus bar pages since these are visible bars)
        { start = 61, prefix = "MULTIACTIONBAR1BUTTON" },   -- Bar 2 (Bottom Left)
        { start = 49, prefix = "MULTIACTIONBAR2BUTTON" },   -- Bar 3 (Bottom Right)
        { start = 25, prefix = "MULTIACTIONBAR3BUTTON" },   -- Bar 4 (Right)
        { start = 37, prefix = "MULTIACTIONBAR4BUTTON" },   -- Bar 5 (Right 2)
        { start = 145, prefix = "MULTIACTIONBAR5BUTTON" },  -- Bar 6
        { start = 157, prefix = "MULTIACTIONBAR6BUTTON" },  -- Bar 7
        { start = 169, prefix = "MULTIACTIONBAR7BUTTON" },  -- Bar 8

        -- Bonus bar pages (check AFTER multi-action bars)
        -- These are hidden bar pages that share slot ranges with multi-action bars
        { start = 13, prefix = "ACTIONBUTTON" },     -- Page 2 (bonus bar / stance)
        { start = 25, prefix = "ACTIONBUTTON" },     -- Page 3 (bonus bar / stance)
        { start = 37, prefix = "ACTIONBUTTON" },     -- Page 4 (bonus bar / stance)
        { start = 49, prefix = "ACTIONBUTTON" },     -- Page 5 (bonus bar / stance)
        { start = 61, prefix = "ACTIONBUTTON" },     -- Page 6 (bonus bar / stance)
        { start = 73, prefix = "ACTIONBUTTON" },     -- Bonus bar page
        { start = 85, prefix = "ACTIONBUTTON" },     -- Bonus bar page
        { start = 97, prefix = "ACTIONBUTTON" },     -- Bonus bar page
        { start = 109, prefix = "ACTIONBUTTON" },    -- Bonus bar page
        { start = 121, prefix = "ACTIONBUTTON" },    -- Bonus bar page
        { start = 133, prefix = "ACTIONBUTTON" },    -- Bonus bar page
    }

    -- Helper function to check if a spell matches
    local function checkSpellMatch(actionType, id)
        if actionType == "spell" then
            if id == spellId then
                return true
            end
            -- Check if it's the same spell by name (handles spell rank differences)
            local slotSpellInfo = id and C_Spell.GetSpellInfo(id)
            if slotSpellInfo and slotSpellInfo.name == name then
                return true
            end
        elseif actionType == "macro" then
            -- Check if macro contains this spell
            local macroSpell, _ = GetMacroSpell(id)
            if macroSpell then
                -- macroSpell can be spell ID or name
                if macroSpell == spellId or macroSpell == name then
                    return true
                end
                -- If it returned a different ID, check by name
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

    -- Search all action bar slots for this spell
    for slot = 1, 180 do
        local actionType, id = GetActionInfo(slot)

        if checkSpellMatch(actionType, id) then
            -- Find which bar this slot belongs to and get the binding
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

    -- Check for direct spell binding (bound directly to spell, not action bar)
    local key = GetBindingKey("SPELL " .. name)
    if key then
        self.keybindCache[spellId] = key
        return key
    end

    -- Also try with spell ID directly
    key = GetBindingKey("SPELL " .. spellId)
    if key then
        self.keybindCache[spellId] = key
        return key
    end

    -- No keybind found, cache this result too
    self.keybindCache[spellId] = false
    return nil
end

-- Clear keybind cache (call when bindings change)
function Utils:ClearKeybindCache()
    self.keybindCache = {}
    self.keybindCacheTime = 0
end

-- Format keybind for display
function Utils:FormatKeybind(key)
    if not key then return "" end
    
    -- Shorten common modifiers
    key = key:gsub("SHIFT%-", "S-")
    key = key:gsub("CTRL%-", "C-")
    key = key:gsub("ALT%-", "A-")
    key = key:gsub("BUTTON", "M")
    key = key:gsub("MOUSEWHEELUP", "WU")
    key = key:gsub("MOUSEWHEELDOWN", "WD")
    
    return key
end

-- =============================================================================
-- SPEC DETECTION
-- =============================================================================

function Utils:GetCurrentSpec()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    
    local specId = GetSpecializationInfo(specIndex)
    return specId
end

function Utils:IsTankSpec(specId)
    specId = specId or self:GetCurrentSpec()
    if not specId then return false end
    
    local tankSpecs = {
        [250] = true,   -- Blood DK
        [268] = true,   -- Brewmaster
        [73] = true,    -- Protection Warrior
        [66] = true,    -- Protection Paladin
        [581] = true,   -- Vengeance DH
        [104] = true,   -- Guardian Druid
    }
    
    return tankSpecs[specId] == true
end

function Utils:GetSpecName(specId)
    if TA.Constants and TA.Constants.SPEC_NAMES then
        return TA.Constants.SPEC_NAMES[specId] or "Unknown"
    end
    return "Unknown"
end

-- =============================================================================
-- FRAME UTILITIES
-- =============================================================================

-- Create a simple icon frame
function Utils:CreateIcon(parent, size, template)
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

-- Apply glow effect to frame
function Utils:ApplyGlow(frame, color, intensity)
    if not frame.glowFrame then
        frame.glowFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.glowFrame:SetPoint("TOPLEFT", -4, 4)
        frame.glowFrame:SetPoint("BOTTOMRIGHT", 4, -4)
        frame.glowFrame:SetFrameLevel(frame:GetFrameLevel() - 1)
    end
    
    color = color or { 1, 1, 0 }
    intensity = intensity or 0.8
    
    -- Use built-in glow if available
    if ActionButton_ShowOverlayGlow then
        ActionButton_ShowOverlayGlow(frame)
    else
        -- Simple colored border as fallback
        frame.glowFrame:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
        })
        frame.glowFrame:SetBackdropBorderColor(color[1], color[2], color[3], intensity)
    end
end

-- Remove glow effect
function Utils:RemoveGlow(frame)
    if ActionButton_HideOverlayGlow then
        ActionButton_HideOverlayGlow(frame)
    elseif frame.glowFrame then
        frame.glowFrame:SetBackdrop(nil)
    end
end

-- =============================================================================
-- ANIMATION UTILITIES
-- =============================================================================

-- Simple fade animation
function Utils:FadeIn(frame, duration)
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

function Utils:FadeOut(frame, duration)
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

-- =============================================================================
-- DEBUG/LOGGING
-- =============================================================================

Utils.debugMode = false

function Utils:Debug(...)
    if self.debugMode then
        print("|cFF00FF00[TankAssist]|r", ...)
    end
end

function Utils:SetDebug(enabled)
    self.debugMode = enabled
end

function Utils:PrintTable(t, indent)
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
