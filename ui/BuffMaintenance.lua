-- TankAssist Buff Maintenance Display
-- Tracks tank-specific maintenance buffs (Bone Shield, Shuffle, Ironfur, etc.)

local ADDON_NAME, TA = ...

TA.BuffMaintenance = {}
local BM = TA.BuffMaintenance

-- =============================================================================
-- BUFF TRACKING DATA STRUCTURE
-- =============================================================================

--[[
    Each tracked buff should have this structure:
    {
        spellId = 195181,           -- Spell ID of the buff
        name = "Bone Shield",       -- Display name
        refreshSpell = 195182,      -- Spell that refreshes this buff (optional)
        minStacks = 5,              -- Minimum desired stacks (optional)
        maxStacks = 10,             -- Maximum stacks (optional)
        refreshThreshold = 3,       -- Refresh when < this many seconds remain
        priority = "CRITICAL",      -- CRITICAL, HIGH, NORMAL
        resourceType = nil,         -- Resource to show (RUNIC_POWER, RAGE, etc.)
        resourceCost = nil,         -- Cost of the refresh spell
    }
]]

-- =============================================================================
-- DISPLAY CREATION
-- =============================================================================

function BM:Create(parent)
    local settings = TA.Addon.db.profile.buffMaintenance
    
    -- Main container
    self.frame = CreateFrame("Frame", "TankAssistBuffMaintenance", parent)
    self.frame:SetSize(400, settings.iconSize + 20)
    self.frame:SetPoint("TOP", parent, "TOP", 0, -100)
    
    -- Title
    self.title = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.title:SetPoint("TOP", self.frame, "TOP", 0, 0)
    self.title:SetText("Maintenance Buffs")
    self.title:SetTextColor(0.8, 0.8, 0.8, 1)
    
    -- Icons container
    self.iconsContainer = CreateFrame("Frame", nil, self.frame)
    self.iconsContainer:SetPoint("TOP", self.title, "BOTTOM", 0, -4)
    self.iconsContainer:SetSize(400, settings.iconSize)
    
    -- Storage for buff icons
    self.buffIcons = {}
    self.trackedBuffs = {}
    
    return self.frame
end

function BM:CreateBuffIcon(index)
    local settings = TA.Addon.db.profile.buffMaintenance
    local size = settings.iconSize
    
    local frame = CreateFrame("Frame", nil, self.iconsContainer)
    frame:SetSize(size + 40, size) -- Extra width for text
    
    -- Icon
    frame.icon = CreateFrame("Frame", nil, frame)
    frame.icon:SetSize(size, size)
    frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
    
    -- Icon texture
    frame.icon.texture = frame.icon:CreateTexture(nil, "ARTWORK")
    frame.icon.texture:SetPoint("TOPLEFT", 2, -2)
    frame.icon.texture:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    
    -- Background
    frame.icon.bg = frame.icon:CreateTexture(nil, "BACKGROUND")
    frame.icon.bg:SetAllPoints()
    frame.icon.bg:SetColorTexture(0, 0, 0, 0.6)
    
    -- Border (changes color based on status)
    frame.icon.border = frame.icon:CreateTexture(nil, "OVERLAY")
    frame.icon.border:SetPoint("TOPLEFT", -1, 1)
    frame.icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.icon.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.icon.border:SetBlendMode("ADD")
    
    -- Stack text
    frame.stacks = frame.icon:CreateFontString(nil, "OVERLAY")
    frame.stacks:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    frame.stacks:SetPoint("CENTER", frame.icon, "CENTER", 0, 0)
    frame.stacks:SetTextColor(1, 1, 1, 1)
    
    -- Timer bar
    frame.timerBar = CreateFrame("StatusBar", nil, frame)
    frame.timerBar:SetSize(size, 4)
    frame.timerBar:SetPoint("TOP", frame.icon, "BOTTOM", 0, -2)
    frame.timerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame.timerBar:SetMinMaxValues(0, 1)
    
    frame.timerBar.bg = frame.timerBar:CreateTexture(nil, "BACKGROUND")
    frame.timerBar.bg:SetAllPoints()
    frame.timerBar.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    
    -- Timer text
    frame.timer = frame:CreateFontString(nil, "OVERLAY")
    frame.timer:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    frame.timer:SetPoint("LEFT", frame.icon, "RIGHT", 4, 0)
    frame.timer:SetTextColor(1, 1, 1, 1)
    
    -- Status indicator (shows UP, LOW, DOWN)
    frame.status = frame:CreateFontString(nil, "OVERLAY")
    frame.status:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    frame.status:SetPoint("TOP", frame.timer, "BOTTOM", 0, -2)
    
    -- Tooltip
    frame.icon:SetScript("OnEnter", function(self)
        if frame.buffData and frame.buffData.spellId then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(frame.buffData.spellId)
            if frame.buffData.refreshSpell then
                GameTooltip:AddLine(" ")
                local refreshSpellInfo = C_Spell.GetSpellInfo(frame.buffData.refreshSpell)
                local refreshName = refreshSpellInfo and refreshSpellInfo.name
                GameTooltip:AddLine("Refresh with: " .. (refreshName or "Unknown"), 0.5, 0.8, 1)
            end
            GameTooltip:Show()
        end
    end)
    frame.icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    frame:EnableMouse(true)
    frame.icon:EnableMouse(true)
    
    return frame
