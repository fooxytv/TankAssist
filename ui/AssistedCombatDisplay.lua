local ADDON_NAME, TankAssist = ...

local lem
local lemLoadSuccess, lemResult = pcall(function()
    return LibStub("LibEQOLEditMode-1.0")
end)
if lemLoadSuccess then
    lem = lemResult
else
    print("|cFFFF6600[TankAssist]|r LibEQOL not available, using basic Edit Mode support")
end

TankAssist.AssistedCombatDisplay = {}
local acd = TankAssist.AssistedCombatDisplay

local assistedCombatAPI = {}

function assistedCombatAPI:IsAvailable()
    return C_AssistedCombat and C_AssistedCombat.GetNextCastSpell ~= nil
end

function assistedCombatAPI:GetRecommendedSpell()
    if C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
        local spellId = C_AssistedCombat.GetNextCastSpell(false)
        if spellId then
            return spellId
        end
    end

    local rotationSpells = self:GetRotationSpells()
    if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
        for _, spellId in ipairs(rotationSpells) do
            if C_SpellActivationOverlay.IsSpellOverlayed(spellId) then
                return spellId
            end
        end
    end

    return nil
end

function assistedCombatAPI:GetRotationSpells()
    if C_AssistedCombat and C_AssistedCombat.GetRotationSpells then
        return C_AssistedCombat.GetRotationSpells() or {}
    end
    return {}
end

local function IsLibEQOLAvailable()
    return lem ~= nil
end

local function IsEditModeAvailable()
    return EditModeManagerFrame ~= nil and EventRegistry ~= nil
end

local function IsInEditMode()
    return EditModeManagerFrame and EditModeManagerFrame.editModeActive
end

function acd:Create()
    local settings = TankAssist.Addon.db.profile.assistedCombat

    self.frame = CreateFrame("Frame", "TankAssistRotationFrame", UIParent, "BackdropTemplate")
    self.frame:SetSize(settings.iconSize * 2 + 4, settings.iconSize + 2)
    self.frame.editModeName = "TankAssist"
    self.frame:SetPoint(
        settings.position.point or "CENTER",
        UIParent,
        settings.position.relativePoint or "CENTER",
        settings.position.x or 0,
        settings.position.y or -200
    )
    self.frame:SetScale(settings.scale or 1.0)
    self.frame:SetClampedToScreen(true)

    self.frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = nil,
        tile = true,
        tileSize = 16,
        edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    self.frame:SetBackdropColor(0, 0, 0, 0.2)

    self.mainIcon = self:CreateIcon(self.frame, settings.iconSize)
    self.mainIcon:SetPoint("LEFT", self.frame, "LEFT", 1, 0)

    self.aoeIcon = self:CreateIcon(self.frame, settings.iconSize)
    self.aoeIcon:SetPoint("LEFT", self.mainIcon, "RIGHT", 2, 0)

    self.apiAvailable = assistedCombatAPI:IsAvailable()
    self.editMode = false
    self.inCombat = false

    self:RegisterEditMode()
    self:RegisterCombatEvents()

    if not self:IsEnabled() and not self:IsInEditMode() then
        self.frame:Hide()
    end

    return self.frame
end

