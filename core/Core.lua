local ADDON_NAME, TankAssist = ...

if LibStub and LibStub("AceAddon-3.0", true) then
    TankAssist.Addon = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0")
else
    TankAssist.Addon = CreateFrame("Frame")
    TankAssist.Addon.events = {}

    local nativeRegisterEvent = TankAssist.Addon.RegisterEvent
    function TankAssist.Addon:RegisterEvent(event, callback)
        self.events[event] = callback or event
        nativeRegisterEvent(self, event)
    end

    function TankAssist.Addon:UnregisterEvent(event)
        self.events[event] = nil
        local nativeUnregister = getmetatable(self).__index.UnregisterEvent
        if nativeUnregister then
            nativeUnregister(self, event)
        end
    end

    TankAssist.Addon:SetScript("OnEvent", function(self, event, ...)
        local handler = self.events[event]
        if handler then
            if type(handler) == "function" then
                handler(self, event, ...)
            elseif type(handler) == "string" and self[handler] then
                self[handler](self, event, ...)
            end
        end
    end)
    
    function TankAssist.Addon:Print(...)
        print("|cFF00CCFF[TankAssist]|r", ...)
    end
end

local addon = TankAssist.Addon
addon.specModules = {}

local defaults = {
    profile = {
        enabled = true,
        locked = false,
        display = {
            scale = 1.0,
            alpha = 1.0,
            showOutOfCombat = false,
            showWithoutTarget = false,
            hideInMythicPlus = false,
            position = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = -200,
            },
        },
        assistedCombat = {
            enabled = true,
            iconSize = 50,
            scale = 1.0,
            showKeybinds = true,
            position = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = -200,
            },
        },
        specs = {},
        sounds = {
            enabled = true,
            buffExpiring = "Interface\\AddOns\\TankAssist\\Sounds\\warning.ogg",
            cooldownReady = "Interface\\AddOns\\TankAssist\\Sounds\\ready.ogg",
        },
    },
}

local function DeepMerge(defaults, saved)
    if type(defaults) ~= "table" then
        return saved ~= nil and saved or defaults
    end
    saved = saved or {}
    local result = {}

    for k, v in pairs(defaults) do
        if type(v) == "table" then
            result[k] = DeepMerge(v, saved[k])
        else
            result[k] = saved[k] ~= nil and saved[k] or v
        end
    end

    for k, v in pairs(saved) do
        if result[k] == nil then
            result[k] = v
        end
    end
    return result
end

function addon:OnInitialize()
    if LibStub and LibStub("AceDB-3.0", true) then
        self.db = LibStub("AceDB-3.0"):New("TankAssistDB", defaults, true)
    else
        if not TankAssistDB then
            TankAssistDB = {}
        end

        TankAssistDB = DeepMerge(defaults.profile, TankAssistDB)
        self.db = { profile = TankAssistDB }
    end
    self:RegisterSlashCommands()
    self.activeSpec = nil
    self:Print("Initialized. Type /ta or /tankassist for options.")
end

function addon:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellCast")
    self:RegisterEvent("UPDATE_BINDINGS", "OnBindingsChanged")
    self:SetupUI()
    self:UpdateSpecModule()
    if not self.ticker then
        self.ticker = C_Timer.NewTicker(0.1, function()
            self:OnUpdate()
        end)
    end
end

function addon:OnSpellCast(event, unit, castGUID, spellId)
    if unit == "player" and spellId then
        TankAssist.SecretValues:OnSpellCast(spellId)
    end
end

function addon:OnBindingsChanged()
    TankAssist.Utils:ClearKeybindCache()
end

function addon:OnDisable()
    self:HideAllFrames()
end

function addon:OnPlayerEnteringWorld()
    self:UpdateSpecModule()
    self:UpdateVisibility()
end

function addon:OnSpecChanged()
    self:UpdateSpecModule()
    self:UpdateVisibility()
end

