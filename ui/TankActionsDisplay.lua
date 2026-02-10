local ADDON_NAME, TankAssist = ...

TankAssist.TankActionsDisplay = {}
local tad = TankAssist.TankActionsDisplay

tad.CATEGORIES = {
    MITIGATION = {
        name = "Active Mitigation",
        color = { 0.2, 0.6, 1.0 },
        order = 1,
    },
    SHIELD = {
        name = "Shield/Absorb",
        color = { 0.8, 0.6, 0.2 },
        order = 2,
    },
    DEFENSIVE = {
        name = "Major Defensive",
        color = { 1.0, 0.3, 0.3 },
        order = 3,
    },
    HEAL = {
        name = "Self-Heal",
        color = { 0.2, 1.0, 0.4 },
        order = 4,
    },
}

function tad:Create(parent)
    local settings = TankAssist.Addon.db.profile.tankActions

    self.frame = CreateFrame("Frame", "TankAssistTankActions", UIParent, "BackdropTemplate")
    self.frame:SetSize(settings.iconSize * 4 + 30, settings.iconSize + 20)
    self.frame:SetPoint(
        settings.position.point or "CENTER",
        UIParent,
        settings.position.relativePoint or "CENTER",
        settings.position.x or 0,
        settings.position.y or -280
    )

    self.frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    self.frame:SetBackdropColor(0, 0, 0, 0.6)
    self.frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    self.frame:SetMovable(true)
    self.frame:EnableMouse(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", function(frame)
        if not TankAssist.Addon.db.profile.locked then
            frame:StartMoving()
        end
    end)
    self.frame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint()
        TankAssist.Addon.db.profile.tankActions.position.point = point
        TankAssist.Addon.db.profile.tankActions.position.relativePoint = relativePoint
        TankAssist.Addon.db.profile.tankActions.position.x = x
        TankAssist.Addon.db.profile.tankActions.position.y = y
    end)

    self.title = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.title:SetPoint("TOP", self.frame, "TOP", 0, -4)
    self.title:SetText("Tank Actions")
    self.title:SetTextColor(0.8, 0.8, 0.8)

    self.iconsContainer = CreateFrame("Frame", nil, self.frame)
    self.iconsContainer:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 10, -18)
    self.iconsContainer:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -10, 6)

    self.icons = {}
    self:CreateCategoryIcons()

    return self.frame
end

function tad:CreateCategoryIcons()
    local settings = TankAssist.Addon.db.profile.tankActions
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

function tad:CreateIcon(parent, size, category)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetSize(size, size)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0, 0, 0, 0.5)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", 2, -2)
    frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints(frame.icon)
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetHideCountdownNumbers(false)

    frame.gcdCooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.gcdCooldown:SetAllPoints(frame.icon)
    frame.gcdCooldown:SetDrawEdge(true)
    frame.gcdCooldown:SetDrawSwipe(true)
    frame.gcdCooldown:SetSwipeColor(1, 1, 1, 0.4)
    frame.gcdCooldown:SetHideCountdownNumbers(true)
    frame.gcdCooldown:SetFrameLevel(frame.cooldown:GetFrameLevel() + 1)

    frame.border = frame:CreateTexture(nil, "OVERLAY")
    frame.border:SetPoint("TOPLEFT", -1, 1)
    frame.border:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.border:SetBlendMode("ADD")

    local catColor = self.CATEGORIES[category] and self.CATEGORIES[category].color or { 1, 1, 1 }
    frame.border:SetVertexColor(catColor[1], catColor[2], catColor[3], 0.8)

    frame.keybind = frame:CreateFontString(nil, "OVERLAY")
    frame.keybind:SetFont("Fonts\\FRIZQT__.TTF", size > 40 and 11 or 9, "OUTLINE")
    frame.keybind:SetPoint("TOPLEFT", 2, -2)
    frame.keybind:SetTextColor(1, 1, 1, 1)

    frame.count = frame:CreateFontString(nil, "OVERLAY")
    frame.count:SetFont("Fonts\\FRIZQT__.TTF", size > 40 and 12 or 10, "OUTLINE")
    frame.count:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.count:SetTextColor(1, 1, 1, 1)

    frame.unusable = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    frame.unusable:SetAllPoints(frame.icon)
    frame.unusable:SetColorTexture(0.1, 0.1, 0.1, 0.7)
    frame.unusable:Hide()

    frame.glow = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    frame.glow:SetPoint("TOPLEFT", -4, 4)
    frame.glow:SetPoint("BOTTOMRIGHT", 4, -4)
    frame.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.glow:SetBlendMode("ADD")
    frame.glow:SetVertexColor(1, 1, 0, 0.8)
    frame.glow:Hide()

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