end

-- =============================================================================
-- BUFF CONFIGURATION
-- =============================================================================

function BM:SetBuffs(buffs)
    self.trackedBuffs = buffs or {}
    
    -- Create/update icons for each tracked buff
    local settings = TA.Addon.db.profile.buffMaintenance
    local iconWidth = settings.iconSize + 50
    local totalWidth = #self.trackedBuffs * iconWidth
    local startX = -totalWidth / 2 + iconWidth / 2
    
    for i, buffData in ipairs(self.trackedBuffs) do
        if not self.buffIcons[i] then
            self.buffIcons[i] = self:CreateBuffIcon(i)
        end
        
        local icon = self.buffIcons[i]
        icon.buffData = buffData
        icon:SetPoint("LEFT", self.iconsContainer, "CENTER", startX + (i - 1) * iconWidth, 0)
        icon:Show()
        
        -- Set initial icon texture
        local spellInfo = C_Spell.GetSpellInfo(buffData.spellId)
        local spellIcon = spellInfo and spellInfo.iconID
        if spellIcon then
            icon.icon.texture:SetTexture(spellIcon)
        end
    end
    
    -- Hide unused icons
    for i = #self.trackedBuffs + 1, #self.buffIcons do
        self.buffIcons[i]:Hide()
    end
end

-- =============================================================================
-- UPDATE LOGIC
-- =============================================================================

function BM:Update()
    if not self.frame or not self.frame:IsShown() then return end
    
    for i, buffData in ipairs(self.trackedBuffs) do
        local icon = self.buffIcons[i]
        if icon then
            self:UpdateBuffIcon(icon, buffData)
        end
    end
end

function BM:UpdateBuffIcon(icon, buffData)
    local info = TA.SecretValues:GetBuffInfo("player", buffData.spellId)
    local colors = TA.Constants.DISPLAY.COLORS

    if info.isSecret then
        -- Data is secret (M+ or restricted) - show unknown state
        self:SetIconState(icon, "UNKNOWN", buffData)
        return
    end

    if not info.exists then
        -- Buff is DOWN
        self:SetIconState(icon, "DOWN", buffData)
        return
    end

    -- Special handling for absorb shields (Blood Shield, Ignore Pain, etc.)
    -- We can only track existence, not the actual absorb amount
    if buffData.isAbsorb then
        self:SetIconState(icon, "ABSORB_ACTIVE", buffData)
        return
    end

    -- Buff exists - check status
    local remaining = (info.expirationTime or 0) - GetTime()
    local stacks = info.stacks or 0

    -- Update visual elements
    icon.stacks:SetText(stacks > 0 and stacks or "")

    -- Timer display
    if remaining > 0 then
        icon.timer:SetText(TA.Utils:FormatDuration(remaining))
        icon.timerBar:SetValue(remaining / (info.duration or remaining))
    else
        icon.timer:SetText("")
        icon.timerBar:SetValue(0)
    end

    -- Determine state based on thresholds
    local needsRefresh = false
    local isLow = false

    -- Check stack threshold
    if buffData.minStacks and stacks < buffData.minStacks then
        needsRefresh = true
        isLow = true
    end

    -- Check time threshold
    local refreshThreshold = buffData.refreshThreshold or TA.Addon.db.profile.buffMaintenance.warningThreshold
    if remaining < refreshThreshold then
        needsRefresh = true
    end

    if needsRefresh then
        if isLow then
            self:SetIconState(icon, "LOW_STACKS", buffData, stacks, remaining)
        else
            self:SetIconState(icon, "EXPIRING", buffData, stacks, remaining)
        end
    else
        self:SetIconState(icon, "ACTIVE", buffData, stacks, remaining)
    end