function addon:OnCombatStart()
    self.inCombat = true
    self:UpdateVisibility()
    if not self.ticker then
        self.ticker = C_Timer.NewTicker(0.1, function()
            self:OnUpdate()
        end)
    end
end

function addon:OnCombatEnd()
    self.inCombat = false
    self:UpdateVisibility()
end

function addon:OnTargetChanged()
    self:UpdateVisibility()
end

function addon:OnUpdate()
    if not self.db.profile.enabled then return end
    if self.assistedCombatDisplay and self.db.profile.assistedCombat.enabled then
        self.assistedCombatDisplay:Update()
    end

    if self.activeSpecModule and self.activeSpecModule.OnUpdate then
        self.activeSpecModule:OnUpdate()
    end
end

function addon:RegisterSpecModule(specId, module)
    self.specModules[specId] = module
    TankAssist.Utils:Debug("Registered spec module for", TankAssist.Utils:GetSpecName(specId))
end

function addon:UpdateSpecModule()
    local specId = TankAssist.Utils:GetCurrentSpec()
    if not specId then
        self.activeSpecModule = nil
        self.activeSpec = nil
        self.isTankSpec = false
        return
    end
    self.activeSpec = specId
    self.isTankSpec = TankAssist.Utils:IsTankSpec(specId)
    if not self.isTankSpec then
        self.activeSpecModule = self:CreateNonTankModule()
        TankAssist.Utils:Debug("Non-tank spec - main rotation button enabled, secondary button hidden")
        return
    end

    local module = self.specModules[specId]
    if not module then
        self:Print("No module found for " .. TankAssist.Utils:GetSpecName(specId) .. ". Using generic tank mode.")
        module = self.specModules["generic"] or self:CreateGenericModule()
    end
    if self.activeSpecModule and self.activeSpecModule.OnDeactivate then
        self.activeSpecModule:OnDeactivate()
    end
    self.activeSpecModule = module

    if module.OnActivate then
        module:OnActivate()
    end
    self:UpdateUIForSpec()
    TankAssist.Utils:Debug("Activated spec module for", TankAssist.Utils:GetSpecName(specId))
end

function addon:CreateGenericModule()
    local generic = {
        name = "Generic Tank",
        buffsToTrack = {},
        cooldownsToTrack = {},
        isTank = true,
    }
    function generic:GetRecommendation()
        return nil
    end

    function generic:GetMaintenanceStatus()
        return {}
    end

    self.specModules["generic"] = generic
    return generic
end

function addon:CreateNonTankModule()
    local nonTank = {
        name = "Non-Tank",
        buffsToTrack = {},
        cooldownsToTrack = {},
        isTank = false,
        secondarySpells = {},
    }

    local _, classFile = UnitClass("player")
    nonTank.secondarySpells = self:GetClassCooldowns(classFile) or {}
    function nonTank:GetRecommendation()
        return nil
    end

    function nonTank:GetSecondarySpell()
        for _, spellData in ipairs(self.secondarySpells) do
            local spellId = spellData.spellId
            if spellId and IsSpellKnown(spellId) then
                local canCast = TankAssist.SecretValues:CanCastSpell(spellId)
                if canCast then
                    local conditionMet = not spellData.condition or spellData.condition(self)
                    if conditionMet then
                        return spellId, spellData.category == "DEFENSIVE" and "utility" or "offensive", spellData.urgency or "NORMAL"
                    end
                end
            end
        end
        return nil
    end

    function nonTank:GetHealthPercent()
        return TankAssist.SecretValues:GetHealthPercent("player")
    end

    function nonTank:HealthBelow(threshold)
        local hp = self:GetHealthPercent()
        return hp and hp < threshold
    end

    function nonTank:HasTarget()
        return UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target")
    end

    function nonTank:InCombat()
        return UnitAffectingCombat("player")
    end

    function nonTank:GetMaintenanceStatus()
        return {}
    end

    return nonTank
end

function addon:GetClassCooldowns(classFile)
    return TankAssist.ClassCooldowns:GetForClass(classFile)
end

