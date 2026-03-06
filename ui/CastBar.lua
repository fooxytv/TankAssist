local ADDON_NAME, TankAssist = ...

local lem
local lemLoadSuccess, lemResult = pcall(function()
    return LibStub("LibEQOLEditMode-1.0")
end)
if lemLoadSuccess then
    lem = lemResult
end

TankAssist.CastBar = {}
local CastBar = TankAssist.CastBar

local function IsLibEQOLAvailable()
    return lem ~= nil
end

local function IsInEditMode()
    return EditModeManagerFrame and EditModeManagerFrame.editModeActive
end

-- Try to read a secret boolean from the WoW API. Because secret values block
-- all comparisons and string conversion, we attempt the check inside pcall.
-- If the value is tainted we cannot determine true vs false, so return nil
-- to signal "unknown".
local function IsSecretTrue(val)
    if val == nil then return false end
    local ok, result = pcall(function() return val == true end)
    if not ok then return nil end
    return result
end

function CastBar:New(config)
    local instance = {}
    setmetatable(instance, { __index = self })
    instance.unit = config.unit
    instance.settingsKey = config.settingsKey
    instance.frameName = config.frameName
    instance.editModeName = config.editModeName
    return instance
end

function CastBar:GetSettings()
    return TankAssist.Addon.db.profile[self.settingsKey]
end

function CastBar:Create()
    local settings = self:GetSettings()

    self.frame = CreateFrame("Frame", self.frameName, UIParent, "BackdropTemplate")
    self.frame:SetSize(settings.width, settings.height + 16)
    self.frame.editModeName = self.editModeName

    local validAnchors = { CENTER=1, TOP=1, BOTTOM=1, LEFT=1, RIGHT=1, TOPLEFT=1, TOPRIGHT=1, BOTTOMLEFT=1, BOTTOMRIGHT=1 }
    local pos = settings.position or {}
    if validAnchors[pos.point] and type(pos.x) == "number" and type(pos.y) == "number" then
        self.frame:SetPoint(pos.point, UIParent, validAnchors[pos.relativePoint] and pos.relativePoint or pos.point, pos.x, pos.y)
    else
        local defaultY = self.unit == "player" and -100 or 100
        settings.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = defaultY }
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, defaultY)
    end
    self.frame:SetScale(settings.scale or 1.0)
    self.frame:SetClampedToScreen(true)

    self.frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        tile = true,
        tileSize = 16,
        edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })

    -- Status bar
    self.statusBar = CreateFrame("StatusBar", nil, self.frame)
    self.statusBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    self.statusBar:SetMinMaxValues(0, 1)
    self.statusBar:SetValue(0)

    self.statusBar.bg = self.statusBar:CreateTexture(nil, "BACKGROUND")
    self.statusBar.bg:SetAllPoints()

    -- Spell name (left) — parented to statusBar so text draws above the bar fill
    self.spellName = self.statusBar:CreateFontString(nil, "OVERLAY")
    self.spellName:SetJustifyH("LEFT")
    self.spellName:SetTextColor(1, 1, 1, 1)

    -- Cast time remaining (right)
    self.castTime = self.statusBar:CreateFontString(nil, "OVERLAY")
    self.castTime:SetJustifyH("RIGHT")
    self.castTime:SetTextColor(1, 1, 1, 1)

    -- Border textures
    self.borderTop = self.frame:CreateTexture(nil, "OVERLAY")
    self.borderTop:SetPoint("TOPLEFT", 0, 0)
    self.borderTop:SetPoint("TOPRIGHT", 0, 0)
    self.borderTop:SetHeight(1)

    self.borderBottom = self.frame:CreateTexture(nil, "OVERLAY")
    self.borderBottom:SetPoint("BOTTOMLEFT", 0, 0)
    self.borderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
    self.borderBottom:SetHeight(1)

    self.borderLeft = self.frame:CreateTexture(nil, "OVERLAY")
    self.borderLeft:SetPoint("TOPLEFT", 0, 0)
    self.borderLeft:SetPoint("BOTTOMLEFT", 0, 0)
    self.borderLeft:SetWidth(1)

    self.borderRight = self.frame:CreateTexture(nil, "OVERLAY")
    self.borderRight:SetPoint("TOPRIGHT", 0, 0)
    self.borderRight:SetPoint("BOTTOMRIGHT", 0, 0)
    self.borderRight:SetWidth(1)

    -- Spell icon
    self.icon = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    self.icon.texture = self.icon:CreateTexture(nil, "ARTWORK")
    self.icon.texture:SetAllPoints()
    self.icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    self.iconBorders = {}
    self.iconBorders.top = self.icon:CreateTexture(nil, "OVERLAY")
    self.iconBorders.top:SetPoint("TOPLEFT", 0, 0)
    self.iconBorders.top:SetPoint("TOPRIGHT", 0, 0)
    self.iconBorders.top:SetHeight(1)

    self.iconBorders.bottom = self.icon:CreateTexture(nil, "OVERLAY")
    self.iconBorders.bottom:SetPoint("BOTTOMLEFT", 0, 0)
    self.iconBorders.bottom:SetPoint("BOTTOMRIGHT", 0, 0)
    self.iconBorders.bottom:SetHeight(1)

    self.iconBorders.left = self.icon:CreateTexture(nil, "OVERLAY")
    self.iconBorders.left:SetPoint("TOPLEFT", 0, 0)
    self.iconBorders.left:SetPoint("BOTTOMLEFT", 0, 0)
    self.iconBorders.left:SetWidth(1)

    self.iconBorders.right = self.icon:CreateTexture(nil, "OVERLAY")
    self.iconBorders.right:SetPoint("TOPRIGHT", 0, 0)
    self.iconBorders.right:SetPoint("BOTTOMRIGHT", 0, 0)
    self.iconBorders.right:SetWidth(1)

    self.casting = false
    self.channeling = false
    self.editMode = false
    self.notInterruptible = false

    self:ApplySettings()
    self:RegisterEditMode()
    self:RegisterEvents()

    self.frame:Hide()

    return self.frame
