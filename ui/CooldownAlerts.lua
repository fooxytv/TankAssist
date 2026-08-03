local ADDON_NAME, TankAssist = ...

local lem
local lemLoadSuccess, lemResult = pcall(function()
    return LibStub("LibEQOLEditMode-1.0")
end)
if lemLoadSuccess then
    lem = lemResult
end

TankAssist.CooldownAlerts = {}
local ca = TankAssist.CooldownAlerts

local function IsLibEQOLAvailable()
    return lem ~= nil
end

local function IsEditModeAvailable()
    return EditModeManagerFrame ~= nil and EventRegistry ~= nil
end

local function IsInEditMode()
    return EditModeManagerFrame and EditModeManagerFrame.editModeActive
end

local DISPLAY_MODES = {
    ICON_ONLY = "Icon Only",
    ICON_NAME = "Icon + Name",
    NAME_ONLY = "Name Only",
}

local READY_FLASH_DURATION = 2.0

ca.spellStates = {}

function ca:GetSettings()
    return TankAssist.Addon.db.profile.cooldownAlerts
end

function ca:GetCurrentSpecId()
    return TankAssist.Utils and TankAssist.Utils:GetCurrentSpec() or 0
end

function ca:GetTrackedSpells()
    local settings = self:GetSettings()
    if settings.trackedSpells and #settings.trackedSpells > 0 and type(settings.trackedSpells[1]) == "number" then
        local specId = self:GetCurrentSpecId()
        if specId and specId > 0 then
            if not settings.trackedSpellsBySpec then
                settings.trackedSpellsBySpec = {}
            end
            settings.trackedSpellsBySpec[specId] = settings.trackedSpells
            settings.trackedSpells = nil
        end
    end

    if not settings.trackedSpellsBySpec then
        settings.trackedSpellsBySpec = {}
    end

    local specId = self:GetCurrentSpecId()
    if not specId or specId == 0 then return {} end

    if not settings.trackedSpellsBySpec[specId] then
        settings.trackedSpellsBySpec[specId] = {}
    end

    return settings.trackedSpellsBySpec[specId]
end

function ca:Create()
    local settings = self:GetSettings()

    self.frame = CreateFrame("Frame", "TankAssistCooldownAlerts", UIParent)
    self.frame:SetSize(1, 1)
    self.frame.editModeName = "Cooldown Alerts"

    local validAnchors = { CENTER=1, TOP=1, BOTTOM=1, LEFT=1, RIGHT=1, TOPLEFT=1, TOPRIGHT=1, BOTTOMLEFT=1, BOTTOMRIGHT=1 }
    local pos = settings.position or {}
    if validAnchors[pos.point] and type(pos.x) == "number" and type(pos.y) == "number" then
        self.frame:SetPoint(pos.point, UIParent, validAnchors[pos.relativePoint] and pos.relativePoint or pos.point, pos.x, pos.y)
    else
        settings.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -320 }
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, -320)
    end
    self.frame:SetScale(settings.scale or 1.0)
    self.frame:SetClampedToScreen(true)

    self.icons = {}
    self.activeCount = 0
    self.editMode = false
    self.inCombat = UnitAffectingCombat("player") or false
    self:InitSpellStates()
    self:RegisterEditMode()
    self:RegisterEvents()
    self.frame:Hide()
    return self.frame
end

function ca:InitSpellStates()
    self.spellStates = {}
    self.unavailableSpells = {}
    local settings = self:GetSettings()
    local customCDs = settings.customCooldowns
    if customCDs then
        for spellIdStr, duration in pairs(customCDs) do
            local spellId = tonumber(spellIdStr)
            if spellId and duration > 0 then
                TankAssist.SecretValues.KnownCooldowns[spellId] = duration
            end
        end
    end
    self.spellCache = {}

    local trackedSpells = self:GetTrackedSpells()
    for _, spellId in ipairs(trackedSpells) do
        self.spellStates[spellId] = { wasOnCooldown = false, readyFlashTime = 0 }
        self:EnsureSpellRegistered(spellId)
        self:CacheSpellInfo(spellId)
    end
end

function ca:CacheSpellInfo(spellId)
    local info = C_Spell.GetSpellInfo(spellId)
    if info and info.iconID then
        self.spellCache[spellId] = {
            name = info.name or "Unknown",
            icon = info.iconID,
        }
    elseif not self.spellCache[spellId] then
        self.spellCache[spellId] = {
            name = "Unknown",
            icon = 134400,
            needsRefresh = true,
        }
    end
end


