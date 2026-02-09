-- TankAssist Main Frame
-- Container frame that holds all UI components

local ADDON_NAME, TA = ...

TA.MainFrame = {}
local MF = TA.MainFrame

-- =============================================================================
-- MAIN FRAME CREATION
-- =============================================================================

function MF:Create()
    -- This is called by Core.lua in SetupUI
    -- The mainFrame is already created there
    -- This module handles additional main frame features
    
    local mainFrame = TA.Addon.mainFrame
    if not mainFrame then return end
    
    -- Add unlock visual indicator
    self:CreateUnlockOverlay(mainFrame)
    
    -- Add spec indicator
    self:CreateSpecIndicator(mainFrame)
    
    -- Add mode indicator (shows current tracking mode)
    self:CreateModeIndicator(mainFrame)
end

-- =============================================================================
-- UNLOCK OVERLAY
-- Shows when frame is unlocked for dragging
-- =============================================================================

function MF:CreateUnlockOverlay(parent)
    local overlay = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    overlay:SetAllPoints()
    overlay:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    overlay:SetBackdropColor(0, 0.5, 0, 0.3)
    overlay:SetBackdropBorderColor(0, 1, 0, 0.5)
    overlay:Hide()
    
    local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetText("Drag to move\n/ta lock to lock")
    text:SetTextColor(0, 1, 0, 1)
    
    self.unlockOverlay = overlay
    
    -- Show/hide based on lock state
    local function UpdateLockVisual()
        if TA.Addon.db and not TA.Addon.db.profile.locked then
            overlay:Show()
        else
            overlay:Hide()
        end
    end
    
    -- Hook into lock state changes
    hooksecurefunc(TA.Addon, "HandleSlashCommand", function()
        C_Timer.After(0.1, UpdateLockVisual)
    end)
end

-- =============================================================================
-- SPEC INDICATOR
-- Shows current tank spec icon
-- =============================================================================

function MF:CreateSpecIndicator(parent)
    local indicator = CreateFrame("Frame", nil, parent)
    indicator:SetSize(24, 24)
    indicator:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -5)
    
    indicator.icon = indicator:CreateTexture(nil, "ARTWORK")
    indicator.icon:SetAllPoints()
    indicator.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    
    indicator.border = indicator:CreateTexture(nil, "OVERLAY")
    indicator.border:SetPoint("TOPLEFT", -1, 1)
    indicator.border:SetPoint("BOTTOMRIGHT", 1, -1)
    indicator.border:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    
    -- Tooltip
    indicator:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local specId = TA.Utils:GetCurrentSpec()
        GameTooltip:SetText(TA.Utils:GetSpecName(specId))
        GameTooltip:AddLine("TankAssist active", 0.5, 1, 0.5)
        GameTooltip:Show()
    end)
    indicator:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    indicator:EnableMouse(true)
    
    self.specIndicator = indicator
end

function MF:UpdateSpecIndicator()
    if not self.specIndicator then return end
    
    local specId = TA.Utils:GetCurrentSpec()
    if not specId then
        self.specIndicator:Hide()
        return
    end
    
    -- Get spec icon
    local _, _, _, icon = GetSpecializationInfoByID(specId)
    if icon then
        self.specIndicator.icon:SetTexture(icon)
        self.specIndicator:Show()
    else
        self.specIndicator:Hide()
    end
end

-- =============================================================================
-- MODE INDICATOR
-- Shows current tracking mode (Assisted Combat, Fallback, etc.)
-- =============================================================================

function MF:CreateModeIndicator(parent)
    local indicator = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    indicator:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, -5)
    indicator:SetTextColor(0.7, 0.7, 0.7, 1)
    
    self.modeIndicator = indicator
end

function MF:UpdateModeIndicator(mode)
    if not self.modeIndicator then return end
    
    local modeTexts = {
        ASSISTED = "|cFF00FF00Assisted|r",
        FALLBACK = "|cFFFFFF00Fallback|r",
        LIMITED = "|cFFFF6600Limited|r",
        DISABLED = "|cFFFF0000Disabled|r",
    }
    
    self.modeIndicator:SetText(modeTexts[mode] or "")
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

local function Initialize()
    C_Timer.After(0.8, function()
        MF:Create()
        MF:UpdateSpecIndicator()
        MF:UpdateModeIndicator("ASSISTED")
    end)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", Initialize)