function tad:Update()
    if not self.frame then return end

    local settings = TankAssist.Addon.db.profile.tankActions

    if not settings.enabled then
        self.frame:Hide()
        return
    end

    if settings.showMode == "combat" and not TankAssist.SecretValues:InCombat() then
        self.frame:Hide()
        return
    end

    self.frame:Show()

    local specModule = TankAssist.Addon.activeSpecModule
    if not specModule or not specModule.tankActions then
        self:ClearAllIcons()
        return
    end

    for category, icon in pairs(self.icons) do
        local actionData = specModule.tankActions[category]
        if actionData and actionData.spellId then
            self:UpdateIcon(icon, actionData)
        else
            self:ClearIcon(icon)
        end
    end
end

function tad:UpdateIcon(icon, actionData)
    local spellId = actionData.spellId
    icon.spellId = spellId

    local spellInfo = C_Spell.GetSpellInfo(spellId)
    if not spellInfo then
        self:ClearIcon(icon)
        return
    end

    icon.icon:SetTexture(spellInfo.iconID)
    icon:Show()

    local keybind = TankAssist.Utils:GetSpellKeybind(spellId)
    icon.keybind:SetText(TankAssist.Utils:FormatKeybind(keybind) or "")

    local cdInfo = TankAssist.SecretValues:GetCooldownInfo(spellId)
    if cdInfo.onCooldown and cdInfo.remaining and cdInfo.remaining > 1.5 then
        local cdStart = GetTime() - cdInfo.remaining
        icon.cooldown:SetCooldown(cdStart, cdInfo.remaining + (GetTime() - cdStart))
        icon.unusable:Show()
        icon.glow:Hide()
    else
        icon.cooldown:Clear()
        icon.unusable:Hide()
    end

    local gcdInfo = C_Spell.GetSpellCooldown(61304)
    if gcdInfo and gcdInfo.startTime and gcdInfo.duration and gcdInfo.duration > 0 then
        icon.gcdCooldown:SetCooldown(gcdInfo.startTime, gcdInfo.duration)
    else
        icon.gcdCooldown:Clear()
    end

    if cdInfo.charges and cdInfo.maxCharges and cdInfo.maxCharges > 1 then
        icon.count:SetText(cdInfo.charges)
        if cdInfo.charges > 0 then
            icon.unusable:Hide()
        end
    else
        icon.count:SetText("")
    end

    local shouldHighlight = false
    if actionData.condition then
        shouldHighlight = actionData.condition()
    end

    if shouldHighlight and not cdInfo.onCooldown then
        icon.glow:Show()
        icon.border:SetVertexColor(1, 1, 0, 1)
    else
        icon.glow:Hide()
        local catColor = self.CATEGORIES[icon.category].color
        icon.border:SetVertexColor(catColor[1], catColor[2], catColor[3], 0.8)
    end
end

function tad:ClearIcon(icon)
    icon.spellId = nil
    icon.icon:SetTexture(nil)
    icon.keybind:SetText("")
    icon.count:SetText("")
    icon.cooldown:Clear()
    icon.gcdCooldown:Clear()
    icon.unusable:Hide()
    icon.glow:Hide()
end

function tad:ClearAllIcons()
    for _, icon in pairs(self.icons) do
        self:ClearIcon(icon)
    end
end

function tad:Show()
    if self.frame then
        self.frame:Show()
    end
end

function tad:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function tad:SetScale(scale)
    if self.frame then
        self.frame:SetScale(scale)
    end
end

local function Initialize()
    if TankAssist.Addon.mainFrame then
        TankAssist.Addon.tankActionsDisplay = TAD
        tad:Create(TankAssist.Addon.mainFrame)
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.6, Initialize)
end)
