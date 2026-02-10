-- TankAssist Configuration Panel

local ADDON_NAME, TankAssist = ...

TankAssist.ConfigPanel = {}
local cp = TankAssist.ConfigPanel

function cp:Create()
    local panel = CreateFrame("Frame", "TankAssistOptionsPanel", UIParent, "BackdropTemplate")
    panel:SetSize(400, 500)
    panel:SetPoint("CENTER")
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetFrameStrata("DIALOG")
    panel:Hide()

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("TankAssist Options")

    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local content = CreateFrame("Frame", nil, panel)
    content:SetPoint("TOPLEFT", 15, -50)
    content:SetPoint("BOTTOMRIGHT", -15, 15)

    self.panel = panel
    self.content = content

    self:BuildOptions()

    return panel
end

function cp:BuildOptions()
    local yOffset = 0
    local db = TankAssist.Addon.db.profile

    yOffset = self:CreateCheckbox("Enable TankAssist",
        function() return db.enabled end,
        function(value)
            db.enabled = value
            TankAssist.Addon:UpdateVisibility()
        end,
        yOffset
    )

    yOffset = self:CreateHeader("Display Options", yOffset - 20)

    yOffset = self:CreateCheckbox("Show out of combat",
        function() return db.display.showOutOfCombat end,
        function(value) db.display.showOutOfCombat = value end,
        yOffset
    )

    yOffset = self:CreateCheckbox("Show without target",
        function() return db.display.showWithoutTarget end,
        function(value) db.display.showWithoutTarget = value end,
        yOffset
    )

    yOffset = self:CreateCheckbox("Hide in M+ (limited API)",
        function() return db.display.hideInMythicPlus end,
        function(value) db.display.hideInMythicPlus = value end,
        yOffset
    )

    yOffset = self:CreateSlider("Scale", 0.5, 2.0, 0.1,
        function() return db.display.scale end,
        function(value)
            db.display.scale = value
            if TankAssist.Addon.mainFrame then
                TankAssist.Addon.mainFrame:SetScale(value)
            end
        end,
        yOffset - 10
    )

    yOffset = self:CreateHeader("Assisted Combat", yOffset - 30)

    yOffset = self:CreateCheckbox("Enable Assisted Combat display",
        function() return db.assistedCombat.enabled end,
        function(value) db.assistedCombat.enabled = value end,
        yOffset
    )

    yOffset = self:CreateCheckbox("Show keybinds",
        function() return db.assistedCombat.showKeybinds end,
        function(value) db.assistedCombat.showKeybinds = value end,
        yOffset
    )

    yOffset = self:CreateHeader("Cooldown Tracker", yOffset - 20)

    yOffset = self:CreateCheckbox("Enable Cooldown Tracker",
        function() return db.cooldowns.enabled end,
        function(value) db.cooldowns.enabled = value end,
        yOffset
    )

    yOffset = self:CreateCheckbox("Show Major cooldowns",
        function() return db.cooldowns.showMajor end,
        function(value) db.cooldowns.showMajor = value end,
        yOffset
    )

    yOffset = self:CreateCheckbox("Show Defensive cooldowns",
        function() return db.cooldowns.showDefensive end,
        function(value) db.cooldowns.showDefensive = value end,
        yOffset
    )

    yOffset = self:CreateHeader("Buff Maintenance", yOffset - 20)

    yOffset = self:CreateCheckbox("Enable Buff Tracker",
        function() return db.buffMaintenance.enabled end,
        function(value) db.buffMaintenance.enabled = value end,
        yOffset
    )

    yOffset = self:CreateSlider("Warning threshold (sec)", 1, 10, 1,
        function() return db.buffMaintenance.warningThreshold end,
        function(value) db.buffMaintenance.warningThreshold = value end,
        yOffset - 10
    )
end

function cp:CreateHeader(text, yOffset)
    local header = self.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 0, yOffset)
    header:SetText(text)
    header:SetTextColor(1, 0.8, 0, 1)

    local line = self.content:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    line:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
    line:SetHeight(1)
    line:SetColorTexture(0.5, 0.5, 0.5, 0.5)

    return yOffset - 25
end

function cp:CreateCheckbox(label, getter, setter, yOffset)
    local check = CreateFrame("CheckButton", nil, self.content, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("TOPLEFT", 0, yOffset)
    check.Text:SetText(label)
    check:SetChecked(getter())
    check:SetScript("OnClick", function(self)
        setter(self:GetChecked())
    end)

    return yOffset - 25
end

function cp:CreateSlider(label, min, max, step, getter, setter, yOffset)
    local container = CreateFrame("Frame", nil, self.content)
    container:SetPoint("TOPLEFT", 0, yOffset)
    container:SetSize(300, 40)

    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT")
    text:SetText(label)

    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 0, -15)
    slider:SetSize(200, 17)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(getter())

    slider.Low:SetText(min)
    slider.High:SetText(max)

    local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    valueText:SetText(string.format("%.1f", getter()))

    slider:SetScript("OnValueChanged", function(self, value)
        setter(value)
        valueText:SetText(string.format("%.1f", value))
    end)

    return yOffset - 45
end

function cp:Show()
    if not self.panel then
        self:Create()
    end
    self.panel:Show()
end

function cp:Hide()
    if self.panel then
        self.panel:Hide()
    end
end

function cp:Toggle()
    if self.panel and self.panel:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

local function Initialize()
    TankAssist.Addon.configPanel = CP
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(1, Initialize)
end)
