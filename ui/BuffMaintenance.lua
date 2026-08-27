local ADDON_NAME, TankAssist = ...

TankAssist.BuffMaintenance = {}
local bm = TankAssist.BuffMaintenance

--[[
    Each tracked buff should have this structure:
    {
        spellId = 195181,           -- Spell ID of the buff
        name = "Bone Shield",       -- Display name
        refreshSpell = 195182,      -- Spell that refreshes this buff (optional)
        minStacks = 5,              -- Minimum desired stacks (optional)
        maxStacks = 10,             -- Maximum stacks (optional)
        refreshThreshold = 3,       -- Refresh when < this many seconds remain
        priority = "CRITICAL",      -- CRITICAL, HIGH, NORMAL
        resourceType = nil,         -- Resource to show (RUNIC_POWER, RAGE, etc.)
        resourceCost = nil,         -- Cost of the refresh spell
    }
]]

function bm:Create(parent)
    local settings = TankAssist.Addon.db.profile.buffMaintenance

    self.frame = CreateFrame("Frame", "TankAssistBuffMaintenance", parent)
    self.frame:SetSize(400, settings.iconSize + 20)
    self.frame:SetPoint("TOP", parent, "TOP", 0, -100)

    self.title = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.title:SetPoint("TOP", self.frame, "TOP", 0, 0)
    self.title:SetText("Maintenance Buffs")
    self.title:SetTextColor(0.8, 0.8, 0.8, 1)

    self.iconsContainer = CreateFrame("Frame", nil, self.frame)
    self.iconsContainer:SetPoint("TOP", self.title, "BOTTOM", 0, -4)
    self.iconsContainer:SetSize(400, settings.iconSize)

    self.buffIcons = {}
    self.trackedBuffs = {}

    return self.frame
end

function bm:CreateBuffIcon(index)
    local settings = TankAssist.Addon.db.profile.buffMaintenance
    local size = settings.iconSize

    local frame = CreateFrame("Frame", nil, self.iconsContainer)
    frame:SetSize(size + 40, size)

    frame.icon = CreateFrame("Frame", nil, frame)
    frame.icon:SetSize(size, size)
    frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)

    frame.icon.texture = frame.icon:CreateTexture(nil, "ARTWORK")
    frame.icon.texture:SetPoint("TOPLEFT", 2, -2)
    frame.icon.texture:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.icon.bg = frame.icon:CreateTexture(nil, "BACKGROUND")
    frame.icon.bg:SetAllPoints()
    frame.icon.bg:SetColorTexture(0, 0, 0, 0.6)

    frame.icon.border = frame.icon:CreateTexture(nil, "OVERLAY")
    frame.icon.border:SetPoint("TOPLEFT", -1, 1)
    frame.icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.icon.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.icon.border:SetBlendMode("ADD")

    frame.stacks = frame.icon:CreateFontString(nil, "OVERLAY")
    frame.stacks:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    frame.stacks:SetPoint("CENTER", frame.icon, "CENTER", 0, 0)
    frame.stacks:SetTextColor(1, 1, 1, 1)

    frame.timerBar = CreateFrame("StatusBar", nil, frame)
    frame.timerBar:SetSize(size, 4)
    frame.timerBar:SetPoint("TOP", frame.icon, "BOTTOM", 0, -2)
    frame.timerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame.timerBar:SetMinMaxValues(0, 1)

    frame.timerBar.bg = frame.timerBar:CreateTexture(nil, "BACKGROUND")
    frame.timerBar.bg:SetAllPoints()
    frame.timerBar.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    frame.timer = frame:CreateFontString(nil, "OVERLAY")
    frame.timer:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    frame.timer:SetPoint("LEFT", frame.icon, "RIGHT", 4, 0)
    frame.timer:SetTextColor(1, 1, 1, 1)

    frame.status = frame:CreateFontString(nil, "OVERLAY")
    frame.status:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    frame.status:SetPoint("TOP", frame.timer, "BOTTOM", 0, -2)

    frame.icon:SetScript("OnEnter", function(self)
        if frame.buffData and frame.buffData.spellId then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(frame.buffData.spellId)
            if frame.buffData.refreshSpell then
                GameTooltip:AddLine(" ")
                local refreshSpellInfo = C_Spell.GetSpellInfo(frame.buffData.refreshSpell)
                local refreshName = refreshSpellInfo and refreshSpellInfo.name
                GameTooltip:AddLine("Refresh with: " .. (refreshName or "Unknown"), 0.5, 0.8, 1)
            end
            GameTooltip:Show()
        end
    end)
    frame.icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    frame:EnableMouse(true)
    frame.icon:EnableMouse(true)

    return frame