function acd:CreateIcon(parent, size)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetSize(size, size)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0.12, 0.12, 0.12, 1)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", 2, -2)
    frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local borderColor = {0.3, 0.3, 0.3, 1}
    frame.borderTop = frame:CreateTexture(nil, "OVERLAY")
    frame.borderTop:SetPoint("TOPLEFT", 0, 0)
    frame.borderTop:SetPoint("TOPRIGHT", 0, 0)
    frame.borderTop:SetHeight(1)
    frame.borderTop:SetColorTexture(unpack(borderColor))
    frame.borderBottom = frame:CreateTexture(nil, "OVERLAY")
    frame.borderBottom:SetPoint("BOTTOMLEFT", 0, 0)
    frame.borderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.borderBottom:SetHeight(1)
    frame.borderBottom:SetColorTexture(unpack(borderColor))
    frame.borderLeft = frame:CreateTexture(nil, "OVERLAY")
    frame.borderLeft:SetPoint("TOPLEFT", 0, 0)
    frame.borderLeft:SetPoint("BOTTOMLEFT", 0, 0)
    frame.borderLeft:SetWidth(1)
    frame.borderLeft:SetColorTexture(unpack(borderColor))
    frame.borderRight = frame:CreateTexture(nil, "OVERLAY")
    frame.borderRight:SetPoint("TOPRIGHT", 0, 0)
    frame.borderRight:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.borderRight:SetWidth(1)
    frame.borderRight:SetColorTexture(unpack(borderColor))
    frame.border = {
        top = frame.borderTop,
        bottom = frame.borderBottom,
        left = frame.borderLeft,
        right = frame.borderRight,
    }
    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", 0, 0)
    frame.cooldown:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 0, 0)
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetHideCountdownNumbers(false)
    frame.gcdCooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.gcdCooldown:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", 0, 0)
    frame.gcdCooldown:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 0, 0)
    frame.gcdCooldown:SetDrawEdge(true)
    frame.gcdCooldown:SetDrawSwipe(true)
    frame.gcdCooldown:SetSwipeColor(1, 1, 1, 0.5)
    frame.gcdCooldown:SetHideCountdownNumbers(true)
    frame.gcdCooldown:SetFrameLevel(frame.cooldown:GetFrameLevel() + 1)
    frame.keybind = frame:CreateFontString(nil, "OVERLAY")
    frame.keybind:SetFont("Fonts\\FRIZQT__.TTF", size > 50 and 12 or 10, "OUTLINE")
    frame.keybind:SetPoint("TOPLEFT", 4, -4)
    frame.keybind:SetTextColor(1, 1, 1, 1)
    frame.count = frame:CreateFontString(nil, "OVERLAY")
    frame.count:SetFont("Fonts\\FRIZQT__.TTF", size > 50 and 14 or 11, "OUTLINE")
    frame.count:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.count:SetTextColor(1, 1, 1, 1)
    frame.unusable = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    frame.unusable:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", 0, 0)
    frame.unusable:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 0, 0)
    frame.unusable:SetColorTexture(0.1, 0.1, 0.1, 0.7)
    frame.unusable:Hide()
    frame:SetScript("OnEnter", function(self)
        if self.spellId and IsShiftKeyDown() then
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

function acd:BuildLEMSettings()
    local self_ref = self

    return {
        {
            order = 99,
            name = "Enabled",
            kind = lem.SettingType.Checkbox,
            default = true,
            get = function(layoutName)
                local enabled = TankAssist.Addon.db.profile.assistedCombat.enabled
                if enabled == nil then
                    return true
                end
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
                return TankAssist.Addon.db.profile.assistedCombat.scale or 1.0
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
            default = 50,
            minValue = 30,
            maxValue = 80,
            valueStep = 5,
            get = function(layoutName)
                return TankAssist.Addon.db.profile.assistedCombat.iconSize or 50
            end,
            set = function(layoutName, value)
                value = math.floor(value / 5 + 0.5) * 5
                self_ref:SetIconSize(value)
            end,
        },
        {
            order = 102,
            name = "Show Keybinds",
            kind = lem.SettingType.Checkbox,
            default = true,
            get = function(layoutName)
                return TankAssist.Addon.db.profile.assistedCombat.showKeybinds
            end,
            set = function(layoutName, value)
                TankAssist.Addon.db.profile.assistedCombat.showKeybinds = value
            end,
        },
    }
end

function acd:RegisterEditMode()
    if not self.frame then
        return
    end

    if IsLibEQOLAvailable() then
        self:RegisterEditModeLibEQOL()
    elseif IsEditModeAvailable() then
        self:RegisterEditModeBasic()
    end
end

function acd:RegisterEditModeLibEQOL()
    local self_ref = self

    local defaults = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = -200,
    }

    local function OnPositionChanged(point, relativePoint, x, y)
        TankAssist.Addon.db.profile.assistedCombat.position = {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y,
        }
        TankAssist.Utils:Debug("Position saved via LibEQOL:", point, x, y)
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

    TankAssist.Utils:Debug("TankAssist registered with LibEQOL Edit Mode")
end

function acd:RegisterEditModeBasic()
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

    TankAssist.Utils:Debug("TankAssist registered with basic Edit Mode support")
end

function acd:CreateBasicSelectionOverlay()
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
    selection.label:SetText("TankAssist")
    selection.label:SetTextColor(1, 1, 1, 1)
    selection:EnableMouse(true)
    selection:RegisterForDrag("LeftButton")
    selection:SetMovable(true)
    selection:SetScript("OnEnter", function(sel)
        if self.editMode then
            sel.highlight:Show()
        end
    end)
    selection:SetScript("OnLeave", function(sel)
        sel.highlight:Hide()
    end)
    selection:SetScript("OnDragStart", function(sel)
        if self.editMode then
            self.frame:StartMoving()
        end
    end)
    selection:SetScript("OnDragStop", function(sel)
        self.frame:StopMovingOrSizing()
        self:SavePosition()
    end)
    selection:Hide()
    self.selection = selection
end

function acd:SavePosition()
    if not self.frame then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    TankAssist.Addon.db.profile.assistedCombat.position = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
    TankAssist.Addon.db.profile.assistedCombat.scale = self.frame:GetScale()
    TankAssist.Utils:Debug("Position saved:", point, x, y)
end

