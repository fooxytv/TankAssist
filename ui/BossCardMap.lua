-- Boss Card map -- see https://github.com/fooxytv/TankAssist/issues/38
--
-- Renders the real dungeon floor map behind a tank card, with the boss where
-- the game says the boss is. A room you recognise beats an abstract grid: you
-- can see the pillar you are meant to drag it behind.
--
-- The Adventure Guide does not draw a map itself -- its map button just calls
-- OpenWorldMap(dungeonAreaMapID) and hands the job to the World Map. So the
-- tiling here is the same thing the World Map's detail layers do, reproduced
-- at card size. Mechanics taken from Blizzard's own UI source (12.1.0.69404,
-- Blizzard_MapCanvasDetailLayer.lua and EncounterJournalDataProvider.lua):
--
--   * C_Map.GetMapArtLayers(mapID)[n] gives layerWidth/layerHeight and
--     tileWidth/tileHeight; the tile grid is ceil(layer/tile) each way.
--   * C_Map.GetMapArtLayerTextures(mapID, n) returns those tiles in row-major
--     order, indexed (row - 1) * cols + col.
--   * C_EncounterJournal.GetEncountersOnMap(mapID) returns entries carrying
--     .encounterID, .mapX and .mapY -- normalised 0..1 across the map.
--
-- With a map attached, everything on the card is stored in *map* coordinates
-- rather than canvas coordinates, so zooming and panning move the tokens with
-- the room instead of sliding them across it.

local ADDON_NAME, TankAssist = ...

TankAssist.BossCardMap = {}
local cardmap = TankAssist.BossCardMap

local MAX_TILES = 64      -- a floor plan is a handful of tiles; this is a guard
local LAYER_INDEX = 1     -- layer 1 is the overview; higher layers are zoom detail

----------------------------------------------------------------------------
-- Resolution
----------------------------------------------------------------------------

