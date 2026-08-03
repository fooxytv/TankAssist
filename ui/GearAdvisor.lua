local ADDON_NAME, TankAssist = ...

TankAssist.GearAdvisor = {}
local ga = TankAssist.GearAdvisor

local ACCENT    = { 0, 0.75, 0.95, 1 }
local DIM       = { 0.62, 0.62, 0.65, 1 }
local BIS_COLOR = { 1, 0.82, 0, 1 }

-- Prominent colour for the verdict header line in tooltips.
local VERDICT_HEADER_COLOR = {
    BIS       = { 1.00, 0.55, 0.00 }, -- orange-gold
    UPGRADE   = { 1.00, 0.90, 0.15 }, -- yellow
    SIDEGRADE = { 0.75, 0.75, 0.75 },
    DOWNGRADE = { 0.95, 0.35, 0.35 },
    OFFSPEC   = { 0.60, 0.60, 0.60 },
    UNKNOWN   = { 0.60, 0.60, 0.60 },
}

-- Coloured "+N" / "-N" string for embedding in a tooltip line.
local function deltaStr(d)
    local c = d > 0 and "ff40d040" or (d < 0 and "ffe85050" or "ffaaaaaa")
    return string.format("|c%s%+d|r", c, d)
end

local STAT_DISPLAY = {
    stamina = "Stamina", strength = "Strength", agility = "Agility", intellect = "Intellect",
    crit = "Critical Strike", haste = "Haste", mastery = "Mastery", versatility = "Versatility",
    avoidance = "Avoidance", leech = "Leech", speed = "Speed",
}

local function round(n)
    if n >= 0 then return math.floor(n + 0.5) end
    return math.ceil(n - 0.5)
end

local PLATE_SPECS   = { [73] = true, [66] = true, [250] = true }
local LEATHER_SPECS = { [104] = true, [268] = true, [581] = true }

-- Short spec name (without the class word) + class file token for class colour.
local SPEC_INFO = {
    [250] = { short = "Blood",      class = "DEATHKNIGHT" },
    [268] = { short = "Brewmaster", class = "MONK" },
    [73]  = { short = "Protection", class = "WARRIOR" },
    [66]  = { short = "Protection", class = "PALADIN" },
    [581] = { short = "Vengeance",  class = "DEMONHUNTER" },
    [104] = { short = "Guardian",   class = "DRUID" },
}

local function coloredSpecName(specId, fallback)
    local info = SPEC_INFO[specId]
    if not info then return fallback end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.class]
    if c and c.colorStr then
        return "|c" .. c.colorStr .. info.short .. "|r"
    elseif c then
        return string.format("|cff%02x%02x%02x%s|r",
            math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5), info.short)
    end
    return info.short
end

-- ============================================================================
-- API wrappers (prefer C_Item namespace, fall back to globals)
-- ============================================================================
local function getInfoInstant(link)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(link) end
    return GetItemInfoInstant(link)
end

local function getItemStats(link)
    if C_Item and C_Item.GetItemStats then return C_Item.GetItemStats(link) end
    if GetItemStats then return GetItemStats(link) end
    return nil
end

local function getItemLevel(link)
    if C_Item and C_Item.GetDetailedItemLevelInfo then return C_Item.GetDetailedItemLevelInfo(link) end
    if GetDetailedItemLevelInfo then return GetDetailedItemLevelInfo(link) end
    return nil
end

-- ============================================================================
-- Settings / profiles
-- ============================================================================
function ga:GetSettings()
    if TankAssist.Addon and TankAssist.Addon.db then
        return TankAssist.Addon.db.profile.gearAdvisor
    end
    return nil
end

function ga:GetActiveProfile()
    local s = self:GetSettings()
    local specId = TankAssist.Utils:GetCurrentSpec()
    if not s or not specId then return nil end
    return s.profiles[tostring(specId)]
end

function ga:GetRawImport(specId)
    local s = self:GetSettings()
    if not s then return "" end
    local p = s.profiles[tostring(specId)]
    return (p and p.raw) or ""
end

