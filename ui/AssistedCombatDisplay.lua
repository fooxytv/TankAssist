-- TankAssist Assisted Combat Display
-- Simple 2-button display: Main Rotation + AoE/Utility
-- Integrates with WoW's Edit Mode for repositioning via LibEQOL

local ADDON_NAME, TA = ...

-- Get LibEQOL Edit Mode library (bundled with addon, with error handling)
local LEM
local lemLoadSuccess, lemResult = pcall(function()
    return LibStub("LibEQOLEditMode-1.0")
end)
if lemLoadSuccess then
    LEM = lemResult
else
    -- LibEQOL failed to load - will use basic Edit Mode fallback
    print("|cFFFF6600[TankAssist]|r LibEQOL not available, using basic Edit Mode support")
end

TA.AssistedCombatDisplay = {}
local ACD = TA.AssistedCombatDisplay

-- =============================================================================
-- BLIZZARD ASSISTED COMBAT API WRAPPER
-- =============================================================================

local AssistedCombatAPI = {}

function AssistedCombatAPI:IsAvailable()
    return C_AssistedCombat and C_AssistedCombat.GetNextCastSpell ~= nil
end

function AssistedCombatAPI:GetRecommendedSpell()
    if C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
        local spellId = C_AssistedCombat.GetNextCastSpell(false)
        if spellId then
            return spellId
        end
    end

    -- Fallback: Check spell overlay
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

function AssistedCombatAPI:GetRotationSpells()
    if C_AssistedCombat and C_AssistedCombat.GetRotationSpells then
        return C_AssistedCombat.GetRotationSpells() or {}
    end
    return {}
end

-- =============================================================================
-- EDIT MODE INTEGRATION (via LibEQOL if available, otherwise basic support)
-- =============================================================================

local function IsLibEQOLAvailable()
    return LEM ~= nil
end

local function IsEditModeAvailable()
    return EditModeManagerFrame ~= nil and EventRegistry ~= nil
end

local function IsInEditMode()
    return EditModeManagerFrame and EditModeManagerFrame.editModeActive
end

-- =============================================================================
-- DISPLAY FRAME
-- =============================================================================

function ACD:Create()
    local settings = TA.Addon.db.profile.assistedCombat

    -- Main container frame - tight fit around icons
    self.frame = CreateFrame("Frame", "TankAssistRotationFrame", UIParent, "BackdropTemplate")
    self.frame:SetSize(settings.iconSize * 2 + 4, settings.iconSize + 2)

    -- Set Edit Mode display name (used by LibEQOL for the selection label)
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

    -- Minimal background - very subtle
    self.frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = nil,
        tile = true,
        tileSize = 16,
        edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    self.frame:SetBackdropColor(0, 0, 0, 0.2)

    -- Create the two icons - tight spacing
    self.mainIcon = self:CreateIcon(self.frame, settings.iconSize)
    self.mainIcon:SetPoint("LEFT", self.frame, "LEFT", 1, 0)

    self.aoeIcon = self:CreateIcon(self.frame, settings.iconSize)
    self.aoeIcon:SetPoint("LEFT", self.mainIcon, "RIGHT", 2, 0)

    self.apiAvailable = AssistedCombatAPI:IsAvailable()
    self.editMode = false
    self.inCombat = false

    -- Register with WoW's Edit Mode if available
    self:RegisterEditMode()

    -- Register for combat events
    self:RegisterCombatEvents()

    return self.frame
end

