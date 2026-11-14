-- Photon Sword - Project A-Life: A-Life NPCs who carry a photon sword.
--
-- A-Life builds an NPC's loadout each time it puts the NPC in the world: ProfileHydrator.plan(actor)
-- picks its weapons (plan.weapons.primary / secondary / melee, as item type names) and
-- ProfileHydrator.apply(shell, plan) adds them to the NPC's body (a zombie "shell") and equips one.
-- Wrapped:
--   plan   an armed NPC's melee weapon becomes the ignited photon sword at the Photon Sword Chance,
--          rolled from the NPC's uid (PS.stableRoll), so each NPC keeps its answer every time A-Life
--          rebuilds it.
--   apply  readies the swords it added (PS.issueNpcBlade): the damage multiplier and the NPC's
--          blade color. A-Life's strikes read damage from that item.
-- The light, hum, and clean blade are Photon Sword's (PS.forEachNpcWielder); a dropped sword gets a
-- battery when a player picks it up (PS_PowerDrain.lua). All of this runs where A-Life builds NPCs:
-- in single player, or on the multiplayer server.

require "ProjectALife/Shells/ALifeProfileHydrator"
require "PhotonSword/PS_Core"

local PS = PhotonSword
local Hydrator = ProjectALife and ProjectALife.ProfileHydrator
if not Hydrator then
    print("[PhotonSwordALife] ProjectALife.ProfileHydrator not found; NPCs won't carry photon swords")
    return
end

local DEFAULT_CHANCE = 2
local BARE = { ["Base.BareHands"] = true, none = true, [""] = true }

local function settings()
    return SandboxVars and SandboxVars.PhotonSwordALife or {}
end

local function arm(plan, actor)
    local weapons = type(plan) == "table" and plan.weapons or nil
    local uid = type(actor) == "table" and actor.uid or nil
    if type(weapons) ~= "table" or uid == nil then return end
    local melee = weapons.melee
    if melee == nil or BARE[melee] then return end
    if melee ~= PS.BLADE_TYPE
            and PS.stableRoll(tostring(uid) .. ":photonsword") >= (settings().SpawnChance or DEFAULT_CHANCE) then
        return
    end
    weapons.melee = PS.BLADE_TYPE
    plan.photonSwordColor = PS.npcBladeColor(uid, settings().BladeColor)
end

local plan = Hydrator.plan
function Hydrator.plan(actor, ...)
    local results = PS.pack(plan(actor, ...))
    if results[1] ~= nil then arm(results[1], actor) end
    return unpack(results, 1, results.n)
end

local apply = Hydrator.apply
function Hydrator.apply(shell, plan, ...)
    local results = PS.pack(apply(shell, plan, ...))
    if results[1] and type(plan) == "table" and plan.photonSwordColor then
        local blades = shell:getInventory():getAllTypeRecurse(PS.BLADE_TYPE)
        for i = 0, blades:size() - 1 do
            PS.issueNpcBlade(blades:get(i), plan.photonSwordColor)
        end
    end
    return unpack(results, 1, results.n)
end