function ca:EnsureSpellRegistered(spellId)
    local sv = TankAssist.SecretValues
    if sv.KnownCooldowns[spellId] then return end
    local cdInfo = C_Spell.GetSpellCooldown(spellId)
    if cdInfo and cdInfo.duration then
        local ok, isReal = pcall(function()
            return cdInfo.duration > 1.5
        end)
        if ok and isReal then
            sv.KnownCooldowns[spellId] = cdInfo.duration
            return
        end
    end

    local knownDurations = {
        [6552]   = 15,  -- Pummel
        [96231]  = 15,  -- Rebuke
        [47528]  = 15,  -- Mind Freeze
        [116705] = 15,  -- Spear Hand Strike
        [183752] = 15,  -- Disrupt
        [106839] = 15,  -- Skull Bash
        -- Defensives
        [871]    = 210, -- Shield Wall
        [12975]  = 180, -- Last Stand
        [31850]  = 120, -- Ardent Defender
        [86659]  = 300, -- Guardian of Ancient Kings
        [48792]  = 120, -- Icebound Fortitude
        [55233]  = 90,  -- Vampiric Blood
        [115203] = 180, -- Fortifying Brew
        [122278] = 120, -- Dampen Harm
        [187827] = 180, -- Metamorphosis
        [204021] = 60,  -- Fiery Brand
        [22812]  = 60,  -- Barkskin
        [61336]  = 180, -- Survival Instincts
    }
    if knownDurations[spellId] then
        sv.KnownCooldowns[spellId] = knownDurations[spellId]
    end
end

function ca:CreateAlertIcon()
    local settings = self:GetSettings()
    local size = settings.iconSize

    local frame = CreateFrame("Frame", nil, self.frame)
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
    local saved = self:GetSettings().borderColor or { r = 0.9, g = 0.7, b = 0.2, a = 1 }
    local borderColor = { saved.r or 0.9, saved.g or 0.7, saved.b or 0.2, saved.a or 1 }
    frame.icon.borderTop = frame.icon:CreateTexture(nil, "OVERLAY")
    frame.icon.borderTop:SetPoint("TOPLEFT", 0, 0)
    frame.icon.borderTop:SetPoint("TOPRIGHT", 0, 0)
    frame.icon.borderTop:SetHeight(1)
    frame.icon.borderTop:SetColorTexture(unpack(borderColor))
    frame.icon.borderBottom = frame.icon:CreateTexture(nil, "OVERLAY")
    frame.icon.borderBottom:SetPoint("BOTTOMLEFT", 0, 0)
    frame.icon.borderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.icon.borderBottom:SetHeight(1)
    frame.icon.borderBottom:SetColorTexture(unpack(borderColor))
    frame.icon.borderLeft = frame.icon:CreateTexture(nil, "OVERLAY")
    frame.icon.borderLeft:SetPoint("TOPLEFT", 0, 0)
    frame.icon.borderLeft:SetPoint("BOTTOMLEFT", 0, 0)
    frame.icon.borderLeft:SetWidth(1)
    frame.icon.borderLeft:SetColorTexture(unpack(borderColor))
    frame.icon.borderRight = frame.icon:CreateTexture(nil, "OVERLAY")
    frame.icon.borderRight:SetPoint("TOPRIGHT", 0, 0)
    frame.icon.borderRight:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.icon.borderRight:SetWidth(1)
    frame.icon.borderRight:SetColorTexture(unpack(borderColor))
    frame.timerInside = frame.icon:CreateFontString(nil, "OVERLAY")
    frame.timerInside:SetFont("Fonts\\FRIZQT__.TTF", 16, "THICKOUTLINE")
    frame.timerInside:SetPoint("CENTER", frame.icon, "CENTER", 0, 0)
    frame.timerInside:SetTextColor(1, 1, 1, 1)
    frame.timerBelow = frame:CreateFontString(nil, "OVERLAY")
    frame.timerBelow:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    frame.timerBelow:SetPoint("TOP", frame.icon, "BOTTOM", 0, -2)
    frame.timerBelow:SetTextColor(1, 1, 1, 1)
    frame.spellName = frame:CreateFontString(nil, "OVERLAY")
    frame.spellName:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    frame.spellName:SetTextColor(1, 1, 1, 1)
    frame.spellName:SetWordWrap(false)
    frame.readyFlash = frame.icon:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.readyFlash:SetAllPoints(frame.icon.texture)
    frame.readyFlash:SetColorTexture(0.2, 1, 0.2, 0.5)
    frame.readyFlash:Hide()
    frame.readyText = frame.icon:CreateFontString(nil, "OVERLAY")
    frame.readyText:SetFont("Fonts\\FRIZQT__.TTF", 12, "THICKOUTLINE")
    frame.readyText:SetPoint("CENTER", frame.icon, "CENTER", 0, 0)
    frame.readyText:SetTextColor(0.2, 1, 0.2, 1)
    frame.readyText:SetText("READY")
    frame.readyText:Hide()
    frame.icon:EnableMouse(true)
    frame.icon:SetScript("OnEnter", function(self)
        if frame.spellId then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(frame.spellId)
            GameTooltip:Show()
        end
    end)
    frame.icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    frame.spellId = nil
    return frame
