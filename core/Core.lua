-- TankAssist Core
-- Main addon initialization and event handling

local ADDON_NAME, TA = ...

-- Create main addon object using AceAddon if available, otherwise simple table
if LibStub and LibStub("AceAddon-3.0", true) then
    TA.Addon = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0")
else
    -- Simple fallback without Ace libraries
    TA.Addon = CreateFrame("Frame")
    TA.Addon.events = {}
    
    -- Store the native frame method before we override
    local nativeRegisterEvent = TA.Addon.RegisterEvent
    
    function TA.Addon:RegisterEvent(event, callback)
        self.events[event] = callback or event
        -- Use the native frame RegisterEvent, not our custom one
        nativeRegisterEvent(self, event)
    end
    
    function TA.Addon:UnregisterEvent(event)
        self.events[event] = nil
        -- Use native unregister
        local nativeUnregister = getmetatable(self).__index.UnregisterEvent
        if nativeUnregister then
            nativeUnregister(self, event)
        end
    end
    
    -- Set up the OnEvent handler once
    TA.Addon:SetScript("OnEvent", function(self, event, ...)
        local handler = self.events[event]
        if handler then
            if type(handler) == "function" then
                handler(self, event, ...)
            elseif type(handler) == "string" and self[handler] then
                self[handler](self, event, ...)
            end
        end
    end)
    
    function TA.Addon:Print(...)
        print("|cFF00CCFF[TankAssist]|r", ...)
    end
end

local Addon = TA.Addon

-- Initialize specModules early so spec modules can register during file load
Addon.specModules = {}

-- =============================================================================
-- ADDON DEFAULTS
-- =============================================================================

local defaults = {
    profile = {
        enabled = true,
        locked = false,
        
        -- Display options
        display = {
            scale = 1.0,
            alpha = 1.0,
            showOutOfCombat = false,
            showWithoutTarget = false,
            hideInMythicPlus = false, -- Some may want this due to secret values
            
            -- Main display position
            position = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = -200,
            },
        },
        
        -- Assisted Combat display (2 buttons: main rotation + AoE)
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
        
        -- Per-spec settings (will be populated by spec modules)
        specs = {},
        
        -- Sound alerts
        sounds = {
            enabled = true,
            buffExpiring = "Interface\\AddOns\\TankAssist\\Sounds\\warning.ogg",
            cooldownReady = "Interface\\AddOns\\TankAssist\\Sounds\\ready.ogg",
        },
    },
}

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

-- Helper to deep merge tables (saved data takes priority)
local function DeepMerge(defaults, saved)
    if type(defaults) ~= "table" then
        return saved ~= nil and saved or defaults
    end

    saved = saved or {}
    local result = {}

    -- Copy defaults first
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            result[k] = DeepMerge(v, saved[k])
        else
            result[k] = saved[k] ~= nil and saved[k] or v
        end
    end

    -- Also copy any saved values that aren't in defaults
    for k, v in pairs(saved) do
        if result[k] == nil then
            result[k] = v
        end
    end

    return result
end

function Addon:OnInitialize()
    -- Initialize saved variables
    if LibStub and LibStub("AceDB-3.0", true) then
        self.db = LibStub("AceDB-3.0"):New("TankAssistDB", defaults, true)
    else
        -- Simple saved variables fallback with proper merging
        if not TankAssistDB then
            TankAssistDB = {}
        end

        -- Merge defaults with saved data (saved data takes priority)
        TankAssistDB = DeepMerge(defaults.profile, TankAssistDB)
        self.db = { profile = TankAssistDB }
    end

    -- Register slash commands
    self:RegisterSlashCommands()

    -- Initialize active spec tracking
    self.activeSpec = nil

    self:Print("Initialized. Type /ta or /tankassist for options.")
end

function Addon:OnEnable()
    -- Register events
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellCast")
    self:RegisterEvent("UPDATE_BINDINGS", "OnBindingsChanged")

    -- Initial setup
    self:SetupUI()
    self:UpdateSpecModule()

    -- Start update ticker (runs always, not just in combat)
    if not self.ticker then
        self.ticker = C_Timer.NewTicker(0.1, function()
            self:OnUpdate()
        end)
    end
end





-- Track spell casts for cooldown tracking
function Addon:OnSpellCast(event, unit, castGUID, spellId)
    if unit == "player" and spellId then
        TA.SecretValues:OnSpellCast(spellId)
    end
end

-- Clear keybind cache when bindings change
function Addon:OnBindingsChanged()
    TA.Utils:ClearKeybindCache()