function acd:RestorePosition()
    if not self.frame then return end
    local settings = TankAssist.Addon.db.profile.assistedCombat
    self.frame:ClearAllPoints()
    self.frame:SetPoint(
        settings.position.point or "CENTER",
        UIParent,
        settings.position.relativePoint or "CENTER",
        settings.position.x or 0,
        settings.position.y or -200
    )
    self.frame:SetScale(settings.scale or 1.0)
end

function acd:OnEditModeEnter()
    if not self.frame then return end
    self.editMode = true
    self.frame:SetMovable(true)
    self.frame:Show()
    self:UpdateDisabledVisual()
    if self.selection and not IsLibEQOLAvailable() then
        self.selection:Show()
    end
end

function acd:OnEditModeExit()
    if not self.frame then return end
    self.editMode = false
    self:UpdateDisabledVisual()
    if not self:IsEnabled() then
        self.frame:Hide()
    end
    if self.selection and not IsLibEQOLAvailable() then
        self.selection:Hide()
    end
end

function acd:RegisterCombatEvents()
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            self.inCombat = true
            self:UpdateCombatVisuals()
        elseif event == "PLAYER_REGEN_ENABLED" then
            self.inCombat = false
            self:UpdateCombatVisuals()
        end
    end)
    self.inCombat = UnitAffectingCombat("player")
    C_Timer.After(0.1, function()
        self:UpdateCombatVisuals()
    end)
end

function acd:UpdateCombatVisuals()
    if not self.frame then return end
    if self.inCombat then
        self.frame:SetAlpha(1.0)
        self.mainIcon:SetAlpha(1.0)
        self.aoeIcon:SetAlpha(1.0)
        self.frame:SetBackdropColor(0, 0, 0, 0.4)
    else
        self.frame:SetAlpha(0.2)
        self.mainIcon:SetAlpha(0.3)
        self.aoeIcon:SetAlpha(0.3)
        self.frame:SetBackdropColor(0, 0, 0, 0.1)
    end
end

function acd:Update()
    if not self.frame or not self.frame:IsShown() then return end
    local mainSpell = assistedCombatAPI:GetRecommendedSpell()
    local specModule = TankAssist.Addon.activeSpecModule
    local isTankSpec = TankAssist.Addon.isTankSpec
    if mainSpell then
        self:UpdateIcon(self.mainIcon, mainSpell, "main")
    else
        local recs = {}
        if specModule and specModule.GetRecommendations then
            recs = specModule:GetRecommendations() or {}
        end
        if recs[1] then
            self:UpdateIcon(self.mainIcon, recs[1].spellId, "main")
        else
            self:ClearIcon(self.mainIcon)
        end
    end
    local secondarySpell, spellType, priority = nil, "aoe", "NORMAL"
    if specModule then
        if specModule.GetSecondarySpell then
            secondarySpell, spellType, priority = specModule:GetSecondarySpell()
        elseif specModule.GetBestAoESpell then
            secondarySpell = specModule:GetBestAoESpell()
        else
            secondarySpell = specModule.aoeSpell
        end
    end
    if secondarySpell then
        self:UpdateIcon(self.aoeIcon, secondarySpell, spellType, priority)
        self.aoeIcon:Show()
    else
        self:ClearIcon(self.aoeIcon)
        if not isTankSpec then
            self.aoeIcon:Hide()
        end
    end
end

function acd:UpdateIcon(icon, spellId, spellType, priority)
    if not spellId then
        self:ClearIcon(icon)
        return
    end
    icon.spellId = spellId
    local spellInfo = C_Spell.GetSpellInfo(spellId)
    if not spellInfo then
        self:ClearIcon(icon)
        return
    end
    icon.icon:SetTexture(spellInfo.iconID)
    icon:Show()

    if TankAssist.Addon.db.profile.assistedCombat.showKeybinds then
        local keybind = TankAssist.Utils:GetSpellKeybind(spellId)
        icon.keybind:SetText(TankAssist.Utils:FormatKeybind(keybind) or "")
    else
        icon.keybind:SetText("")
    end

    local cdInfo = TankAssist.SecretValues:GetCooldownInfo(spellId)
    if cdInfo.onCooldown and cdInfo.remaining and cdInfo.remaining > 1.5 then
        local cdStart = GetTime() - cdInfo.remaining
        icon.cooldown:SetCooldown(cdStart, cdInfo.remaining + (GetTime() - cdStart))
    else
        icon.cooldown:Clear()
    end

    local gcdInfo = C_Spell.GetSpellCooldown(61304)
    if gcdInfo and gcdInfo.startTime and gcdInfo.duration and gcdInfo.duration > 0 then
        icon.gcdCooldown:SetCooldown(gcdInfo.startTime, gcdInfo.duration)
    else
        icon.gcdCooldown:Clear()
    end

    if cdInfo.charges and cdInfo.maxCharges and cdInfo.maxCharges > 1 then
        icon.count:SetText(cdInfo.charges)
    else
        icon.count:SetText("")
    end

    local usable = TankAssist.SecretValues:IsSpellUsable(spellId)
    local isUnusable = usable == false or (cdInfo.onCooldown and (not cdInfo.charges or cdInfo.charges == 0))

    if isUnusable then
        icon.unusable:Show()
        if self.inCombat then
            icon.unusable:SetColorTexture(0.1, 0.1, 0.1, 0.5)
        else
            icon.unusable:SetColorTexture(0.1, 0.1, 0.1, 0.7)
        end
    else
        icon.unusable:Hide()
    end

    icon.isUtility = (spellType == "utility")
    icon.isOffensive = (spellType == "offensive")
    if icon.border then
        local r, g, b, a = 0.3, 0.3, 0.3, 1
        if spellType == "utility" then
            if priority == "URGENT" then
                r, g, b = 0.9, 0.1, 0.1
            else
                r, g, b = 0.9, 0.7, 0.1
            end
        elseif spellType == "offensive" then
            r, g, b = 0.7, 0.3, 0.9
        end
        if icon.border.top then
            icon.border.top:SetColorTexture(r, g, b, a)
            icon.border.bottom:SetColorTexture(r, g, b, a)
            icon.border.left:SetColorTexture(r, g, b, a)
            icon.border.right:SetColorTexture(r, g, b, a)
        elseif icon.border.SetVertexColor then
            icon.border:SetVertexColor(r, g, b, a)
        end
    end

    icon.icon:SetDesaturated(false)
    icon.icon:SetVertexColor(1, 1, 1, 1)
    icon:SetAlpha(1.0)
