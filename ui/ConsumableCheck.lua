local ADDON_NAME, TankAssist = ...

local lem
local lemLoadSuccess, lemResult = pcall(function()
    return LibStub("LibEQOLEditMode-1.0")
end)
if lemLoadSuccess then
    lem = lemResult
end

TankAssist.ConsumableCheck = {}
local cc = TankAssist.ConsumableCheck

local AUTO_HIDE_DELAY = 8
local PRESENT_COLOR = { 0.2, 1.0, 0.2 }
local MISSING_GLOW_COLOR = { 1.0, 0.85, 0.2, 0.8 }

local function IsLibEQOLAvailable()
    return lem ~= nil
end

function cc:GetSettings()
    return TankAssist.Addon.db.profile.consumableCheck
end

function cc:GetSpecId()
    return TankAssist.Utils and TankAssist.Utils:GetCurrentSpec() or 0
end

function cc:Create()
    local settings = self:GetSettings()
    self.frame = CreateFrame("Frame", "TankAssistConsumableCheck", UIParent)
    self.frame:SetSize(1, 1)
    self.frame.editModeName = "Consumable Check"
    local validAnchors = { CENTER=1, TOP=1, BOTTOM=1, LEFT=1, RIGHT=1, TOPLEFT=1, TOPRIGHT=1, BOTTOMLEFT=1, BOTTOMRIGHT=1 }
    local pos = settings.position or {}
    if validAnchors[pos.point] and type(pos.x) == "number" and type(pos.y) == "number" then
        self.frame:SetPoint(pos.point, UIParent, validAnchors[pos.relativePoint] and pos.relativePoint or pos.point, pos.x, pos.y)
    else
        settings.position = { point = "TOP", relativePoint = "TOP", x = 0, y = -180 }
        self.frame:SetPoint("TOP", UIParent, "TOP", 0, -180)
    end
    self.frame:SetScale(settings.scale or 1.0)
    self.frame:SetClampedToScreen(true)
    self.icons = {}
    self.editMode = false
    self.autoHideAt = 0
    self.collapsed = false
    self:BuildIcons()
    self:BuildMinimizeButton()
    self:BuildMiniFrame()
    self:RegisterEditMode()
    self:RegisterEvents()
    self.frame:Hide()
    return self.frame
end