end

function CastBar:ApplySettings()
    local settings = self:GetSettings()

    -- Dimensions
    self.frame:SetSize(settings.width, settings.height + (settings.textPosition == "ABOVE" and 16 or 0))
    self.frame:SetScale(settings.scale or 1.0)

    -- Background
    local bg = settings.bgColor or { 0.15, 0.15, 0.15, 0.8 }
    self.frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 0.8)
    self.statusBar.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 0.8)

    -- Status bar position
    self.statusBar:ClearAllPoints()
    self.statusBar:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 1, 1)
    self.statusBar:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -1, 1)
    self.statusBar:SetHeight(settings.height - 2)

    -- Bar color
    self.statusBar:SetStatusBarColor(unpack(settings.interruptibleColor))

    -- Border
    local bc = settings.borderColor or { 0.3, 0.3, 0.3 }
    self:SetBorderColor(bc[1], bc[2], bc[3], 1)

    -- Font
    local fontSize = settings.fontSize or 11
    local fontPath = self:ResolveFontPath(settings.fontFace)
    local fontFlag = self:ResolveFontFlag(settings.fontFlag)
    self.spellName:SetFont(fontPath, fontSize, fontFlag)
    self.castTime:SetFont(fontPath, fontSize, fontFlag)

    -- Text visibility
    if settings.showSpellName == false then
        self.spellName:Hide()
    else
        self.spellName:Show()
    end
    if settings.showCastTime == false then
        self.castTime:Hide()
    else
        self.castTime:Show()
    end

    -- Bar texture
    local barTexturePath = self:ResolveBarTexture(settings.barTexture)
    self.statusBar:SetStatusBarTexture(barTexturePath)

    -- Text alignment
    self.spellName:SetJustifyH(settings.nameAlignment or "LEFT")
    self.castTime:SetJustifyH(settings.timerAlignment or "RIGHT")

    -- Text position
    self:ApplyTextPosition()

    -- Icon layout
    self:ApplyIconLayout()
end

function CastBar:ResolveFontPath(name)
    for _, entry in ipairs(TankAssist.Constants.Fonts) do
        if entry.name == name then return entry.path end
    end
    return "Fonts\\FRIZQT__.TTF"
end

function CastBar:ResolveFontFlag(name)
    for _, entry in ipairs(TankAssist.Constants.FontFlags) do
        if entry.name == name then return entry.flag end
    end
    return "OUTLINE"
end

function CastBar:ResolveBarTexture(name)
    for _, entry in ipairs(TankAssist.Constants.BarTextures) do
        if entry.name == name then return entry.path end
    end
    return "Interface\\Buttons\\WHITE8x8"
end

function CastBar:ApplyTextPosition()
    local settings = self:GetSettings()
    local textPos = settings.textPosition or "ABOVE"

    self.spellName:ClearAllPoints()
    self.castTime:ClearAllPoints()

    if textPos == "INSIDE" then
        self.spellName:SetPoint("LEFT", self.statusBar, "LEFT", 4, 0)
        self.castTime:SetPoint("RIGHT", self.statusBar, "RIGHT", -4, 0)
        -- No extra height needed for text above
        self.frame:SetSize(settings.width, settings.height)
    else -- "ABOVE"
        self.spellName:SetPoint("BOTTOMLEFT", self.statusBar, "TOPLEFT", 2, 1)
        self.castTime:SetPoint("BOTTOMRIGHT", self.statusBar, "TOPRIGHT", -2, 1)
        self.frame:SetSize(settings.width, settings.height + 16)
    end
