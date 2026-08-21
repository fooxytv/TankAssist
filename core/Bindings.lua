local ADDON_NAME, TankAssist = ...

-- Handler for Bindings.xml, which the client loads out of the addon folder by
-- itself -- it is never listed in the .toc. The binding calls this function by
-- name, so it has to be a global.
--
-- BINDING_HEADER_* and BINDING_NAME_* are what Blizzard's Key Bindings panel
-- shows for the section and the row. Without them the panel lists the raw
-- binding name, TANKASSIST_TARGETMARKER_MENU.

BINDING_HEADER_TANKASSIST = "TankAssist"
BINDING_NAME_TANKASSIST_TARGETMARKER_MENU = "Target marker menu"

-- Skull first: it is the mark a tank reaches for most, so it sits nearest the
-- cursor when the menu opens.
local MARKERS = {
    { index = 8, label = "Skull" },
    { index = 7, label = "Cross" },
    { index = 6, label = "Square" },
    { index = 5, label = "Moon" },
    { index = 4, label = "Triangle" },
    { index = 3, label = "Diamond" },
    { index = 2, label = "Circle" },
    { index = 1, label = "Star" },
    { index = 0, label = "Clear" },
}

-- A long string keeps the texture path free of backslash escaping.
local ICON_TEXTURE = [[|TInterface\TargetingFrame\UI-RaidTargetingIcon_%d:16|t ]]

function TankAssist_OpenTargetMarkerMenu()
    -- Nothing to mark, and a menu with no subject is worse than no menu.
    if not UnitExists("target") then
        return
    end

    -- MenuUtil replaced the old dropdown API in 11.0. Guarded rather than
    -- assumed, so a missing menu system degrades to doing nothing instead of
    -- erroring out of a keypress.
    if not MenuUtil or not MenuUtil.CreateContextMenu then
        return
    end

    MenuUtil.CreateContextMenu(UIParent, function(_, rootDescription)
        rootDescription:CreateTitle(UnitName("target") or "Target")

        for _, marker in ipairs(MARKERS) do
            local label = marker.label
            if marker.index > 0 then
                label = ICON_TEXTURE:format(marker.index) .. label
            end

            rootDescription:CreateButton(label, function()
                SetRaidTarget("target", marker.index)
            end)
        end
    end)
end