end

function ca:GetIcon(index)
    if not self.icons[index] then
        self.icons[index] = self:CreateAlertIcon()
    end
    return self.icons[index]
end

function ca:Update()
    if self.editMode then return end

    local settings = self:GetSettings()
    if settings.showOnlyInCombat and not self.inCombat then
        self.frame:Hide()
        return
    end

    local trackedSpells = self:GetTrackedSpells()
    if #trackedSpells == 0 then
        self.frame:Hide()
        return
    end

    local now = GetTime()
    local countdownDuration = settings.countdownDuration or 3
    local displayMode = settings.displayMode or "ICON_ONLY"
    local iconSize = settings.iconSize or 36
    local alertStyle = settings.alertStyle or "BOTH"
    local activeIcons = {}
    local sv = TankAssist.SecretValues

    for _, spellId in ipairs(trackedSpells) do
        if not (self.unavailableSpells and self.unavailableSpells[spellId]) then
            if not self.spellStates[spellId] then
                self.spellStates[spellId] = { wasOnCooldown = false, readyFlashTime = 0 }
            end
            local state = self.spellStates[spellId]
            local tracked = sv.trackedCooldowns[spellId]
            local remaining = 0
            local onCooldown = false

            if tracked then
                remaining = tracked.duration - (now - tracked.castTime)
                if remaining > 0 then
                    onCooldown = true
                else
                    remaining = 0
                end
            end

            local showIcon = false
            local isReady = false

            if state.wasOnCooldown and not onCooldown then
                state.readyFlashTime = now
                if TankAssist.Sounds then
                    TankAssist.Sounds:PlayForSpell(spellId, "cooldownReady")
                end
            end

            if alertStyle ~= "READY_ONLY" and onCooldown and remaining <= countdownDuration then
                showIcon = true
            end

            if alertStyle ~= "COUNTDOWN_ONLY" then
                if state.readyFlashTime > 0 and (now - state.readyFlashTime) < READY_FLASH_DURATION then
                    showIcon = true
                    isReady = true
                elseif state.readyFlashTime > 0 and (now - state.readyFlashTime) >= READY_FLASH_DURATION then
                    state.readyFlashTime = 0
                end
            else
                state.readyFlashTime = 0
            end

            state.wasOnCooldown = onCooldown

            if showIcon then
                table.insert(activeIcons, {
                    spellId = spellId,
                    remaining = remaining,
                    isReady = isReady,
                    onCooldown = onCooldown,
                    startTime = tracked and tracked.castTime or 0,
                    duration = tracked and tracked.duration or 0,
                })
            end
        end
    end

    if #activeIcons == 0 then
        self.frame:Hide()
        self.activeCount = 0
        return
    end

    local allReady = true
    for _, data in ipairs(activeIcons) do
        if not data.isReady then
            allReady = false
            break
        end
    end

    local spacing = allReady and 2 or 4
    local iconWidth = iconSize
    if displayMode == "ICON_NAME" then
        iconWidth = allReady and (iconSize + 30) or (iconSize + 50)
    elseif displayMode == "NAME_ONLY" then
        iconWidth = 80
    end

    if allReady and #activeIcons >= 3 and displayMode ~= "NAME_ONLY" then
        spacing = -(iconSize * 0.2)
    end

    local totalWidth = #activeIcons * iconWidth + math.max(0, #activeIcons - 1) * spacing
    local totalHeight = iconSize + 15
    if displayMode == "NAME_ONLY" then
        totalHeight = 20
    end
    self.frame:SetSize(math.max(1, totalWidth), totalHeight)

    local timerPosition = settings.timerPosition or "INSIDE"

    for i, data in ipairs(activeIcons) do
        local icon = self:GetIcon(i)
        icon.timerInside:Hide()
        icon.timerInside:SetText("")
        icon.timerBelow:Hide()
        icon.timerBelow:SetText("")
        if displayMode == "NAME_ONLY" then
            icon:SetSize(iconWidth, 20)
            icon.icon:Hide()
        else
            icon:SetSize(iconWidth, iconSize + 15)
            icon.icon:SetSize(iconSize, iconSize)
            icon.icon:Show()
        end

        icon:ClearAllPoints()
        icon:SetPoint("LEFT", self.frame, "LEFT", (i - 1) * (iconWidth + spacing), 0)

        local cached = self.spellCache and self.spellCache[data.spellId]
        if (not cached or cached.needsRefresh) and not self.inCombat then
            self:CacheSpellInfo(data.spellId)
            cached = self.spellCache[data.spellId]
        end
        local spellIcon = cached and cached.icon or 134400
        local spellName = cached and cached.name or ""
        icon.icon.texture:SetTexture(spellIcon)
        icon.spellId = data.spellId
        icon.spellName:ClearAllPoints()
        if displayMode == "ICON_NAME" then
            if timerPosition == "BELOW" then
                icon.spellName:SetPoint("TOP", icon.timerBelow, "BOTTOM", 0, -1)
            else
                icon.spellName:SetPoint("TOP", icon.icon, "BOTTOM", 0, -2)
            end
            icon.spellName:SetText(spellName)
            icon.spellName:SetTextColor(1, 1, 1, 1)
            icon.spellName:Show()
        elseif displayMode == "NAME_ONLY" then
            icon.spellName:SetPoint("CENTER", icon, "CENTER", 0, 0)
            icon.spellName:Show()
        else
            icon.spellName:SetText("")
            icon.spellName:Hide()
        end

        if data.isReady then
            icon.cooldown:Clear()
            icon.readyFlash:Show()
            icon.readyText:Show()
            if timerPosition == "BELOW" then
                icon.timerBelow:SetText("READY")
                icon.timerBelow:SetTextColor(0.2, 1, 0.2, 1)
                icon.timerBelow:Show()
            end
            if displayMode == "NAME_ONLY" then
                icon.spellName:SetText(spellName .. " READY")
                icon.spellName:SetTextColor(0.2, 1, 0.2, 1)
            end
        else
            icon.readyFlash:Hide()
            icon.readyText:Hide()
            if data.onCooldown and data.startTime > 0 and data.duration > 0 then
                icon.cooldown:SetCooldown(data.startTime, data.duration)
                if data.remaining > 0 then
                    local timerText = format("%.1f", data.remaining)
                    if timerPosition == "BELOW" then
                        icon.timerBelow:SetText(timerText)
                        icon.timerBelow:SetTextColor(1, 1, 1, 1)
                        icon.timerBelow:Show()
                    else
                        icon.timerInside:SetText(timerText)
                        icon.timerInside:Show()
                    end
                end
            else
                icon.cooldown:Clear()
            end
            if displayMode == "NAME_ONLY" then
                local timerStr = data.remaining > 0 and format("%.1f", data.remaining) or ""
                icon.spellName:SetText(spellName .. " " .. timerStr)
                icon.spellName:SetTextColor(1, 1, 1, 1)
            end
        end

        icon:Show()
    end

    -- Hide unused icons
    for i = #activeIcons + 1, #self.icons do
        self.icons[i]:Hide()
    end

    self.activeCount = #activeIcons
    self.frame:Show()
