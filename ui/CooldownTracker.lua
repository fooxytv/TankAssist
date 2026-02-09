-- TankAssist Cooldown Tracker
-- Tracks major defensive and offensive cooldowns

local ADDON_NAME, TA = ...

TA.CooldownTracker = {}
local CT = TA.CooldownTracker

-- =============================================================================
-- COOLDOWN CATEGORIES
-- =============================================================================

CT.CATEGORIES = {
    MAJOR = {
        name = "Major",
        color = { 0.9, 0.2, 0.9, 1 }, -- Purple
    },
    DEFENSIVE = {
        name = "Defensive",
        color = { 0.2, 0.6, 1, 1 }, -- Blue
    },
    OFFENSIVE = {
        name = "Offensive",
        color = { 1, 0.4, 0.2, 1 }, -- Orange
    },
}

-- =============================================================================
-- DISPLAY CREATION
-- =============================================================================

function CT:Create(parent)
    local settings = TA.Addon.db.profile.cooldowns
    
    -- Main container
    self.frame = CreateFrame("Frame", "TankAssistCooldownTracker", parent)
    self.frame:SetSize(400, settings.iconSize + 30)
    self.frame:SetPoint("TOP", parent, "TOP", 0, -160)
    
    -- Title
    self.title = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.title:SetPoint("TOP", self.frame, "TOP", 0, 0)
    self.title:SetText("Cooldowns")
    self.title:SetTextColor(0.8, 0.8, 0.8, 1)
    
    -- Icons container
    self.iconsContainer = CreateFrame("Frame", nil, self.frame)
    self.iconsContainer:SetPoint("TOP", self.title, "BOTTOM", 0, -4)
    self.iconsContainer:SetSize(400, settings.iconSize)
    
    -- Storage for cooldown icons
    self.cooldownIcons = {}
    self.trackedCooldowns = {}
    
    return self.frame
end

function CT:CreateCooldownIcon(index)
    local settings = TA.Addon.db.profile.cooldowns
    local size = settings.iconSize
    
    local frame = CreateFrame("Frame", nil, self.iconsContainer)
    frame:SetSize(size, size + 15) -- Extra height for timer
    
    -- Icon container
    frame.icon = CreateFrame("Frame", nil, frame)
    frame.icon:SetSize(size, size)
    frame.icon:SetPoint("TOP", frame, "TOP", 0, 0)
    
    -- Background
    frame.icon.bg = frame.icon:CreateTexture(nil, "BACKGROUND")
    frame.icon.bg:SetAllPoints()
    frame.icon.bg:SetColorTexture(0, 0, 0, 0.6)
    
    -- Icon texture
    frame.icon.texture = frame.icon:CreateTexture(nil, "ARTWORK")
    frame.icon.texture:SetPoint("TOPLEFT", 2, -2)
    frame.icon.texture:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    
    -- Cooldown swipe
    frame.cooldown = CreateFrame("Cooldown", nil, frame.icon, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints(frame.icon.texture)
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetHideCountdownNumbers(true) -- We show our own
    
    -- Border (colored by category)
    frame.icon.border = frame.icon:CreateTexture(nil, "OVERLAY")
    frame.icon.border:SetPoint("TOPLEFT", -1, 1)
    frame.icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.icon.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.icon.border:SetBlendMode("ADD")
    
    -- Charges text
    frame.charges = frame.icon:CreateFontString(nil, "OVERLAY")
    frame.charges:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    frame.charges:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", -2, 2)
    frame.charges:SetTextColor(1, 1, 1, 1)
    
    -- Keybind text
    frame.keybind = frame.icon:CreateFontString(nil, "OVERLAY")
    frame.keybind:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    frame.keybind:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", 2, -2)
    frame.keybind:SetTextColor(1, 1, 0.8, 1)
    
    -- Timer text (below icon)
    frame.timer = frame:CreateFontString(nil, "OVERLAY")
    frame.timer:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    frame.timer:SetPoint("TOP", frame.icon, "BOTTOM", 0, -2)
    frame.timer:SetTextColor(1, 1, 1, 1)
    
    -- Ready flash overlay
    frame.readyFlash = frame.icon:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.readyFlash:SetAllPoints()
    frame.readyFlash:SetTexture("Interface\\Cooldown\\star4")
    frame.readyFlash:SetBlendMode("ADD")
    frame.readyFlash:SetAlpha(0)
    
    -- Tooltip
    frame.icon:SetScript("OnEnter", function(self)
        if frame.cdData and frame.cdData.spellId then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(frame.cdData.spellId)
            GameTooltip:Show()
        end
    end)
    frame.icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    frame:EnableMouse(true)
    frame.icon:EnableMouse(true)
    
    -- Animation for ready state
    frame.readyAnim = frame.readyFlash:CreateAnimationGroup()
    local fadeIn = frame.readyAnim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(0.8)
    fadeIn:SetDuration(0.3)
    fadeIn:SetOrder(1)
    local fadeOut = frame.readyAnim:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(0.8)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.5)
    fadeOut:SetOrder(2)
    
    return frame
end

-- =============================================================================
-- COOLDOWN CONFIGURATION
-- =============================================================================