function ACD:CreateIcon(parent, size)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetSize(size, size)

    -- Dark gray background (slightly lighter than pure black)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0.12, 0.12, 0.12, 1)

    -- Icon texture with rounded corners via texcoord
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", 2, -2)
    frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Thin border using 4 pixel lines (1px thick)
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

    -- Store border reference for color changes
    frame.border = {
        top = frame.borderTop,
        bottom = frame.borderBottom,
        left = frame.borderLeft,
        right = frame.borderRight,
    }

    -- Cooldown overlay (spell cooldown)
    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", 0, 0)
    frame.cooldown:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 0, 0)
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetHideCountdownNumbers(false)

    -- GCD overlay
    frame.gcdCooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.gcdCooldown:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", 0, 0)
    frame.gcdCooldown:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 0, 0)
    frame.gcdCooldown:SetDrawEdge(true)
    frame.gcdCooldown:SetDrawSwipe(true)
    frame.gcdCooldown:SetSwipeColor(1, 1, 1, 0.5)
    frame.gcdCooldown:SetHideCountdownNumbers(true)
    frame.gcdCooldown:SetFrameLevel(frame.cooldown:GetFrameLevel() + 1)

    -- Keybind text
    frame.keybind = frame:CreateFontString(nil, "OVERLAY")
    frame.keybind:SetFont("Fonts\\FRIZQT__.TTF", size > 50 and 12 or 10, "OUTLINE")
    frame.keybind:SetPoint("TOPLEFT", 4, -4)
    frame.keybind:SetTextColor(1, 1, 1, 1)

    -- Charges text
    frame.count = frame:CreateFontString(nil, "OVERLAY")
    frame.count:SetFont("Fonts\\FRIZQT__.TTF", size > 50 and 14 or 11, "OUTLINE")
    frame.count:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.count:SetTextColor(1, 1, 1, 1)

    -- Unusable overlay
    frame.unusable = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    frame.unusable:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", 0, 0)
    frame.unusable:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 0, 0)
    frame.unusable:SetColorTexture(0.1, 0.1, 0.1, 0.7)
    frame.unusable:Hide()

    -- Tooltip - only show when Shift is held
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

-- =============================================================================
-- LIBEQUOL SETTINGS (shown when frame is selected in Edit Mode)
-- =============================================================================

function ACD:BuildLEMSettings()
    local self_ref = self

    return {
        {
            order = 100,
            name = "Scale",
            kind = LEM.SettingType.Slider,
            default = 1.0,
            minValue = 0.5,
            maxValue = 2.0,
            valueStep = 0.1,
            get = function(layoutName)
                return TA.Addon.db.profile.assistedCombat.scale or 1.0
            end,
            set = function(layoutName, value)
                value = math.floor(value * 10 + 0.5) / 10
                self_ref:SetScale(value)
            end,
        },
        {
            order = 101,
            name = "Icon Size",
            kind = LEM.SettingType.Slider,
            default = 50,
            minValue = 30,
            maxValue = 80,
            valueStep = 5,
            get = function(layoutName)
                return TA.Addon.db.profile.assistedCombat.iconSize or 50
            end,
            set = function(layoutName, value)
                value = math.floor(value / 5 + 0.5) * 5
                self_ref:SetIconSize(value)
            end,
        },
        {
            order = 102,
            name = "Show Keybinds",
            kind = LEM.SettingType.Checkbox,
            default = true,
            get = function(layoutName)
                return TA.Addon.db.profile.assistedCombat.showKeybinds
            end,
            set = function(layoutName, value)
                TA.Addon.db.profile.assistedCombat.showKeybinds = value
            end,
        },
    }
end

-- =============================================================================
-- EDIT MODE REGISTRATION (via LibEQOL if available, otherwise basic support)
-- =============================================================================

function ACD:RegisterEditMode()
    if not self.frame then
        return
    end

    -- Use LibEQOL if available (provides better integration)
    if IsLibEQOLAvailable() then
        self:RegisterEditModeLibEQOL()
    elseif IsEditModeAvailable() then
        self:RegisterEditModeBasic()
    end
end

-- LibEQOL-based Edit Mode (full integration with Blizzard Edit Mode UI)
function ACD:RegisterEditModeLibEQOL()
    local self_ref = self

    -- Default position for reset functionality
    local defaults = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = -200,
    }

    -- Callback when position changes in Edit Mode
    local function OnPositionChanged(point, relativePoint, x, y)
        TA.Addon.db.profile.assistedCombat.position = {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y,
        }
        TA.Utils:Debug("Position saved via LibEQOL:", point, x, y)
    end

    -- Register frame with LibEQOL Edit Mode
    LEM:AddFrame(self.frame, OnPositionChanged, defaults)

    -- Add settings panel for the frame in Edit Mode
    LEM:AddFrameSettings(self.frame, self:BuildLEMSettings())

    -- Enable reset to default position button
    LEM:SetFrameResetVisible(self.frame, true)

    TA.Utils:Debug("TankAssist registered with LibEQOL Edit Mode")
