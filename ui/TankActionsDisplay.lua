-- TankAssist Tank Actions Display
-- Separate display for tank-specific cooldowns: mitigation, defensives, healing
-- These are abilities Blizzard's rotation helper won't recommend

local ADDON_NAME, TA = ...

TA.TankActionsDisplay = {}
local TAD = TA.TankActionsDisplay

-- =============================================================================
-- TANK ACTION CATEGORIES
-- =============================================================================

TAD.CATEGORIES = {
    MITIGATION = {
        name = "Active Mitigation",
        color = { 0.2, 0.6, 1.0 },  -- Blue
        order = 1,
    },
    SHIELD = {
        name = "Shield/Absorb",
        color = { 0.8, 0.6, 0.2 },  -- Gold
        order = 2,
    },
    DEFENSIVE = {
        name = "Major Defensive",
        color = { 1.0, 0.3, 0.3 },  -- Red
        order = 3,
    },
    HEAL = {
        name = "Self-Heal",
        color = { 0.2, 1.0, 0.4 },  -- Green
        order = 4,
    },
}

-- =============================================================================
-- DISPLAY FRAME
-- =============================================================================

function TAD:Create(parent)
    local settings = TA.Addon.db.profile.tankActions

    -- Main container
    self.frame = CreateFrame("Frame", "TankAssistTankActions", UIParent, "BackdropTemplate")
    self.frame:SetSize(settings.iconSize * 4 + 30, settings.iconSize + 20)
    self.frame:SetPoint(
        settings.position.point or "CENTER",
        UIParent,
        settings.position.relativePoint or "CENTER",
        settings.position.x or 0,
        settings.position.y or -280
    )

    -- Background
    self.frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    self.frame:SetBackdropColor(0, 0, 0, 0.6)
    self.frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    -- Make draggable when unlocked
    self.frame:SetMovable(true)
    self.frame:EnableMouse(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", function(frame)
        if not TA.Addon.db.profile.locked then
            frame:StartMoving()
        end
    end)
    self.frame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint()
        TA.Addon.db.profile.tankActions.position.point = point
        TA.Addon.db.profile.tankActions.position.relativePoint = relativePoint
        TA.Addon.db.profile.tankActions.position.x = x
        TA.Addon.db.profile.tankActions.position.y = y
    end)

    -- Title
    self.title = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.title:SetPoint("TOP", self.frame, "TOP", 0, -4)
    self.title:SetText("Tank Actions")
    self.title:SetTextColor(0.8, 0.8, 0.8)

    -- Icons container
    self.iconsContainer = CreateFrame("Frame", nil, self.frame)
    self.iconsContainer:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 10, -18)
    self.iconsContainer:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -10, 6)

    -- Create icons for each category
    self.icons = {}
    self:CreateCategoryIcons()

    return self.frame
end

function TAD:CreateCategoryIcons()
    local settings = TA.Addon.db.profile.tankActions
    local iconSize = settings.iconSize
    local spacing = 6
    local categories = { "MITIGATION", "SHIELD", "DEFENSIVE", "HEAL" }

    for i, category in ipairs(categories) do
        local icon = self:CreateIcon(self.iconsContainer, iconSize, category)
        icon:SetPoint("LEFT", self.iconsContainer, "LEFT", (i - 1) * (iconSize + spacing), 0)
        icon.category = category
        self.icons[category] = icon
    end
end

function TAD:CreateIcon(parent, size, category)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetSize(size, size)

    -- Background
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0, 0, 0, 0.5)

    -- Icon texture
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", 2, -2)
    frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Cooldown overlay
    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints(frame.icon)
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetHideCountdownNumbers(false)

    -- GCD overlay
    frame.gcdCooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.gcdCooldown:SetAllPoints(frame.icon)
    frame.gcdCooldown:SetDrawEdge(true)
    frame.gcdCooldown:SetDrawSwipe(true)
    frame.gcdCooldown:SetSwipeColor(1, 1, 1, 0.4)
    frame.gcdCooldown:SetHideCountdownNumbers(true)
    frame.gcdCooldown:SetFrameLevel(frame.cooldown:GetFrameLevel() + 1)

    -- Border (color based on category)
    frame.border = frame:CreateTexture(nil, "OVERLAY")
    frame.border:SetPoint("TOPLEFT", -1, 1)
    frame.border:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.border:SetBlendMode("ADD")

    local catColor = self.CATEGORIES[category] and self.CATEGORIES[category].color or { 1, 1, 1 }
    frame.border:SetVertexColor(catColor[1], catColor[2], catColor[3], 0.8)

    -- Keybind text
    frame.keybind = frame:CreateFontString(nil, "OVERLAY")
    frame.keybind:SetFont("Fonts\\FRIZQT__.TTF", size > 40 and 11 or 9, "OUTLINE")
    frame.keybind:SetPoint("TOPLEFT", 2, -2)
    frame.keybind:SetTextColor(1, 1, 1, 1)

    -- Charges/stacks text
    frame.count = frame:CreateFontString(nil, "OVERLAY")
    frame.count:SetFont("Fonts\\FRIZQT__.TTF", size > 40 and 12 or 10, "OUTLINE")
    frame.count:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.count:SetTextColor(1, 1, 1, 1)

    -- Unusable overlay
    frame.unusable = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    frame.unusable:SetAllPoints(frame.icon)
    frame.unusable:SetColorTexture(0.1, 0.1, 0.1, 0.7)
    frame.unusable:Hide()

    -- Highlight glow (for recommended)
    frame.glow = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    frame.glow:SetPoint("TOPLEFT", -4, 4)
    frame.glow:SetPoint("BOTTOMRIGHT", 4, -4)
    frame.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.glow:SetBlendMode("ADD")
    frame.glow:SetVertexColor(1, 1, 0, 0.8)
    frame.glow:Hide()

    -- Tooltip
    frame:SetScript("OnEnter", function(self)
        if self.spellId then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellId)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    frame.spellId = nil
    return frame