end

function bm:SetBuffs(buffs)
    self.trackedBuffs = buffs or {}

    local settings = TankAssist.Addon.db.profile.buffMaintenance
    local iconWidth = settings.iconSize + 50
    local totalWidth = #self.trackedBuffs * iconWidth
    local startX = -totalWidth / 2 + iconWidth / 2

    for i, buffData in ipairs(self.trackedBuffs) do
        if not self.buffIcons[i] then
            self.buffIcons[i] = self:CreateBuffIcon(i)
        end

        local icon = self.buffIcons[i]
        icon.buffData = buffData
        icon:SetPoint("LEFT", self.iconsContainer, "CENTER", startX + (i - 1) * iconWidth, 0)
        icon:Show()

        local spellInfo = C_Spell.GetSpellInfo(buffData.spellId)
        local spellIcon = spellInfo and spellInfo.iconID
        if spellIcon then
            icon.icon.texture:SetTexture(spellIcon)
        end
    end

    for i = #self.trackedBuffs + 1, #self.buffIcons do
        self.buffIcons[i]:Hide()
    end
end

function bm:Update()
    if not self.frame or not self.frame:IsShown() then return end

    for i, buffData in ipairs(self.trackedBuffs) do
        local icon = self.buffIcons[i]
        if icon then
            self:UpdateBuffIcon(icon, buffData)
        end
    end
end

function bm:UpdateBuffIcon(icon, buffData)
    local info = TankAssist.SecretValues:GetBuffInfo("player", buffData.spellId)
    local colors = TankAssist.Constants.Display.Colors

    if info.isSecret then
        self:SetIconState(icon, "UNKNOWN", buffData)
        -- Unreadable is not the same as unshowable. The client will format the
        -- stack count for display even when the addon may not look at it, so
        -- the player still gets the real number on the icon -- which beats the
        -- "?" that used to be the whole answer here.
        TankAssist.AuraDisplay:SetCountOn(icon.stacks, buffData.spellId)
        return
    end

    if not info.exists then
        self:SetIconState(icon, "DOWN", buffData)
        return
    end

    if buffData.isAbsorb then
        self:SetIconState(icon, "ABSORB_ACTIVE", buffData)
        return
    end

    local remaining = (info.expirationTime or 0) - GetTime()
    local stacks = info.stacks or 0

    -- Real count first, whatever we think we know. `info.stacks` here is either
    -- a value we were allowed to read or a dead-reckoned estimate from cast
    -- times, and the estimate does not announce itself -- so prefer the number
    -- the client is willing to format for us over both.
    if not TankAssist.AuraDisplay:SetCountOn(icon.stacks, buffData.spellId) then
        icon.stacks:SetText(stacks > 0 and stacks or "")
    end

    if remaining > 0 then
        icon.timer:SetText(TankAssist.Utils:FormatDuration(remaining))
        icon.timerBar:SetValue(remaining / (info.duration or remaining))
    else
        icon.timer:SetText("")
        icon.timerBar:SetValue(0)
    end

    local needsRefresh = false
    local isLow = false

    if buffData.minStacks and stacks < buffData.minStacks then
        needsRefresh = true
        isLow = true
    end

    local refreshThreshold = buffData.refreshThreshold or TankAssist.Addon.db.profile.buffMaintenance.warningThreshold
    if remaining < refreshThreshold then
        needsRefresh = true
    end

    if needsRefresh then
        if isLow then
            self:SetIconState(icon, "LOW_STACKS", buffData, stacks, remaining)
        else
            self:SetIconState(icon, "EXPIRING", buffData, stacks, remaining)
        end
    else
        self:SetIconState(icon, "ACTIVE", buffData, stacks, remaining)
    end
