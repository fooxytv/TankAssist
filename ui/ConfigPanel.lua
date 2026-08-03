local ADDON_NAME, TankAssist = ...

TankAssist.ConfigPanel = {}
local cp = TankAssist.ConfigPanel
local PANEL_WIDTH = 720
local PANEL_HEIGHT = 540
local SIDEBAR_WIDTH = 160
local CONTENT_WIDTH = PANEL_WIDTH - SIDEBAR_WIDTH - 40

local C = {
    bg          = { 0.08, 0.08, 0.12, 0.95 },
    sidebarBg   = { 0.05, 0.05, 0.08, 0.95 },
    contentBg   = { 0.07, 0.07, 0.10, 0.95 },
    border      = { 0.25, 0.25, 0.30, 1 },
    accent      = { 0, 0.75, 0.95, 1 },
    accentDim   = { 0, 0.55, 0.75, 0.6 },
    accentBg    = { 0, 0.4, 0.6, 0.15 },
    textBright  = { 1, 1, 1, 1 },
    textNormal  = { 0.85, 0.85, 0.88, 1 },
    textDim     = { 0.50, 0.50, 0.55, 1 },
    textMuted   = { 0.35, 0.35, 0.40, 1 },
    sidebarBtn  = { 0.10, 0.10, 0.14, 1 },
    sidebarHover = { 0.15, 0.15, 0.20, 1 },
    rowAlt      = { 1, 1, 1, 0.025 },
    success     = { 0.2, 0.85, 0.4, 1 },
    danger      = { 0.9, 0.25, 0.25, 1 },
    warning     = { 1, 0.75, 0.25, 1 },
    headerLine  = { 0.3, 0.6, 1, 0.3 },
}

local BACKDROP_MAIN = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local BACKDROP_INNER = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local BACKDROP_SMALL = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

function cp:Create()
    if self.panel then return self.panel end

    local panel = CreateFrame("Frame", "TankAssistConfigPanel", UIParent, "ButtonFrameTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:Hide()
    panel:SetTitle("TankAssist")
    panel:SetPortraitToUnit("player")

    local inset = panel.Inset or CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
    if not panel.Inset then
        inset:SetPoint("TOPLEFT", 4, -60)
        inset:SetPoint("BOTTOMRIGHT", -6, 6)
    end

    local addonVersion = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or ""
    local version = inset:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    version:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -10, 6)
    version:SetText("v" .. addonVersion)
    version:SetTextColor(unpack(C.textMuted))

    self.panel = panel
    self.inset = inset
    self.categories = {}
    self.categoryFrames = {}
    self.activeCategory = nil
    self:CreateSidebar()
    self:CreateContentArea()
    self:RegisterCategory("general", "General", function(f) self:BuildGeneralPage(f) end)
    self:RegisterCategory("cooldownAlerts", "Cooldown Alerts", function(f) self:BuildCooldownAlertsPage(f) end)
    self:RegisterCategory("externalCDs", "External CDs", function(f) self:BuildExternalCDsPage(f) end)
    self:RegisterCategory("consumables", "Consumables", function(f) self:BuildConsumablesPage(f) end)
    self:RegisterCategory("sounds", "Sounds & Alerts", function(f) self:BuildSoundsPage(f) end)
    self:RegisterCategory("castBars", "Cast Bars", function(f) self:BuildCastBarsPage(f) end)
    self:RegisterCategory("gearAdvisor", "Gear Advisor", function(f) self:BuildGearAdvisorPage(f) end)
    self:SelectCategory("general")
    tinsert(UISpecialFrames, "TankAssistConfigPanel")

    return panel
end

function cp:CreateSidebar()
    local sidebar = CreateFrame("Frame", nil, self.inset, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", 6, -6)
    sidebar:SetPoint("BOTTOMLEFT", 6, 22)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    sidebar:SetBackdrop(BACKDROP_INNER)
    sidebar:SetBackdropColor(unpack(C.sidebarBg))
    sidebar:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.5)

    self.sidebar = sidebar
    self.sidebarButtons = {}
end

function cp:AddSidebarButton(id, label, order)
    local self_ref = self
    local btn = CreateFrame("Button", nil, self.sidebar)
    btn:SetSize(SIDEBAR_WIDTH - 12, 30)
    btn:SetPoint("TOPLEFT", 6, -6 + (-(order - 1) * 34))
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0, 0, 0, 0)
    btn.indicator = btn:CreateTexture(nil, "ARTWORK")
    btn.indicator:SetPoint("TOPLEFT", 0, 0)
    btn.indicator:SetPoint("BOTTOMLEFT", 0, 0)
    btn.indicator:SetWidth(3)
    btn.indicator:SetColorTexture(unpack(C.accent))
    btn.indicator:Hide()
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("LEFT", 12, 0)
    btn.text:SetText(label)
    btn.text:SetTextColor(unpack(C.textDim))
    btn:SetScript("OnEnter", function()
        if self_ref.activeCategory ~= id then
            btn.bg:SetColorTexture(unpack(C.sidebarHover))
            btn.text:SetTextColor(unpack(C.textNormal))
        end
    end)

    btn:SetScript("OnLeave", function()
        if self_ref.activeCategory ~= id then
            btn.bg:SetColorTexture(0, 0, 0, 0)
            btn.text:SetTextColor(unpack(C.textDim))
        end
    end)

    btn:SetScript("OnClick", function()
        self_ref:SelectCategory(id)
    end)

    btn.id = id
    self.sidebarButtons[id] = btn
end