end

-- =============================================================================
-- UPDATE LOGIC
-- =============================================================================

function TAD:Update()
    if not self.frame then return end

    local settings = TA.Addon.db.profile.tankActions

    -- Check visibility setting
    if not settings.enabled then
        self.frame:Hide()
        return
    end

    if settings.showMode == "combat" and not TA.SecretValues:InCombat() then
        self.frame:Hide()
        return
    end

    self.frame:Show()

    -- Get the active spec module's tank actions
    local specModule = TA.Addon.activeSpecModule
    if not specModule or not specModule.tankActions then
        self:ClearAllIcons()
        return
    end

    -- Update each category icon
    for category, icon in pairs(self.icons) do
        local actionData = specModule.tankActions[category]
        if actionData and actionData.spellId then
            self:UpdateIcon(icon, actionData)
        else
            self:ClearIcon(icon)
        end
    end
end

function TAD:UpdateIcon(icon, actionData)
    local spellId = actionData.spellId
    icon.spellId = spellId

    -- Get spell info
    local spellInfo = C_Spell.GetSpellInfo(spellId)
    if not spellInfo then
        self:ClearIcon(icon)
        return
    end

    icon.icon:SetTexture(spellInfo.iconID)
    icon:Show()

    -- Keybind
    local keybind = TA.Utils:GetSpellKeybind(spellId)
    icon.keybind:SetText(TA.Utils:FormatKeybind(keybind) or "")

    -- Cooldown
    local cdInfo = TA.SecretValues:GetCooldownInfo(spellId)
    if cdInfo.onCooldown and cdInfo.remaining and cdInfo.remaining > 1.5 then
        local cdStart = GetTime() - cdInfo.remaining
        icon.cooldown:SetCooldown(cdStart, cdInfo.remaining + (GetTime() - cdStart))
        icon.unusable:Show()
        icon.glow:Hide()
    else
        icon.cooldown:Clear()
        icon.unusable:Hide()
    end

    -- GCD
    local gcdInfo = C_Spell.GetSpellCooldown(61304)
    if gcdInfo and gcdInfo.startTime and gcdInfo.duration and gcdInfo.duration > 0 then
        icon.gcdCooldown:SetCooldown(gcdInfo.startTime, gcdInfo.duration)
    else
        icon.gcdCooldown:Clear()
    end

    -- Charges
    if cdInfo.charges and cdInfo.maxCharges and cdInfo.maxCharges > 1 then
        icon.count:SetText(cdInfo.charges)
        -- Show as usable if has charges
        if cdInfo.charges > 0 then
            icon.unusable:Hide()
        end
    else
        icon.count:SetText("")
    end

    -- Highlight if recommended (check condition)
    local shouldHighlight = false
    if actionData.condition then
        shouldHighlight = actionData.condition()
    end

    if shouldHighlight and not cdInfo.onCooldown then
        icon.glow:Show()
        icon.border:SetVertexColor(1, 1, 0, 1) -- Yellow highlight
    else
        icon.glow:Hide()
        local catColor = self.CATEGORIES[icon.category].color
        icon.border:SetVertexColor(catColor[1], catColor[2], catColor[3], 0.8)
    end
end

function TAD:ClearIcon(icon)
    icon.spellId = nil
    icon.icon:SetTexture(nil)
    icon.keybind:SetText("")
    icon.count:SetText("")
    icon.cooldown:Clear()
    icon.gcdCooldown:Clear()
    icon.unusable:Hide()
    icon.glow:Hide()
end

function TAD:ClearAllIcons()
    for _, icon in pairs(self.icons) do
        self:ClearIcon(icon)
    end
end

-- =============================================================================
-- PUBLIC INTERFACE
-- =============================================================================

function TAD:Show()
    if self.frame then
        self.frame:Show()
    end
end

function TAD:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function TAD:SetScale(scale)
    if self.frame then
        self.frame:SetScale(scale)
    end
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

local function Initialize()
    if TA.Addon.mainFrame then
        TA.Addon.tankActionsDisplay = TAD
        TAD:Create(TA.Addon.mainFrame)
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.6, Initialize)
end)