function addon:SetupUI()
    self.mainFrame = CreateFrame("Frame", "TankAssistMainFrame", UIParent)
    self.mainFrame:SetSize(400, 200)
    self.mainFrame:SetPoint(
        self.db.profile.display.position.point,
        UIParent,
        self.db.profile.display.position.relativePoint,
        self.db.profile.display.position.x,
        self.db.profile.display.position.y
    )
    self.mainFrame:SetScale(self.db.profile.display.scale)
    self.mainFrame:SetAlpha(self.db.profile.display.alpha)
    self.mainFrame:SetMovable(true)
    self.mainFrame:EnableMouse(not self.db.profile.locked)
    self.mainFrame:RegisterForDrag("LeftButton")
    self.mainFrame:SetScript("OnDragStart", function(frame)
        if not self.db.profile.locked then
            frame:StartMoving()
        end
    end)
    self.mainFrame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint()
        self.db.profile.display.position.point = point
        self.db.profile.display.position.relativePoint = relativePoint
        self.db.profile.display.position.x = x
        self.db.profile.display.position.y = y
    end)
    self.assistedCombatDisplay = nil
    self.cooldownTracker = nil
    self.buffMaintenance = nil
end

function addon:UpdateUIForSpec()
    if not self.activeSpecModule then return end

    if self.buffMaintenance then
        self.buffMaintenance:SetBuffs(self.activeSpecModule.buffsToTrack or {})
    end

    if self.cooldownTracker then
        self.cooldownTracker:SetCooldowns(self.activeSpecModule.cooldownsToTrack or {})
    end
end

function addon:UpdateVisibility()
    if not self.db.profile.enabled then
        self:HideAllFrames()
        return
    end

    local shouldShow = self:ShouldShowUI()
    if shouldShow then
        self:ShowAllFrames()
    else
        self:HideAllFrames()
    end
end

function addon:ShouldShowUI()
    if self.db.profile.display.hideInMythicPlus and TankAssist.SecretValues:InMythicPlus() then
        return false
    end

    if not self.db.profile.display.showOutOfCombat and not self.inCombat then
        return false
    end

    if not self.db.profile.display.showWithoutTarget and not TankAssist.SecretValues:HasTarget() then
        return false
    end

    return true
end

function addon:ShowAllFrames()
    if self.mainFrame then
        self.mainFrame:Show()
    end
end

function addon:HideAllFrames()
    if self.mainFrame then
        self.mainFrame:Hide()
    end
end

function addon:RegisterSlashCommands()
    SLASH_TANKASSIST1 = "/tankassist"
    SLASH_TANKASSIST2 = "/ta"
    SlashCmdList["TANKASSIST"] = function(msg)
        self:HandleSlashCommand(msg)
    end
end

