require "Items/ProceduralDistributions"

-- Rare hilt spawns. Hilts spawn without a battery, so the player has to power them.

local SPAWNS = {
    -- container list name = weight
    MedievalWeaponsJapan = 1.5,
    MeleeWeapons_Late = 0.15,
    CrateRandomJunk = 0.03,
}

local function addSpawns()
    for listName, weight in pairs(SPAWNS) do
        local list = ProceduralDistributions.list[listName]
        if list and list.items then
            table.insert(list.items, "PhotonSword.PhotonSwordHilt")
            table.insert(list.items, weight)
        else
            print("[PhotonSword] Missing ProceduralDistributions list: " .. listName)
        end
    end
end

Events.OnPreDistributionMerge.Add(addSpawns)