end

function ca:AddTrackedSpell(spellId)
    local trackedSpells = self:GetTrackedSpells()
    for _, id in ipairs(trackedSpells) do
        if id == spellId then
            TankAssist.Addon:Print("Spell already tracked.")
            return
        end
    end
    table.insert(trackedSpells, spellId)
    self.spellStates[spellId] = { wasOnCooldown = false, readyFlashTime = 0 }
    self:EnsureSpellRegistered(spellId)
    self.spellCache = self.spellCache or {}
    self:CacheSpellInfo(spellId)
    local cached = self.spellCache[spellId]
    TankAssist.Addon:Print("Now tracking: " .. (cached and cached.name or "Spell " .. spellId))
end

function ca:RemoveTrackedSpell(spellId)
    local trackedSpells = self:GetTrackedSpells()
    for i, id in ipairs(trackedSpells) do
        if id == spellId then
            table.remove(trackedSpells, i)
            self.spellStates[spellId] = nil
            local spellInfo = C_Spell.GetSpellInfo(spellId)
            TankAssist.Addon:Print("Removed: " .. (spellInfo and spellInfo.name or "Spell " .. spellId))
            return
        end
    end
    TankAssist.Addon:Print("Spell not found in tracked list.")
end

function ca:LoadSpecDefaults()
    local specId = TankAssist.Utils:GetCurrentSpec()
    if not specId then
        TankAssist.Addon:Print("Could not determine current spec.")
        return
    end

    local defaults = TankAssist.Constants.CooldownAlertDefaults[specId]
    if not defaults then
        TankAssist.Addon:Print("No default spells for " .. (TankAssist.Constants.SpecNames[specId] or "this spec") .. ".")
        return
    end

    local settings = self:GetSettings()
    if not settings.trackedSpellsBySpec then
        settings.trackedSpellsBySpec = {}
    end
    settings.trackedSpellsBySpec[specId] = {}
    self.spellStates = {}
    self.unavailableSpells = {}

    local trackedSpells = self:GetTrackedSpells()
    for _, spellId in ipairs(defaults) do
        table.insert(trackedSpells, spellId)
        self.spellStates[spellId] = { wasOnCooldown = false, readyFlashTime = 0 }
        self:EnsureSpellRegistered(spellId)
    end

    TankAssist.Addon:Print("Loaded " .. #defaults .. " default spells for " .. (TankAssist.Constants.SpecNames[specId] or "this spec") .. ".")

    -- Print the list
    for _, spellId in ipairs(trackedSpells) do
        local spellInfo = C_Spell.GetSpellInfo(spellId)
        local spellName = spellInfo and spellInfo.name or "Unknown"
        print(string.format("  %s (ID: %d)", spellName, spellId))
    end
end

function ca:RegisterEditMode()
    if not self.frame then return end

    if IsLibEQOLAvailable() then
        self:RegisterEditModeLibEQOL()
    elseif IsEditModeAvailable() then
        self:RegisterEditModeBasic()
    end
end

function ca:BuildLEMSettings()
    local self_ref = self

    return {
        {
            order = 199,
            name = "Enabled",
            kind = lem.SettingType.Checkbox,
            default = true,
            get = function(layoutName)
                local enabled = self_ref:GetSettings().enabled
                if enabled == nil then return true end
                return enabled
            end,
            set = function(layoutName, value)
                self_ref:SetEnabled(value)
            end,
        },
        {
            order = 200,
            name = "Scale",
            kind = lem.SettingType.Slider,
            default = 1.0,
            minValue = 0.5,
            maxValue = 2.0,
            valueStep = 0.1,
            get = function(layoutName)
                return self_ref:GetSettings().scale or 1.0
            end,
            set = function(layoutName, value)
                value = math.floor(value * 10 + 0.5) / 10
                self_ref:SetScale(value)
            end,
        },
        {
            order = 201,
            name = "Icon Size",
            kind = lem.SettingType.Slider,
            default = 36,
            minValue = 24,
            maxValue = 64,
            valueStep = 4,
            get = function(layoutName)
                return self_ref:GetSettings().iconSize or 36
            end,
            set = function(layoutName, value)
                value = math.floor(value / 4 + 0.5) * 4
                self_ref:SetIconSize(value)
            end,
        },
        {
            order = 202,
            name = "Display Mode",
            kind = lem.SettingType.Dropdown,
            default = "Icon Only",
            values = {
                { text = "Icon Only" },
                { text = "Icon + Name" },
                { text = "Name Only" },
            },
            get = function(layoutName)
                local mode = self_ref:GetSettings().displayMode or "ICON_ONLY"
                if mode == "ICON_NAME" then return "Icon + Name"
                elseif mode == "NAME_ONLY" then return "Name Only"
                end
                return "Icon Only"
            end,
            set = function(layoutName, value)
                if value == "Icon + Name" then
                    self_ref:GetSettings().displayMode = "ICON_NAME"
                elseif value == "Name Only" then
                    self_ref:GetSettings().displayMode = "NAME_ONLY"
                else
                    self_ref:GetSettings().displayMode = "ICON_ONLY"
                end
                if self_ref.editMode then
                    self_ref:OnEditModeEnter()
                end
            end,
        },
        {
            order = 203,
            name = "Alert Style",
            kind = lem.SettingType.Dropdown,
            default = "Countdown + Ready",
            values = {
                { text = "Ready Only" },
                { text = "Countdown Only" },
                { text = "Countdown + Ready" },
            },
            get = function(layoutName)
                local style = self_ref:GetSettings().alertStyle or "BOTH"
                if style == "READY_ONLY" then return "Ready Only"
                elseif style == "COUNTDOWN_ONLY" then return "Countdown Only"
                end
                return "Countdown + Ready"
            end,
            set = function(layoutName, value)
                if value == "Ready Only" then
                    self_ref:GetSettings().alertStyle = "READY_ONLY"
                elseif value == "Countdown Only" then
                    self_ref:GetSettings().alertStyle = "COUNTDOWN_ONLY"
                else
                    self_ref:GetSettings().alertStyle = "BOTH"
                end
            end,
        },
        {
            order = 204,
            name = "Show Only In Combat",
            kind = lem.SettingType.Checkbox,
            default = false,
            get = function(layoutName)
                return self_ref:GetSettings().showOnlyInCombat or false
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().showOnlyInCombat = value
            end,
        },
        {
            order = 205,
            name = "Countdown Duration",
            kind = lem.SettingType.Slider,
            default = 3,
            minValue = 2,
            maxValue = 15,
            valueStep = 1,
            get = function(layoutName)
                return self_ref:GetSettings().countdownDuration or 3
            end,
            set = function(layoutName, value)
                value = math.floor(value + 0.5)
                self_ref:GetSettings().countdownDuration = value
            end,
        },
        {
            order = 206,
            name = "Timer Position",
            kind = lem.SettingType.Dropdown,
            default = "Inside Icon",
            values = {
                { text = "Inside Icon" },
                { text = "Below Icon" },
            },
            get = function(layoutName)
                local pos = self_ref:GetSettings().timerPosition or "INSIDE"
                if pos == "BELOW" then return "Below Icon" end
                return "Inside Icon"
            end,
            set = function(layoutName, value)
                if value == "Below Icon" then
                    self_ref:GetSettings().timerPosition = "BELOW"
                else
                    self_ref:GetSettings().timerPosition = "INSIDE"
                end
                if self_ref.editMode then
                    self_ref:OnEditModeEnter()
                end
            end,
        },
        {
            order = 207,
            name = "Border Color",
            kind = lem.SettingType.Color,
            default = { r = 0.9, g = 0.7, b = 0.2, a = 1 },
            hasOpacity = false,
            get = function(layoutName)
                return self_ref:GetSettings().borderColor or { r = 0.9, g = 0.7, b = 0.2, a = 1 }
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().borderColor = { r = value.r, g = value.g, b = value.b, a = value.a or 1 }
                self_ref:UpdateBorderColor()
            end,
        },
        {
            order = 208,
            name = "Sound Enabled (Coming Soon)",
            kind = lem.SettingType.Checkbox,
            default = false,
            isEnabled = false,
            get = function(layoutName)
                return false
            end,
            set = function(layoutName, value)
            end,
        },
    }
end

function ca:RegisterEditModeLibEQOL()
    local self_ref = self
    local settings = self:GetSettings()

    local defaults = {
        point = settings.position.point or "CENTER",
        relativePoint = settings.position.relativePoint or "CENTER",
        x = settings.position.x or 0,
        y = settings.position.y or -320,
    }

    local function OnPositionChanged(...)
        local point, relativePoint, x, y
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if type(v) == "string" and not point then
                local anchors = { CENTER=1, TOP=1, BOTTOM=1, LEFT=1, RIGHT=1, TOPLEFT=1, TOPRIGHT=1, BOTTOMLEFT=1, BOTTOMRIGHT=1 }
                if anchors[v] then
                    point = v
                end
            elseif type(v) == "string" and point and not relativePoint then
                local anchors = { CENTER=1, TOP=1, BOTTOM=1, LEFT=1, RIGHT=1, TOPLEFT=1, TOPRIGHT=1, BOTTOMLEFT=1, BOTTOMRIGHT=1 }
                if anchors[v] then
                    relativePoint = v
                end
            elseif type(v) == "number" and not x then
                x = v
            elseif type(v) == "number" and x and not y then
                y = v
            end
        end
        if not point then return end
        self_ref:GetSettings().position = {
            point = point,
            relativePoint = relativePoint or point,
            x = x or 0,
            y = y or 0,
        }
    end

    lem:AddFrame(self.frame, OnPositionChanged, defaults)
    lem:AddFrameSettings(self.frame, self:BuildLEMSettings())
    lem:SetFrameResetVisible(self.frame, true)

    lem:RegisterCallback("enter", function()
        self_ref:OnEditModeEnter()
    end)

    lem:RegisterCallback("exit", function()
        self_ref:OnEditModeExit()
    end)
end

function ca:RegisterEditModeBasic()
    local self_ref = self

    EventRegistry:RegisterCallback("EditMode.Enter", function()
        self_ref:OnEditModeEnter()
    end, self)

    EventRegistry:RegisterCallback("EditMode.Exit", function()
        self_ref:OnEditModeExit()
    end, self)

    if EditModeManagerFrame then
        hooksecurefunc(EditModeManagerFrame, "SaveLayouts", function()
            self_ref:SavePosition()
        end)
        hooksecurefunc(EditModeManagerFrame, "RevertAllChanges", function()
            self_ref:RestorePosition()
        end)
    end

    self:CreateBasicSelectionOverlay()

    if IsInEditMode() then
        self:OnEditModeEnter()
    end
end

function ca:CreateBasicSelectionOverlay()
    local self_ref = self
    local selection = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    selection:SetAllPoints()
    selection:SetFrameStrata("HIGH")
    selection:SetFrameLevel(100)
    selection:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
    })
    selection:SetBackdropBorderColor(0.9, 0.7, 0.2, 1)
    selection.highlight = selection:CreateTexture(nil, "OVERLAY")
    selection.highlight:SetAllPoints()
    selection.highlight:SetColorTexture(0.9, 0.7, 0.2, 0.15)
    selection.highlight:Hide()
    selection.label = selection:CreateFontString(nil, "OVERLAY")
    selection.label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    selection.label:SetPoint("CENTER")
    selection.label:SetText("CD Alerts")
    selection.label:SetTextColor(1, 1, 1, 1)
    selection:EnableMouse(true)
    selection:RegisterForDrag("LeftButton")
    selection:SetMovable(true)
    selection:SetScript("OnEnter", function(sel)
        if self_ref.editMode then
            sel.highlight:Show()
        end
    end)
    selection:SetScript("OnLeave", function(sel)
        sel.highlight:Hide()
    end)
    selection:SetScript("OnDragStart", function(sel)
        if self_ref.editMode then
            self_ref.frame:StartMoving()
        end
    end)
    selection:SetScript("OnDragStop", function(sel)
        self_ref.frame:StopMovingOrSizing()
        self_ref:SavePosition()
    end)
    selection:Hide()
    self.selection = selection