function cp:CreateContentArea()
    local content = CreateFrame("Frame", nil, self.inset, "BackdropTemplate")
    content:SetPoint("TOPLEFT", self.sidebar, "TOPRIGHT", 6, 0)
    content:SetPoint("BOTTOMRIGHT", self.inset, "BOTTOMRIGHT", -6, 22)
    content:SetBackdrop(BACKDROP_INNER)
    content:SetBackdropColor(unpack(C.contentBg))
    content:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.5)
    self.contentArea = content
end

function cp:RegisterCategory(id, label, builder)
    local order = #self.categories + 1
    table.insert(self.categories, { id = id, label = label, builder = builder, order = order })
    self:AddSidebarButton(id, label, order)
end

function cp:SelectCategory(id)
    for _, frame in pairs(self.categoryFrames) do
        frame:Hide()
    end

    for btnId, btn in pairs(self.sidebarButtons) do
        if btnId == id then
            btn.bg:SetColorTexture(unpack(C.accentBg))
            btn.text:SetTextColor(unpack(C.accent))
            btn.indicator:Show()
        else
            btn.bg:SetColorTexture(0, 0, 0, 0)
            btn.text:SetTextColor(unpack(C.textDim))
            btn.indicator:Hide()
        end
    end

    self.activeCategory = id

    if not self.categoryFrames[id] then
        local frame = CreateFrame("Frame", nil, self.contentArea)
        frame:SetPoint("TOPLEFT", 12, -12)
        frame:SetPoint("BOTTOMRIGHT", -12, 12)
        self.categoryFrames[id] = frame

        for _, cat in ipairs(self.categories) do
            if cat.id == id then
                cat.builder(frame)
                break
            end
        end
    end

    self.categoryFrames[id]:Show()

    if id == "cooldownAlerts" then
        self:RefreshAlertSpellList()
    elseif id == "gearAdvisor" then
        self:RefreshGearAdvisorPage()
    end
end

function cp:MakeSectionHeader(parent, text, yOffset)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 0, yOffset)
    header:SetText(text)
    header:SetTextColor(unpack(C.accent))

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    line:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    line:SetHeight(1)
    line:SetColorTexture(unpack(C.headerLine))

    return yOffset - 22
end

function cp:MakeCheckbox(parent, label, yOffset, getter, setter)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 0, yOffset)
    row:SetSize(CONTENT_WIDTH, 24)

    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetPoint("LEFT", -2, 0)
    check:SetSize(24, 24)
    check.text:SetText(label)
    check.text:SetFontObject("GameFontNormalSmall")
    check.text:SetTextColor(unpack(C.textNormal))
    check:SetChecked(getter())
    check:SetScript("OnClick", function(self)
        setter(self:GetChecked())
    end)

    return yOffset - 26
end

function cp:MakeSlider(parent, label, yOffset, min, max, step, getter, setter, formatter)
    formatter = formatter or function(v) return string.format("%.1f", v) end

    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 0, yOffset)
    row:SetSize(CONTENT_WIDTH, 38)

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", 2, 0)
    text:SetText(label)
    text:SetTextColor(unpack(C.textNormal))

    local slider = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 2, -14)
    slider:SetSize(200, 17)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(getter())
    slider.Low:SetText(min)
    slider.High:SetText(max)

    local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    valueText:SetText(formatter(getter()))
    valueText:SetTextColor(unpack(C.accent))

    slider:SetScript("OnValueChanged", function(_, value)
        setter(value)
        valueText:SetText(formatter(value))
    end)

    return yOffset - 42
end

function cp:MakeDropdown(parent, label, yOffset, options, getter, setter)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 0, yOffset)
    row:SetSize(CONTENT_WIDTH, 24)

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 2, 0)
    text:SetText(label)
    text:SetTextColor(unpack(C.textNormal))
    local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
    btn:SetPoint("LEFT", text, "RIGHT", 10, 0)
    btn:SetSize(150, 22)
    btn:SetBackdrop(BACKDROP_SMALL)
    btn:SetBackdropColor(0.12, 0.12, 0.16, 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.label:SetPoint("LEFT", 8, 0)
    btn.label:SetTextColor(unpack(C.textNormal))
    btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.arrow:SetPoint("RIGHT", -6, 0)
    btn.arrow:SetText("|cFF888888>|r")
    btn:SetScript("OnClick", function()
        local current = getter()
        for i, opt in ipairs(options) do
            if opt.value == current then
                local next = options[(i % #options) + 1]
                setter(next.value)
                btn.label:SetText(next.label)
                return
            end
        end
        setter(options[1].value)
        btn.label:SetText(options[1].label)
    end)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(C.accentDim))
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    end)

    -- Set initial label
    local currentVal = getter()
    for _, opt in ipairs(options) do
        if opt.value == currentVal then
            btn.label:SetText(opt.label)
            break
        end
    end

    return yOffset - 28
end

function cp:MakeSoundDropdown(parent, label, yOffset, getter, setter)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 0, yOffset)
    row:SetSize(CONTENT_WIDTH, 28)

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 2, 0)
    text:SetText(label)
    text:SetTextColor(unpack(C.textNormal))

    local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("LEFT", text, "RIGHT", 10, 0)
    dropdown:SetSize(200, 22)

    dropdown:SetupMenu(function(_, rootDescription)
        rootDescription:SetScrollMode(220)
        if not TankAssist.Sounds then
            rootDescription:CreateRadio("None", function() return true end, function() end)
            return
        end
        local options = TankAssist.Sounds:GetSoundOptions()
        for _, opt in ipairs(options) do
            local value, optLabel = opt.value, opt.label
            rootDescription:CreateRadio(
                optLabel,
                function() return getter() == value end,
                function()
                    setter(value)
                    dropdown:OverrideText(optLabel)
                end
            )
        end
    end)

    dropdown:OverrideText(getter() or "None")

    local previewBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    previewBtn:SetPoint("LEFT", dropdown, "RIGHT", 8, 0)
    previewBtn:SetSize(60, 22)
    previewBtn:SetText("Preview")
    previewBtn:SetScript("OnClick", function()
        if TankAssist.Sounds then
            TankAssist.Sounds:PlayByName(getter())
        end
    end)

    return yOffset - 32
