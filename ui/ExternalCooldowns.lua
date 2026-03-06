local ADDON_NAME, TankAssist = ...

local lem
local lemLoadSuccess, lemResult = pcall(function()
    return LibStub("LibEQOLEditMode-1.0")
end)
if lemLoadSuccess then
    lem = lemResult
end

TankAssist.ExternalCooldowns = {}
local ec = TankAssist.ExternalCooldowns

local function IsLibEQOLAvailable()
    return lem ~= nil
end

local function IsEditModeAvailable()
    return EditModeManagerFrame ~= nil and EventRegistry ~= nil
end

local function IsInEditMode()
    return EditModeManagerFrame and EditModeManagerFrame.editModeActive
end

-- External defensive cooldowns from healers/allies
-- fallbackIcon: guaranteed texture path in case C_Spell.GetSpellInfo returns nil for cross-class spells
ec.EXTERNALS = {
    { spellId = 33206,  name = "Pain Suppression",        source = "Discipline Priest",   fallbackIcon = "Interface\\Icons\\Spell_Holy_PainSupression" },
    { spellId = 47788,  name = "Guardian Spirit",          source = "Holy Priest",          fallbackIcon = "Interface\\Icons\\Spell_Holy_GuardianSpirit" },
    { spellId = 102342, name = "Ironbark",                 source = "Restoration Druid",    fallbackIcon = "Interface\\Icons\\Spell_Druid_Ironbark" },
    { spellId = 116849, name = "Life Cocoon",              source = "Mistweaver Monk",      fallbackIcon = "Interface\\Icons\\Life_Cocoon" },
    { spellId = 6940,   name = "Blessing of Sacrifice",    source = "Paladin",              fallbackIcon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
    { spellId = 1022,   name = "Blessing of Protection",   source = "Paladin",              fallbackIcon = "Interface\\Icons\\Spell_Holy_SealOfProtection" },
    { spellId = 204018, name = "Blessing of Spellwarding", source = "Paladin",              fallbackIcon = "Interface\\Icons\\Spell_Holy_BlessingOfProtection" },
    { spellId = 97462,  name = "Rallying Cry",             source = "Warrior",              fallbackIcon = "Interface\\Icons\\Ability_Warrior_RallyingCry" },
}

-- Detect an external buff on the player (not restricted to self-cast)
function ec:GetExternalBuffInfo(spellId)
    local result = {
        exists = false,
        duration = 0,
        expirationTime = 0,
        isSecret = false,
    }

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
        if auraData then
            result.exists = true
            local duration = auraData.duration
            local expiration = auraData.expirationTime
            if TankAssist.SecretValues and TankAssist.SecretValues.IsSecret then
                if TankAssist.SecretValues:IsSecret(duration) or TankAssist.SecretValues:IsSecret(expiration) then
                    result.isSecret = true
                    result.duration = 0
                    result.expirationTime = 0
                else
                    result.duration = tonumber(tostring(duration)) or 0
                    result.expirationTime = tonumber(tostring(expiration)) or 0
                end
            else
                result.duration = tonumber(tostring(duration)) or 0
                result.expirationTime = tonumber(tostring(expiration)) or 0
            end
        end
    else
        -- Fallback: use AuraUtil with "HELPFUL" (no |PLAYER) to detect externals
        local spellInfo = C_Spell.GetSpellInfo(spellId)
        local spellName = spellInfo and spellInfo.name
        if spellName and AuraUtil and AuraUtil.FindAuraByName then
            local name, _, _, _, duration, expirationTime = AuraUtil.FindAuraByName(
                spellName, "player", "HELPFUL"
            )
            if name then
                result.exists = true
                result.duration = tonumber(tostring(duration)) or 0
                result.expirationTime = tonumber(tostring(expirationTime)) or 0
            end
        end
    end

    return result
end

function ec:GetSettings()
    return TankAssist.Addon.db.profile.externalCooldowns
end

function ec:Create()
    local settings = self:GetSettings()

    self.frame = CreateFrame("Frame", "TankAssistExternalCooldowns", UIParent)
    self.frame:SetSize(1, 1) -- Resized dynamically based on active icons
    self.frame.editModeName = "External Cooldowns"

    local validAnchors = { CENTER=1, TOP=1, BOTTOM=1, LEFT=1, RIGHT=1, TOPLEFT=1, TOPRIGHT=1, BOTTOMLEFT=1, BOTTOMRIGHT=1 }
    local pos = settings.position or {}
    if validAnchors[pos.point] and type(pos.x) == "number" and type(pos.y) == "number" then
        self.frame:SetPoint(pos.point, UIParent, validAnchors[pos.relativePoint] and pos.relativePoint or pos.point, pos.x, pos.y)
    else
        settings.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -260 }
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, -260)
    end
    self.frame:SetScale(settings.scale or 1.0)
    self.frame:SetClampedToScreen(true)

    self.icons = {}
    self.activeCount = 0
    self.editMode = false
    self.inCombat = UnitAffectingCombat("player") or false

    self:RegisterEditMode()
    self:RegisterEvents()

    self.frame:Hide()

    return self.frame