end

function bm:SetIconState(icon, state, buffData, stacks, remaining)
    local colors = TankAssist.Constants.Display.Colors

    if state == "DOWN" then
        icon.icon.texture:SetDesaturated(true)
        icon.icon.border:SetVertexColor(unpack(colors.URGENT))
        icon.status:SetText("DOWN")
        icon.status:SetTextColor(unpack(colors.URGENT))
        icon.timerBar:SetStatusBarColor(unpack(colors.URGENT))
        icon.timerBar:SetValue(0)
        icon.timer:SetText("")
        icon.stacks:SetText("")
        TankAssist.Utils:ApplyGlow(icon.icon, colors.URGENT)

    elseif state == "LOW_STACKS" then
        icon.icon.texture:SetDesaturated(false)
        icon.icon.border:SetVertexColor(unpack(colors.URGENT))
        icon.status:SetText(string.format("%d/%d", stacks, buffData.minStacks))
        icon.status:SetTextColor(unpack(colors.URGENT))
        icon.timerBar:SetStatusBarColor(unpack(colors.HIGH))
        TankAssist.Utils:ApplyGlow(icon.icon, colors.URGENT)

    elseif state == "EXPIRING" then
        icon.icon.texture:SetDesaturated(false)
        icon.icon.border:SetVertexColor(unpack(colors.BUFF_EXPIRING))
        icon.status:SetText("EXPIRING")
        icon.status:SetTextColor(unpack(colors.BUFF_EXPIRING))
        icon.timerBar:SetStatusBarColor(unpack(colors.BUFF_EXPIRING))
        TankAssist.Utils:ApplyGlow(icon.icon, colors.BUFF_EXPIRING)

    elseif state == "ACTIVE" then
        icon.icon.texture:SetDesaturated(false)
        icon.icon.border:SetVertexColor(unpack(colors.BUFF_ACTIVE))
        icon.status:SetText("")
        icon.timerBar:SetStatusBarColor(unpack(colors.BUFF_ACTIVE))
        TankAssist.Utils:RemoveGlow(icon.icon)

    elseif state == "ABSORB_ACTIVE" then
        icon.icon.texture:SetDesaturated(false)
        icon.icon.border:SetVertexColor(unpack(colors.BUFF_ACTIVE))
        icon.stacks:SetText("")
        icon.status:SetText("SHIELD")
        icon.status:SetTextColor(0.4, 0.8, 1, 1)
        icon.timer:SetText("")
        icon.timerBar:SetValue(1)
        icon.timerBar:SetStatusBarColor(0.4, 0.8, 1, 1)
        TankAssist.Utils:RemoveGlow(icon.icon)

    elseif state == "UNKNOWN" then
        icon.icon.texture:SetDesaturated(true)
        icon.icon.border:SetVertexColor(0.5, 0.5, 0.5, 1)
        icon.status:SetText("?")
        icon.status:SetTextColor(0.7, 0.7, 0.7, 1)
        icon.timer:SetText("")
        icon.timerBar:SetValue(0.5)
        icon.timerBar:SetStatusBarColor(0.5, 0.5, 0.5, 1)
        TankAssist.Utils:RemoveGlow(icon.icon)
    end
end

function bm:Show()
    if self.frame then
        self.frame:Show()
    end
end

function bm:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

local function Initialize()
    if TankAssist.Addon.mainFrame then
        TankAssist.Addon.buffMaintenance = bm
        bm:Create(TankAssist.Addon.mainFrame)
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.6, Initialize)
end)