end

-- ============================================================================
-- General Page
-- ============================================================================

function cp:BuildGeneralPage(frame)
    local y = 0
    local db = TankAssist.Addon.db.profile

    y = self:MakeSectionHeader(frame, "General", y)

    y = self:MakeCheckbox(frame, "Enable TankAssist", y,
        function() return db.enabled end,
        function(v)
            db.enabled = v
            TankAssist.Addon:UpdateVisibility()
        end
    )

    y = self:MakeSectionHeader(frame, "Display", y - 10)

    y = self:MakeCheckbox(frame, "Show out of combat", y,
        function() return db.display.showOutOfCombat end,
        function(v) db.display.showOutOfCombat = v end
    )

    y = self:MakeCheckbox(frame, "Show without target", y,
        function() return db.display.showWithoutTarget end,
        function(v) db.display.showWithoutTarget = v end
    )

    y = self:MakeCheckbox(frame, "Hide in M+ (limited API)", y,
        function() return db.display.hideInMythicPlus end,
        function(v) db.display.hideInMythicPlus = v end
    )

    y = self:MakeSlider(frame, "Scale", y - 5, 0.5, 2.0, 0.1,
        function() return db.display.scale end,
        function(v)
            db.display.scale = v
            if TankAssist.Addon.mainFrame then
                TankAssist.Addon.mainFrame:SetScale(v)
            end
        end
    )

    y = self:MakeSectionHeader(frame, "Assisted Combat", y - 10)

    y = self:MakeCheckbox(frame, "Enable Assisted Combat display", y,
        function() return db.assistedCombat.enabled end,
        function(v) db.assistedCombat.enabled = v end
    )

    y = self:MakeCheckbox(frame, "Show keybinds", y,
        function() return db.assistedCombat.showKeybinds end,
        function(v) db.assistedCombat.showKeybinds = v end
    )
end

-- ============================================================================
-- Consumables Page
-- ============================================================================

function cp:BuildConsumablesPage(frame)
    local db = TankAssist.Addon.db.profile
    local y = 0

    y = self:MakeSectionHeader(frame, "Consumable Check", y)

    y = self:MakeCheckbox(frame, "Enable consumable check", y,
        function() return db.consumableCheck.enabled end,
        function(v)
            db.consumableCheck.enabled = v
            if TankAssist.Addon.consumableCheck then
                TankAssist.Addon.consumableCheck:SetEnabled(v)
            end
        end
    )

    y = self:MakeCheckbox(frame, "Also check outside instances", y,
        function() return db.consumableCheck.alsoOutsideInstances end,
        function(v) db.consumableCheck.alsoOutsideInstances = v end
    )

    y = self:MakeSlider(frame, "Scale", y - 5, 0.5, 2.0, 0.1,
        function() return db.consumableCheck.scale or 1.0 end,
        function(v)
            db.consumableCheck.scale = v
            if TankAssist.Addon.consumableCheck and TankAssist.Addon.consumableCheck.frame then
                TankAssist.Addon.consumableCheck.frame:SetScale(v)
            end
        end
    )

    y = self:MakeSlider(frame, "Icon Size", y - 5, 24, 64, 4,
        function() return db.consumableCheck.iconSize or 40 end,
        function(v)
            v = math.floor(v / 4 + 0.5) * 4
            db.consumableCheck.iconSize = v
            if TankAssist.Addon.consumableCheck and TankAssist.Addon.consumableCheck.Layout then
                TankAssist.Addon.consumableCheck:Layout()
            end
        end,
        function(v) return string.format("%d", v) end
    )

    y = self:MakeSectionHeader(frame, "Manual Check", y - 10)

    local btnRow = CreateFrame("Frame", nil, frame)
    btnRow:SetPoint("TOPLEFT", 0, y)
    btnRow:SetSize(CONTENT_WIDTH, 28)

    local checkBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
    checkBtn:SetPoint("LEFT", 0, 0)
    checkBtn:SetSize(120, 24)
    checkBtn:SetText("Check Now")
    checkBtn:SetScript("OnClick", function()
        if TankAssist.Addon.consumableCheck then
            TankAssist.Addon.consumableCheck:ManualCheck()
        end
    end)

    local hint = btnRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("LEFT", checkBtn, "RIGHT", 10, 0)
    hint:SetText("Re-scans your buffs and shows the panel.")
    hint:SetTextColor(unpack(C.textDim))
end

-- ============================================================================
-- Cooldown Alerts Page
-- ============================================================================