function cc:BuildMinimizeButton()
    local btn = CreateFrame("Button", nil, self.frame)
    btn:SetSize(14, 14)
    btn:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 2, 2)
    btn:SetFrameLevel(self.frame:GetFrameLevel() + 5)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0, 0, 0, 0.7)
    btn.x = btn:CreateFontString(nil, "OVERLAY")
    btn.x:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    btn.x:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.x:SetText("x")
    btn.x:SetTextColor(0.8, 0.8, 0.8, 1)
    btn:SetScript("OnEnter", function(self)
        self.x:SetTextColor(1, 0.4, 0.4, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Minimize")
        GameTooltip:AddLine("Collapse to a single indicator.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self.x:SetTextColor(0.8, 0.8, 0.8, 1)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function() cc:Collapse() end)
    self.minimizeBtn = btn
end

function cc:BuildMiniFrame()
    local mini = CreateFrame("Button", nil, self.frame)
    local size = 28
    mini:SetSize(size, size)
    mini:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
    mini.bg = mini:CreateTexture(nil, "BACKGROUND")
    mini.bg:SetAllPoints()
    mini.bg:SetColorTexture(0, 0, 0, 0.7)
    mini.icon = mini:CreateTexture(nil, "ARTWORK")
    mini.icon:SetPoint("TOPLEFT", 2, -2)
    mini.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    mini.icon:SetTexture("Interface\\Icons\\inv_misc_food_legion_lavishsuramarfeast")
    mini.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    mini.glow = mini:CreateTexture(nil, "OVERLAY", nil, 6)
    mini.glow:SetPoint("TOPLEFT", -5, 5)
    mini.glow:SetPoint("BOTTOMRIGHT", 5, -5)
    mini.glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    mini.glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    mini.glow:SetBlendMode("ADD")
    mini.glow:SetVertexColor(unpack(MISSING_GLOW_COLOR))
    mini.glow:Hide()
    mini.glowAnim = mini.glow:CreateAnimationGroup()
    mini.glowAnim:SetLooping("BOUNCE")
    local fade = mini.glowAnim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1.0)
    fade:SetToAlpha(0.25)
    fade:SetDuration(0.7)
    fade:SetSmoothing("IN_OUT")
    mini.count = mini:CreateFontString(nil, "OVERLAY")
    mini.count:SetFont("Fonts\\FRIZQT__.TTF", 14, "THICKOUTLINE")
    mini.count:SetPoint("BOTTOMRIGHT", mini, "BOTTOMRIGHT", -1, 1)
    mini.count:SetTextColor(1, 0.85, 0.2, 1)
    mini:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Consumable Check (minimized)")
        if cc.lastMissingList and #cc.lastMissingList > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Missing:", 0.7, 0.85, 1.0)
            for _, name in ipairs(cc.lastMissingList) do
                GameTooltip:AddLine("- " .. name, 1, 0.6, 0.2, true)
            end
        else
            GameTooltip:AddLine("All detected.", 0.4, 1.0, 0.4, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to expand.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mini:SetScript("OnClick", function() cc:Expand() end)
    mini:Hide()

    self.miniFrame = mini
end

function cc:Collapse()
    if self.editMode then return end
    self.collapsed = true
    self:Update()
end

function cc:Expand()
    self.collapsed = false
    self:Update()
end

function cc:UpdateMiniFrame(missingCount)
    if not self.miniFrame then return end
    if missingCount > 0 then
        self.miniFrame.count:SetText(tostring(missingCount))
        self.miniFrame.count:Show()
        self.miniFrame.glow:Show()
        if not self.miniFrame.glowAnim:IsPlaying() then
            self.miniFrame.glowAnim:Play()
        end
        self.miniFrame.icon:SetDesaturated(true)
    else
        self.miniFrame.count:SetText("")
        self.miniFrame.count:Hide()
        self.miniFrame.glow:Hide()
        if self.miniFrame.glowAnim:IsPlaying() then
            self.miniFrame.glowAnim:Stop()
        end
        self.miniFrame.icon:SetDesaturated(false)
    end
end

function cc:CreateCategoryIcon(category)
    local settings = self:GetSettings()
    local size = settings.iconSize or 40
    local frame = CreateFrame("Frame", nil, self.frame)
    frame:SetSize(size, size + 14)
    frame.category = category
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
    frame.icon.texture:SetTexture(category.fallbackIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local saved = settings.borderColor or { r = 0.5, g = 0.5, b = 0.55, a = 1 }
    local r, g, b, a = saved.r or 0.5, saved.g or 0.5, saved.b or 0.55, saved.a or 1
    frame.icon.borderTop = frame.icon:CreateTexture(nil, "OVERLAY")
    frame.icon.borderTop:SetPoint("TOPLEFT", 0, 0)
    frame.icon.borderTop:SetPoint("TOPRIGHT", 0, 0)
    frame.icon.borderTop:SetHeight(1)
    frame.icon.borderTop:SetColorTexture(r, g, b, a)
    frame.icon.borderBottom = frame.icon:CreateTexture(nil, "OVERLAY")
    frame.icon.borderBottom:SetPoint("BOTTOMLEFT", 0, 0)
    frame.icon.borderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.icon.borderBottom:SetHeight(1)
    frame.icon.borderBottom:SetColorTexture(r, g, b, a)
    frame.icon.borderLeft = frame.icon:CreateTexture(nil, "OVERLAY")
    frame.icon.borderLeft:SetPoint("TOPLEFT", 0, 0)
    frame.icon.borderLeft:SetPoint("BOTTOMLEFT", 0, 0)
    frame.icon.borderLeft:SetWidth(1)
    frame.icon.borderLeft:SetColorTexture(r, g, b, a)
    frame.icon.borderRight = frame.icon:CreateTexture(nil, "OVERLAY")
    frame.icon.borderRight:SetPoint("TOPRIGHT", 0, 0)
    frame.icon.borderRight:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.icon.borderRight:SetWidth(1)
    frame.icon.borderRight:SetColorTexture(r, g, b, a)
    frame.glow = frame.icon:CreateTexture(nil, "OVERLAY", nil, 6)
    frame.glow:SetPoint("TOPLEFT", -6, 6)
    frame.glow:SetPoint("BOTTOMRIGHT", 6, -6)
    frame.glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    frame.glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    frame.glow:SetBlendMode("ADD")
    frame.glow:SetVertexColor(unpack(MISSING_GLOW_COLOR))
    frame.glow:Hide()
    frame.glowAnim = frame.glow:CreateAnimationGroup()
    frame.glowAnim:SetLooping("BOUNCE")
    local fade = frame.glowAnim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1.0)
    fade:SetToAlpha(0.25)
    fade:SetDuration(0.7)
    fade:SetSmoothing("IN_OUT")
    frame.tick = frame.icon:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.tick:SetSize(size * 0.55, size * 0.55)
    frame.tick:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 2, -2)
    frame.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    frame.tick:Hide()
    frame.icon.dim = frame.icon:CreateTexture(nil, "OVERLAY", nil, 5)
    frame.icon.dim:SetPoint("TOPLEFT", 2, -2)
    frame.icon.dim:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.icon.dim:SetColorTexture(0, 0, 0, 0.35)
    frame.icon.dim:Hide()
    frame.label = frame:CreateFontString(nil, "OVERLAY")
    frame.label:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    frame.label:SetPoint("TOP", frame.icon, "BOTTOM", 0, -2)
    frame.label:SetTextColor(1, 1, 1, 1)
    frame.label:SetWordWrap(false)
    frame.label:SetText(category.displayName)

    frame.icon:EnableMouse(true)
    frame.icon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(category.displayName)
        local status = frame.present and "|cff66ff66Detected|r" or "|cffff8800Missing|r"
        GameTooltip:AddLine(status, 1, 1, 1)
        local recs = TankAssist.Consumables:GetRecommendations(cc:GetSpecId())
        if recs and recs[category.key] then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Recommended:", 0.7, 0.85, 1.0)
            GameTooltip:AddLine(recs[category.key], 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    frame.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return frame
end

function cc:BuildIcons()
    local categories = TankAssist.Consumables:GetCategories()
    for i, category in ipairs(categories) do
        self.icons[i] = self:CreateCategoryIcon(category)
    end
    self:Layout()
end

function cc:Layout()
    local settings = self:GetSettings()
    local size = settings.iconSize or 40
    local spacing = 6
    local count = #self.icons
    if count == 0 then return end

    if self.collapsed then
        local miniSize = 28
        self.frame:SetSize(miniSize, miniSize)
        for _, icon in ipairs(self.icons) do icon:Hide() end
        if self.minimizeBtn then self.minimizeBtn:Hide() end
        if self.miniFrame then
            self.miniFrame:ClearAllPoints()
            self.miniFrame:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
            self.miniFrame:Show()
        end
        return
    end

    local totalWidth = count * size + (count - 1) * spacing
    local totalHeight = size + 16
    self.frame:SetSize(totalWidth, totalHeight)

    for i, icon in ipairs(self.icons) do
        icon:SetSize(size, size + 14)
        icon.icon:SetSize(size, size)
        icon.tick:SetSize(size * 0.55, size * 0.55)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", self.frame, "LEFT", (i - 1) * (size + spacing), 0)
        icon:Show()
    end
    if self.miniFrame then self.miniFrame:Hide() end
    if self.minimizeBtn then self.minimizeBtn:Show() end
end

local function CollectPlayerBuffs()
    local byId, byName = {}, {}
    local sv = TankAssist.SecretValues
    local function isSecret(v)
        return sv and sv:IsSecret(v)
    end
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local data = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not data then break end
            if data.spellId and not isSecret(data.spellId) then
                byId[data.spellId] = true
            end
            if data.name and not isSecret(data.name) then
                byName[data.name] = true
            end
        end
    elseif AuraUtil and AuraUtil.ForEachAura then
        AuraUtil.ForEachAura("player", "HELPFUL", nil, function(...)
            local name, _, _, _, _, _, _, _, _, spellId = ...
            if spellId and not isSecret(spellId) then
                byId[spellId] = true
            end
            if name and not isSecret(name) then
                byName[name] = true
            end
        end, true)
    end
    return byId, byName
end

local function HasWeaponEnchant()
    if not GetWeaponEnchantInfo then return false end
    local hasMainHand = GetWeaponEnchantInfo()
    return hasMainHand and true or false
end

function cc:DetectCategory(category, byId, byName)
    if category.checkType == "weaponEnchant" then
        return HasWeaponEnchant()
    end
    if category.buffIds then
        for _, id in ipairs(category.buffIds) do
            if byId[id] then return true end
        end
    end
    if category.buffNamePatterns then
        for buffName in pairs(byName) do
            for _, pattern in ipairs(category.buffNamePatterns) do
                if buffName:find(pattern, 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

function cc:Update()
    if self.editMode then return end
    if not self:IsEnabled() then
        self.frame:Hide()
        return
    end

    local byId, byName = CollectPlayerBuffs()
    local anyMissing = false
    local missingNames = {}

    for _, icon in ipairs(self.icons) do
        local present = self:DetectCategory(icon.category, byId, byName)
        icon.present = present
        if present then
            icon.tick:Show()
            icon.glow:Hide()
            if icon.glowAnim:IsPlaying() then icon.glowAnim:Stop() end
            icon.icon.dim:Hide()
            icon.icon.texture:SetVertexColor(1, 1, 1, 1)
            icon.label:SetTextColor(unpack(PRESENT_COLOR))
        else
            icon.tick:Hide()
            icon.glow:Show()
            if not icon.glowAnim:IsPlaying() then icon.glowAnim:Play() end
            icon.icon.dim:Show()
            icon.icon.texture:SetVertexColor(0.85, 0.85, 0.85, 1)
            icon.label:SetTextColor(1.0, 0.6, 0.2)
            anyMissing = true
            table.insert(missingNames, icon.category.displayName)
        end
    end

    self.lastMissingList = missingNames
    self:Layout()
    self:UpdateMiniFrame(#missingNames)

    self.frame:Show()

    if not anyMissing then
        self.autoHideAt = GetTime() + AUTO_HIDE_DELAY
        if not self.hideTicker then
            self.hideTicker = C_Timer.NewTicker(0.5, function()
                if self.editMode then return end
                if self.autoHideAt > 0 and GetTime() >= self.autoHideAt then
                    self.frame:Hide()
                    self.autoHideAt = 0
                    if self.hideTicker then
                        self.hideTicker:Cancel()
                        self.hideTicker = nil
                    end
                end
            end)
        end
    else
        self.autoHideAt = 0
        if self.hideTicker then
            self.hideTicker:Cancel()
            self.hideTicker = nil
        end
    end
end

function cc:ShouldCheckHere()
    local inInstance, instanceType = IsInInstance()
    if not inInstance then
        return self:GetSettings().alsoOutsideInstances == true
    end
    return instanceType == "party"
        or instanceType == "raid"
        or instanceType == "scenario"
end

function cc:OnEnteringWorld()
    if not self:IsEnabled() then return end
    if not self:ShouldCheckHere() then
        self.frame:Hide()
        return
    end
    self.collapsed = false
    C_Timer.After(1.0, function()
        if self:IsEnabled() and self:ShouldCheckHere() then
            self:Update()
        end
    end)
end

function cc:ManualCheck()
    if not self:IsEnabled() then
        TankAssist.Addon:Print("Consumable check is disabled. Enable it in /ta config.")
        return
    end
    self:Update()
    local missing = {}
    for _, icon in ipairs(self.icons) do
        if not icon.present then
            table.insert(missing, icon.category.displayName)
        end
    end
    if #missing == 0 then
        TankAssist.Addon:Print("All consumable categories detected.")
    else
        TankAssist.Addon:Print("Missing: " .. table.concat(missing, ", "))
    end
end

function cc:RegisterEditMode()
    if not self.frame or not IsLibEQOLAvailable() then return end
    local self_ref = self
    local settings = self:GetSettings()

    local defaults = {
        point = settings.position.point or "TOP",
        relativePoint = settings.position.relativePoint or "TOP",
        x = settings.position.x or 0,
        y = settings.position.y or -180,
    }

    local function OnPositionChanged(...)
        local point, relativePoint, x, y
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if type(v) == "string" and not point then
                local anchors = { CENTER=1, TOP=1, BOTTOM=1, LEFT=1, RIGHT=1, TOPLEFT=1, TOPRIGHT=1, BOTTOMLEFT=1, BOTTOMRIGHT=1 }
                if anchors[v] then point = v end
            elseif type(v) == "string" and point and not relativePoint then
                local anchors = { CENTER=1, TOP=1, BOTTOM=1, LEFT=1, RIGHT=1, TOPLEFT=1, TOPRIGHT=1, BOTTOMLEFT=1, BOTTOMRIGHT=1 }
                if anchors[v] then relativePoint = v end
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

    lem:RegisterCallback("enter", function() self_ref:OnEditModeEnter() end)
    lem:RegisterCallback("exit", function() self_ref:OnEditModeExit() end)
end

function cc:BuildLEMSettings()
    local self_ref = self
    return {
        {
            order = 299,
            name = "Enabled",
            kind = lem.SettingType.Checkbox,
            default = true,
            get = function() local v = self_ref:GetSettings().enabled; if v == nil then return true end return v end,
            set = function(_, value) self_ref:SetEnabled(value) end,
        },
        {
            order = 300,
            name = "Scale",
            kind = lem.SettingType.Slider,
            default = 1.0,
            minValue = 0.5, maxValue = 2.0, valueStep = 0.1,
            get = function() return self_ref:GetSettings().scale or 1.0 end,
            set = function(_, value)
                value = math.floor(value * 10 + 0.5) / 10
                self_ref.frame:SetScale(value)
                self_ref:GetSettings().scale = value
            end,
        },
        {
            order = 301,
            name = "Icon Size",
            kind = lem.SettingType.Slider,
            default = 40,
            minValue = 24, maxValue = 64, valueStep = 4,
            get = function() return self_ref:GetSettings().iconSize or 40 end,
            set = function(_, value)
                value = math.floor(value / 4 + 0.5) * 4
                self_ref:GetSettings().iconSize = value
                self_ref:Layout()
                if self_ref.editMode then self_ref:OnEditModeEnter() end
            end,
        },
        {
            order = 302,
            name = "Also Check Outside Instances",
            kind = lem.SettingType.Checkbox,
            default = false,
            get = function() return self_ref:GetSettings().alsoOutsideInstances or false end,
            set = function(_, value) self_ref:GetSettings().alsoOutsideInstances = value end,
        },
    }
end

function cc:OnEditModeEnter()
    if not self.frame then return end
    self.editMode = true
    self.frame:SetMovable(true)
    self.collapsed = false
    if self.miniFrame then self.miniFrame:Hide() end
    if self.minimizeBtn then self.minimizeBtn:Hide() end
    self:Layout()
    for _, icon in ipairs(self.icons) do
        icon.tick:Hide()
        icon.glow:Hide()
        if icon.glowAnim:IsPlaying() then icon.glowAnim:Stop() end
        icon.icon.dim:Hide()
        icon.icon.texture:SetVertexColor(1, 1, 1, 1)
        icon.label:SetTextColor(1, 1, 1, 1)
    end
    if self.icons[1] then
        local first = self.icons[1]
        first.tick:Show()
    end
    if self.icons[2] then
        local second = self.icons[2]
        second.glow:Show()
        if not second.glowAnim:IsPlaying() then second.glowAnim:Play() end
        second.icon.dim:Show()
    end
    self.frame:Show()
    self:UpdateDisabledVisual()
end

function cc:OnEditModeExit()
    if not self.frame then return end
    self.editMode = false
    for _, icon in ipairs(self.icons) do
        if icon.glowAnim:IsPlaying() then icon.glowAnim:Stop() end
        icon.glow:Hide()
        icon.tick:Hide()
        icon.icon.dim:Hide()
    end
    if self.miniFrame then
        if self.miniFrame.glowAnim:IsPlaying() then
            self.miniFrame.glowAnim:Stop()
        end
        self.miniFrame:Hide()
    end
    if self.minimizeBtn then self.minimizeBtn:Hide() end
    self.frame:Hide()
end

function cc:IsEnabled()
    local enabled = self:GetSettings().enabled
    if enabled == nil then return true end
    return enabled
end

function cc:SetEnabled(enabled)
    self:GetSettings().enabled = enabled
    if not enabled and not self.editMode then
        self.frame:Hide()
    end
    self:UpdateDisabledVisual()
end

function cc:UpdateDisabledVisual()
    if not self.frame then return end
    self.frame:SetAlpha(self:IsEnabled() and 1.0 or 0.4)
end

function cc:RegisterEvents()
    local self_ref = self
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    self.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.inCombat = UnitAffectingCombat("player") or false
    self.eventFrame:SetScript("OnEvent", function(_, event)
        if self_ref.editMode then return end
        if event == "PLAYER_ENTERING_WORLD" then
            self_ref:OnEnteringWorld()
        elseif event == "PLAYER_REGEN_DISABLED" then
            self_ref.inCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            self_ref.inCombat = false
            if self_ref.frame:IsShown() then
                self_ref:Update()
            end
        elseif self_ref.frame:IsShown() and not self_ref.inCombat then
            self_ref:Update()
        end
    end)
end

local function Initialize()
    if TankAssist.Addon then
        cc:Create()
        TankAssist.Addon.consumableCheck = cc
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.8, Initialize)
end)