end

function BM:SetIconState(icon, state, buffData, stacks, remaining)
    local colors = TA.Constants.DISPLAY.COLORS
    
    if state == "DOWN" then
        -- Buff not active - urgent
        icon.icon.texture:SetDesaturated(true)
        icon.icon.border:SetVertexColor(unpack(colors.URGENT))
        icon.status:SetText("DOWN")
        icon.status:SetTextColor(unpack(colors.URGENT))
        icon.timerBar:SetStatusBarColor(unpack(colors.URGENT))
        icon.timerBar:SetValue(0)
        icon.timer:SetText("")
        icon.stacks:SetText("")
        TA.Utils:ApplyGlow(icon.icon, colors.URGENT)
        
    elseif state == "LOW_STACKS" then
        -- Stacks too low - urgent
        icon.icon.texture:SetDesaturated(false)
        icon.icon.border:SetVertexColor(unpack(colors.URGENT))
        icon.status:SetText(string.format("%d/%d", stacks, buffData.minStacks))
        icon.status:SetTextColor(unpack(colors.URGENT))
        icon.timerBar:SetStatusBarColor(unpack(colors.HIGH))
        TA.Utils:ApplyGlow(icon.icon, colors.URGENT)
        
    elseif state == "EXPIRING" then
        -- About to expire - warning
        icon.icon.texture:SetDesaturated(false)
        icon.icon.border:SetVertexColor(unpack(colors.BUFF_EXPIRING))
        icon.status:SetText("EXPIRING")
        icon.status:SetTextColor(unpack(colors.BUFF_EXPIRING))
        icon.timerBar:SetStatusBarColor(unpack(colors.BUFF_EXPIRING))
        TA.Utils:ApplyGlow(icon.icon, colors.BUFF_EXPIRING)
        
    elseif state == "ACTIVE" then
        -- Buff is healthy
        icon.icon.texture:SetDesaturated(false)
        icon.icon.border:SetVertexColor(unpack(colors.BUFF_ACTIVE))
        icon.status:SetText("")
        icon.timerBar:SetStatusBarColor(unpack(colors.BUFF_ACTIVE))
        TA.Utils:RemoveGlow(icon.icon)

    elseif state == "ABSORB_ACTIVE" then
        -- Absorb shield is active (amount is secret/unknown)
        -- Show a shield indicator since we can't display the actual value
        icon.icon.texture:SetDesaturated(false)
        icon.icon.border:SetVertexColor(unpack(colors.BUFF_ACTIVE))
        icon.stacks:SetText("")
        icon.status:SetText("SHIELD")
        icon.status:SetTextColor(0.4, 0.8, 1, 1) -- Light blue for absorb
        icon.timer:SetText("")
        icon.timerBar:SetValue(1) -- Full bar since we don't know remaining amount
        icon.timerBar:SetStatusBarColor(0.4, 0.8, 1, 1) -- Light blue
        TA.Utils:RemoveGlow(icon.icon)

    elseif state == "UNKNOWN" then
        -- Can't determine state (secrets)
        icon.icon.texture:SetDesaturated(true)
        icon.icon.border:SetVertexColor(0.5, 0.5, 0.5, 1)
        icon.status:SetText("?")
        icon.status:SetTextColor(0.7, 0.7, 0.7, 1)
        icon.timer:SetText("")
        icon.timerBar:SetValue(0.5)
        icon.timerBar:SetStatusBarColor(0.5, 0.5, 0.5, 1)
        TA.Utils:RemoveGlow(icon.icon)
    end
end

-- =============================================================================
-- PUBLIC INTERFACE
-- =============================================================================

function BM:Show()
    if self.frame then
        self.frame:Show()
    end
end

function BM:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

local function Initialize()
    if TA.Addon.mainFrame then
        TA.Addon.buffMaintenance = BM
        BM:Create(TA.Addon.mainFrame)
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.6, Initialize)
end)