end

function CastBar:ApplyIconLayout()
    local settings = self:GetSettings()
    local showIcon = settings.showIcon
    if showIcon == nil then showIcon = true end
    local iconPos = settings.iconPosition or "LEFT"
    local iconSize = settings.height

    self.statusBar:ClearAllPoints()

    if not showIcon then
        self.icon:Hide()
        self.statusBar:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 1, 1)
        self.statusBar:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -1, 1)
        self.statusBar:SetHeight(settings.height - 2)

        local textPos = settings.textPosition or "ABOVE"
        if textPos == "INSIDE" then
            self.frame:SetSize(settings.width, settings.height)
        else
            self.frame:SetSize(settings.width, settings.height + 16)
        end
        return
    end

    self.icon:Show()
    self.icon:ClearAllPoints()
    self.icon:SetSize(iconSize, iconSize)

    local textPos = settings.textPosition or "ABOVE"
    local frameHeight = textPos == "INSIDE" and settings.height or (settings.height + 16)
    self.frame:SetSize(settings.width + iconSize, frameHeight)

    if iconPos == "LEFT" then
        self.icon:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 0, 0)
        self.statusBar:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", iconSize + 1, 1)
        self.statusBar:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -1, 1)
    else
        self.icon:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
        self.statusBar:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 1, 1)
        self.statusBar:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -(iconSize + 1), 1)
    end
    self.statusBar:SetHeight(settings.height - 2)
end

function CastBar:SetIcon(texture)
    if self.icon and self.icon.texture then
        self.icon.texture:SetTexture(texture)
    end
end

function CastBar:SetBorderColor(r, g, b, a)
    a = a or 1
    self.borderTop:SetColorTexture(r, g, b, a)
    self.borderBottom:SetColorTexture(r, g, b, a)
    self.borderLeft:SetColorTexture(r, g, b, a)
    self.borderRight:SetColorTexture(r, g, b, a)
    if self.iconBorders then
        for _, border in pairs(self.iconBorders) do
            border:SetColorTexture(r, g, b, a)
        end
    end
end

function CastBar:UpdateBarAppearance()
    local settings = self:GetSettings()
    local thick = 1
    if self.notInterruptible then
        self.statusBar:SetStatusBarColor(unpack(settings.nonInterruptibleColor))
        self:SetBorderColor(0.8, 0.1, 0.1, 1)
        thick = 2
    elseif self.channeling then
        self.statusBar:SetStatusBarColor(unpack(settings.channelColor))
        local bc = settings.borderColor or { 0.3, 0.3, 0.3 }
        self:SetBorderColor(bc[1], bc[2], bc[3], 1)
    else
        self.statusBar:SetStatusBarColor(unpack(settings.interruptibleColor))
        local bc = settings.borderColor or { 0.3, 0.3, 0.3 }
        self:SetBorderColor(bc[1], bc[2], bc[3], 1)
    end
    self.borderTop:SetHeight(thick)
    self.borderBottom:SetHeight(thick)
    self.borderLeft:SetWidth(thick)
    self.borderRight:SetWidth(thick)
    if self.iconBorders then
        self.iconBorders.top:SetHeight(thick)
        self.iconBorders.bottom:SetHeight(thick)
        self.iconBorders.left:SetWidth(thick)
        self.iconBorders.right:SetWidth(thick)
    end
end

function CastBar:SetupCastDuration(durationObj)
    self.activeDuration = durationObj
    if durationObj then
        local total = durationObj:GetTotalDuration()
        self.statusBar:SetMinMaxValues(0, total)
        self.statusBar:SetTimerDuration(durationObj, 0)
    end
end

function CastBar:StartCast(unit)
    if unit ~= self.unit then return end

    local name, _, texture, _, _, _, _, notInterruptible = UnitCastingInfo(self.unit)
    if not name then
        self:StopCast()
        return
    end

    self.casting = true
    self.channeling = false
    self.interrupted = false
    self.frame:SetAlpha(1)
    -- Default to interruptible (false); the UNIT_SPELLCAST_NOT_INTERRUPTIBLE
    -- event will correct this if needed. The secret API value is unreadable.
    self.notInterruptible = IsSecretTrue(notInterruptible) or false

    local castDuration = UnitCastingDuration(self.unit)
    self:SetupCastDuration(castDuration)

    self.spellName:SetText(name)
    self:SetIcon(texture)
    self:UpdateBarAppearance()
    self:SetupOnUpdate()

    if self:ShouldBeVisible() then
        self.frame:Show()
    end
end

