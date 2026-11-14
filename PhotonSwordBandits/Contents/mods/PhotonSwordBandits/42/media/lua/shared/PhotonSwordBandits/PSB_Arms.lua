-- Photon Sword - Bandits: bandits who carry a photon sword.
--
-- A bandit's melee weapon is a type name on its brain (brain.weapons.melee), copied from its
-- Bandits profile, and Bandits makes the item from it (BanditCompatibility.InstanceItem) for the
-- hands (Bandit.SetHands), each swing (ZASmack), and the corpse (Bandit.UpdateItemsToSpawnAtDeath).
-- Wrapped:
--   Bandit.ApplyVisuals(zombie, brain)  runs on each new brain before Bandits stores it. Where the
--       game has authority, an armed bandit's melee weapon becomes the ignited photon sword at the
--       Photon Sword Chance, rolled from its name and profile (PS.stableRoll), so a bandit Bandits
--       rebuilds (BanditServerSpawner's spawnRestore) gets the same answer.
--   BanditCompatibility.InstanceItem    readies every photon sword Bandits makes (PS.issueNpcBlade):
--       the damage multiplier, and for the hands and the corpse, that bandit's blade color.
-- A profile that names PhotonSword.PhotonSword itself (Bandit Creator) is honored as it is. The
-- light, hum, and clean blade are Photon Sword's (PS.forEachNpcWielder); a dropped sword gets a
-- battery when a player picks it up (PS_PowerDrain.lua).

require "Bandit"
require "BanditCompatibility"
require "BanditBrain"
require "PhotonSword/PS_Core"

local PS = PhotonSword

local DEFAULT_CHANCE = 2

local function settings()
    return SandboxVars and SandboxVars.PhotonSwordBandits or {}
end

-- The same for one bandit on every machine and through a rebuild (which keeps its name).
local function npcKey(brain)
    return tostring(brain.fullname or brain.id) .. "|" .. tostring(brain.bid)
end

local function arm(brain)
    local weapons = type(brain) == "table" and brain.weapons or nil
    if type(weapons) ~= "table" or brain.photonSword ~= nil or isClient() then return end
    local melee = weapons.melee
    if melee == nil or melee == "Base.BareHands" then return end
    brain.photonSword = melee == PS.BLADE_TYPE
        or PS.stableRoll(npcKey(brain) .. ":photonsword") < (settings().SpawnChance or DEFAULT_CHANCE)
    if brain.photonSword then weapons.melee = PS.BLADE_TYPE end
end

local applyVisuals = Bandit.ApplyVisuals
function Bandit.ApplyVisuals(zombie, brain, ...)
    arm(brain)
    return applyVisuals(zombie, brain, ...)
end

-- The blade color for the item being made, while Bandits makes one a bandit shows.
local issuingColor = nil

local function issuing(brain, fn, ...)
    issuingColor = type(brain) == "table" and PS.npcBladeColor(npcKey(brain), settings().BladeColor) or nil
    local results = PS.pack(pcall(fn, ...))
    issuingColor = nil
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2, results.n)
end

local instanceItem = BanditCompatibility.InstanceItem
BanditCompatibility.InstanceItem = function(itemFullType, ...)
    local results = PS.pack(instanceItem(itemFullType, ...))
    if results[1] and itemFullType == PS.BLADE_TYPE then
        PS.issueNpcBlade(results[1], issuingColor)
    end
    return unpack(results, 1, results.n)
end

local setHands = Bandit.SetHands
function Bandit.SetHands(zombie, itemType, ...)
    if itemType ~= PS.BLADE_TYPE then return setHands(zombie, itemType, ...) end
    return issuing(BanditBrain.Get(zombie), setHands, zombie, itemType, ...)
end

local updateItemsToSpawnAtDeath = Bandit.UpdateItemsToSpawnAtDeath
function Bandit.UpdateItemsToSpawnAtDeath(zombie, brain, ...)
    return issuing(brain or BanditBrain.Get(zombie), updateItemsToSpawnAtDeath, zombie, brain, ...)
end
