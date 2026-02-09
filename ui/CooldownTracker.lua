local ADDON_NAME, TankAssist = ...

TankAssist.CooldownTracker = {}
local ct = TankAssist.CooldownTracker

ct.CATEGORIES = {
    MAJOR = {
        name = "Major",
        color = { 0.9, 0.2, 0.9, 1 },
    },
    DEFENSIVE = {
        name = "Defensive",
        color = { 0.2, 0.6, 1, 1 },
    },
    OFFENSIVE = {
        name = "Offensive",
        color = { 1, 0.4, 0.2, 1 },
    },
}

function ct:Create(parent)
    local settings = TankAssist.Addon.db.profile.cooldowns

    self.frame = CreateFrame("Frame", "TankAssistCooldownTracker", parent)
    self.frame:SetSize(400, settings.iconSize + 30)
    self.frame:SetPoint("TOP", parent, "TOP", 0, -160)

    self.title = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.title:SetPoint("TOP", self.frame, "TOP", 0, 0)
    self.title:SetText("Cooldowns")
    self.title:SetTextColor(0.8, 0.8, 0.8, 1)

    self.iconsContainer = CreateFrame("Frame", nil, self.frame)
    self.iconsContainer:SetPoint("TOP", self.title, "BOTTOM", 0, -4)
    self.iconsContainer:SetSize(400, settings.iconSize)

    self.cooldownIcons = {}
    self.trackedCooldowns = {}

    return self.frame
end

function ct:CreateCooldownIcon(index)
    local settings = TankAssist.Addon.db.profile.cooldowns
    local size = settings.iconSize

    local frame = CreateFrame("Frame", nil, self.iconsContainer)
    frame:SetSize(size, size + 15)

    frame.icon = CreateFrame("Frame", nil, frame)
    frame.icon:SetSize(size, size)
    frame.icon:SetPoint("TOP", frame, "TOP", 0, 0)

    frame.icon.bg = frame.icon:CreateTexture(nil, "BACKGROUND")
    frame.icon.bg:SetAllPoints()
    frame.icon.bg:SetColorTexture(0, 0, 0, 0.6)

    frame.icon.texture = frame.icon:CreateTexture(nil, "ARTWORK")
    frame.icon.texture:SetPoint("TOPLEFT", 2, -2)
    frame.icon.texture:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.cooldown = CreateFrame("Cooldown", nil, frame.icon, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints(frame.icon.texture)
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetHideCountdownNumbers(true)

    frame.icon.border = frame.icon:CreateTexture(nil, "OVERLAY")
    frame.icon.border:SetPoint("TOPLEFT", -1, 1)
    frame.icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.icon.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.icon.border:SetBlendMode("ADD")

    frame.charges = frame.icon:CreateFontString(nil, "OVERLAY")
    frame.charges:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    frame.charges:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", -2, 2)
    frame.charges:SetTextColor(1, 1, 1, 1)

    frame.keybind = frame.icon:CreateFontString(nil, "OVERLAY")
    frame.keybind:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    frame.keybind:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", 2, -2)
    frame.keybind:SetTextColor(1, 1, 0.8, 1)

    frame.timer = frame:CreateFontString(nil, "OVERLAY")
    frame.timer:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    frame.timer:SetPoint("TOP", frame.icon, "BOTTOM", 0, -2)
    frame.timer:SetTextColor(1, 1, 1, 1)

    frame.readyFlash = frame.icon:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.readyFlash:SetAllPoints()
    frame.readyFlash:SetTexture("Interface\\Cooldown\\star4")
    frame.readyFlash:SetBlendMode("ADD")
    frame.readyFlash:SetAlpha(0)

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

function ct:SetCooldowns(cooldowns)
    self.trackedCooldowns = cooldowns or {}

    local settings = TankAssist.Addon.db.profile.cooldowns
    local iconSize = settings.iconSize
    local spacing = 6

    local grouped = {
        MAJOR = {},
        DEFENSIVE = {},
        OFFENSIVE = {},
    }

    for _, cd in ipairs(self.trackedCooldowns) do
        local category = cd.category or "DEFENSIVE"
        table.insert(grouped[category], cd)
    end

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

    local totalWidth = #displayOrder * (iconSize + spacing) - spacing
    local startX = -totalWidth / 2 + iconSize / 2

    for i, cdData in ipairs(displayOrder) do
        if not self.cooldownIcons[i] then
            self.cooldownIcons[i] = self:CreateCooldownIcon(i)
        end

        local icon = self.cooldownIcons[i]
        icon.cdData = cdData
        icon:SetPoint("LEFT", self.iconsContainer, "CENTER", startX + (i - 1) * (iconSize + spacing), 0)
        icon:Show()

        local spellInfo = C_Spell.GetSpellInfo(cdData.spellId)
        local spellIcon = spellInfo and spellInfo.iconID
        if spellIcon then
            icon.icon.texture:SetTexture(spellIcon)
        end

        local categoryColor = self.CATEGORIES[cdData.category or "DEFENSIVE"].color
        icon.icon.border:SetVertexColor(unpack(categoryColor))

        local keybind = TankAssist.Utils:GetSpellKeybind(cdData.spellId)
        icon.keybind:SetText(TankAssist.Utils:FormatKeybind(keybind) or "")
    end

    for i = #displayOrder + 1, #self.cooldownIcons do
        self.cooldownIcons[i]:Hide()
    end
end

function ct:Update()
    if not self.frame or not self.frame:IsShown() then return end

    for i, icon in ipairs(self.cooldownIcons) do
        if icon:IsShown() and icon.cdData then
            self:UpdateCooldownIcon(icon)
        end
    end
end

function ct:UpdateCooldownIcon(icon)
    local cdData = icon.cdData
    local cdInfo = TankAssist.SecretValues:GetCooldownInfo(cdData.spellId)

    if cdInfo.isSecret then
        icon.icon.texture:SetDesaturated(true)
        icon.timer:SetText("?")
        icon.charges:SetText("")
        icon.cooldown:Clear()
        return
    end

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

    if cdInfo.onCooldown and cdInfo.remaining > 0 then
        local start = GetTime() - (cdInfo.remaining > 0 and 0 or 0)
        local duration = cdInfo.remaining + 0.1
        icon.cooldown:SetCooldown(GetTime() - duration + cdInfo.remaining, duration)

        if cdInfo.remaining > 60 then
            icon.timer:SetText(string.format("%d:%02d", math.floor(cdInfo.remaining / 60), math.floor(cdInfo.remaining % 60)))
        else
            icon.timer:SetText(string.format("%.1f", cdInfo.remaining))
        end
        icon.timer:SetTextColor(1, 0.3, 0.3, 1)

        if icon.wasReady then
            icon.wasReady = false
        end
    else
        icon.cooldown:Clear()
        icon.timer:SetText("READY")
        icon.timer:SetTextColor(0.3, 1, 0.3, 1)

        if not icon.wasReady then
            icon.wasReady = true
            icon.readyAnim:Play()

            if TankAssist.Addon.db.profile.sounds.enabled and TankAssist.Addon.db.profile.sounds.cooldownReady then
                -- PlaySoundFile(TankAssist.Addon.db.profile.sounds.cooldownReady)
            end
        end
    end
end

function ct:Show()
    if self.frame then
        self.frame:Show()
    end
end

function ct:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

local function Initialize()
    if TankAssist.Addon.mainFrame then
        TankAssist.Addon.cooldownTracker = CT
        ct:Create(TankAssist.Addon.mainFrame)
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.7, Initialize)
end)