function CastBar:StartChannel(unit)
    if unit ~= self.unit then return end

    local name, _, texture, _, _, _, notInterruptible = UnitChannelInfo(self.unit)
    if not name then
        self:StopCast()
        return
    end

    self.casting = false
    self.channeling = true
    self.interrupted = false
    self.frame:SetAlpha(1)
    self.notInterruptible = IsSecretTrue(notInterruptible) or false

    local channelDuration = UnitChannelDuration(self.unit)
    self:SetupCastDuration(channelDuration)

    self.spellName:SetText(name)
    self:SetIcon(texture)
    self:UpdateBarAppearance()
    self:SetupOnUpdate()

    if self:ShouldBeVisible() then
        self.frame:Show()
    end
end

function CastBar:StartEmpower(unit)
    if unit ~= self.unit then return end

    -- Empowered casts are channels internally — try UnitChannelInfo first
    local name, _, texture, _, _, _, notInterruptible = UnitChannelInfo(self.unit)
    local isChannel = true
    if not name then
        -- Fallback to UnitCastingInfo in case the API varies by context
        name, _, texture, _, _, _, _, notInterruptible = UnitCastingInfo(self.unit)
        isChannel = false
    end
    if not name then
        self:StopCast()
        return
    end

    self.casting = not isChannel
    self.channeling = isChannel
    self.interrupted = false
    self.frame:SetAlpha(1)
    self.notInterruptible = IsSecretTrue(notInterruptible) or false

    local duration
    if isChannel then
        duration = UnitChannelDuration(self.unit)
    else
        duration = UnitCastingDuration(self.unit)
    end
    self:SetupCastDuration(duration)

    self.spellName:SetText(name)
    self:SetIcon(texture)
    self:UpdateBarAppearance()
    self:SetupOnUpdate()

    if self:ShouldBeVisible() then
        self.frame:Show()
    end
end

function CastBar:SetupOnUpdate()
    local settings = self:GetSettings()
    local self_ref = self
    self.frame:SetScript("OnUpdate", function()
        if not self_ref.activeDuration then return end
        local remaining = self_ref.activeDuration:GetRemainingDuration()
        self_ref.statusBar:SetValue(remaining)
        if settings.showCastTime ~= false then
            local ok, text = pcall(function()
                if remaining < 5 then
                    return format("%.1fs", remaining)
                else
                    return format("%.0fs", remaining)
                end
            end)
            if ok then
                self_ref.castTime:SetText(text)
            end
        end
    end)
end

function CastBar:StopCast()
    self.casting = false
    self.channeling = false
    self.interrupted = false
    self.activeDuration = nil
    self.frame:SetScript("OnUpdate", nil)
    self.frame:SetAlpha(1)
    if not self.editMode then
        self.frame:Hide()
    end
end

function CastBar:Update()
    if self.editMode then return end
    if self.interrupted then return end
    if not self.casting and not self.channeling then return end

    local castName = UnitCastingInfo(self.unit)
    if castName then return end

    local chanName = UnitChannelInfo(self.unit)
    if chanName then return end

    self:StopCast()
end

function CastBar:CheckUnitCast()
    local name, _, texture, _, _, _, _, notInterruptible = UnitCastingInfo(self.unit)
    if name then
        self.casting = true
        self.channeling = false
        self.notInterruptible = IsSecretTrue(notInterruptible) or false
        self.spellName:SetText(name)
        self:SetIcon(texture)

        local castDuration = UnitCastingDuration(self.unit)
        self:SetupCastDuration(castDuration)
        self:UpdateBarAppearance()
        self:SetupOnUpdate()

        if self:ShouldBeVisible() then
            self.frame:Show()
        end
        return
    end

    local cName, _, cTexture, _, _, _, cNotInterruptible = UnitChannelInfo(self.unit)
    if cName then
        self.casting = false
        self.channeling = true
        self.notInterruptible = IsSecretTrue(cNotInterruptible) or false
        self.spellName:SetText(cName)
        self:SetIcon(cTexture)

        local channelDuration = UnitChannelDuration(self.unit)
        self:SetupCastDuration(channelDuration)
        self:UpdateBarAppearance()
        self:SetupOnUpdate()

        if self:ShouldBeVisible() then
            self.frame:Show()
        end
        return
    end

    self:StopCast()
end