end

-- Basic Edit Mode support (fallback when LibEQOL is not available)
function ACD:RegisterEditModeBasic()
    local self_ref = self

    EventRegistry:RegisterCallback("EditMode.Enter", function()
        self_ref:OnEditModeEnter()
    end, self)

    EventRegistry:RegisterCallback("EditMode.Exit", function()
        self_ref:OnEditModeExit()
    end, self)

    -- Hook into Edit Mode save to persist position
    if EditModeManagerFrame then
        hooksecurefunc(EditModeManagerFrame, "SaveLayouts", function()
            self_ref:SavePosition()
        end)
        hooksecurefunc(EditModeManagerFrame, "RevertAllChanges", function()
            self_ref:RestorePosition()
        end)
    end

    -- Create basic selection overlay for dragging
    self:CreateBasicSelectionOverlay()

    if IsInEditMode() then
        self:OnEditModeEnter()
    end

    TA.Utils:Debug("TankAssist registered with basic Edit Mode support")
end

-- Basic selection overlay (used when LibEQOL is not available)
function ACD:CreateBasicSelectionOverlay()
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

-- Save current position to saved variables (called externally)
function ACD:SavePosition()
    if not self.frame then return end

    local point, _, relativePoint, x, y = self.frame:GetPoint()
    TA.Addon.db.profile.assistedCombat.position = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
    TA.Addon.db.profile.assistedCombat.scale = self.frame:GetScale()

    TA.Utils:Debug("Position saved:", point, x, y)
end

-- Restore position from saved variables
function ACD:RestorePosition()
    if not self.frame then return end

    local settings = TA.Addon.db.profile.assistedCombat
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

function ACD:OnEditModeEnter()
    if not self.frame then return end
    self.editMode = true
    self.frame:SetMovable(true)

    -- Show basic selection overlay if using fallback mode
    if self.selection and not IsLibEQOLAvailable() then
        self.selection:Show()
    end
end

function ACD:OnEditModeExit()
    if not self.frame then return end
    self.editMode = false

    -- Hide basic selection overlay if using fallback mode
    if self.selection and not IsLibEQOLAvailable() then
        self.selection:Hide()
    end
end

-- =============================================================================
-- COMBAT EVENTS
-- =============================================================================

function ACD:RegisterCombatEvents()
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

    -- Initial state check
    self.inCombat = UnitAffectingCombat("player")

    -- Delay initial visual update to ensure frame is ready
    C_Timer.After(0.1, function()
        self:UpdateCombatVisuals()
    end)
end

function ACD:UpdateCombatVisuals()
    if not self.frame then return end

    if self.inCombat then
        -- IN COMBAT: Fully visible
        self.frame:SetAlpha(1.0)
        self.mainIcon:SetAlpha(1.0)
        self.aoeIcon:SetAlpha(1.0)
        self.frame:SetBackdropColor(0, 0, 0, 0.4)
    else
        -- OUT OF COMBAT: Very faded, barely visible
        self.frame:SetAlpha(0.2)
        self.mainIcon:SetAlpha(0.3)
        self.aoeIcon:SetAlpha(0.3)
        self.frame:SetBackdropColor(0, 0, 0, 0.1)
    end
end

-- =============================================================================
-- UPDATE LOGIC
-- =============================================================================

function ACD:Update()
    if not self.frame or not self.frame:IsShown() then return end

    local mainSpell = AssistedCombatAPI:GetRecommendedSpell()
    local specModule = TA.Addon.activeSpecModule
    local isTankSpec = TA.Addon.isTankSpec

    -- Main button: Blizzard's assisted combat recommendation (works for all specs)
    if mainSpell then
        self:UpdateIcon(self.mainIcon, mainSpell, "main")
    else
        -- Fallback to spec module recommendations if available
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

    -- Secondary button: Tank utilities/AoE for tanks, offensive cooldowns for non-tanks
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
        -- Hide secondary button completely if no spell available
        if not isTankSpec then
            self.aoeIcon:Hide()
        end
    end
end