function cp:BuildCooldownAlertsPage(frame)
    local self_ref = self
    local y = 0

    y = self:MakeSectionHeader(frame, "Tracked Spells", y)

    -- Spell list area
    local listContainer = CreateFrame("Frame", nil, frame)
    listContainer:SetPoint("TOPLEFT", 0, y)
    listContainer:SetSize(CONTENT_WIDTH, 270)
    self.alertListContainer = listContainer
    self.alertSpellRows = {}

    -- Buttons row
    local btnRow = CreateFrame("Frame", nil, frame)
    btnRow:SetPoint("TOPLEFT", listContainer, "BOTTOMLEFT", 0, -4)
    btnRow:SetSize(CONTENT_WIDTH, 28)

    local defaultsBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
    defaultsBtn:SetPoint("LEFT", 0, 0)
    defaultsBtn:SetSize(140, 24)
    defaultsBtn:SetText("Load Spec Defaults")
    defaultsBtn:SetScript("OnClick", function()
        if TankAssist.Addon.cooldownAlerts then
            TankAssist.Addon.cooldownAlerts:LoadSpecDefaults()
            self_ref:RefreshAlertSpellList()
        end
    end)

    local clearBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
    clearBtn:SetPoint("LEFT", defaultsBtn, "RIGHT", 5, 0)
    clearBtn:SetSize(80, 24)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        if TankAssist.Addon.cooldownAlerts then
            local trackedSpells = TankAssist.Addon.cooldownAlerts:GetTrackedSpells()
            wipe(trackedSpells)
            TankAssist.Addon.cooldownAlerts.spellStates = {}
        end
        self_ref:RefreshAlertSpellList()
    end)

    -- Add spell section
    local addSection = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    addSection:SetPoint("TOPLEFT", btnRow, "BOTTOMLEFT", 0, -8)
    addSection:SetSize(CONTENT_WIDTH, 52)
    addSection:SetBackdrop(BACKDROP_SMALL)
    addSection:SetBackdropColor(0.06, 0.06, 0.09, 0.9)
    addSection:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.5)

    local addTitle = addSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addTitle:SetPoint("TOPLEFT", 8, -6)
    addTitle:SetText("Add Spell")
    addTitle:SetTextColor(unpack(C.accent))

    local idLabel = addSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    idLabel:SetPoint("TOPLEFT", 8, -22)
    idLabel:SetText("Spell ID:")
    idLabel:SetTextColor(unpack(C.textDim))

    local idInput = CreateFrame("EditBox", nil, addSection, "InputBoxTemplate")
    idInput:SetPoint("LEFT", idLabel, "RIGHT", 6, 0)
    idInput:SetSize(70, 18)
    idInput:SetAutoFocus(false)
    idInput:SetNumeric(true)

    local cdLabel = addSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cdLabel:SetPoint("LEFT", idInput, "RIGHT", 12, 0)
    cdLabel:SetText("CD (sec):")
    cdLabel:SetTextColor(unpack(C.textDim))

    local cdInput = CreateFrame("EditBox", nil, addSection, "InputBoxTemplate")
    cdInput:SetPoint("LEFT", cdLabel, "RIGHT", 6, 0)
    cdInput:SetSize(50, 18)
    cdInput:SetAutoFocus(false)
    cdInput:SetNumeric(true)

    local addBtn = CreateFrame("Button", nil, addSection, "UIPanelButtonTemplate")
    addBtn:SetPoint("LEFT", cdInput, "RIGHT", 10, 0)
    addBtn:SetSize(50, 22)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local spellId = tonumber(idInput:GetText())
        local cdDuration = tonumber(cdInput:GetText())
        if spellId and spellId > 0 then
            if cdDuration and cdDuration > 0 then
                TankAssist.SecretValues.KnownCooldowns[spellId] = cdDuration
                -- Persist custom CD
                local customCDs = TankAssist.Addon.db.profile.cooldownAlerts.customCooldowns
                if not customCDs then
                    TankAssist.Addon.db.profile.cooldownAlerts.customCooldowns = {}
                    customCDs = TankAssist.Addon.db.profile.cooldownAlerts.customCooldowns
                end
                customCDs[tostring(spellId)] = cdDuration
            end
            if TankAssist.Addon.cooldownAlerts then
                TankAssist.Addon.cooldownAlerts:AddTrackedSpell(spellId)
            end
            idInput:SetText("")
            cdInput:SetText("")
            self_ref:RefreshAlertSpellList()
        end
    end)

    idInput:SetScript("OnEnterPressed", function() addBtn:Click() end)
    cdInput:SetScript("OnEnterPressed", function() addBtn:Click() end)

    self:RefreshAlertSpellList()
end