function CastBar:RegisterEvents()
    local self_ref = self
    self.eventFrame = CreateFrame("Frame")

    if self.unit == "player" then
        -- Use RegisterUnitEvent for efficiency — only fires for "player"
        self.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        self.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
        self.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        self.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
        self.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        self.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
        self.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
        self.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
        self.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")

        self.eventFrame:SetScript("OnEvent", function(_, event, unit, ...)
            if unit ~= "player" then return end
            if event == "UNIT_SPELLCAST_START" then
                self_ref:StartCast(unit)
            elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
                self_ref:StartChannel(unit)
            elseif event == "UNIT_SPELLCAST_EMPOWER_START" then
                self_ref:StartEmpower(unit)
            elseif event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
                self_ref:StartEmpower(unit)
            elseif event == "UNIT_SPELLCAST_STOP"
                or event == "UNIT_SPELLCAST_FAILED"
                or event == "UNIT_SPELLCAST_CHANNEL_STOP"
                or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
                self_ref:StopCast()
            elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
                self_ref:OnInterrupted()
            end
        end)
    else
        -- Target bar: generic events filtered by unit, plus target change
        self.eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
        self.eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
        self.eventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
        self.eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
        self.eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
        self.eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
        self.eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
        self.eventFrame:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
        self.eventFrame:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START")
        self.eventFrame:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
        self.eventFrame:RegisterEvent("UNIT_SPELLCAST_EMPOWER_UPDATE")
        self.eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

        self.eventFrame:SetScript("OnEvent", function(_, event, unit, ...)
            if event == "PLAYER_TARGET_CHANGED" then
                self_ref:CheckUnitCast()
            elseif unit == "target" then
                if event == "UNIT_SPELLCAST_START" then
                    self_ref:StartCast(unit)
                elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
                    self_ref:StartChannel(unit)
                elseif event == "UNIT_SPELLCAST_EMPOWER_START" then
                    self_ref:StartEmpower(unit)
                elseif event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
                    self_ref:StartEmpower(unit)
                elseif event == "UNIT_SPELLCAST_STOP"
                    or event == "UNIT_SPELLCAST_FAILED"
                    or event == "UNIT_SPELLCAST_CHANNEL_STOP"
                    or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
                    self_ref:StopCast()
                elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
                    self_ref:OnInterrupted()
                elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
                    self_ref.notInterruptible = false
                    self_ref:UpdateBarAppearance()
                elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
                    self_ref.notInterruptible = true
                    self_ref:UpdateBarAppearance()
                end
            end
        end)
    end
end

function CastBar:OnInterrupted()
    if not self.frame then return end
    self.statusBar:SetStatusBarColor(1, 0, 0)
    self.spellName:SetText("INTERRUPTED")
    self.castTime:SetText("")
    self.casting = false
    self.channeling = false
    self.interrupted = true

    -- Freeze the bar and stop the normal OnUpdate
    self.frame:SetScript("OnUpdate", nil)
    self.frame:SetAlpha(1)
    self.frame:Show()

    -- Fade out over the linger duration
    local lingerDuration = 0.8
    local fadeDuration = 0.4
    local self_ref = self
    local startTime = GetTime()

    self.frame:SetScript("OnUpdate", function(frame)
        local elapsed = GetTime() - startTime
        if elapsed >= lingerDuration + fadeDuration then
            frame:SetScript("OnUpdate", nil)
            self_ref.interrupted = false
            if not self_ref.casting and not self_ref.channeling then
                self_ref:StopCast()
                self_ref.frame:SetAlpha(1)
            end
            return
        end
        -- Start fading after the linger period
        if elapsed > lingerDuration then
            local fadeProgress = (elapsed - lingerDuration) / fadeDuration
            frame:SetAlpha(1 - fadeProgress)
        end
    end)
end

-- Edit Mode Integration

function CastBar:RegisterEditMode()
    if not self.frame then return end

    if IsLibEQOLAvailable() then
        self:RegisterEditModeLibEQOL()
    elseif EditModeManagerFrame and EventRegistry then
        self:RegisterEditModeBasic()
    end
end