end

function ca:SavePosition()
    if not self.frame then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    local settings = self:GetSettings()
    settings.position = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
    settings.scale = self.frame:GetScale()
end

function ca:RestorePosition()
    if not self.frame then return end
    local validAnchors = { CENTER=1, TOP=1, BOTTOM=1, LEFT=1, RIGHT=1, TOPLEFT=1, TOPRIGHT=1, BOTTOMLEFT=1, BOTTOMRIGHT=1 }
    local settings = self:GetSettings()
    local pos = settings.position or {}
    self.frame:ClearAllPoints()
    if validAnchors[pos.point] and type(pos.x) == "number" and type(pos.y) == "number" then
        self.frame:SetPoint(pos.point, UIParent, validAnchors[pos.relativePoint] and pos.relativePoint or pos.point, pos.x, pos.y)
    else
        settings.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -320 }
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, -320)
    end
    self.frame:SetScale(settings.scale or 1.0)
end

function ca:OnEditModeEnter()
    if not self.frame then return end
    self.editMode = true
    self.frame:SetMovable(true)

    local settings = self:GetSettings()
    local iconSize = settings.iconSize or 36
    local displayMode = settings.displayMode or "ICON_ONLY"
    local spacing = 4
    local placeholderSpells = { 871, 12975, 6552 }
    local specId = TankAssist.Utils:GetCurrentSpec()
    if specId and TankAssist.Constants.CooldownAlertDefaults[specId] then
        placeholderSpells = TankAssist.Constants.CooldownAlertDefaults[specId]
    end
    local placeholderCount = math.min(3, #placeholderSpells)

    local iconWidth = iconSize
    if displayMode == "ICON_NAME" then
        iconWidth = iconSize + 50
    elseif displayMode == "NAME_ONLY" then
        iconWidth = 80
    end
    local totalWidth = placeholderCount * iconWidth + (placeholderCount - 1) * spacing
    local totalHeight = iconSize + 15
    if displayMode == "NAME_ONLY" then
        totalHeight = 20
    end
    self.frame:SetSize(totalWidth, totalHeight)

    local timerPosition = settings.timerPosition or "INSIDE"

    for i = 1, placeholderCount do
        local icon = self:GetIcon(i)
        local spellId = placeholderSpells[i]

        if displayMode == "NAME_ONLY" then
            icon:SetSize(iconWidth, 20)
            icon.icon:Hide()
        else
            icon:SetSize(iconWidth, iconSize + 15)
            icon.icon:SetSize(iconSize, iconSize)
            icon.icon:Show()
        end

        icon:ClearAllPoints()
        icon:SetPoint("LEFT", self.frame, "LEFT", (i - 1) * (iconWidth + spacing), 0)

        local spellInfo = C_Spell.GetSpellInfo(spellId)
        local spellIcon = spellInfo and spellInfo.iconID
        icon.icon.texture:SetTexture(spellIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon.spellId = spellId
        icon.cooldown:Clear()
        local fakeTimer = string.format("%.1f", 1.5 + i * 0.5)
        icon.timerInside:Hide()
        icon.timerInside:SetText("")
        icon.timerBelow:Hide()
        icon.timerBelow:SetText("")
        if timerPosition == "BELOW" then
            icon.timerBelow:SetText(fakeTimer)
            icon.timerBelow:SetTextColor(1, 1, 1, 1)
            icon.timerBelow:Show()
        else
            icon.timerInside:SetText(fakeTimer)
            icon.timerInside:Show()
        end
        icon.readyFlash:Hide()
        icon.readyText:Hide()

        local spellName = spellInfo and spellInfo.name or "Spell"
        icon.spellName:ClearAllPoints()
        if displayMode == "ICON_NAME" then
            if timerPosition == "BELOW" then
                icon.spellName:SetPoint("TOP", icon.timerBelow, "BOTTOM", 0, -1)
            else
                icon.spellName:SetPoint("TOP", icon.icon, "BOTTOM", 0, -2)
            end
            icon.spellName:SetText(spellName)
            icon.spellName:SetTextColor(1, 1, 1, 1)
            icon.spellName:Show()
        elseif displayMode == "NAME_ONLY" then
            icon.spellName:SetPoint("CENTER", icon, "CENTER", 0, 0)
            icon.spellName:SetText(spellName .. " " .. fakeTimer)
            icon.spellName:SetTextColor(1, 1, 1, 1)
            icon.spellName:Show()
        else
            icon.spellName:SetText("")
            icon.spellName:Hide()
        end

        icon:Show()
    end

    for i = placeholderCount + 1, #self.icons do
        self.icons[i]:Hide()
    end

    self.frame:Show()
    self:UpdateDisabledVisual()
    if self.selection and not IsLibEQOLAvailable() then
        self.selection:Show()
    end
end

function ca:OnEditModeExit()
    if not self.frame then return end
    self.editMode = false
    if self.selection and not IsLibEQOLAvailable() then
        self.selection:Hide()
    end
    self.frame:Hide()
end

function ca:IsEnabled()
    local enabled = self:GetSettings().enabled
    if enabled == nil then return true end
    return enabled
end

function ca:SetEnabled(enabled)
    self:GetSettings().enabled = enabled
    TankAssist.Addon.db.profile.cooldownAlerts.enabled = enabled
    if not enabled and not self.editMode then
        self.frame:Hide()
    end
    self:UpdateDisabledVisual()
end

function ca:UpdateDisabledVisual()
    if not self.frame then return end
    if self:IsEnabled() then
        self.frame:SetAlpha(1.0)
    else
        self.frame:SetAlpha(0.4)
    end
end

function ca:SetScale(scale)
    if self.frame then
        self.frame:SetScale(scale)
        self:GetSettings().scale = scale
    end
end

function ca:SetIconSize(size)
    if not self.frame then return end
    self:GetSettings().iconSize = size
    if self.editMode then
        self:OnEditModeEnter()
    end
end

function ca:UpdateBorderColor()
    local saved = self:GetSettings().borderColor or { r = 0.9, g = 0.7, b = 0.2, a = 1 }
    local r, g, b, a = saved.r or 0.9, saved.g or 0.7, saved.b or 0.2, saved.a or 1
    for _, icon in ipairs(self.icons) do
        if icon.icon then
            icon.icon.borderTop:SetColorTexture(r, g, b, a)
            icon.icon.borderBottom:SetColorTexture(r, g, b, a)
            icon.icon.borderLeft:SetColorTexture(r, g, b, a)
            icon.icon.borderRight:SetColorTexture(r, g, b, a)
        end
    end
end

function ca:IsInEditMode()
    return self.editMode or (EditModeManagerFrame and EditModeManagerFrame.editModeActive)
end

-- Events

function ca:OnTrackedSpellCast(spellId)
    local sv = TankAssist.SecretValues
    local trackedSpells = self:GetTrackedSpells()

    for _, trackedId in ipairs(trackedSpells) do
        if trackedId == spellId then
            local knownCD = sv.KnownCooldowns[spellId]
            if knownCD and knownCD > 1.5 then
                sv.trackedCooldowns[spellId] = {
                    castTime = GetTime(),
                    duration = knownCD,
                }
            end
            return
        end
    end
end

function ca:RegisterEvents()
    local self_ref = self
    self.eventFrame = CreateFrame("Frame")

    self.eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    self.eventFrame:SetScript("OnEvent", function(_, event, unit, castGUID, spellId)
        if event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
            if self_ref:IsEnabled() and not self_ref.editMode then
                self_ref:OnTrackedSpellCast(spellId)
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            self_ref.inCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            self_ref.inCombat = false
            if self_ref:GetSettings().showOnlyInCombat and not self_ref.editMode then
                self_ref.frame:Hide()
            end
        end
    end)

end

local function Initialize()
    if TankAssist.Addon then
        ca:Create()
        TankAssist.Addon.cooldownAlerts = ca
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.7, Initialize)
end)