end

function ec:CreateExternalIcon()
    local settings = self:GetSettings()
    local size = settings.iconSize

    local frame = CreateFrame("Frame", nil, self.frame)
    frame:SetSize(size, size + 15)

    -- Icon container
    frame.icon = CreateFrame("Frame", nil, frame)
    frame.icon:SetSize(size, size)
    frame.icon:SetPoint("TOP", frame, "TOP", 0, 0)

    -- Background
    frame.icon.bg = frame.icon:CreateTexture(nil, "BACKGROUND")
    frame.icon.bg:SetAllPoints()
    frame.icon.bg:SetColorTexture(0, 0, 0, 0.6)

    -- Spell texture
    frame.icon.texture = frame.icon:CreateTexture(nil, "ARTWORK")
    frame.icon.texture:SetPoint("TOPLEFT", 2, -2)
    frame.icon.texture:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Cooldown sweep
    frame.cooldown = CreateFrame("Cooldown", nil, frame.icon, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints(frame.icon.texture)
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetHideCountdownNumbers(true)

    -- Border color (configurable via Edit Mode settings)
    local saved = self:GetSettings().borderColor or { r = 0.2, g = 0.8, b = 0.3, a = 1 }
    local borderColor = { saved.r or 0.2, saved.g or 0.8, saved.b or 0.3, saved.a or 1 }
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

    -- Timer text — inside icon (centered, large)
    frame.timerInside = frame.icon:CreateFontString(nil, "OVERLAY")
    frame.timerInside:SetFont("Fonts\\FRIZQT__.TTF", 16, "THICKOUTLINE")
    frame.timerInside:SetPoint("CENTER", frame.icon, "CENTER", 0, 0)
    frame.timerInside:SetTextColor(1, 1, 1, 1)

    -- Timer text — below icon (original style)
    frame.timerBelow = frame:CreateFontString(nil, "OVERLAY")
    frame.timerBelow:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    frame.timerBelow:SetPoint("TOP", frame.icon, "BOTTOM", 0, -2)
    frame.timerBelow:SetTextColor(1, 1, 1, 1)

    -- Keep .timer as alias for backward compat
    frame.timer = frame.timerBelow

    -- Spell name text (for ICON_NAME display mode)
    frame.spellName = frame:CreateFontString(nil, "OVERLAY")
    frame.spellName:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    frame.spellName:SetTextColor(1, 1, 1, 1)
    frame.spellName:SetWordWrap(false)

    -- Tooltip on hover
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

function ec:GetIcon(index)
    if not self.icons[index] then
        self.icons[index] = self:CreateExternalIcon()
    end
    return self.icons[index]
end

function ec:Update()
    if self.editMode then return end

    local settings = self:GetSettings()
    if settings.showOnlyInCombat and not self.inCombat then
        self.frame:Hide()
        return
    end

    local activeExternals = {}
    local now = GetTime()

    for _, ext in ipairs(self.EXTERNALS) do
        local info = self:GetExternalBuffInfo(ext.spellId)
        if info.exists then
            table.insert(activeExternals, {
                spellId = ext.spellId,
                name = ext.name,
                source = ext.source,
                fallbackIcon = ext.fallbackIcon,
                duration = info.duration,
                expirationTime = info.expirationTime,
                isSecret = info.isSecret,
            })
        end
    end

    if #activeExternals == 0 then
        self.frame:Hide()
        self.activeCount = 0
        return
    end

    local iconSize = settings.iconSize
    local displayMode = settings.displayMode or "ICON_ONLY"
    local timerPosition = settings.timerPosition or "BELOW"
    local spacing = 4

    local iconWidth = iconSize
    if displayMode == "ICON_NAME" then
        iconWidth = iconSize + 50
    elseif displayMode == "NAME_ONLY" then
        iconWidth = 80
    end
    local totalWidth = #activeExternals * iconWidth + (#activeExternals - 1) * spacing
    local totalHeight = displayMode == "NAME_ONLY" and 20 or (iconSize + 15)
    self.frame:SetSize(totalWidth, totalHeight)

    for i, ext in ipairs(activeExternals) do
        local icon = self:GetIcon(i)

        -- Hide both timers, then show the active one as needed
        icon.timerInside:Hide()
        icon.timerInside:SetText("")
        icon.timerBelow:Hide()
        icon.timerBelow:SetText("")

        -- Update icon size
        if displayMode == "NAME_ONLY" then
            icon:SetSize(iconWidth, 20)
            icon.icon:Hide()
        else
            icon:SetSize(iconWidth, iconSize + 15)
            icon.icon:SetSize(iconSize, iconSize)
            icon.icon:Show()
        end

        -- Position
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", self.frame, "LEFT", (i - 1) * (iconWidth + spacing), 0)

        -- Spell texture (with fallback for cross-class spells)
        local spellInfo = C_Spell.GetSpellInfo(ext.spellId)
        local spellIcon = spellInfo and spellInfo.iconID
        icon.icon.texture:SetTexture(spellIcon or ext.fallbackIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon.spellId = ext.spellId

        -- Spell name display
        icon.spellName:ClearAllPoints()
        if displayMode == "ICON_NAME" then
            if timerPosition == "BELOW" then
                icon.spellName:SetPoint("TOP", icon.timerBelow, "BOTTOM", 0, -1)
            else
                icon.spellName:SetPoint("TOP", icon.icon, "BOTTOM", 0, -2)
            end
            icon.spellName:SetText(ext.name)
            icon.spellName:Show()
        elseif displayMode == "NAME_ONLY" then
            icon.spellName:SetPoint("CENTER", icon, "CENTER", 0, 0)
            icon.spellName:Show()
        else
            icon.spellName:SetText("")
            icon.spellName:Hide()
        end

        -- Cooldown sweep and timer
        if not ext.isSecret and ext.duration > 0 and ext.expirationTime > 0 then
            local startTime = ext.expirationTime - ext.duration
            icon.cooldown:SetCooldown(startTime, ext.duration)
            local remaining = ext.expirationTime - now
            if remaining > 0 then
                local timerText
                if remaining < 10 then
                    timerText = format("%.1f", remaining)
                else
                    timerText = format("%.0f", remaining)
                end

                if displayMode == "NAME_ONLY" then
                    icon.spellName:SetText(ext.name .. " " .. timerText)
                elseif timerPosition == "BELOW" then
                    icon.timerBelow:SetText(timerText)
                    icon.timerBelow:Show()
                else
                    icon.timerInside:SetText(timerText)
                    icon.timerInside:Show()
                end
            end
        else
            icon.cooldown:Clear()
            if ext.isSecret then
                if displayMode == "NAME_ONLY" then
                    icon.spellName:SetText(ext.name .. " ?")
                elseif timerPosition == "BELOW" then
                    icon.timerBelow:SetText("?")
                    icon.timerBelow:Show()
                else
                    icon.timerInside:SetText("?")
                    icon.timerInside:Show()
                end
            end
        end

        icon:Show()
    end

    -- Hide unused icons
    for i = #activeExternals + 1, #self.icons do
        self.icons[i]:Hide()
    end

    self.activeCount = #activeExternals
    self.frame:Show()
end

-- Edit Mode

function ec:RegisterEditMode()
    if not self.frame then return end

    if IsLibEQOLAvailable() then
        self:RegisterEditModeLibEQOL()
    elseif IsEditModeAvailable() then
        self:RegisterEditModeBasic()
    end
end

function ec:BuildLEMSettings()
    local self_ref = self

    return {
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
                self_ref:SetScale(value)
            end,
        },
        {
            order = 101,
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
            order = 102,
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
            order = 103,
            name = "Timer Position",
            kind = lem.SettingType.Dropdown,
            default = "Below Icon",
            values = {
                { text = "Inside Icon" },
                { text = "Below Icon" },
            },
            get = function(layoutName)
                local pos = self_ref:GetSettings().timerPosition or "BELOW"
                if pos == "INSIDE" then return "Inside Icon" end
                return "Below Icon"
            end,
            set = function(layoutName, value)
                if value == "Inside Icon" then
                    self_ref:GetSettings().timerPosition = "INSIDE"
                else
                    self_ref:GetSettings().timerPosition = "BELOW"
                end
                if self_ref.editMode then
                    self_ref:OnEditModeEnter()
                end
            end,
        },
        {
            order = 104,
            name = "Border Color",
            kind = lem.SettingType.Color,
            default = { r = 0.2, g = 0.8, b = 0.3, a = 1 },
            hasOpacity = false,
            get = function(layoutName)
                return self_ref:GetSettings().borderColor or { r = 0.2, g = 0.8, b = 0.3, a = 1 }
            end,
            set = function(layoutName, value)
                self_ref:GetSettings().borderColor = { r = value.r, g = value.g, b = value.b, a = value.a or 1 }
                self_ref:UpdateBorderColor()
            end,
        },
        {
            order = 105,
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
    }
end

function ec:RegisterEditModeLibEQOL()
    local self_ref = self
    local settings = self:GetSettings()

    local defaults = {
        point = settings.position.point or "CENTER",
        relativePoint = settings.position.relativePoint or "CENTER",
        x = settings.position.x or 0,
        y = settings.position.y or -260,
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

function ec:RegisterEditModeBasic()
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

function ec:CreateBasicSelectionOverlay()
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
    selection.label:SetText("External CDs")
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

function ec:SavePosition()
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

function ec:RestorePosition()
    if not self.frame then return end
    local validAnchors = { CENTER=1, TOP=1, BOTTOM=1, LEFT=1, RIGHT=1, TOPLEFT=1, TOPRIGHT=1, BOTTOMLEFT=1, BOTTOMRIGHT=1 }
    local settings = self:GetSettings()
    local pos = settings.position or {}
    self.frame:ClearAllPoints()
    if validAnchors[pos.point] and type(pos.x) == "number" and type(pos.y) == "number" then
        self.frame:SetPoint(pos.point, UIParent, validAnchors[pos.relativePoint] and pos.relativePoint or pos.point, pos.x, pos.y)
    else
        settings.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -260 }
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, -260)
    end
    self.frame:SetScale(settings.scale or 1.0)
end

function ec:OnEditModeEnter()
    if not self.frame then return end
    self.editMode = true
    self.frame:SetMovable(true)

    -- Show 2 placeholder icons: Pain Suppression + Ironbark
    local placeholders = {
        self.EXTERNALS[1], -- Pain Suppression
        self.EXTERNALS[3], -- Ironbark
    }

    local settings = self:GetSettings()
    local iconSize = settings.iconSize
    local displayMode = settings.displayMode or "ICON_ONLY"
    local timerPosition = settings.timerPosition or "BELOW"
    local spacing = 4

    local iconWidth = iconSize
    if displayMode == "ICON_NAME" then
        iconWidth = iconSize + 50
    elseif displayMode == "NAME_ONLY" then
        iconWidth = 80
    end
    local totalWidth = #placeholders * iconWidth + (#placeholders - 1) * spacing
    local totalHeight = displayMode == "NAME_ONLY" and 20 or (iconSize + 15)
    self.frame:SetSize(totalWidth, totalHeight)

    for i, ph in ipairs(placeholders) do
        local icon = self:GetIcon(i)
        local fakeTimer = (i == 1) and "8s" or "5s"

        -- Reset both timers
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

        local spellInfo = C_Spell.GetSpellInfo(ph.spellId)
        local spellIcon = spellInfo and spellInfo.iconID
        icon.icon.texture:SetTexture(spellIcon or ph.fallbackIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon.spellId = ph.spellId
        icon.cooldown:Clear()

        -- Timer display
        if displayMode == "NAME_ONLY" then
            -- handled below with spell name
        elseif timerPosition == "BELOW" then
            icon.timerBelow:SetText(fakeTimer)
            icon.timerBelow:SetTextColor(1, 1, 1, 1)
            icon.timerBelow:Show()
        else
            icon.timerInside:SetText(fakeTimer)
            icon.timerInside:SetTextColor(1, 1, 1, 1)
            icon.timerInside:Show()
        end

        -- Spell name display
        local spellName = spellInfo and spellInfo.name or ph.name
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

    -- Hide extra icons
    for i = #placeholders + 1, #self.icons do
        self.icons[i]:Hide()
    end

    self.frame:Show()
    self:UpdateDisabledVisual()
    if self.selection and not IsLibEQOLAvailable() then
        self.selection:Show()
    end
end

function ec:OnEditModeExit()
    if not self.frame then return end
    self.editMode = false
    if self.selection and not IsLibEQOLAvailable() then
        self.selection:Hide()
    end
    -- Hide frame; Update() will show it again if externals are active
    self.frame:Hide()
end

-- Visibility / Settings

function ec:IsEnabled()
    local enabled = self:GetSettings().enabled
    if enabled == nil then return true end
    return enabled
end

function ec:SetEnabled(enabled)
    self:GetSettings().enabled = enabled
    TankAssist.Addon.db.profile.externalCooldowns.enabled = enabled
    if not enabled and not self.editMode then
        self.frame:Hide()
    end
    self:UpdateDisabledVisual()
end

function ec:UpdateDisabledVisual()
    if not self.frame then return end
    if self:IsEnabled() then
        self.frame:SetAlpha(1.0)
    else
        self.frame:SetAlpha(0.4)
    end
end

function ec:SetScale(scale)
    if self.frame then
        self.frame:SetScale(scale)
        self:GetSettings().scale = scale
    end
end

function ec:SetIconSize(size)
    if not self.frame then return end
    self:GetSettings().iconSize = size
    -- Icons will be resized on next Update() or edit mode refresh
    if self.editMode then
        self:OnEditModeEnter()
    end
end

function ec:UpdateBorderColor()
    local saved = self:GetSettings().borderColor or { r = 0.2, g = 0.8, b = 0.3, a = 1 }
    local r, g, b, a = saved.r or 0.2, saved.g or 0.8, saved.b or 0.3, saved.a or 1
    for _, icon in ipairs(self.icons) do
        if icon.icon then
            icon.icon.borderTop:SetColorTexture(r, g, b, a)
            icon.icon.borderBottom:SetColorTexture(r, g, b, a)
            icon.icon.borderLeft:SetColorTexture(r, g, b, a)
            icon.icon.borderRight:SetColorTexture(r, g, b, a)
        end
    end
end

function ec:IsInEditMode()
    return self.editMode or (EditModeManagerFrame and EditModeManagerFrame.editModeActive)
end

-- Events

function ec:RegisterEvents()
    local self_ref = self
    self.eventFrame = CreateFrame("Frame")

    self.eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    self.eventFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_AURA" and unit == "player" then
            -- Immediate update on aura change (the 0.1s ticker also calls Update)
            if self_ref:IsEnabled() and not self_ref.editMode then
                self_ref:Update()
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            self_ref.inCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            self_ref.inCombat = false
            -- Re-evaluate visibility for showOnlyInCombat
            if self_ref:GetSettings().showOnlyInCombat and not self_ref.editMode then
                self_ref.frame:Hide()
            end
        end
    end)
end

-- Initialization

local function Initialize()
    if TankAssist.Addon then
        ec:Create()
        TankAssist.Addon.externalCooldowns = ec
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.6, Initialize)
end)