function CastBar:BuildLEMSettings()
    local self_ref = self

    local settings = {
        -- General
        {
            order = 99,
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
    }

    -- Player-only: option to hide Blizzard's default cast bar
    if self.unit == "player" then
        table.insert(settings, {
            order = 99.5,
            name = "Hide Blizzard Cast Bar",
            kind = lem.SettingType.Checkbox,
            default = false,
            get = function(layoutName)
                return self_ref:GetSettings().hideBlizzardCastBar or false
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().hideBlizzardCastBar = value
                self_ref:ApplyBlizzardCastBarVisibility()
            end,
        })
    end

    local remaining = {
        {
            order = 100,
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
                self_ref:SetBarScale(value)
            end,
        },
        {
            order = 101,
            name = "Width",
            kind = lem.SettingType.Slider,
            default = 200,
            minValue = 100,
            maxValue = 400,
            valueStep = 1,
            get = function(layoutName)
                return self_ref:GetSettings().width or 200
            end,
            set = function(layoutName, value)
                value = math.floor(value + 0.5)
                self_ref:SetBarWidth(value)
            end,
        },
        {
            order = 102,
            name = "Height",
            kind = lem.SettingType.Slider,
            default = 20,
            minValue = 10,
            maxValue = 40,
            valueStep = 1,
            get = function(layoutName)
                return self_ref:GetSettings().height or 20
            end,
            set = function(layoutName, value)
                value = math.floor(value + 0.5)
                self_ref:SetBarHeight(value)
            end,
        },
        -- Colors divider
        {
            order = 200,
            name = "Colors",
            kind = lem.SettingType.Divider,
        },
        {
            order = 201,
            name = "Cast Color",
            kind = lem.SettingType.Color,
            default = self_ref.unit == "player"
                and { r = 0.0, g = 0.6, b = 1.0 }
                or { r = 1.0, g = 0.7, b = 0.0 },
            get = function(layoutName)
                local c = self_ref:GetSettings().interruptibleColor
                return { r = c[1], g = c[2], b = c[3] }
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().interruptibleColor = { value.r, value.g, value.b }
                self_ref:ApplySettings()
            end,
        },
        {
            order = 202,
            name = "Non-Interruptible",
            kind = lem.SettingType.Color,
            default = self_ref.unit == "player"
                and { r = 0.0, g = 0.6, b = 1.0 }
                or { r = 0.6, g = 0.3, b = 0.3 },
            get = function(layoutName)
                local c = self_ref:GetSettings().nonInterruptibleColor
                return { r = c[1], g = c[2], b = c[3] }
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().nonInterruptibleColor = { value.r, value.g, value.b }
                self_ref:ApplySettings()
            end,
        },
        {
            order = 203,
            name = "Channel Color",
            kind = lem.SettingType.Color,
            default = self_ref.unit == "player"
                and { r = 0.0, g = 0.8, b = 0.4 }
                or { r = 0.0, g = 0.6, b = 1.0 },
            get = function(layoutName)
                local c = self_ref:GetSettings().channelColor
                return { r = c[1], g = c[2], b = c[3] }
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().channelColor = { value.r, value.g, value.b }
                self_ref:ApplySettings()
            end,
        },
        {
            order = 204,
            name = "Background Color",
            kind = lem.SettingType.Color,
            hasOpacity = true,
            default = { r = 0.15, g = 0.15, b = 0.15, a = 0.8 },
            get = function(layoutName)
                local c = self_ref:GetSettings().bgColor or { 0.15, 0.15, 0.15, 0.8 }
                return { r = c[1], g = c[2], b = c[3], a = c[4] }
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().bgColor = { value.r, value.g, value.b, value.a or 0.8 }
                self_ref:ApplySettings()
            end,
        },
        {
            order = 205,
            name = "Border Color",
            kind = lem.SettingType.Color,
            default = { r = 0.3, g = 0.3, b = 0.3 },
            get = function(layoutName)
                local c = self_ref:GetSettings().borderColor or { 0.3, 0.3, 0.3 }
                return { r = c[1], g = c[2], b = c[3] }
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().borderColor = { value.r, value.g, value.b }
                self_ref:ApplySettings()
            end,
        },
        -- Text divider
        {
            order = 300,
            name = "Text",
            kind = lem.SettingType.Divider,
        },
        {
            order = 301,
            name = "Show Spell Name",
            kind = lem.SettingType.Checkbox,
            default = true,
            get = function(layoutName)
                local v = self_ref:GetSettings().showSpellName
                if v == nil then return true end
                return v
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().showSpellName = value
                self_ref:ApplySettings()
            end,
        },
        {
            order = 302,
            name = "Show Cast Time",
            kind = lem.SettingType.Checkbox,
            default = true,
            get = function(layoutName)
                local v = self_ref:GetSettings().showCastTime
                if v == nil then return true end
                return v
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().showCastTime = value
                self_ref:ApplySettings()
            end,
        },
        {
            order = 303,
            name = "Font Size",
            kind = lem.SettingType.Slider,
            default = 11,
            minValue = 8,
            maxValue = 18,
            valueStep = 1,
            get = function(layoutName)
                return self_ref:GetSettings().fontSize or 11
            end,
            set = function(layoutName, value)
                value = math.floor(value + 0.5)
                self_ref:GetSettings().fontSize = value
                self_ref:ApplySettings()
            end,
        },
        {
            order = 304,
            name = "Text Position",
            kind = lem.SettingType.Dropdown,
            default = "Above Bar",
            values = {
                { text = "Above Bar" },
                { text = "Inside Bar" },
            },
            get = function(layoutName)
                local pos = self_ref:GetSettings().textPosition or "ABOVE"
                return pos == "INSIDE" and "Inside Bar" or "Above Bar"
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().textPosition = value == "Inside Bar" and "INSIDE" or "ABOVE"
                self_ref:ApplySettings()
            end,
        },
        {
            order = 305,
            name = "Font Face",
            kind = lem.SettingType.Dropdown,
            default = "Friz Quadrata",
            values = (function()
                local v = {}
                for _, entry in ipairs(TankAssist.Constants.Fonts) do
                    table.insert(v, { text = entry.name })
                end
                return v
            end)(),
            get = function(layoutName)
                return self_ref:GetSettings().fontFace or "Friz Quadrata"
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().fontFace = value
                self_ref:ApplySettings()
            end,
        },
        {
            order = 306,
            name = "Font Style",
            kind = lem.SettingType.Dropdown,
            default = "Outline",
            values = (function()
                local v = {}
                for _, entry in ipairs(TankAssist.Constants.FontFlags) do
                    table.insert(v, { text = entry.name })
                end
                return v
            end)(),
            get = function(layoutName)
                return self_ref:GetSettings().fontFlag or "Outline"
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().fontFlag = value
                self_ref:ApplySettings()
            end,
        },
        {
            order = 307,
            name = "Bar Texture",
            kind = lem.SettingType.Dropdown,
            default = "Solid",
            values = (function()
                local v = {}
                for _, entry in ipairs(TankAssist.Constants.BarTextures) do
                    table.insert(v, { text = entry.name })
                end
                return v
            end)(),
            get = function(layoutName)
                return self_ref:GetSettings().barTexture or "Solid"
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().barTexture = value
                self_ref:ApplySettings()
            end,
        },
        {
            order = 308,
            name = "Name Alignment",
            kind = lem.SettingType.Dropdown,
            default = "Left",
            values = {
                { text = "Left" },
                { text = "Center" },
                { text = "Right" },
            },
            get = function(layoutName)
                local align = self_ref:GetSettings().nameAlignment or "LEFT"
                return align:sub(1,1) .. align:sub(2):lower()
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().nameAlignment = value:upper()
                self_ref:ApplySettings()
            end,
        },
        {
            order = 309,
            name = "Timer Alignment",
            kind = lem.SettingType.Dropdown,
            default = "Right",
            values = {
                { text = "Left" },
                { text = "Center" },
                { text = "Right" },
            },
            get = function(layoutName)
                local align = self_ref:GetSettings().timerAlignment or "RIGHT"
                return align:sub(1,1) .. align:sub(2):lower()
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().timerAlignment = value:upper()
                self_ref:ApplySettings()
            end,
        },
        -- Icon divider
        {
            order = 400,
            name = "Icon",
            kind = lem.SettingType.Divider,
        },
        {
            order = 401,
            name = "Show Spell Icon",
            kind = lem.SettingType.Checkbox,
            default = true,
            get = function(layoutName)
                local v = self_ref:GetSettings().showIcon
                if v == nil then return true end
                return v
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().showIcon = value
                self_ref:ApplySettings()
            end,
        },
        {
            order = 402,
            name = "Icon Position",
            kind = lem.SettingType.Dropdown,
            default = "Left",
            values = {
                { text = "Left" },
                { text = "Right" },
            },
            get = function(layoutName)
                local pos = self_ref:GetSettings().iconPosition or "LEFT"
                return pos == "RIGHT" and "Right" or "Left"
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().iconPosition = value == "Right" and "RIGHT" or "LEFT"
                self_ref:ApplySettings()
            end,
        },
    }

    for _, entry in ipairs(remaining) do
        table.insert(settings, entry)
    end

    return settings
end

function CastBar:RegisterEditModeLibEQOL()
    local self_ref = self
    local settings = self:GetSettings()

    local defaults = {
        point = settings.position.point or "CENTER",
        relativePoint = settings.position.relativePoint or "CENTER",
        x = settings.position.x or 0,
        y = settings.position.y or (self.unit == "player" and -100 or 100),
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

function CastBar:RegisterEditModeBasic()
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

function CastBar:CreateBasicSelectionOverlay()
    local self_ref = self
    local selection = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    selection:SetAllPoints()
    selection:SetFrameStrata("HIGH")
    selection:SetFrameLevel(100)
    selection:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
    })
    selection:SetBackdropBorderColor(0, 0.6, 1, 1)
    selection.highlight = selection:CreateTexture(nil, "OVERLAY")
    selection.highlight:SetAllPoints()
    selection.highlight:SetColorTexture(0, 0.6, 1, 0.15)
    selection.highlight:Hide()
    selection.label = selection:CreateFontString(nil, "OVERLAY")
    selection.label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    selection.label:SetPoint("CENTER")
    selection.label:SetText(self.editModeName)
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