function cp:RefreshAlertSpellList()
    if not self.alertListContainer then return end

    -- Clear existing rows
    for _, row in ipairs(self.alertSpellRows or {}) do
        row:Hide()
        row:SetParent(nil)
    end
    self.alertSpellRows = {}

    local spells
    if TankAssist.Addon.cooldownAlerts then
        spells = TankAssist.Addon.cooldownAlerts:GetTrackedSpells()
    else
        spells = {}
    end
    local sv = TankAssist.SecretValues
    local self_ref = self

    -- Column headers
    local headerRow = CreateFrame("Frame", nil, self.alertListContainer)
    headerRow:SetSize(CONTENT_WIDTH, 20)
    headerRow:SetPoint("TOPLEFT", 0, 0)

    local headerLine = headerRow:CreateTexture(nil, "ARTWORK")
    headerLine:SetPoint("BOTTOMLEFT", 0, 0)
    headerLine:SetPoint("BOTTOMRIGHT", 0, 0)
    headerLine:SetHeight(1)
    headerLine:SetColorTexture(unpack(C.headerLine))

    local hSpell = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hSpell:SetPoint("LEFT", 4, 2)
    hSpell:SetText("SPELL")
    hSpell:SetTextColor(unpack(C.textMuted))

    local hCD = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hCD:SetPoint("LEFT", 240, 2)
    hCD:SetText("CD")
    hCD:SetTextColor(unpack(C.textMuted))

    local hSound = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hSound:SetPoint("LEFT", 310, 2)
    hSound:SetText("SOUND")
    hSound:SetTextColor(unpack(C.textMuted))

    table.insert(self.alertSpellRows, headerRow)

    if #spells == 0 then
        local empty = CreateFrame("Frame", nil, self.alertListContainer)
        empty:SetSize(CONTENT_WIDTH, 40)
        empty:SetPoint("TOPLEFT", 0, -24)
        local text = empty:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", 4, 0)
        text:SetText("No spells tracked. Use 'Load Spec Defaults' or add a spell below.")
        text:SetTextColor(unpack(C.textMuted))
        table.insert(self.alertSpellRows, empty)
        return
    end

    for i, spellId in ipairs(spells) do
        local rowY = -(i * 30) + 8
        local row = CreateFrame("Frame", nil, self.alertListContainer)
        row:SetSize(CONTENT_WIDTH, 28)
        row:SetPoint("TOPLEFT", 0, rowY)

        -- Alternating row background
        if i % 2 == 0 then
            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetColorTexture(unpack(C.rowAlt))
        end

        -- Spell icon
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("LEFT", 4, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local spellInfo = C_Spell.GetSpellInfo(spellId)
        if spellInfo and spellInfo.iconID then
            icon:SetTexture(spellInfo.iconID)
        else
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        -- Spell name + ID
        local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        name:SetWidth(195)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        local spellName = spellInfo and spellInfo.name or "Unknown"
        name:SetText(spellName .. "  |cFF404045" .. spellId .. "|r")

        -- CD duration (editable)
        local knownCD = sv.KnownCooldowns[spellId]
        local cdBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        cdBtn:SetPoint("LEFT", 240, 0)
        cdBtn:SetSize(55, 22)
        cdBtn:SetBackdrop(BACKDROP_SMALL)
        cdBtn:SetBackdropColor(0.10, 0.10, 0.14, 1)
        cdBtn:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.8)

        local cdText = cdBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cdText:SetPoint("CENTER")
        if knownCD then
            cdText:SetText(knownCD .. "s")
            cdText:SetTextColor(unpack(C.textNormal))
        else
            cdText:SetText("?")
            cdText:SetTextColor(unpack(C.textMuted))
        end

        -- Click to edit CD
        cdBtn.editBox = CreateFrame("EditBox", nil, cdBtn, "InputBoxTemplate")
        cdBtn.editBox:SetPoint("CENTER", 0, 0)
        cdBtn.editBox:SetSize(40, 16)
        cdBtn.editBox:SetAutoFocus(false)
        cdBtn.editBox:SetNumeric(true)
        cdBtn.editBox:Hide()

        cdBtn:SetScript("OnClick", function()
            cdText:Hide()
            local liveCD = sv.KnownCooldowns[spellId]
            cdBtn.editBox:SetText(liveCD and tostring(liveCD) or "")
            cdBtn.editBox:Show()
            cdBtn.editBox:SetFocus()
        end)

        cdBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(unpack(C.accentDim))
        end)
        cdBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.8)
        end)

        local currentSpellId = spellId
        cdBtn.editBox:SetScript("OnEnterPressed", function(self)
            local newCD = tonumber(self:GetText())
            if newCD and newCD > 0 then
                sv.KnownCooldowns[currentSpellId] = newCD
                -- Persist to saved settings
                local customCDs = TankAssist.Addon.db.profile.cooldownAlerts.customCooldowns
                if not customCDs then
                    TankAssist.Addon.db.profile.cooldownAlerts.customCooldowns = {}
                    customCDs = TankAssist.Addon.db.profile.cooldownAlerts.customCooldowns
                end
                customCDs[tostring(currentSpellId)] = newCD
                cdText:SetText(newCD .. "s")
                cdText:SetTextColor(unpack(C.warning))
            end
            self:Hide()
            cdText:Show()
        end)

        cdBtn.editBox:SetScript("OnEscapePressed", function(self)
            self:Hide()
            cdText:Show()
        end)

        -- Availability colour on the spell name (replaces the old status text)
        local isKnown = IsSpellKnown(spellId) or (IsPlayerSpell and IsPlayerSpell(spellId))
        if isKnown then
            name:SetTextColor(unpack(C.textNormal))
        else
            name:SetTextColor(unpack(C.textDim))
        end

        -- Per-spell sound dropdown
        local cdProfile = TankAssist.Addon.db.profile.cooldownAlerts
        cdProfile.spellSounds = cdProfile.spellSounds or {}
        local spellIdStr = tostring(spellId)

        local function getSpellSound()
            return cdProfile.spellSounds[spellIdStr] or "Default"
        end
        local function setSpellSound(value)
            if value == "Default" then
                cdProfile.spellSounds[spellIdStr] = nil
            else
                cdProfile.spellSounds[spellIdStr] = value
            end
        end

        local soundDropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
        soundDropdown:SetPoint("LEFT", 310, 0)
        soundDropdown:SetSize(150, 22)

        soundDropdown:SetupMenu(function(_, root)
            root:SetScrollMode(220)
            root:CreateRadio(
                "Default",
                function() return getSpellSound() == "Default" end,
                function()
                    setSpellSound("Default")
                    soundDropdown:OverrideText("Default")
                end
            )
            if TankAssist.Sounds then
                for _, opt in ipairs(TankAssist.Sounds:GetSoundOptions()) do
                    local v, l = opt.value, opt.label
                    root:CreateRadio(
                        l,
                        function() return getSpellSound() == v end,
                        function()
                            setSpellSound(v)
                            soundDropdown:OverrideText(l)
                        end
                    )
                end
            end
        end)
        soundDropdown:OverrideText(getSpellSound())

        local previewBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        previewBtn:SetPoint("LEFT", soundDropdown, "RIGHT", 4, 0)
        previewBtn:SetSize(26, 22)
        previewBtn:SetText("|TInterface\\Common\\VoiceChat-Speaker:0:0:0:0:64:64:0:64:0:64|t")
        previewBtn:SetScript("OnClick", function()
            if not TankAssist.Sounds then return end
            local v = getSpellSound()
            if v == "Default" then
                local s = TankAssist.Sounds:GetSettings()
                TankAssist.Sounds:PlayByName(s and s.cooldownReady or "None")
            else
                TankAssist.Sounds:PlayByName(v)
            end
        end)

        -- Remove button
        local removeBtn = CreateFrame("Button", nil, row)
        removeBtn:SetSize(20, 20)
        removeBtn:SetPoint("RIGHT", -2, 0)

        removeBtn.text = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        removeBtn.text:SetPoint("CENTER")
        removeBtn.text:SetText("|cFFCC3333x|r")

        removeBtn:SetScript("OnEnter", function()
            removeBtn.text:SetText("|cFFFF4444x|r")
        end)
        removeBtn:SetScript("OnLeave", function()
            removeBtn.text:SetText("|cFFCC3333x|r")
        end)
        removeBtn:SetScript("OnClick", function()
            if TankAssist.Addon.cooldownAlerts then
                TankAssist.Addon.cooldownAlerts:RemoveTrackedSpell(currentSpellId)
            end
            self_ref:RefreshAlertSpellList()
        end)

        row:Show()
        table.insert(self.alertSpellRows, row)
    end