end

function Addon:OnDisable()
    self:HideAllFrames()
end

-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================

function Addon:OnPlayerEnteringWorld()
    self:UpdateSpecModule()
    self:UpdateVisibility()
end

function Addon:OnSpecChanged()
    self:UpdateSpecModule()
    self:UpdateVisibility()
end

function Addon:OnCombatStart()
    self.inCombat = true
    self:UpdateVisibility()
    
    -- Start update ticker
    if not self.ticker then
        self.ticker = C_Timer.NewTicker(0.1, function()
            self:OnUpdate()
        end)
    end
end

function Addon:OnCombatEnd()
    self.inCombat = false
    self:UpdateVisibility()

    -- We keep the ticker running but at a slower rate out of combat
    -- This allows pre-pull preparation
end

function Addon:OnTargetChanged()
    self:UpdateVisibility()
end

-- =============================================================================
-- MAIN UPDATE LOOP
-- =============================================================================

function Addon:OnUpdate()
    if not self.db.profile.enabled then return end

    -- Update assisted combat display (works for all specs)
    if self.assistedCombatDisplay and self.db.profile.assistedCombat.enabled then
        self.assistedCombatDisplay:Update()
    end

    -- Let the active spec module do any custom updates (tank specs only)
    if self.activeSpecModule and self.activeSpecModule.OnUpdate then
        self.activeSpecModule:OnUpdate()
    end
end

-- =============================================================================
-- SPEC MODULE MANAGEMENT
-- =============================================================================

function Addon:RegisterSpecModule(specId, module)
    self.specModules[specId] = module
    TA.Utils:Debug("Registered spec module for", TA.Utils:GetSpecName(specId))
end

function Addon:UpdateSpecModule()
    local specId = TA.Utils:GetCurrentSpec()

    if not specId then
        self.activeSpecModule = nil
        self.activeSpec = nil
        self.isTankSpec = false
        return
    end

    self.activeSpec = specId
    self.isTankSpec = TA.Utils:IsTankSpec(specId)

    -- For non-tank specs, use a minimal module (main button still works via Blizzard API)
    if not self.isTankSpec then
        self.activeSpecModule = self:CreateNonTankModule()
        TA.Utils:Debug("Non-tank spec - main rotation button enabled, secondary button hidden")
        return
    end

    -- Get the spec module for tank specs
    local module = self.specModules[specId]

    if not module then
        self:Print("No module found for " .. TA.Utils:GetSpecName(specId) .. ". Using generic tank mode.")
        module = self.specModules["generic"] or self:CreateGenericModule()
    end

    -- Deactivate old module
    if self.activeSpecModule and self.activeSpecModule.OnDeactivate then
        self.activeSpecModule:OnDeactivate()
    end

    -- Activate new module
    self.activeSpecModule = module

    if module.OnActivate then
        module:OnActivate()
    end

    -- Update UI with new spec data
    self:UpdateUIForSpec()

    TA.Utils:Debug("Activated spec module for", TA.Utils:GetSpecName(specId))
end

function Addon:CreateGenericModule()
    -- Fallback generic module for unsupported tank specs
    local generic = {
        name = "Generic Tank",
        buffsToTrack = {},
        cooldownsToTrack = {},
        isTank = true,
    }

    function generic:GetRecommendation()
        return nil -- Rely on Blizzard's assisted combat
    end

    function generic:GetMaintenanceStatus()
        return {}
    end

    self.specModules["generic"] = generic
    return generic
end

function Addon:CreateNonTankModule()
    -- Module for non-tank specs - shows offensive/defensive cooldowns
    local nonTank = {
        name = "Non-Tank",
        buffsToTrack = {},
        cooldownsToTrack = {},
        isTank = false,
        secondarySpells = {}, -- Will be populated based on class
    }

    -- Populate secondarySpells based on current class
    local _, classFile = UnitClass("player")
    nonTank.secondarySpells = self:GetClassCooldowns(classFile) or {}

    function nonTank:GetRecommendation()
        return nil -- Rely on Blizzard's assisted combat
    end

    function nonTank:GetSecondarySpell()
        -- Check each secondary spell in priority order
        for _, spellData in ipairs(self.secondarySpells) do
            local spellId = spellData.spellId
            if spellId and IsSpellKnown(spellId) then
                local canCast = TA.SecretValues:CanCastSpell(spellId)
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
        return TA.SecretValues:GetHealthPercent("player")
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