function addon:HandleSlashCommand(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word:lower())
    end
    
    local cmd = args[1] or "help"
    if cmd == "toggle" then
        self.db.profile.enabled = not self.db.profile.enabled
        self:Print("TankAssist " .. (self.db.profile.enabled and "enabled" or "disabled"))
        self:UpdateVisibility()
        
    elseif cmd == "edit" or cmd == "lock" or cmd == "unlock" then
        self:Print("To reposition TankAssist, use WoW's Edit Mode:")
        print("  1. Press Escape")
        print("  2. Click 'Edit Mode'")
        print("  3. Drag the TankAssist frame")
        print("  4. Click 'Save Changes' when done")
        
    elseif cmd == "config" or cmd == "options" then
        if self.configPanel then
            self.configPanel:Show()
        else
            self:Print("Config panel not yet implemented. Use slash commands.")
        end
        
    elseif cmd == "debug" then
        local subCmd = args[2]
        if subCmd == "utility" or subCmd == "utilities" then
            -- Toggle utility debugging
            if self.activeSpecModule then
                local enabled = not self.activeSpecModule.debugUtilities
                self.activeSpecModule.debugUtilities = enabled
                self:Print("Utility debug " .. (enabled and "enabled" or "disabled"))
                if enabled then
                    print("  Watch chat for utility condition checks")
                end
            else
                self:Print("No active spec module to debug")
            end
        elseif subCmd == "stagger" then
            self:Print("Stagger diagnostic:")
            print("  UnitStagger exists:", UnitStagger ~= nil)
            if UnitStagger then
                local rawStagger = UnitStagger("player")
                print("  UnitStagger raw value:", rawStagger)
            end
            if Enum and Enum.PowerType and Enum.PowerType.Stagger then
                local powerStagger = UnitPower("player", Enum.PowerType.Stagger)
                print("  UnitPower(Stagger) value:", powerStagger)
            else
                print("  Enum.PowerType.Stagger: not found")
            end
            print("  Max Health:", UnitHealthMax("player"))
            local specId = TankAssist.Utils:GetCurrentSpec()
            print("  Current Spec ID:", specId, "(Brewmaster is 268)")
            local stagger = TankAssist.SecretValues:GetStaggerInfo()
            print("  Computed Level:", stagger.level)
            print("  Computed Percent:", string.format("%.1f%%", (stagger.percent or 0) * 100))
            print("  Computed Amount:", stagger.amount)
            print("  Is Secret:", stagger.isSecret)
        elseif subCmd == "health" then
            local hp = TankAssist.SecretValues:GetHealthPercent("player")
            self:Print("Health percent:", hp and string.format("%.1f%%", hp * 100) or "SECRET")
        elseif subCmd == "rage" or subCmd == "resource" then
            self:Print("Resource diagnostic:")
            print("  Raw UnitPower test:")
            print("    Enum.PowerType.Rage:", Enum.PowerType.Rage)
            local rawRage = UnitPower("player", Enum.PowerType.Rage)
            print("    UnitPower(player, Rage):", rawRage)
            print("    type:", type(rawRage))
            print("    isSecret:", TankAssist.SecretValues:IsSecret(rawRage))
            print("  GetResource test:")
            local rage = TankAssist.SecretValues:GetResource("RAGE")
            print("    GetResource('RAGE'):", rage)
            print("    type:", type(rage))
            print("  Other resources:")
            local energy = TankAssist.SecretValues:GetResource("ENERGY")
            print("    GetResource('ENERGY'):", energy)
            local holyPower = TankAssist.SecretValues:GetResource("HOLY_POWER")
            print("    GetResource('HOLY_POWER'):", holyPower)

        elseif subCmd == "tracking" or subCmd == "cooldowns" then
            self:Print("Tracked cooldowns (internal timer):")
            local hasTracked = false
            for spellId, data in pairs(TankAssist.SecretValues.trackedCooldowns) do
                hasTracked = true
                local spellInfo = C_Spell.GetSpellInfo(spellId)
                local spellName = spellInfo and spellInfo.name or "Unknown"
                local remaining = data.duration - (GetTime() - data.castTime)
                if remaining > 0 then
                    print(string.format("  %s: %.1fs remaining (of %ds)", spellName, remaining, data.duration))
                else
                    print(string.format("  %s: READY (was %ds CD)", spellName, data.duration))
                end
            end
            if not hasTracked then
                print("  No regular cooldowns tracked yet.")
            end
            print("")
            print("  Tracked charges (charge-based spells):")
            local hasCharges = false
            for spellId, data in pairs(TankAssist.SecretValues.trackedCharges) do
                hasCharges = true
                local spellInfo = C_Spell.GetSpellInfo(spellId)
                local spellName = spellInfo and spellInfo.name or "Unknown"
                local charges, maxCharges = TankAssist.SecretValues:GetTrackedCharges(spellId)
                print(string.format("  %s: %d/%d charges", spellName, charges or 0, maxCharges or 0))
                for i, castTime in ipairs(data.castTimes) do
                    local elapsed = GetTime() - castTime
                    local remaining = data.rechargeTime - elapsed
                    if remaining > 0 then
                        print(string.format("    Charge %d recharging: %.1fs", i, remaining))
                    end
                end
            end
            if not hasCharges then
                print("  No charge-based spells tracked yet.")
            end

            print("")
            print("  Known cooldowns configured:", self:CountTable(TankAssist.SecretValues.KnownCooldowns))
            print("  Known charge spells configured:", self:CountTable(TankAssist.SecretValues.KnownChargeSpells))

        elseif subCmd == "combat" then
            self:Print("Combat state diagnostic:")
            print("  UnitAffectingCombat:", UnitAffectingCombat("player"))
            print("  Core.inCombat:", self.inCombat)
            if TankAssist.AssistedCombatDisplay then
                print("  ACD.inCombat:", TankAssist.AssistedCombatDisplay.inCombat)
                print("  ACD.frame alpha:", TankAssist.AssistedCombatDisplay.frame and TankAssist.AssistedCombatDisplay.frame:GetAlpha())
            end

        elseif subCmd == "settings" or subCmd == "saved" then
            self:Print("Saved settings:")
            local ac = self.db.profile.assistedCombat
            print("  Scale:", ac.scale)
            print("  Icon Size:", ac.iconSize)
            print("  Position:", ac.position.point, ac.position.x, ac.position.y)
            print("  TankAssistDB exists:", TankAssistDB ~= nil)

        elseif subCmd == "secondary" or subCmd == "aoe" then
            self:Print("Secondary spell diagnostic:")
            local specModule = self.activeSpecModule
            if not specModule then
                print("  No active spec module!")
                return
            end
            print("  Spec:", specModule.specName or "Unknown")
            print("  IsPlayerSpell API exists:", IsPlayerSpell ~= nil)

            if specModule.aoeSpells then
                print("  AoE spell candidates:")
                for i, aoeData in ipairs(specModule.aoeSpells) do
                    local spellId = aoeData.spellId
                    local spellInfo = C_Spell.GetSpellInfo(spellId)
                    local spellName = spellInfo and spellInfo.name or "Unknown"
                    local isKnown = IsSpellKnown(spellId)
                    local isPlayerSpell = IsPlayerSpell and IsPlayerSpell(spellId)
                    local cdInfo = C_Spell.GetSpellCooldown(spellId)
                    local hasCDInfo = cdInfo and cdInfo.startTime ~= nil
                    local usable, noMana = C_Spell.IsSpellUsable(spellId)
                    local cdData = TankAssist.SecretValues:GetCooldownInfo(spellId)
                    local conditionMet = not aoeData.condition or aoeData.condition()
                    print(string.format("    %d. %s (ID:%d)", i, spellName, spellId))
                    print(string.format("       IsSpellKnown: %s", tostring(isKnown)))
                    print(string.format("       IsPlayerSpell: %s", tostring(isPlayerSpell)))
                    print(string.format("       Has CD Info: %s", tostring(hasCDInfo)))
                    print(string.format("       IsSpellUsable: %s (noMana: %s)", tostring(usable), tostring(noMana)))
                    print(string.format("       OnCD: %s, Charges: %s", tostring(cdData.onCooldown), tostring(cdData.charges)))
                    print(string.format("       Condition: %s", tostring(conditionMet)))
                end
            else
                print("  No aoeSpells defined")
            end

            if specModule.GetBestAoESpell then
                local bestAoE = specModule:GetBestAoESpell()
                local spellInfo = bestAoE and C_Spell.GetSpellInfo(bestAoE)
                print("  GetBestAoESpell result:", spellInfo and spellInfo.name or "nil", "(ID:", bestAoE or "nil", ")")
            end

            if specModule.GetSecondarySpell then
                local spell, spellType, priority = specModule:GetSecondarySpell()
                local spellInfo = spell and C_Spell.GetSpellInfo(spell)
                print("  GetSecondarySpell result:", spellInfo and spellInfo.name or "nil", "Type:", spellType, "Priority:", priority)
            end

            print("  CanCastSpell results (unified cooldown + resource check):")
            if specModule.aoeSpells then
                for i, aoeData in ipairs(specModule.aoeSpells) do
                    local spellId = aoeData.spellId
                    local spellInfo = C_Spell.GetSpellInfo(spellId)
                    local spellName = spellInfo and spellInfo.name or "Unknown"
                    local canCast, reason = TankAssist.SecretValues:CanCastSpell(spellId)
                    print(string.format("    %s: canCast=%s, reason=%s",
                        spellName, tostring(canCast), tostring(reason)))
                end
            end

            local pbId = TankAssist.Constants.Brewmaster and TankAssist.Constants.Brewmaster.Spells.PurifyingBrew
            if pbId then
                print("  Purifying Brew charge check:")
                local chargeInfo = C_Spell.GetSpellCharges(pbId)
                if chargeInfo then
                    print(string.format("    Charges: %s/%s, CD: %.1fs",
                        tostring(chargeInfo.currentCharges),
                        tostring(chargeInfo.maxCharges),
                        chargeInfo.cooldownDuration or 0))
                else
                    print("    No charge info available")
                end
                local canCast, reason = TankAssist.SecretValues:CanCastSpell(pbId)
                print(string.format("    CanCastSpell: %s, reason: %s", tostring(canCast), tostring(reason)))
            end
        else
            local enabled = subCmd == "on" or subCmd == "true" or subCmd == "1"
            TankAssist.Utils:SetDebug(enabled)
            TankAssist.SecretValues:SetDebug(enabled)
            self:Print("Debug mode " .. (enabled and "enabled" or "disabled"))
        end
        
    elseif cmd == "reset" then
        self.db.profile.display.position = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = -200,
        }
        if self.mainFrame then
            self.mainFrame:ClearAllPoints()
            self.mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
        end
        self:Print("Position reset to default")
        
    elseif cmd == "test" then
        self:RunTestMode()  
    else
        self:PrintHelp()
    end
