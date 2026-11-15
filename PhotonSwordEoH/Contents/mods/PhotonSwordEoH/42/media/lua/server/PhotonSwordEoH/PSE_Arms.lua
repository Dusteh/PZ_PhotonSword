-- Photon Sword - Echoes of Humanity: EoH NPCs who carry a photon sword.
--
-- EoH arms its NPCs in Java, so this looks over its NPCs every ARM_MS instead: one holding a melee
-- weapon rolls once, from its instance id (PS.stableRoll, so it keeps its answer), against the
-- Photon Sword Chance, and on a hit gets an ignited photon sword in its inventory and in its hands,
-- readied as an NPC's (PS.issueNpcBlade: the damage multiplier and its blade color). An NPC with
-- one is handed it back whenever it holds another melee weapon (EoH's own weapon choice may swap
-- it). EoH strikes with whatever HandWeapon is held, so its damage is the sword's. Runs where EoH
-- runs its NPCs: single player, or the multiplayer server.

require "PhotonSword/PS_Core"
require "PhotonSwordEoH/PSE_Core"

local PS = PhotonSword
local PSE = PhotonSwordEoH

local ARM_MS = 2000
local DEFAULT_CHANCE = 2
local nextArm = 0

local function melee(item)
    return item ~= nil and instanceof(item, "HandWeapon") and not item:isRanged()
end

local function hold(npc, blade)
    npc:setPrimaryHandItem(blade)
    npc:setSecondaryHandItem(blade:isTwoHandWeapon() and blade or nil)
end

function PSE.arm(npc, id)
    local data = npc:getModData()
    local held = npc:getPrimaryHandItem()
    if data.PSE_armed then
        local blade = npc:getInventory():getFirstTypeRecurse(PS.BLADE_TYPE)
        if blade and held ~= blade and melee(held) then hold(npc, blade) end
        return
    end
    if data.PSE_rolled or not melee(held) then return end
    data.PSE_rolled = true
    local chance = PSE.settings().SpawnChance or DEFAULT_CHANCE
    if PS.stableRoll(id .. ":photonsword") >= chance then return end
    local blade = npc:getInventory():AddItem(PS.BLADE_TYPE)
    if not blade then return end
    PS.issueNpcBlade(blade, PS.npcBladeColor(id, PSE.settings().BladeColor))
    data.PSE_armed = true
    hold(npc, blade)
    print("[PhotonSwordEoH] NPC " .. id .. " carries a photon sword")
end

local function onTick()
    local now = getTimestampMs()
    if now < nextArm then return end
    nextArm = now + ARM_MS
    PSE.forEachNpc(PSE.arm)
end

if not isClient() then Events.OnTick.Add(onTick) end
