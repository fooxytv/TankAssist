local ADDON_NAME, TankAssist = ...

TankAssist.Consumables = {}
local consumables = TankAssist.Consumables

consumables.Categories = {
    {
        key = "food",
        displayName = "Food",
        fallbackIcon = "Interface\\Icons\\inv_misc_food_legion_lavishsuramarfeast",
        buffIds = {
            433886,
            225597,
        },
        buffNamePatterns = {
            "Well Fed",
        },
    },
    {
        key = "flask",
        displayName = "Flask",
        fallbackIcon = "Interface\\Icons\\trade_alchemy_dpotion_a15",
        buffIds = {},
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
        buffIds = {},
        buffNamePatterns = {
            "Augment Rune",
            "Augmentation",
        },
    },
}

consumables.Recommendations = {
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