end

function addon:CountTable(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

function addon:PrintHelp()
    self:Print("Commands:")
    print("  /ta toggle - Enable/disable addon")
    print("  /ta reset - Reset frame position")
    print("  /ta config - Open configuration panel")
    print("  /ta debug on/off - Toggle debug mode")
    print("  /ta debug utility - Toggle tank utility debug")
    print("  /ta debug stagger - Show stagger info (Brewmaster)")
    print("  /ta debug health - Show health percent")
    print("  /ta debug rage - Show rage/resource info (Guardian)")
    print("  /ta debug secondary - Show secondary button spell selection")
    print("  /ta debug tracking - Show tracked cooldowns (internal timers)")
    print("  /ta debug combat - Show combat state")
    print("  /ta debug settings - Show saved settings")
    print("  /ta test - Run test mode")
    print("")
    print("  To reposition: Use WoW's Edit Mode (Escape > Edit Mode)")
end

function addon:RunTestMode()
    self:Print("Running test mode...")
    local specId = TankAssist.Utils:GetCurrentSpec()
    print("  Current spec:", TankAssist.Utils:GetSpecName(specId))
    print("  Is tank:", TankAssist.Utils:IsTankSpec(specId))
    print("  Can access secrets:", TankAssist.SecretValues:CanAccessSecrets())
    print("  In M+:", TankAssist.SecretValues:InMythicPlus())
    if self.activeSpecModule and self.activeSpecModule.buffsToTrack then
        print("  Tracked buffs:")
        for _, buffData in ipairs(self.activeSpecModule.buffsToTrack) do
            local info = TankAssist.SecretValues:GetBuffInfo("player", buffData.spellId)
            print("    -", buffData.name, "exists:", info.exists, "secret:", info.isSecret)
        end
    end
end

local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ADDON_LOADED")
loadFrame:RegisterEvent("PLAYER_LOGIN")
loadFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        if addon.OnInitialize then
            addon:OnInitialize()
        end
    elseif event == "PLAYER_LOGIN" then
        if addon.OnEnable then
            addon:OnEnable()
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
