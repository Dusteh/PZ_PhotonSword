-- Photon Sword - Project A-Life: keeps photon swords out of A-Life's mod loot scan.
--
-- With A-Life's mod loot experiment on (modloot_weapons), it scans every mod's weapons and hands
-- them out by score, where the ignited blade would land in the top tier and turn up far more often
-- than a rare weapon should. Excluding both item types leaves the patch's Photon Sword Chance
-- (PSA_Arms.lua) as the only way an A-Life NPC gets one.

require "ProjectALife/ModLoot/ALifeModLootData"
require "PhotonSword/PS_Core"

local PS = PhotonSword
local Data = ProjectALife and ProjectALife.ModLootData

if Data and type(Data.excludeExact) == "table" then
    Data.excludeExact[PS.HILT_TYPE] = true
    Data.excludeExact[PS.BLADE_TYPE] = true
end
