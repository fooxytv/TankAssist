-- TankAssist Icon Style
--
-- The look shared by every icon widget in the addon: how far the spell art is
-- cropped, whether the button is square or the squat "cropped" shape action-bar
-- skins use, whether a border is drawn, and which font its text is in.
--
-- This lives in one place because it is the same six settings on every widget,
-- and they were already duplicated once. A second copy is how the Assisted
-- Combat buttons and the external cooldowns end up subtly disagreeing about
-- what "5.5%" means.
--
-- Every function takes the widget's own settings table, so a widget owns its
-- values and this owns the behaviour.

local ADDON_NAME, TankAssist = ...

TankAssist.IconStyle = {}
local iconStyle = TankAssist.IconStyle

-- Matches the default of the action-bar skins this is meant to sit alongside;
-- EllesmereUI calls it Icon Zoom and ships 5.5.
local DEFAULT_ZOOM_PERCENT = 5.5

-- The skins' "cropped" button shape: full width, 80% height.
local CROPPED_HEIGHT_RATIO = 0.80

local SQUARE, CROPPED = "Square", "Cropped"

--- The fraction of the art trimmed off each edge.
function iconStyle:GetTrim(settings)
    local percent = settings and settings.iconZoomPercent
    if percent == nil then percent = DEFAULT_ZOOM_PERCENT end
    return percent / 100
end

function iconStyle:GetShape(settings)
    local shape = settings and settings.iconShape
    return shape == CROPPED and CROPPED or SQUARE
end

--- Button dimensions for an icon size, honouring the shape.
-- The art needs no special case: GetIconTexCoords derives the vertical trim
-- from the button's own aspect, so a cropped button crops rather than squashes.
function iconStyle:GetDimensions(settings, size)
    size = tonumber(size) or 36
    if self:GetShape(settings) == CROPPED then
        return size, math.floor(size * CROPPED_HEIGHT_RATIO + 0.5)
    end
    return size, size
end

--- Whether the border is drawn.
-- `default` differs by widget on purpose. The Assisted Combat buttons draw no
-- border because an action button does not; the external and alert icons use a
-- coloured one to say what kind of thing you are looking at, which is signal
-- rather than chrome, so theirs stays on unless turned off.
function iconStyle:ShowBorder(settings, default)
    local value = settings and settings.showBorder
    if value == nil then return default and true or false end
    return value == true
end

--- Show or hide a border built as { top =, bottom =, left =, right = }.
function iconStyle:ApplyBorder(border, show)
    if not border then return end
    for _, edge in pairs(border) do
        if edge and edge.SetShown then edge:SetShown(show and true or false) end
    end
end

function iconStyle:ApplyTexCoords(texture, settings, width, height)
    TankAssist.Utils:ApplyIconZoom(texture, self:GetTrim(settings), width, height)
end

--- Apply the widget's font at a base size, with the widget's size offset.
-- `baseSize` is the size the widget would have used before any of this existed,
-- so an untouched profile looks exactly as it did.
function iconStyle:ApplyFont(settings, fontString, baseSize)
    if not settings then settings = {} end
    local size = (tonumber(baseSize) or 11) + (settings.fontSizeOffset or 0)
    TankAssist.Media:SetFont(fontString, settings.fontFace, size, settings.fontFlag)
end

--- The Edit Mode entries for all of it, so a widget adds one line rather than
-- six blocks that drift apart.
--
-- opts.getSettings  required, returns the widget's settings table
-- opts.refresh      required, re-applies the look to existing icons
-- opts.resize       optional, called instead of refresh when the button
--                   geometry changes and the frame has to be laid out again
-- opts.borderDefault  default for Show Border (see ShowBorder)
-- opts.startOrder   first order value; entries step by 0.01 from it
function iconStyle:BuildSettings(opts)
    local lem = LibStub and LibStub("LibEQOLEditMode-1.0", true)
    if not lem then return {} end

    local getSettings = opts.getSettings
    local refresh = opts.refresh
    local resize = opts.resize or refresh
    local borderDefault = opts.borderDefault and true or false
    local order = opts.startOrder or 150

    local function nextOrder()
        order = order + 0.01
        return order
    end

    return {
        {
            -- Percent, matching what action-bar skins call Icon Zoom, so the
            -- number you already use there produces the same crop here.
            order = nextOrder(),
            name = "Icon Zoom %",
            kind = lem.SettingType.Slider,
            default = DEFAULT_ZOOM_PERCENT,
            minValue = 0,
            maxValue = 25,
            valueStep = 0.5,
            get = function()
                local percent = getSettings().iconZoomPercent
                if percent == nil then return DEFAULT_ZOOM_PERCENT end
                return percent
            end,
            set = function(_, value)
                getSettings().iconZoomPercent = math.floor(value * 2 + 0.5) / 2
                refresh()
            end,
        },
        {
            order = nextOrder(),
            name = "Icon Shape",
            kind = lem.SettingType.Dropdown,
            default = SQUARE,
            values = { { text = SQUARE }, { text = CROPPED } },
            get = function()
                return iconStyle:GetShape(getSettings())
            end,
            set = function(_, value)
                getSettings().iconShape = (value == CROPPED) and CROPPED or SQUARE
                -- Shape changes the button, not just the art, so the frame
                -- around it has to be laid out again.
                resize()
            end,
        },
        {
            order = nextOrder(),
            name = "Show Border",
            kind = lem.SettingType.Checkbox,
            default = borderDefault,
            get = function()
                return iconStyle:ShowBorder(getSettings(), borderDefault)
            end,
            set = function(_, value)
                getSettings().showBorder = value and true or false
                refresh()
            end,
        },
        {
            order = nextOrder(),
            name = "Font Face",
            kind = lem.SettingType.Dropdown,
            default = TankAssist.Media.DefaultFontName(),
            values = TankAssist.Media:FontDropdownValues(),
            get = function()
                return getSettings().fontFace or TankAssist.Media.DefaultFontName()
            end,
            set = function(_, value)
                getSettings().fontFace = value
                refresh()
            end,
        },
        {
            order = nextOrder(),
            name = "Font Style",
            kind = lem.SettingType.Dropdown,
            default = TankAssist.Media.DefaultFontFlagName(),
            values = TankAssist.Media:FontFlagDropdownValues(),
            get = function()
                return getSettings().fontFlag or TankAssist.Media.DefaultFontFlagName()
            end,
            set = function(_, value)
                getSettings().fontFlag = value
                refresh()
            end,
        },
        {
            order = nextOrder(),
            name = "Text Size Adjust",
            kind = lem.SettingType.Slider,
            default = 0,
            minValue = -4,
            maxValue = 8,
            valueStep = 1,
            get = function()
                return getSettings().fontSizeOffset or 0
            end,
            set = function(_, value)
                getSettings().fontSizeOffset = math.floor(value + 0.5)
                refresh()
            end,
        },
    }
end

--- The profile defaults a widget adopting this needs.
-- `borderDefault` is the widget's own answer to the chrome-or-signal question.
function iconStyle.Defaults(borderDefault)
    return {
        iconZoomPercent = DEFAULT_ZOOM_PERCENT,
        iconShape = SQUARE,
        showBorder = borderDefault and true or false,
        fontFace = "Friz Quadrata",
        fontFlag = "Outline",
        fontSizeOffset = 0,
    }
end