local function formatResult(profile, errors)
    local warnings = {}
    local hardError = nil
    for _, e in ipairs(errors) do
        if e.level == "error" then
            hardError = hardError or e.msg
        else
            warnings[#warnings + 1] = (e.line and ("line " .. e.line .. ": ") or "") .. e.msg
        end
    end
    return warnings, hardError
end

function ga:ImportForSpec(specId, text)
    local profile, errors = TankAssist.GearData:Parse(text)
    local warnings, hardError = formatResult(profile, errors)

    if hardError then
        return false, hardError .. (#warnings > 0 and (" (+" .. #warnings .. " warnings)") or ""), "error"
    end

    local nW = TankAssist.GearData:CountWeights(profile)
    local nB = TankAssist.GearData:CountBis(profile)
    local msg = string.format("Imported: %d weights, %d BIS items", nW, nB)
    local level = "ok"
    if #warnings > 0 then
        msg = msg .. string.format("  (%d warnings - /ta gear for detail)", #warnings)
        level = "warn"
    end

    local s = self:GetSettings()
    s.profiles[tostring(specId)] = {
        raw = text,
        weights = profile.weights,
        bis = profile.bis,
        declaredSpec = profile.declaredSpec,
        parsedAt = time(),
        status = msg,
        statusLevel = level,
        warnings = warnings,
    }
    return true, msg, level
end

function ga:ClearForSpec(specId)
    local s = self:GetSettings()
    if s then s.profiles[tostring(specId)] = nil end
end

-- ============================================================================
-- Scoring
-- ============================================================================
function ga:ScoreItem(link, weights)
    if not link then return nil end
    local stats = getItemStats(link)
    if not stats then return nil end
    local SV = TankAssist.SecretValues
    local total, any = 0, false
    for statKey, value in pairs(stats) do
        if SV:IsSecret(value) then
            return nil -- secret/tainted -> caller falls back to ilvl
        end
        local v = SV:SafeNumber(value, nil)
        if v then
            local internal = TankAssist.GearData:CanonicalStat(statKey)
            local w = internal and weights[internal]
            if w then
                total = total + v * w
                any = true
            end
        end
    end
    if not any then return nil end
    return total
end

function ga:GetEquippedComparison(equipLoc, weights)
    local slots = TankAssist.GearData.INVTYPE_TO_SLOTS[equipLoc]
    if not slots then return nil end
    local SV = TankAssist.SecretValues
    local worst
    for _, slotID in ipairs(slots) do
        local link = GetInventoryItemLink("player", slotID)
        if not link then
            return { link = nil, score = 0, ilvl = 0, emptySlot = true }
        end
        local score = self:ScoreItem(link, weights) or 0
        local ilvl = SV:SafeNumber(getItemLevel(link), 0) or 0
        if not worst or score < worst.score then
            worst = { link = link, score = score, ilvl = ilvl }
        end
    end
    return worst
end

function ga:ClassCanUse(specId, classID, subClassID, equipLoc)
    if classID ~= 4 then return true end -- not armor (weapon/jewelry handled elsewhere)
    if subClassID == 4 then
        return PLATE_SPECS[specId] == true
    elseif subClassID == 3 then
        return false -- mail: no tank in this set wears mail
    elseif subClassID == 2 then
        return LEATHER_SPECS[specId] == true
    elseif subClassID == 1 then
        -- cloth: cloaks are cloth but everyone wears them; block cloth body armor
        return equipLoc == "INVTYPE_CLOAK"
    end
    return true -- generic (neck/finger/trinket) etc.
end

-- Returns a list of { internal, name, delta } for every weighted stat that
-- differs between candidate and equipped, sorted by weighted impact.
local function buildStatDeltas(candLink, cmpLink, weights)
    local cs = getItemStats(candLink)
    if not cs then return nil end
    local ms = cmpLink and getItemStats(cmpLink) or nil
    local SV = TankAssist.SecretValues
    local deltas = {}

    local function accum(stats, sign)
        if not stats then return end
        for k, v in pairs(stats) do
            if not SV:IsSecret(v) then
                local nv = SV:SafeNumber(v, nil)
                local internal = nv and TankAssist.GearData:CanonicalStat(k)
                if internal and weights[internal] then
                    deltas[internal] = (deltas[internal] or 0) + sign * nv
                end
            end
        end
    end
    accum(cs, 1)
    accum(ms, -1)

    local list = {}
    for internal, d in pairs(deltas) do
        if math.abs(d) >= 1 then
            list[#list + 1] = {
                internal = internal,
                name = STAT_DISPLAY[internal] or internal,
                delta = round(d),
                impact = math.abs(d) * (weights[internal] or 0),
            }
        end
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a.impact > b.impact end)
    return list
end

local function statDeltasToString(list)
    if not list then return nil end
    local parts = {}
    for i = 1, math.min(4, #list) do
        parts[#parts + 1] = string.format("%s %+d", list[i].name, list[i].delta)
    end
    return table.concat(parts, ", ")
end

local function classifyByIlvl(candIlvl, cmp, ilvlDelta, tainted)
    if not candIlvl or not cmp or not cmp.ilvl then
        return {
            tier = "UNKNOWN", label = "Can't compare", color = DIM, glow = false, tainted = tainted,
            reasons = { tainted and "Item stats unavailable (in combat?)" or "Not enough item data" },
        }
    end
    local tier, label, color
    if ilvlDelta > 0 then tier, label, color = "UPGRADE", "Upgrade", ACCENT
    elseif ilvlDelta < 0 then tier, label, color = "DOWNGRADE", "Downgrade", DIM
    else tier, label, color = "SIDEGRADE", "Sidegrade", DIM end
    return {
        tier = tier, label = label, color = color, glow = (tier == "UPGRADE"),
        ilvlDelta = ilvlDelta, ilvlCurrent = cmp.ilvl, ilvlNew = candIlvl, tainted = tainted,
        reasons = { tainted and "stat scoring unavailable - item level only" or "comparing item level only" },
    }
end

-- The single brain used by the tooltip and loot surfaces.
function ga:GetVerdict(itemLink)
    local s = self:GetSettings()
    if not s or not s.enabled or not itemLink then return nil end

    local itemID, _, _, equipLoc, _, classID, subClassID = getInfoInstant(itemLink)
    if not itemID then return nil end

    local slots = TankAssist.GearData.INVTYPE_TO_SLOTS[equipLoc]
    if not slots then return nil end -- not comparable gear

    local specId = TankAssist.Utils:GetCurrentSpec()
    local specName = TankAssist.Utils:GetSpecName(specId)

    if not self:ClassCanUse(specId, classID, subClassID, equipLoc) then
        return { tier = "OFFSPEC", label = "Wrong armor type", color = DIM, glow = false,
                 specName = specName, reasons = { "Not usable by " .. specName } }
    end

    local profile = self:GetActiveProfile()
    local weights = (profile and profile.weights) or TankAssist.GearData:GetDefaultWeights(specId)

    -- LAYER 2: explicit BIS override
    if profile and profile.bis then
        local bisKey = TankAssist.GearData:BisKeyForEquipLoc(equipLoc)
        if bisKey and profile.bis[bisKey] and profile.bis[bisKey][itemID] then
            return {
                tier = "BIS", label = "Best in Slot", color = BIS_COLOR, glow = true,
                specName = specName, reasons = { "On your BIS list" },
            }
        end
    end

    local SV = TankAssist.SecretValues
    local candIlvl = SV:SafeNumber(getItemLevel(itemLink), nil)
    local cmp = self:GetEquippedComparison(equipLoc, weights)

    if cmp and cmp.emptySlot then
        return {
            tier = "UPGRADE", label = "Upgrade", color = ACCENT, glow = true,
            specName = specName, ilvlNew = candIlvl, reasons = { "Nothing equipped in this slot" },
        }
    end

    local candScore = self:ScoreItem(itemLink, weights)
    local cmpScore = cmp and cmp.link and self:ScoreItem(cmp.link, weights) or nil
    local ilvlDelta = (candIlvl and cmp and cmp.ilvl) and (candIlvl - cmp.ilvl) or nil

    -- LAYER 1 fallback: pure item level when stats are unreadable
    if candScore == nil or cmpScore == nil then
        local v = classifyByIlvl(candIlvl, cmp, ilvlDelta, candScore == nil)
        v.specName = specName
        return v
    end

    -- LAYER 3: weighted stat score
    local scoreDelta = candScore - cmpScore
    local eps = math.max(1, cmpScore * 0.005)
    local tier, label, color
    if scoreDelta > eps then tier, label, color = "UPGRADE", "Upgrade", ACCENT
    elseif scoreDelta < -eps then tier, label, color = "DOWNGRADE", "Downgrade", DIM
    elseif ilvlDelta and ilvlDelta > 0 then tier, label, color = "UPGRADE", "Upgrade", ACCENT
    elseif ilvlDelta and ilvlDelta < 0 then tier, label, color = "DOWNGRADE", "Downgrade", DIM
    else tier, label, color = "SIDEGRADE", "Sidegrade", DIM end

    return {
        tier = tier, label = label, color = color, glow = (tier == "UPGRADE"),
        specName = specName,
        ilvlDelta = ilvlDelta, ilvlCurrent = cmp.ilvl, ilvlNew = candIlvl, scoreDelta = scoreDelta,
        statDeltas = buildStatDeltas(itemLink, cmp.link, weights),
    }
end

function ga:VerdictRank(verdict)
    if not verdict then return 0 end
    if verdict.tier == "BIS" then return 3 end
    if verdict.tier == "UPGRADE" then return 2 end
    if verdict.tier == "SIDEGRADE" then return 1 end
    return 0
end

-- ============================================================================
-- Tooltip annotation
-- ============================================================================
function ga:AnnotateTooltip(tooltip, itemID)
    local s = self:GetSettings()
    if not s or not s.enabled or not s.annotateTooltips then return end
    if not tooltip or not tooltip.AddLine then return end

    local link
    if tooltip.GetItem then
        local _, l = tooltip:GetItem()
        link = l
    end
    if not link and itemID then link = "item:" .. itemID end
    if not link then return end

    local ok, v = pcall(function() return self:GetVerdict(link) end)
    if not ok or not v then return end

    tooltip:AddLine(" ")

    -- Header: TankAssist: <Spec> (class-coloured)
    local header = "|cFF00BFFFTankAssist:|r"
    local specId = TankAssist.Utils:GetCurrentSpec()
    local nameStr = coloredSpecName(specId, v.specName)
    if nameStr then header = header .. " " .. nameStr end
    tooltip:AddLine(header)

    -- Verdict (prominent, coloured)
    local hc = VERDICT_HEADER_COLOR[v.tier] or { 1, 1, 1 }
    tooltip:AddLine(v.label or "", hc[1], hc[2], hc[3])

    -- Item level line (white)
    if v.ilvlCurrent and v.ilvlNew then
        tooltip:AddLine(string.format("Item Level: %d > %d  %s",
            v.ilvlCurrent, v.ilvlNew, deltaStr(v.ilvlNew - v.ilvlCurrent)), 1, 1, 1)
    elseif v.ilvlNew then
        tooltip:AddLine(string.format("Item Level: %d", v.ilvlNew), 1, 1, 1)
    end

    -- Stat differences, one per line
    if v.statDeltas then
        for _, st in ipairs(v.statDeltas) do
            tooltip:AddLine(st.name .. "  " .. deltaStr(st.delta), 0.85, 0.85, 0.85)
        end
    end

    -- Explanatory notes (BIS / empty slot / off-spec / ilvl-only)
    if v.reasons then
        for _, r in ipairs(v.reasons) do
            tooltip:AddLine(r, 0.55, 0.55, 0.55)
        end
    end
end

function ga:HookTooltip()
    if self.tooltipHooked then return end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        self.tooltipHooked = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            ga:AnnotateTooltip(tt, data and data.id)
        end)
    end
end

-- ============================================================================
-- Glow helpers (event-driven; never run from the combat ticker)
-- A bright additive border drawn ON TOP of the target frame, so it stays
-- visible over Blizzard art (unlike a backdrop placed behind the frame).
-- ============================================================================
-- Next strata up, so the ring sits above the frame's own item art.
local STRATA_BUMP = {
    BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG",
    DIALOG = "FULLSCREEN", FULLSCREEN = "FULLSCREEN_DIALOG",
}

local function showGlow(frame, color)
    if not frame.taGlow then
        local g = CreateFrame("Frame", nil, frame)
        -- A higher frame level alone isn't reliable across Blizzard's item
        -- frames, so also nudge the strata up one band so the ring stays
        -- visible over the displayed item.
        local baseStrata = (frame.GetFrameStrata and frame:GetFrameStrata()) or "MEDIUM"
        g:SetFrameStrata(STRATA_BUMP[baseStrata] or baseStrata)
        g:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
        g:SetPoint("TOPLEFT", -10, 10)
        g:SetPoint("BOTTOMRIGHT", 10, -10)
        local tex = g:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        tex:SetBlendMode("ADD")
        g.tex = tex
        frame.taGlow = g
    end
    frame.taGlow.tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    frame.taGlow:Show()
end

local function hideGlow(frame)
    if frame and frame.taGlow then frame.taGlow:Hide() end
end

function ga:ClearLootGlows()
    if not self.lootGlowed then return end
    for _, frame in ipairs(self.lootGlowed) do
        pcall(function() hideGlow(frame) end)
    end
    wipe(self.lootGlowed)
end

function ga:ClearAllGlows()
    self:ClearLootGlows()
end

function ga:GetGlowColor()
    local s = self:GetSettings()
    return (s and s.glowColor) or ACCENT
end

function ga:RefreshLootGlow()
    local s = self:GetSettings()
    if not s or not s.enabled or not s.glowLoot then return end
    if InCombatLockdown() then return end -- avoid frame taint during combat rolls
    pcall(function() self:_DoLootGlow() end)
end

function ga:_DoLootGlow()
    self:ClearLootGlows()
    local glowColor = self:GetGlowColor()
    local count = NUM_GROUP_LOOT_FRAMES or 4
    for i = 1, count do
        local frame = _G["GroupLootFrame" .. i]
        if frame and frame:IsShown() and frame.rollID then
            local link = GetLootRollItemLink and GetLootRollItemLink(frame.rollID)
            if link and self:VerdictRank(self:GetVerdict(link)) >= 2 then
                pcall(function() showGlow(frame, glowColor) end)
                self.lootGlowed[#self.lootGlowed + 1] = frame
            end
        end
    end
end

-- ============================================================================
-- Events
-- ============================================================================
local function safeRegister(frame, event)
    pcall(function() frame:RegisterEvent(event) end)
end

function ga:RegisterEvents()
    if self.eventFrame then return end
    local f = CreateFrame("Frame")
    self.eventFrame = f
    f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    safeRegister(f, "START_LOOT_ROLL")
    safeRegister(f, "CANCEL_LOOT_ROLL")

    f:SetScript("OnEvent", function(_, event)
        if event == "START_LOOT_ROLL" then
            C_Timer.After(0.05, function() ga:RefreshLootGlow() end)
        elseif event == "CANCEL_LOOT_ROLL" then
            ga:ClearLootGlows()
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            ga:ClearAllGlows()
        end
    end)
end

-- ============================================================================
-- Debug
-- ============================================================================
function ga:DebugDump(arg)
    local specId = TankAssist.Utils:GetCurrentSpec()
    local specName = TankAssist.Utils:GetSpecName(specId)
    local s = self:GetSettings()
    print("|cFF00BFFF[TankAssist Gear]|r Spec:", specName, "(" .. tostring(specId) .. ")",
        (s and s.enabled) and "" or "|cFFFF8080[disabled]|r")

    local profile = self:GetActiveProfile()
    if not profile then
        print("  No imported profile. Using default weights + item-level baseline.")
        local w = TankAssist.GearData:GetDefaultWeights(specId)
        local parts = {}
        for k, v in pairs(w) do parts[#parts + 1] = (STAT_DISPLAY[k] or k) .. "=" .. v end
        print("  Default weights:", table.concat(parts, " "))
    else
        print("  " .. (profile.status or "imported"))
        if profile.weights then
            local parts = {}
            for k, v in pairs(profile.weights) do parts[#parts + 1] = (STAT_DISPLAY[k] or k) .. "=" .. v end
            print("  Weights:", table.concat(parts, " "))
        else
            print("  Weights: (none - using defaults)")
        end
        if profile.bis then
            for slot, ids in pairs(profile.bis) do
                local idList = {}
                for id in pairs(ids) do idList[#idList + 1] = id end
                print("  BIS " .. slot .. ":", table.concat(idList, ", "))
            end
        else
            print("  BIS: (none)")
        end
        if profile.warnings and #profile.warnings > 0 then
            print("  Warnings:")
            for _, w in ipairs(profile.warnings) do print("    - " .. w) end
        end
    end

    if arg then
        local link = tonumber(arg) and ("item:" .. arg) or arg
        local v = self:GetVerdict(link)
        if v then
            print("  Verdict for", link .. ":", v.tier, "-", v.label)
            if v.ilvlCurrent and v.ilvlNew then
                print(string.format("    ilvl %d -> %d (%+d)", v.ilvlCurrent, v.ilvlNew, v.ilvlNew - v.ilvlCurrent))
            end
            local sb = statDeltasToString(v.statDeltas)
            if sb then print("    " .. sb) end
            for _, r in ipairs(v.reasons or {}) do print("    " .. r) end
        else
            print("  No verdict for", link, "(not comparable gear or not cached)")
        end
    end
end

-- ============================================================================
-- Lifecycle
-- ============================================================================
function ga:Create()
    if self.created then return end
    self.created = true
    self.lootGlowed = {}
    self:HookTooltip()
    self:RegisterEvents()
end

local function Initialize()
    if TankAssist.Addon then
        ga:Create()
        TankAssist.Addon.gearAdvisor = ga
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.8, Initialize)
end)
