local ADDON_NAME, TankAssist = ...

TankAssist.Consumables = {}
local consumables = TankAssist.Consumables

-- Category-level consumable check data.
-- We deliberately do NOT pin to exact "best" items — we just verify the
-- category aura is present so the check survives patch-to-patch item changes.
-- Detection works two ways:
--   1. buffIds: known spell IDs (fast path, exact match)
--   2. buffNamePatterns: case-sensitive name substrings (fallback for new items)
-- If either matches, the category counts as covered.

consumables.Categories = {
    {
        key = "food",
        displayName = "Food",
        fallbackIcon = "Interface\\Icons\\inv_misc_food_legion_lavishsuramarfeast",
        buffIds = {
            433886, -- Well Fed (TWW/Midnight generic)
            225597, -- Well Fed (legacy generic, kept as safety net)
        },
        buffNamePatterns = {
            "Well Fed",
        },
    },
    {
        key = "flask",
        displayName = "Flask",
        fallbackIcon = "Interface\\Icons\\trade_alchemy_dpotion_a15",
        buffIds = {
            -- Populated as new flask/phial IDs are confirmed. The name
            -- patterns below cover the common cases until then.
        },
        buffNamePatterns = {
            "Flask of",
            "Phial of",
        },
    },
    {
        key = "weaponEnchant",
        displayName = "Oil",
        fallbackIcon = "Interface\\Icons\\inv_alchemy_oils_05",
        checkType = "weaponEnchant",
    },
    {
        key = "augmentRune",
        displayName = "Rune",
        fallbackIcon = "Interface\\Icons\\inv_misc_enchantedscroll",
        buffIds = {
            -- Specific rune IDs added as confirmed. Name pattern below
            -- catches every named Augment Rune.
        },
        buffNamePatterns = {
            "Augment Rune",
            "Augmentation",
        },
    },
}

-- Per-spec recommendation hints, surfaced in the tooltip only.
-- Kept lightweight on purpose: this is a "what should I be using"
-- reference, not a hard requirement we'd alert on.
consumables.Recommendations = {
    -- Brewmaster Monk (specId 268)
    [268] = {
        food = "Silvermoon Parade / Harandar Celebration, or Royal Roast for pure Agility",
        flask = "Flask of the Shattered Sun (Crit) or Flask of the Magisters (Mastery)",
        weaponEnchant = "Thalassian Phoenix Oil",
        augmentRune = "Void-Touched Augment Rune",
    },
}

function consumables:GetCategories()
    return self.Categories
end

function consumables:GetRecommendations(specId)
    return self.Recommendations[specId]
end