-- A dungeon is usually several floors, each its own uiMapID, and only one of
-- them has our boss on it. Rather than guess, ask each candidate which
-- encounters it holds and take the one that answers.
function cardmap:FindFloorFor(encounterID, dungeonAreaMapID)
    if not encounterID or not dungeonAreaMapID then return nil end
    if not C_EncounterJournal or not C_EncounterJournal.GetEncountersOnMap then return nil end

    local candidates = { dungeonAreaMapID }

    if C_Map and C_Map.GetMapChildrenInfo then
        local ok, children = pcall(C_Map.GetMapChildrenInfo, dungeonAreaMapID, nil, true)
        if ok and type(children) == "table" then
            for _, child in ipairs(children) do
                if child.mapID then candidates[#candidates + 1] = child.mapID end
            end
        end
    end

    for _, mapID in ipairs(candidates) do
        local ok, encounters = pcall(C_EncounterJournal.GetEncountersOnMap, mapID)
        if ok and type(encounters) == "table" then
            for _, entry in ipairs(encounters) do
                if entry.encounterID == encounterID then
                    return mapID, entry.mapX, entry.mapY
                end
            end
        end
    end

    return nil
end

function cardmap:GetLayerInfo(mapID)
    if not C_Map or not C_Map.GetMapArtLayers then return nil end
    local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
    if not ok or type(layers) ~= "table" then return nil end
    return layers[LAYER_INDEX]
end

----------------------------------------------------------------------------
-- Tiles
----------------------------------------------------------------------------

-- The tile frame is built at the map's true pixel size and then scaled, which
-- is how the World Map does it too. Scaling one frame keeps every tile and
-- every token in lockstep, so zoom cannot pull the diagram apart.
function cardmap:Build(canvas)
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", nil, canvas)
    frame:SetPoint("CENTER")
    frame:SetSize(256, 256)
    frame.tiles = {}
    frame:Hide()

    self.frame = frame
    return frame
end

function cardmap:SetMap(canvas, mapID)
    local frame = self:Build(canvas)

    if self.mapID == mapID and self.loaded then return true end

    for _, tile in ipairs(frame.tiles) do tile:Hide() end

    self.mapID = mapID
    self.loaded = false
    self.layerWidth, self.layerHeight = nil, nil

    local layerInfo = self:GetLayerInfo(mapID)
    if not layerInfo or not layerInfo.layerWidth or layerInfo.layerWidth <= 0 then
        frame:Hide()
        return false
    end

    local ok, textures = pcall(C_Map.GetMapArtLayerTextures, mapID, LAYER_INDEX)
    if not ok or type(textures) ~= "table" or #textures == 0 then
        frame:Hide()
        return false
    end

    local tileWidth = layerInfo.tileWidth or 256
    local tileHeight = layerInfo.tileHeight or 256
    local cols = math.ceil(layerInfo.layerWidth / tileWidth)
    local rows = math.ceil(layerInfo.layerHeight / tileHeight)

    if cols * rows > MAX_TILES then
        frame:Hide()
        return false
    end

    frame:SetSize(layerInfo.layerWidth, layerInfo.layerHeight)

    local index = 0
    for row = 1, rows do
        for col = 1, cols do
            index = index + 1
            -- Row-major, exactly as Blizzard's detail layer indexes them.
            local textureIndex = (row - 1) * cols + col
            local tile = frame.tiles[index]
            if not tile then
                tile = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
                frame.tiles[index] = tile
            end
            tile:SetSize(tileWidth, tileHeight)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", frame, "TOPLEFT", (col - 1) * tileWidth, -(row - 1) * tileHeight)
            tile:SetTexture(textures[textureIndex], nil, nil, "TRILINEAR")
            tile:Show()
        end
    end
    for extra = index + 1, #frame.tiles do
        frame.tiles[extra]:Hide()
    end

    self.layerWidth = layerInfo.layerWidth
    self.layerHeight = layerInfo.layerHeight
    self.loaded = true
    frame:Show()
    return true
end

function cardmap:IsLoaded()
    return self.loaded and self.mapID ~= nil
end

----------------------------------------------------------------------------
-- View: what part of the map the card is looking at
--
-- `view` is { scale, focusX, focusY }: how zoomed in, and which map point sits
-- at the middle of the canvas. Stored on the card so a boss opens on the same
-- framing every time.
----------------------------------------------------------------------------

function cardmap:DefaultView(bossX, bossY)
    return {
        -- A whole dungeon floor at 1:1 is far too wide to read a pull from, so
        -- the default frames a room around the boss rather than the level.
        scale = 2.2,
        focusX = bossX or 0.5,
        focusY = bossY or 0.5,
    }
end

function cardmap:Apply(canvasSize, view)
    local frame = self.frame
    if not frame or not self:IsLoaded() then return end

    local scale = math.max(0.2, view.scale or 1)
    frame:SetScale(scale)

    -- SetScale multiplies the frame's own coordinate space, so the offset that
    -- puts the focus point at the canvas centre has to be expressed in that
    -- scaled space -- hence the division rather than a multiplication.
    local offsetX = (0.5 - (view.focusX or 0.5)) * self.layerWidth
    local offsetY = ((view.focusY or 0.5) - 0.5) * self.layerHeight

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", frame:GetParent(), "CENTER", offsetX, offsetY)
end

-- Map space (0..1 of the dungeon floor) -> canvas space (0..1 of the card).
function cardmap:MapToCanvas(mx, my, canvasSize, view)
    if not self:IsLoaded() or canvasSize == 0 then return mx, my end
    local scale = math.max(0.2, view.scale or 1)
    local x = 0.5 + (mx - (view.focusX or 0.5)) * self.layerWidth * scale / canvasSize
    local y = 0.5 + (my - (view.focusY or 0.5)) * self.layerHeight * scale / canvasSize
    return x, y
end

function cardmap:CanvasToMap(cx, cy, canvasSize, view)
    if not self:IsLoaded() or canvasSize == 0 then return cx, cy end
    local scale = math.max(0.2, view.scale or 1)
    local mx = (view.focusX or 0.5) + (cx - 0.5) * canvasSize / (self.layerWidth * scale)
    local my = (view.focusY or 0.5) + (cy - 0.5) * canvasSize / (self.layerHeight * scale)
    return mx, my
end

function cardmap:Hide()
    if self.frame then self.frame:Hide() end
    self.loaded = false
    self.mapID = nil
end

----------------------------------------------------------------------------
-- Boss portrait
--
-- The map pins use the creature's display ID through
-- SetPortraitTextureFromCreatureDisplayID, not the ability-style icon that
-- EJ_GetCreatureInfo also returns. That is why the Journal's pins look like the
-- actual boss; the icon is a flat placeholder by comparison.
----------------------------------------------------------------------------

function cardmap:ApplyBossPortrait(texture, encounterID)
    if not encounterID or not EJ_GetCreatureInfo then return false end

    local ok, _, _, _, displayInfo, iconImage = pcall(EJ_GetCreatureInfo, 1, encounterID)
    if not ok then return false end

    if displayInfo and SetPortraitTextureFromCreatureDisplayID then
        local applied = pcall(SetPortraitTextureFromCreatureDisplayID, texture, displayInfo)
        if applied then
            texture:SetTexCoord(0, 1, 0, 1)
            return true
        end
    end

    if iconImage then
        texture:SetTexture(iconImage)
        texture:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        return true
    end

    return false
end
