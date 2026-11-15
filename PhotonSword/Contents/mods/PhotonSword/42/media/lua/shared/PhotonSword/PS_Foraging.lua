require "Foraging/forageSystem"
require "PhotonSword/PS_Core"

-- Loose crystals can be found in search mode, among the vanilla Stones category. Zone values are
-- roll weights within that category, per color: vanilla stones use 5 (common) down to 1 (Limestone),
-- so all eight colors together come to well under one Limestone. Snow buries them like stones.

local PS = PhotonSword

local WILD = 0.1
local TOWN = 0.05

local ZONES = {
    BirchForest = WILD,
    DeepForest = WILD,
    FarmLand = WILD,
    ForagingNav = WILD,
    Forest = WILD,
    OrganicForest = WILD,
    PHForest = WILD,
    PRForest = WILD,
    Vegitation = WILD,
    TownZone = TOWN,
    TrailerPark = TOWN,
}

for _, color in ipairs(PS.BLADE_COLORS) do
    local zones = {}
    for zoneName, weight in pairs(ZONES) do
        zones[zoneName] = weight
    end
    forageSystem.addForageDef("PhotonCrystal_" .. color, {
        type = PS.crystalType(color),
        skill = 2,
        xp = 10,
        snowChance = -50,
        categories = { "Stones" },
        zones = zones,
    })
end