end

-- ============================================================================
-- External CDs Page
-- ============================================================================

function cp:BuildExternalCDsPage(frame)
    local y = 0
    local db = TankAssist.Addon.db.profile

    y = self:MakeSectionHeader(frame, "External Cooldowns", y)

    y = self:MakeCheckbox(frame, "Enable External Cooldowns", y,
        function() return db.externalCooldowns.enabled end,
        function(v)
            db.externalCooldowns.enabled = v
            if TankAssist.Addon.externalCooldowns then
                TankAssist.Addon.externalCooldowns:SetEnabled(v)
            end
        end
    )

    y = self:MakeCheckbox(frame, "Show only in combat", y,
        function() return db.externalCooldowns.showOnlyInCombat end,
        function(v) db.externalCooldowns.showOnlyInCombat = v end
    )

    y = self:MakeSlider(frame, "Icon Size", y - 5, 24, 64, 4,
        function() return db.externalCooldowns.iconSize end,
        function(v)
            v = math.floor(v / 4 + 0.5) * 4
            db.externalCooldowns.iconSize = v
            if TankAssist.Addon.externalCooldowns then
                TankAssist.Addon.externalCooldowns:SetIconSize(v)
            end
        end,
        function(v) return tostring(math.floor(v)) end
    )

    y = self:MakeSlider(frame, "Scale", y - 5, 0.5, 2.0, 0.1,
        function() return db.externalCooldowns.scale end,
        function(v)
            v = math.floor(v * 10 + 0.5) / 10
            db.externalCooldowns.scale = v
            if TankAssist.Addon.externalCooldowns then
                TankAssist.Addon.externalCooldowns:SetScale(v)
            end
        end
    )

    y = self:MakeDropdown(frame, "Display Mode", y - 5,
        {
            { label = "Icon Only", value = "ICON_ONLY" },
            { label = "Icon + Name", value = "ICON_NAME" },
            { label = "Name Only", value = "NAME_ONLY" },
        },
        function() return db.externalCooldowns.displayMode or "ICON_ONLY" end,
        function(v) db.externalCooldowns.displayMode = v end
    )

    y = self:MakeDropdown(frame, "Timer Position", y,
        {
            { label = "Below Icon", value = "BELOW" },
            { label = "Inside Icon", value = "INSIDE" },
        },
        function() return db.externalCooldowns.timerPosition or "BELOW" end,
        function(v) db.externalCooldowns.timerPosition = v end
    )

    y = self:MakeSectionHeader(frame, "Tracked Externals", y - 10)

    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("TOPLEFT", 0, y)
    note:SetWidth(CONTENT_WIDTH - 10)
    note:SetJustifyH("LEFT")
    note:SetText("Pain Suppression, Guardian Spirit, Ironbark, Life Cocoon, Blessing of Sacrifice, Blessing of Protection, Blessing of Spellwarding, Rallying Cry")
    note:SetTextColor(unpack(C.textDim))
end

-- ============================================================================
-- Sounds & Alerts Page
-- ============================================================================

function cp:BuildSoundsPage(frame)
    local y = 0
    local db = TankAssist.Addon.db.profile

    y = self:MakeSectionHeader(frame, "Sounds", y)

    y = self:MakeCheckbox(frame, "Enable sounds", y,
        function() return db.sounds.enabled end,
        function(v) db.sounds.enabled = v end
    )

    y = self:MakeDropdown(frame, "Sound channel", y,
        {
            { label = "Master", value = "Master" },
            { label = "SFX", value = "SFX" },
            { label = "Music", value = "Music" },
            { label = "Dialog", value = "Dialog" },
            { label = "Ambience", value = "Ambience" },
        },
        function() return db.sounds.channel or "Master" end,
        function(v) db.sounds.channel = v end
    )

    y = self:MakeSectionHeader(frame, "Events", y - 10)

    y = self:MakeSoundDropdown(frame, "Cooldown ready", y,
        function() return db.sounds.cooldownReady or "None" end,
        function(v) db.sounds.cooldownReady = v end
    )

    y = self:MakeSoundDropdown(frame, "External applied", y,
        function() return db.sounds.externalApplied or "None" end,
        function(v) db.sounds.externalApplied = v end
    )

    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("TOPLEFT", 0, y - 10)
    note:SetWidth(CONTENT_WIDTH - 10)
    note:SetJustifyH("LEFT")
    note:SetText("Sounds are loaded via LibSharedMedia. Addons like WeakAuras and BigWigs add their sounds to this list automatically.")
    note:SetTextColor(unpack(C.textMuted))