-- Get class-specific cooldowns for non-tank specs
function Addon:GetClassCooldowns(classFile)
    local cooldowns = {}

    -- Common defensive cooldowns by class
    local classCooldowns = {
        WARRIOR = {
            { spellId = 184364, category = "DEFENSIVE", urgency = "URGENT", condition = function(self) return self:HealthBelow(0.40) end }, -- Enraged Regeneration
            { spellId = 97462, category = "DEFENSIVE", urgency = "HIGH", condition = function(self) return self:HealthBelow(0.50) end }, -- Rallying Cry
            { spellId = 1719, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Recklessness
            { spellId = 227847, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Bladestorm
        },
        PALADIN = {
            { spellId = 642, category = "DEFENSIVE", urgency = "URGENT", condition = function(self) return self:HealthBelow(0.20) end }, -- Divine Shield
            { spellId = 633, category = "DEFENSIVE", urgency = "URGENT", condition = function(self) return self:HealthBelow(0.30) end }, -- Lay on Hands
            { spellId = 31884, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Avenging Wrath
        },
        HUNTER = {
            { spellId = 186265, category = "DEFENSIVE", urgency = "URGENT", condition = function(self) return self:HealthBelow(0.30) end }, -- Aspect of the Turtle
            { spellId = 109304, category = "DEFENSIVE", urgency = "HIGH", condition = function(self) return self:HealthBelow(0.50) end }, -- Exhilaration
            { spellId = 288613, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Trueshot/Bestial Wrath/Coordinated Assault
        },
        ROGUE = {
            { spellId = 185311, category = "DEFENSIVE", urgency = "URGENT", condition = function(self) return self:HealthBelow(0.30) end }, -- Crimson Vial
            { spellId = 31224, category = "DEFENSIVE", urgency = "HIGH", condition = function(self) return self:HealthBelow(0.40) end }, -- Cloak of Shadows
            { spellId = 1856, category = "DEFENSIVE", urgency = "HIGH", condition = function(self) return self:HealthBelow(0.25) end }, -- Vanish
            { spellId = 13750, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Adrenaline Rush
        },
        PRIEST = {
            { spellId = 19236, category = "DEFENSIVE", urgency = "URGENT", condition = function(self) return self:HealthBelow(0.35) end }, -- Desperate Prayer
            { spellId = 586, category = "DEFENSIVE", urgency = "HIGH", condition = function(self) return self:HealthBelow(0.50) end }, -- Fade
            { spellId = 10060, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:InCombat() end }, -- Power Infusion
        },
        SHAMAN = {
            { spellId = 108271, category = "DEFENSIVE", urgency = "URGENT", condition = function(self) return self:HealthBelow(0.35) end }, -- Astral Shift
            { spellId = 198103, category = "DEFENSIVE", urgency = "HIGH", condition = function(self) return self:HealthBelow(0.50) end }, -- Earth Elemental
            { spellId = 114051, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Ascendance
        },
        MAGE = {
            { spellId = 45438, category = "DEFENSIVE", urgency = "URGENT", condition = function(self) return self:HealthBelow(0.20) end }, -- Ice Block
            { spellId = 55342, category = "DEFENSIVE", urgency = "HIGH", condition = function(self) return self:HealthBelow(0.40) end }, -- Mirror Image
            { spellId = 12472, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Icy Veins
            { spellId = 190319, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Combustion
            { spellId = 365350, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Arcane Surge
        },
        WARLOCK = {
            { spellId = 104773, category = "DEFENSIVE", urgency = "URGENT", condition = function(self) return self:HealthBelow(0.30) end }, -- Unending Resolve
            { spellId = 108416, category = "DEFENSIVE", urgency = "HIGH", condition = function(self) return self:HealthBelow(0.50) end }, -- Dark Pact
            { spellId = 205180, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Summon Darkglare
        },
        DRUID = {
            { spellId = 22812, category = "DEFENSIVE", urgency = "URGENT", condition = function(self) return self:HealthBelow(0.40) end }, -- Barkskin
            { spellId = 108238, category = "DEFENSIVE", urgency = "HIGH", condition = function(self) return self:HealthBelow(0.50) end }, -- Renewal
            { spellId = 194223, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Celestial Alignment
            { spellId = 102560, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Incarnation
        },
        DEATHKNIGHT = {
            { spellId = 48792, category = "DEFENSIVE", urgency = "URGENT", condition = function(self) return self:HealthBelow(0.35) end }, -- Icebound Fortitude
            { spellId = 48707, category = "DEFENSIVE", urgency = "HIGH", condition = function(self) return self:HealthBelow(0.50) end }, -- Anti-Magic Shell
            { spellId = 47568, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Empower Rune Weapon
        },
        MONK = {
            { spellId = 122783, category = "DEFENSIVE", urgency = "HIGH", condition = function(self) return self:HealthBelow(0.50) end }, -- Diffuse Magic
            { spellId = 122278, category = "DEFENSIVE", urgency = "HIGH", condition = function(self) return self:HealthBelow(0.40) end }, -- Dampen Harm
            { spellId = 137639, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Storm, Earth, and Fire
            { spellId = 152173, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Serenity
        },
        DEMONHUNTER = {
            { spellId = 198589, category = "DEFENSIVE", urgency = "URGENT", condition = function(self) return self:HealthBelow(0.35) end }, -- Blur
            { spellId = 196555, category = "DEFENSIVE", urgency = "HIGH", condition = function(self) return self:HealthBelow(0.50) end }, -- Netherwalk
            { spellId = 191427, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Metamorphosis (Havoc)
            { spellId = 258925, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Fel Barrage
        },
        EVOKER = {
            { spellId = 363916, category = "DEFENSIVE", urgency = "URGENT", condition = function(self) return self:HealthBelow(0.30) end }, -- Obsidian Scales
            { spellId = 374348, category = "DEFENSIVE", urgency = "HIGH", condition = function(self) return self:HealthBelow(0.50) end }, -- Renewing Blaze
            { spellId = 375087, category = "OFFENSIVE", urgency = "NORMAL", condition = function(self) return self:HasTarget() and self:InCombat() end }, -- Dragonrage
        },
    }

    return classCooldowns[classFile] or {}
end

-- =============================================================================
-- UI SETUP
-- =============================================================================

function Addon:SetupUI()
    -- Create main container frame
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
    
    -- Make draggable when unlocked
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
    
    -- Initialize UI components (will be created by their respective modules)
    -- These are placeholders that get populated when UI modules load
    self.assistedCombatDisplay = nil
    self.cooldownTracker = nil
    self.buffMaintenance = nil
end

function Addon:UpdateUIForSpec()
    if not self.activeSpecModule then return end
    
    -- Update buff maintenance with spec-specific buffs
    if self.buffMaintenance then
        self.buffMaintenance:SetBuffs(self.activeSpecModule.buffsToTrack or {})
    end
    
    -- Update cooldown tracker with spec-specific cooldowns
    if self.cooldownTracker then
        self.cooldownTracker:SetCooldowns(self.activeSpecModule.cooldownsToTrack or {})
    end
end

-- =============================================================================
-- VISIBILITY CONTROL
-- =============================================================================

function Addon:UpdateVisibility()
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

function Addon:ShouldShowUI()
    -- Show for all specs now (main button uses Blizzard's assisted combat)
    -- Secondary button is hidden for non-tanks in AssistedCombatDisplay

    -- Check M+ restriction
    if self.db.profile.display.hideInMythicPlus and TA.SecretValues:InMythicPlus() then
        return false
    end

    -- Check combat setting
    if not self.db.profile.display.showOutOfCombat and not self.inCombat then
        return false
    end

    -- Check target setting
    if not self.db.profile.display.showWithoutTarget and not TA.SecretValues:HasTarget() then
        return false
    end

    return true
end

function Addon:ShowAllFrames()
    if self.mainFrame then
        self.mainFrame:Show()
    end
end

function Addon:HideAllFrames()
    if self.mainFrame then
        self.mainFrame:Hide()
    end
end

-- =============================================================================
-- SLASH COMMANDS
-- =============================================================================

function Addon:RegisterSlashCommands()
    SLASH_TANKASSIST1 = "/tankassist"
    SLASH_TANKASSIST2 = "/ta"
    
    SlashCmdList["TANKASSIST"] = function(msg)
        self:HandleSlashCommand(msg)
    end
end

function Addon:HandleSlashCommand(msg)
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
        -- Point users to WoW's Edit Mode
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
            -- Test stagger info (Brewmaster)
            self:Print("Stagger diagnostic:")

            -- Check if UnitStagger exists
            print("  UnitStagger exists:", UnitStagger ~= nil)

            -- Try UnitStagger directly
            if UnitStagger then
                local rawStagger = UnitStagger("player")
                print("  UnitStagger raw value:", rawStagger)
            end

            -- Try power type
            if Enum and Enum.PowerType and Enum.PowerType.Stagger then
                local powerStagger = UnitPower("player", Enum.PowerType.Stagger)
                print("  UnitPower(Stagger) value:", powerStagger)
            else
                print("  Enum.PowerType.Stagger: not found")
            end

            -- Max health for reference
            print("  Max Health:", UnitHealthMax("player"))

            -- Current spec
            local specId = TA.Utils:GetCurrentSpec()
            print("  Current Spec ID:", specId, "(Brewmaster is 268)")

            -- Full stagger info
            local stagger = TA.SecretValues:GetStaggerInfo()
            print("  Computed Level:", stagger.level)
            print("  Computed Percent:", string.format("%.1f%%", (stagger.percent or 0) * 100))
            print("  Computed Amount:", stagger.amount)
            print("  Is Secret:", stagger.isSecret)
        elseif subCmd == "health" then
            -- Test health info
            local hp = TA.SecretValues:GetHealthPercent("player")
            self:Print("Health percent:", hp and string.format("%.1f%%", hp * 100) or "SECRET")

        elseif subCmd == "rage" or subCmd == "resource" then
            -- Test rage/resource info
            self:Print("Resource diagnostic:")

            -- Raw API test
            print("  Raw UnitPower test:")
            print("    Enum.PowerType.Rage:", Enum.PowerType.Rage)
            local rawRage = UnitPower("player", Enum.PowerType.Rage)
            print("    UnitPower(player, Rage):", rawRage)
            print("    type:", type(rawRage))
            print("    isSecret:", TankAssist.SecretValues:IsSecret(rawRage))

            -- Through GetResource
            print("  GetResource test:")
            local rage = TankAssist.SecretValues:GetResource("RAGE")
            print("    GetResource('RAGE'):", rage)
            print("    type:", type(rage))

            -- Other resources
            print("  Other resources:")
            local energy = TankAssist.SecretValues:GetResource("ENERGY")
            print("    GetResource('ENERGY'):", energy)
            local holyPower = TankAssist.SecretValues:GetResource("HOLY_POWER")
            print("    GetResource('HOLY_POWER'):", holyPower)

        elseif subCmd == "tracking" or subCmd == "cooldowns" then
            -- Show tracked cooldowns
            self:Print("Tracked cooldowns (internal timer):")
            local hasTracked = false
            for spellId, data in pairs(TA.SecretValues.trackedCooldowns) do
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

            -- Show tracked charges
            print("")
            print("  Tracked charges (charge-based spells):")
            local hasCharges = false
            for spellId, data in pairs(TA.SecretValues.trackedCharges) do
                hasCharges = true
                local spellInfo = C_Spell.GetSpellInfo(spellId)
                local spellName = spellInfo and spellInfo.name or "Unknown"
                local charges, maxCharges = TA.SecretValues:GetTrackedCharges(spellId)
                print(string.format("  %s: %d/%d charges", spellName, charges or 0, maxCharges or 0))
                -- Show individual charge cooldowns
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
            print("  Known cooldowns configured:", self:CountTable(TA.SecretValues.KNOWN_COOLDOWNS))
            print("  Known charge spells configured:", self:CountTable(TA.SecretValues.KNOWN_CHARGE_SPELLS))

        elseif subCmd == "combat" then
            -- Test combat state
            self:Print("Combat state diagnostic:")
            print("  UnitAffectingCombat:", UnitAffectingCombat("player"))
            print("  Core.inCombat:", self.inCombat)
            if TA.AssistedCombatDisplay then
                print("  ACD.inCombat:", TA.AssistedCombatDisplay.inCombat)
                print("  ACD.frame alpha:", TA.AssistedCombatDisplay.frame and TA.AssistedCombatDisplay.frame:GetAlpha())
            end

        elseif subCmd == "settings" or subCmd == "saved" then
            -- Show saved settings
            self:Print("Saved settings:")
            local ac = self.db.profile.assistedCombat
            print("  Scale:", ac.scale)
            print("  Icon Size:", ac.iconSize)
            print("  Position:", ac.position.point, ac.position.x, ac.position.y)
            print("  TankAssistDB exists:", TankAssistDB ~= nil)

        elseif subCmd == "secondary" or subCmd == "aoe" then
            -- Debug secondary/AoE spell selection
            self:Print("Secondary spell diagnostic:")

            local specModule = self.activeSpecModule
            if not specModule then
                print("  No active spec module!")
                return
            end

            print("  Spec:", specModule.specName or "Unknown")
            print("  IsPlayerSpell API exists:", IsPlayerSpell ~= nil)

            -- Check AoE spells with all availability methods
            if specModule.aoeSpells then
                print("  AoE spell candidates:")
                for i, aoeData in ipairs(specModule.aoeSpells) do
                    local spellId = aoeData.spellId
                    local spellInfo = C_Spell.GetSpellInfo(spellId)
                    local spellName = spellInfo and spellInfo.name or "Unknown"

                    -- Test all availability methods
                    local isKnown = IsSpellKnown(spellId)
                    local isPlayerSpell = IsPlayerSpell and IsPlayerSpell(spellId)
                    local cdInfo = C_Spell.GetSpellCooldown(spellId)
                    local hasCDInfo = cdInfo and cdInfo.startTime ~= nil
                    local usable, noMana = C_Spell.IsSpellUsable(spellId)

                    local cdData = TA.SecretValues:GetCooldownInfo(spellId)
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

            -- Check what GetBestAoESpell returns
            if specModule.GetBestAoESpell then
                local bestAoE = specModule:GetBestAoESpell()
                local spellInfo = bestAoE and C_Spell.GetSpellInfo(bestAoE)
                print("  GetBestAoESpell result:", spellInfo and spellInfo.name or "nil", "(ID:", bestAoE or "nil", ")")
            end

            -- Check what GetSecondarySpell returns
            if specModule.GetSecondarySpell then
                local spell, spellType, priority = specModule:GetSecondarySpell()
                local spellInfo = spell and C_Spell.GetSpellInfo(spell)
                print("  GetSecondarySpell result:", spellInfo and spellInfo.name or "nil", "Type:", spellType, "Priority:", priority)
            end

            -- Show CanCastSpell results (the unified check)
            print("  CanCastSpell results (unified cooldown + resource check):")
            if specModule.aoeSpells then
                for i, aoeData in ipairs(specModule.aoeSpells) do
                    local spellId = aoeData.spellId
                    local spellInfo = C_Spell.GetSpellInfo(spellId)
                    local spellName = spellInfo and spellInfo.name or "Unknown"
                    local canCast, reason = TA.SecretValues:CanCastSpell(spellId)
                    print(string.format("    %s: canCast=%s, reason=%s",
                        spellName, tostring(canCast), tostring(reason)))
                end
            end

            -- Also check Purifying Brew specifically (charge-based)
            local pbId = TA.Constants.BREWMASTER and TA.Constants.BREWMASTER.SPELLS.PURIFYING_BREW
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
                local canCast, reason = TA.SecretValues:CanCastSpell(pbId)
                print(string.format("    CanCastSpell: %s, reason: %s", tostring(canCast), tostring(reason)))
            end
        else
            local enabled = subCmd == "on" or subCmd == "true" or subCmd == "1"
            TA.Utils:SetDebug(enabled)
            TA.SecretValues:SetDebug(enabled)
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

-- Helper to count table entries
function Addon:CountTable(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

function Addon:PrintHelp()
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

function Addon:RunTestMode()
    self:Print("Running test mode...")
    
    -- Show current spec info
    local specId = TA.Utils:GetCurrentSpec()
    print("  Current spec:", TA.Utils:GetSpecName(specId))
    print("  Is tank:", TA.Utils:IsTankSpec(specId))
    
    -- Test secret values
    print("  Can access secrets:", TA.SecretValues:CanAccessSecrets())
    print("  In M+:", TA.SecretValues:InMythicPlus())
    
    -- Test buff tracking
    if self.activeSpecModule and self.activeSpecModule.buffsToTrack then
        print("  Tracked buffs:")
        for _, buffData in ipairs(self.activeSpecModule.buffsToTrack) do
            local info = TA.SecretValues:GetBuffInfo("player", buffData.spellId)
            print("    -", buffData.name, "exists:", info.exists, "secret:", info.isSecret)
        end
    end
end

-- =============================================================================
-- INITIALIZATION TRIGGER
-- =============================================================================

-- Register for events to initialize at the right time
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ADDON_LOADED")
loadFrame:RegisterEvent("PLAYER_LOGIN")
loadFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        -- Saved variables are now loaded - initialize the addon
        if Addon.OnInitialize then
            Addon:OnInitialize()
        end
    elseif event == "PLAYER_LOGIN" then
        -- Player is in game, enable addon
        if Addon.OnEnable then
            Addon:OnEnable()
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- =============================================================================
-- GLOBAL REFERENCE
-- Expose addon for slash commands and macros
-- =============================================================================
TankAssist = TA