function ACD:UpdateIcon(icon, spellId, spellType, priority)
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

    if TA.Addon.db.profile.assistedCombat.showKeybinds then
        local keybind = TA.Utils:GetSpellKeybind(spellId)
        icon.keybind:SetText(TA.Utils:FormatKeybind(keybind) or "")
    else
        icon.keybind:SetText("")
    end

    local cdInfo = TA.SecretValues:GetCooldownInfo(spellId)
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

    local usable = TA.SecretValues:IsSpellUsable(spellId)
    local isUnusable = usable == false or (cdInfo.onCooldown and (not cdInfo.charges or cdInfo.charges == 0))

    if isUnusable then
        -- Show unusable overlay but make it less opaque in combat
        icon.unusable:Show()
        if self.inCombat then
            icon.unusable:SetColorTexture(0.1, 0.1, 0.1, 0.5)
        else
            icon.unusable:SetColorTexture(0.1, 0.1, 0.1, 0.7)
        end
    else
        icon.unusable:Hide()
    end

    -- Visual feedback for spell types via border color
    icon.isUtility = (spellType == "utility")
    icon.isOffensive = (spellType == "offensive")
    if icon.border then
        local r, g, b, a = 0.3, 0.3, 0.3, 1 -- Default dark gray
        if spellType == "utility" then
            if priority == "URGENT" then
                -- Red border for urgent defensive
                r, g, b = 0.9, 0.1, 0.1
            else
                -- Gold border for high priority defensive
                r, g, b = 0.9, 0.7, 0.1
            end
        elseif spellType == "offensive" then
            -- Purple/magenta border for offensive cooldowns
            r, g, b = 0.7, 0.3, 0.9
        end
        -- Update all 4 border textures
        if icon.border.top then
            icon.border.top:SetColorTexture(r, g, b, a)
            icon.border.bottom:SetColorTexture(r, g, b, a)
            icon.border.left:SetColorTexture(r, g, b, a)
            icon.border.right:SetColorTexture(r, g, b, a)
        elseif icon.border.SetVertexColor then
            -- Legacy support for single texture border
            icon.border:SetVertexColor(r, g, b, a)
        end
    end

    -- Always full brightness on icons - frame alpha controls visibility
    icon.icon:SetDesaturated(false)
    icon.icon:SetVertexColor(1, 1, 1, 1)
    icon:SetAlpha(1.0)
end

function ACD:ClearIcon(icon)
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

-- =============================================================================
-- PUBLIC INTERFACE
-- =============================================================================

function ACD:Show()
    if self.frame then
        self.frame:Show()
    end
end

function ACD:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function ACD:SetScale(scale)
    if self.frame then
        self.frame:SetScale(scale)
        TA.Addon.db.profile.assistedCombat.scale = scale
        -- Don't auto-save here - let Edit Mode Save button handle it
    end
end

function ACD:SetIconSize(size)
    if not self.frame then return end

    TA.Addon.db.profile.assistedCombat.iconSize = size

    self.mainIcon:SetSize(size, size)
    self.aoeIcon:SetSize(size, size)
    self.frame:SetSize(size * 2 + 4, size + 2)

    local fontSize = size > 50 and 12 or 10
    self.mainIcon.keybind:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
    self.aoeIcon.keybind:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
end

function ACD:ResetPosition()
    if self.frame then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
        TA.Addon.db.profile.assistedCombat.position = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = -200,
        }
    end
end

function ACD:IsInEditMode()
    return self.editMode
end

-- Legacy functions - LibEQOL handles Edit Mode integration now
function ACD:EnterEditMode()
    TA.Addon:Print("Use WoW's Edit Mode (Escape > Edit Mode) to reposition TankAssist")
end

function ACD:ExitEditMode()
    -- No-op, handled by LibEQOL
end

function ACD:ToggleEditMode()
    TA.Addon:Print("Use WoW's Edit Mode (Escape > Edit Mode) to reposition TankAssist")
end

function ACD:Lock()
    -- No-op, handled by LibEQOL
end

function ACD:Unlock()
    self:EnterEditMode()
end

function ACD:UpdateLockState()
    -- No-op, handled by LibEQOL
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

local function Initialize()
    if TA.Addon then
        TA.Addon.assistedCombatDisplay = ACD
        ACD:Create()
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.5, Initialize)
end)