end

-- ============================================================================
-- Cast Bars Page
-- ============================================================================

function cp:BuildCastBarsPage(frame)
    local y = 0
    local db = TankAssist.Addon.db.profile

    y = self:MakeSectionHeader(frame, "Player Cast Bar", y)

    y = self:MakeCheckbox(frame, "Enable Player Cast Bar", y,
        function() return db.playerCastBar.enabled end,
        function(v)
            db.playerCastBar.enabled = v
            if TankAssist.Addon.playerCastBar then
                TankAssist.Addon.playerCastBar:SetEnabled(v)
            end
        end
    )

    y = self:MakeCheckbox(frame, "Hide Blizzard Cast Bar", y,
        function() return db.playerCastBar.hideBlizzardCastBar or false end,
        function(v)
            db.playerCastBar.hideBlizzardCastBar = v
            if TankAssist.Addon.playerCastBar then
                TankAssist.Addon.playerCastBar:ApplyBlizzardCastBarVisibility()
            end
        end
    )

    y = self:MakeCheckbox(frame, "Use class colour for the bar", y,
        function() return db.playerCastBar.useClassColor or false end,
        function(v)
            db.playerCastBar.useClassColor = v
            if TankAssist.Addon.playerCastBar then
                TankAssist.Addon.playerCastBar:ApplySettings()
                TankAssist.Addon.playerCastBar:UpdateBarAppearance()
            end
        end
    )

    y = self:MakeSlider(frame, "Width", y - 5, 100, 400, 1,
        function() return db.playerCastBar.width end,
        function(v)
            v = math.floor(v + 0.5)
            db.playerCastBar.width = v
            if TankAssist.Addon.playerCastBar then
                TankAssist.Addon.playerCastBar:SetBarWidth(v)
            end
        end,
        function(v) return tostring(math.floor(v)) end
    )

    y = self:MakeSlider(frame, "Height", y - 5, 10, 40, 1,
        function() return db.playerCastBar.height end,
        function(v)
            v = math.floor(v + 0.5)
            db.playerCastBar.height = v
            if TankAssist.Addon.playerCastBar then
                TankAssist.Addon.playerCastBar:SetBarHeight(v)
            end
        end,
        function(v) return tostring(math.floor(v)) end
    )

    y = self:MakeSlider(frame, "Scale", y - 5, 0.5, 2.0, 0.1,
        function() return db.playerCastBar.scale end,
        function(v)
            v = math.floor(v * 10 + 0.5) / 10
            db.playerCastBar.scale = v
            if TankAssist.Addon.playerCastBar then
                TankAssist.Addon.playerCastBar:SetBarScale(v)
            end
        end
    )

    y = self:MakeSectionHeader(frame, "Target Cast Bar", y - 15)

    y = self:MakeCheckbox(frame, "Enable Target Cast Bar", y,
        function() return db.targetCastBar.enabled end,
        function(v)
            db.targetCastBar.enabled = v
            if TankAssist.Addon.targetCastBar then
                TankAssist.Addon.targetCastBar:SetEnabled(v)
            end
        end
    )

    y = self:MakeSlider(frame, "Width", y - 5, 100, 400, 1,
        function() return db.targetCastBar.width end,
        function(v)
            v = math.floor(v + 0.5)
            db.targetCastBar.width = v
            if TankAssist.Addon.targetCastBar then
                TankAssist.Addon.targetCastBar:SetBarWidth(v)
            end
        end,
        function(v) return tostring(math.floor(v)) end
    )

    y = self:MakeSlider(frame, "Height", y - 5, 10, 40, 1,
        function() return db.targetCastBar.height end,
        function(v)
            v = math.floor(v + 0.5)
            db.targetCastBar.height = v
            if TankAssist.Addon.targetCastBar then
                TankAssist.Addon.targetCastBar:SetBarHeight(v)
            end
        end,
        function(v) return tostring(math.floor(v)) end
    )

    y = self:MakeSlider(frame, "Scale", y - 5, 0.5, 2.0, 0.1,
        function() return db.targetCastBar.scale end,
        function(v)
            v = math.floor(v * 10 + 0.5) / 10
            db.targetCastBar.scale = v
            if TankAssist.Addon.targetCastBar then
                TankAssist.Addon.targetCastBar:SetBarScale(v)
            end
        end
    )

    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("TOPLEFT", 0, y - 10)
    note:SetWidth(CONTENT_WIDTH - 10)
    note:SetJustifyH("LEFT")
    note:SetText("For colours, textures, fonts, and icon options use WoW's Edit Mode.")
    note:SetTextColor(unpack(C.textMuted))
end

-- ============================================================================
-- Show / Hide / Toggle
-- ============================================================================

function cp:Show()
    if not self.panel then
        self:Create()
    end
    if self.activeCategory == "cooldownAlerts" then
        self:RefreshAlertSpellList()
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

-- ============================================================================
-- Gear Advisor Page
-- ============================================================================