function CastBar:SavePosition()
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

function CastBar:RestorePosition()
    if not self.frame then return end
    local validAnchors = { CENTER=1, TOP=1, BOTTOM=1, LEFT=1, RIGHT=1, TOPLEFT=1, TOPRIGHT=1, BOTTOMLEFT=1, BOTTOMRIGHT=1 }
    local settings = self:GetSettings()
    local pos = settings.position or {}
    self.frame:ClearAllPoints()
    if validAnchors[pos.point] and type(pos.x) == "number" and type(pos.y) == "number" then
        self.frame:SetPoint(pos.point, UIParent, validAnchors[pos.relativePoint] and pos.relativePoint or pos.point, pos.x, pos.y)
    else
        local defaultY = self.unit == "player" and -100 or 100
        settings.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = defaultY }
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, defaultY)
    end
    self.frame:SetScale(settings.scale or 1.0)
end

function CastBar:OnEditModeEnter()
    if not self.frame then return end
    self.editMode = true
    self.frame:SetMovable(true)
    self.spellName:SetText(self.editModeName)
    self.castTime:SetText("1.5s")
    self.statusBar:SetValue(0.6)
    self:SetIcon("Interface\\Icons\\INV_Misc_QuestionMark")
    local settings = self:GetSettings()
    self.statusBar:SetStatusBarColor(unpack(settings.interruptibleColor))
    local bc = settings.borderColor or { 0.3, 0.3, 0.3 }
    self:SetBorderColor(bc[1], bc[2], bc[3], 1)
    self.frame:Show()
    self:UpdateDisabledVisual()
    if self.selection and not IsLibEQOLAvailable() then
        self.selection:Show()
    end