end

function acd:ClearIcon(icon)
    icon.spellId = nil
    icon.icon:SetTexture(nil)
    icon.keybind:SetText("")
    icon.count:SetText("")
    icon.cooldown:Clear()
    icon.gcdCooldown:Clear()
    icon.unusable:Hide()
    if icon.border then
        local r, g, b, a = 0.3, 0.3, 0.3, 1
        if icon.border.top then
            icon.border.top:SetColorTexture(r, g, b, a)
            icon.border.bottom:SetColorTexture(r, g, b, a)
            icon.border.left:SetColorTexture(r, g, b, a)
            icon.border.right:SetColorTexture(r, g, b, a)
        elseif icon.border.SetVertexColor then
            icon.border:SetVertexColor(r, g, b, a)
        end
    end
end

function acd:Show()
    if self.frame and (self:IsEnabled() or self:IsInEditMode()) then
        self.frame:Show()
    end
end

function acd:Hide()
    if self.frame and not self:IsInEditMode() then
        self.frame:Hide()
    end
end

function acd:IsEnabled()
    local enabled = TankAssist.Addon.db.profile.assistedCombat.enabled
    if enabled == nil then
        return true
    end
    return enabled
end

function acd:SetEnabled(enabled)
    TankAssist.Addon.db.profile.assistedCombat.enabled = enabled
    if enabled or self:IsInEditMode() then
        self.frame:Show()
    else
        self.frame:Hide()
    end
    self:UpdateDisabledVisual()
end

function acd:UpdateDisabledVisual()
    if not self.frame then return end

    if self:IsEnabled() then
        self.frame:SetAlpha(1.0)
    else
        self.frame:SetAlpha(0.4)
    end
end

function acd:SetScale(scale)
    if self.frame then
        self.frame:SetScale(scale)
        TankAssist.Addon.db.profile.assistedCombat.scale = scale
    end
end

function acd:SetIconSize(size)
    if not self.frame then return end

    TankAssist.Addon.db.profile.assistedCombat.iconSize = size

    self.mainIcon:SetSize(size, size)
    self.aoeIcon:SetSize(size, size)
    self.frame:SetSize(size * 2 + 4, size + 2)

    local fontSize = size > 50 and 12 or 10
    self.mainIcon.keybind:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
    self.aoeIcon.keybind:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
end

function acd:ResetPosition()
    if self.frame then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
        TankAssist.Addon.db.profile.assistedCombat.position = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = -200,
        }
    end
end

function acd:IsInEditMode()
    return self.editMode or (EditModeManagerFrame and EditModeManagerFrame.editModeActive)
end

function acd:EnterEditMode()
    TankAssist.Addon:Print("Use WoW's Edit Mode (Escape > Edit Mode) to reposition TankAssist")
end

function acd:ExitEditMode()
end

function acd:ToggleEditMode()
    TankAssist.Addon:Print("Use WoW's Edit Mode (Escape > Edit Mode) to reposition TankAssist")
end

function acd:Lock()
end

function acd:Unlock()
    self:EnterEditMode()
end

function acd:UpdateLockState()
end

local function Initialize()
    if TankAssist.Addon then
        TankAssist.Addon.assistedCombatDisplay = acd
        acd:Create()
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.5, Initialize)
end)
