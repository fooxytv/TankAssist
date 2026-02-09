local ADDON_NAME, TankAssist = ...

TankAssist.MainFrame = {}
local mf = TankAssist.MainFrame

function mf:Create()
    local mainFrame = TankAssist.Addon.mainFrame
    if not mainFrame then return end

    self:CreateUnlockOverlay(mainFrame)
    self:CreateSpecIndicator(mainFrame)
    self:CreateModeIndicator(mainFrame)
end

function mf:CreateUnlockOverlay(parent)
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

    local function UpdateLockVisual()
        if TankAssist.Addon.db and not TankAssist.Addon.db.profile.locked then
            overlay:Show()
        else
            overlay:Hide()
        end
    end

    hooksecurefunc(TankAssist.Addon, "HandleSlashCommand", function()
        C_Timer.After(0.1, UpdateLockVisual)
    end)
end

function mf:CreateSpecIndicator(parent)
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

    indicator:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local specId = TankAssist.Utils:GetCurrentSpec()
        GameTooltip:SetText(TankAssist.Utils:GetSpecName(specId))
        GameTooltip:AddLine("TankAssist active", 0.5, 1, 0.5)
        GameTooltip:Show()
    end)
    indicator:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    indicator:EnableMouse(true)

    self.specIndicator = indicator
end

function mf:UpdateSpecIndicator()
    if not self.specIndicator then return end

    local specId = TankAssist.Utils:GetCurrentSpec()
    if not specId then
        self.specIndicator:Hide()
        return
    end

    local _, _, _, icon = GetSpecializationInfoByID(specId)
    if icon then
        self.specIndicator.icon:SetTexture(icon)
        self.specIndicator:Show()
    else
        self.specIndicator:Hide()
    end
end

function mf:CreateModeIndicator(parent)
    local indicator = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    indicator:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, -5)
    indicator:SetTextColor(0.7, 0.7, 0.7, 1)

    self.modeIndicator = indicator
end

function mf:UpdateModeIndicator(mode)
    if not self.modeIndicator then return end

    local modeTexts = {
        ASSISTED = "|cFF00FF00Assisted|r",
        FALLBACK = "|cFFFFFF00Fallback|r",
        LIMITED = "|cFFFF6600Limited|r",
        DISABLED = "|cFFFF0000Disabled|r",
    }

    self.modeIndicator:SetText(modeTexts[mode] or "")
end

local function Initialize()
    C_Timer.After(0.8, function()
        mf:Create()
        mf:UpdateSpecIndicator()
        mf:UpdateModeIndicator("ASSISTED")
    end)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", Initialize)