function CT:SetCooldowns(cooldowns)
    self.trackedCooldowns = cooldowns or {}
    
    local settings = TA.Addon.db.profile.cooldowns
    local iconSize = settings.iconSize
    local spacing = 6
    
    -- Group cooldowns by category for display
    local grouped = {
        MAJOR = {},
        DEFENSIVE = {},
        OFFENSIVE = {},
    }
    
    for _, cd in ipairs(self.trackedCooldowns) do
        local category = cd.category or "DEFENSIVE"
        table.insert(grouped[category], cd)
    end
    
    -- Build display order based on settings
    local displayOrder = {}
    if settings.showMajor then
        for _, cd in ipairs(grouped.MAJOR) do table.insert(displayOrder, cd) end
    end
    if settings.showDefensive then
        for _, cd in ipairs(grouped.DEFENSIVE) do table.insert(displayOrder, cd) end
    end
    if settings.showOffensive then
        for _, cd in ipairs(grouped.OFFENSIVE) do table.insert(displayOrder, cd) end
    end
    
    -- Calculate total width and starting position
    local totalWidth = #displayOrder * (iconSize + spacing) - spacing
    local startX = -totalWidth / 2 + iconSize / 2
    
    -- Create/update icons
    for i, cdData in ipairs(displayOrder) do
        if not self.cooldownIcons[i] then
            self.cooldownIcons[i] = self:CreateCooldownIcon(i)
        end
        
        local icon = self.cooldownIcons[i]
        icon.cdData = cdData
        icon:SetPoint("LEFT", self.iconsContainer, "CENTER", startX + (i - 1) * (iconSize + spacing), 0)
        icon:Show()
        
        -- Set initial texture and border color
        local spellInfo = C_Spell.GetSpellInfo(cdData.spellId)
        local spellIcon = spellInfo and spellInfo.iconID
        if spellIcon then
            icon.icon.texture:SetTexture(spellIcon)
        end
        
        local categoryColor = self.CATEGORIES[cdData.category or "DEFENSIVE"].color
        icon.icon.border:SetVertexColor(unpack(categoryColor))
        
        -- Set keybind
        local keybind = TA.Utils:GetSpellKeybind(cdData.spellId)
        icon.keybind:SetText(TA.Utils:FormatKeybind(keybind) or "")
    end
    
    -- Hide unused icons
    for i = #displayOrder + 1, #self.cooldownIcons do
        self.cooldownIcons[i]:Hide()
    end
end

-- =============================================================================
-- UPDATE LOGIC
-- =============================================================================

function CT:Update()
    if not self.frame or not self.frame:IsShown() then return end
    
    for i, icon in ipairs(self.cooldownIcons) do
        if icon:IsShown() and icon.cdData then
            self:UpdateCooldownIcon(icon)
        end
    end
end

function CT:UpdateCooldownIcon(icon)
    local cdData = icon.cdData
    local cdInfo = TA.SecretValues:GetCooldownInfo(cdData.spellId)
    
    if cdInfo.isSecret then
        -- Data is secret - show uncertain state
        icon.icon.texture:SetDesaturated(true)
        icon.timer:SetText("?")
        icon.charges:SetText("")
        icon.cooldown:Clear()
        return
    end
    
    -- Update charges
    if cdInfo.charges and cdInfo.maxCharges and cdInfo.maxCharges > 1 then
        icon.charges:SetText(cdInfo.charges)
        if cdInfo.charges > 0 then
            icon.icon.texture:SetDesaturated(false)
        else
            icon.icon.texture:SetDesaturated(true)
        end
    else
        icon.charges:SetText("")
        icon.icon.texture:SetDesaturated(cdInfo.onCooldown)
    end
    
    -- Update cooldown display
    if cdInfo.onCooldown and cdInfo.remaining > 0 then
        -- Calculate start time for the cooldown frame
        local start = GetTime() - (cdInfo.remaining > 0 and 0 or 0)
        -- For proper cooldown display, we need the original start time
        -- This is a workaround since we only have remaining time
        local duration = cdInfo.remaining + 0.1 -- Add small buffer
        icon.cooldown:SetCooldown(GetTime() - duration + cdInfo.remaining, duration)
        
        -- Format timer text
        if cdInfo.remaining > 60 then
            icon.timer:SetText(string.format("%d:%02d", math.floor(cdInfo.remaining / 60), math.floor(cdInfo.remaining % 60)))
        else
            icon.timer:SetText(string.format("%.1f", cdInfo.remaining))
        end
        icon.timer:SetTextColor(1, 0.3, 0.3, 1)
        
        -- Stop ready animation if running
        if icon.wasReady then
            icon.wasReady = false
        end
    else
        -- Ready
        icon.cooldown:Clear()
        icon.timer:SetText("READY")
        icon.timer:SetTextColor(0.3, 1, 0.3, 1)
        
        -- Play ready animation once when becoming ready
        if not icon.wasReady then
            icon.wasReady = true
            icon.readyAnim:Play()
            
            -- Optional sound
            if TA.Addon.db.profile.sounds.enabled and TA.Addon.db.profile.sounds.cooldownReady then
                -- PlaySoundFile(TA.Addon.db.profile.sounds.cooldownReady)
            end
        end
    end
end

-- =============================================================================
-- PUBLIC INTERFACE
-- =============================================================================

function CT:Show()
    if self.frame then
        self.frame:Show()
    end
end

function CT:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

local function Initialize()
    if TA.Addon.mainFrame then
        TA.Addon.cooldownTracker = CT
        CT:Create(TA.Addon.mainFrame)
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.7, Initialize)
end)