function cp:MakeMultiLineImportBox(parent, yOffset, height)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetPoint("TOPLEFT", 0, yOffset)
    container:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    container:SetHeight(height)
    container:SetBackdrop(BACKDROP_SMALL)
    container:SetBackdropColor(0.12, 0.12, 0.16, 1)
    container:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

    local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(CONTENT_WIDTH - 44)
    edit:SetHeight(height - 12) -- give an initial clickable area even when empty
    edit:SetMaxLetters(0)
    edit:SetTextInsets(2, 2, 2, 2)
    edit:EnableMouse(true)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- multi-line edit boxes auto-grow; keep the cursor visible while typing/pasting
    if ScrollingEdit_OnTextChanged then
        edit:SetScript("OnTextChanged", function(self) ScrollingEdit_OnTextChanged(self, scroll) end)
    end
    if ScrollingEdit_OnCursorChanged then
        edit:SetScript("OnCursorChanged", function(self, ...) ScrollingEdit_OnCursorChanged(self, ...) end)
    end
    scroll:SetScrollChild(edit)

    -- Clicking anywhere in the box focuses the edit (the empty edit area is tiny otherwise)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    container:EnableMouse(true)
    container:SetScript("OnMouseDown", function() edit:SetFocus() end)

    return edit, container
end

function cp:SetGearStatus(msg, level)
    if not self.gearStatusText then return end
    local color = C.textDim
    if level == "ok" then color = C.success
    elseif level == "warn" then color = C.warning
    elseif level == "error" then color = C.danger end
    self.gearStatusText:SetText(msg or "")
    self.gearStatusText:SetTextColor(unpack(color))
end

function cp:RefreshGearAdvisorPage()
    if not self.gearImportBox then return end
    local specId = TankAssist.Utils:GetCurrentSpec()
    local specName = TankAssist.Utils:GetSpecName(specId)
    if self.gearSpecLabel then
        self.gearSpecLabel:SetText("Editing profile for: |cFF00BFFF" .. specName .. "|r")
    end
    local raw = (TankAssist.GearAdvisor and specId) and TankAssist.GearAdvisor:GetRawImport(specId) or ""
    self.gearImportBox:SetText(raw)

    local s = TankAssist.Addon.db.profile.gearAdvisor
    local p = s and specId and s.profiles[tostring(specId)]
    if p and p.status then
        self:SetGearStatus(p.status, p.statusLevel or "ok")
    else
        self:SetGearStatus("", "ok")
    end
end

function cp:BuildGearAdvisorPage(frame)
    local y = 0
    local s = TankAssist.Addon.db.profile.gearAdvisor

    y = self:MakeSectionHeader(frame, "Gear Advisor", y)

    local intro = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intro:SetPoint("TOPLEFT", 2, y)
    intro:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    intro:SetText("Optional and disabled by default - dedicated upgrade addons do this better. Enable if you'd rather keep it in one place.")
    intro:SetTextColor(unpack(C.textMuted))
    y = y - 28

    y = self:MakeCheckbox(frame, "Enable Gear Advisor (off by default)", y,
        function() return s.enabled end,
        function(v)
            s.enabled = v
            if not v and TankAssist.GearAdvisor then
                TankAssist.GearAdvisor:ClearAllGlows()
            end
        end
    )
    y = self:MakeCheckbox(frame, "Annotate item tooltips", y,
        function() return s.annotateTooltips end,
        function(v) s.annotateTooltips = v end
    )
    y = self:MakeCheckbox(frame, "Glow upgrade on loot rolls", y,
        function() return s.glowLoot end,
        function(v) s.glowLoot = v end
    )

    y = self:MakeSectionHeader(frame, "Import gear data", y - 10)

    local specLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    specLabel:SetPoint("TOPLEFT", 2, y)
    specLabel:SetTextColor(unpack(C.textDim))
    self.gearSpecLabel = specLabel
    y = y - 16

    local help = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    help:SetPoint("TOPLEFT", 2, y)
    help:SetText("Paste a TankAssist gear block (weights and/or BIS item IDs), then Import.")
    help:SetTextColor(unpack(C.textMuted))
    y = y - 18

    local edit = self:MakeMultiLineImportBox(frame, y, 160)
    self.gearImportBox = edit
    y = y - 160 - 8

    local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importBtn:SetPoint("TOPLEFT", 2, y)
    importBtn:SetSize(90, 22)
    importBtn:SetText("Import")

    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
    clearBtn:SetSize(90, 22)
    clearBtn:SetText("Clear")

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("TOPLEFT", importBtn, "BOTTOMLEFT", 0, -8)
    status:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(true)
    self.gearStatusText = status

    importBtn:SetScript("OnClick", function()
        local specId = TankAssist.Utils:GetCurrentSpec()
        if not specId or not TankAssist.GearAdvisor then
            self:SetGearStatus("No active spec to import for.", "error")
            return
        end
        local _, msg, level = TankAssist.GearAdvisor:ImportForSpec(specId, edit:GetText())
        self:SetGearStatus(msg, level)
    end)

    clearBtn:SetScript("OnClick", function()
        local specId = TankAssist.Utils:GetCurrentSpec()
        if specId and TankAssist.GearAdvisor then
            TankAssist.GearAdvisor:ClearForSpec(specId)
        end
        edit:SetText("")
        self:SetGearStatus("Cleared.", "ok")
    end)

    self:RefreshGearAdvisorPage()
end

-- ============================================================================
-- Initialization
-- ============================================================================

local function Initialize()
    -- Panel is created on-demand when Show() is called
end

C_Timer.After(0, Initialize)
