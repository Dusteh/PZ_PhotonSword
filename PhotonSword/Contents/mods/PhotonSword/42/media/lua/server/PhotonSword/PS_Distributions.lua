require "Items/ProceduralDistributions"
require "PhotonSword/PS_Core"

-- Rare hilt and crystal spawns. Hilts spawn without a battery, so the player has to power them,
-- and hold a crystal of a random color only at the Crystal Spawn Chance sandbox option.

local PS = PhotonSword

local HILT_SPAWNS = {
    -- container list name = weight
    MedievalWeaponsJapan = 1.5,
    MeleeWeapons_Late = 0.15,
    CrateRandomJunk = 0.03,
}

-- Weight for each crystal color; a container's roll picks a color evenly.
local CRYSTAL_SPAWNS = {
    JewelryGems = 0.15,
    MedievalWeaponsJapan = 0.2,
    MeleeWeapons_Late = 0.02,
    CrateRandomJunk = 0.004,
}

local function addSpawn(listName, itemType, weight)
    local list = ProceduralDistributions.list[listName]
    if list and list.items then
        table.insert(list.items, itemType)
        table.insert(list.items, weight)
    else
        print("[PhotonSword] Missing ProceduralDistributions list: " .. listName)
    end
end

local function addSpawns()
    for listName, weight in pairs(HILT_SPAWNS) do
        addSpawn(listName, PS.HILT_TYPE, weight)
    end
    for listName, weight in pairs(CRYSTAL_SPAWNS) do
        for _, color in ipairs(PS.BLADE_COLORS) do
            addSpawn(listName, PS.crystalType(color), weight)
        end
    end
end

-- Hilts come out of the loot table empty; each one found in a freshly filled container gets a
-- crystal at the sandbox chance. Runs where loot is made: the server, or the single-player game.
local function onFillContainer(roomName, containerType, container)
    -- The event can pass things that aren't ItemContainers (e.g. a zombie body), which
    -- getAllTypeRecurse throws on.
    if not (container and instanceof(container, "ItemContainer")) then return end
    local hilts = container:getAllTypeRecurse(PS.HILT_TYPE)
    if hilts:isEmpty() then return end
    local chance = PS.getCrystalSpawnChance()
    for i = 0, hilts:size() - 1 do
        local hilt = hilts:get(i)
        if not PS.hasCrystal(hilt) and ZombRand(100) < chance then
            PS.fitCrystal(hilt, PS.BLADE_COLORS[ZombRand(#PS.BLADE_COLORS) + 1])
        end
    end
end

Events.OnPreDistributionMerge.Add(addSpawns)
Events.OnFillContainer.Add(onFillContainer)