end

function CastBar:OnEditModeExit()
    if not self.frame then return end
    self.editMode = false
    if self.selection and not IsLibEQOLAvailable() then
        self.selection:Hide()
    end
    if not self.casting and not self.channeling then
        self.frame:Hide()
    end
end

-- Visibility

function CastBar:IsEnabled()
    local enabled = self:GetSettings().enabled
    if enabled == nil then return true end
    return enabled
end

function CastBar:SetEnabled(enabled)
    self:GetSettings().enabled = enabled
    if not enabled and not self.editMode then
        self.frame:Hide()
    end
    self:UpdateDisabledVisual()
end

function CastBar:ApplyBlizzardCastBarVisibility()
    if self.unit ~= "player" then return end
    local hide = self:GetSettings().hideBlizzardCastBar or false
    if PlayerCastingBarFrame then
        if hide then
            PlayerCastingBarFrame:UnregisterAllEvents()
            PlayerCastingBarFrame:Hide()
        else
            PlayerCastingBarFrame:RegisterEvent("UNIT_SPELLCAST_START")
            PlayerCastingBarFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
            PlayerCastingBarFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
            PlayerCastingBarFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
            PlayerCastingBarFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
            PlayerCastingBarFrame:RegisterEvent("UNIT_SPELLCAST_DELAYED")
            PlayerCastingBarFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
            PlayerCastingBarFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
            PlayerCastingBarFrame:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
        end
    end
end

function CastBar:ShouldBeVisible()
    if not self:IsEnabled() then return false end
    return true
end

function CastBar:UpdateVisibility()
    if not self.frame then return end
    if self.editMode then
        self.frame:Show()
        return
    end
    if (self.casting or self.channeling) and self:ShouldBeVisible() then
        self.frame:Show()
    else
        self.frame:Hide()
    end
end

function CastBar:UpdateDisabledVisual()
    if not self.frame then return end
    if self:IsEnabled() then
        self.frame:SetAlpha(1.0)
    else
        self.frame:SetAlpha(0.4)
    end
end

-- Size setters

function CastBar:SetBarScale(scale)
    if self.frame then
        self.frame:SetScale(scale)
        self:GetSettings().scale = scale
    end
end

function CastBar:SetBarWidth(width)
    if not self.frame then return end
    self:GetSettings().width = width
    self:ApplySettings()
end

function CastBar:SetBarHeight(height)
    if not self.frame then return end
    self:GetSettings().height = height
    self:ApplySettings()
end

function CastBar:IsInEditMode()
    return self.editMode or (EditModeManagerFrame and EditModeManagerFrame.editModeActive)
end

-- Initialization

local function Initialize()
    if TankAssist.Addon then
        local targetBar = TankAssist.CastBar:New({
            unit = "target",
            settingsKey = "targetCastBar",
            frameName = "TankAssistTargetCastBar",
            editModeName = "Target Cast Bar",
        })
        targetBar:Create()
        TankAssist.Addon.targetCastBar = targetBar

        local playerBar = TankAssist.CastBar:New({
            unit = "player",
            settingsKey = "playerCastBar",
            frameName = "TankAssistPlayerCastBar",
            editModeName = "Player Cast Bar",
        })
        playerBar:Create()
        playerBar:ApplyBlizzardCastBarVisibility()
        TankAssist.Addon.playerCastBar = playerBar
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.5, Initialize)
end)
