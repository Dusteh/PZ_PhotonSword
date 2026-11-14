require "PhotonSword/PS_Core"

-- Server authority for battery drain: every ignited blade a player carries (in hand, on the
-- hotbar, or in a bag) loses charge each in-game minute and extinguishes itself when empty.
-- In single player this runs locally.

local PS = PhotonSword

local function getPlayers()
    if isServer() then return getOnlinePlayers() end
    return IsoPlayer.getPlayers()
end

-- A blade that never had a battery (an NPC's, or one from the debug menu) arrives with a part-
-- drained one, so it doesn't go out the moment a player picks it up.
local NPC_CHARGE_MIN, NPC_CHARGE_MAX = 0.2, 0.6

local function drainBlade(playerObj, blade, drain)
    if not PS.hasBattery(blade) then
        PS.setCharge(blade, ZombRandFloat(NPC_CHARGE_MIN, NPC_CHARGE_MAX))
    end
    local charge = PS.getCharge(blade) - drain
    PS.setCharge(blade, charge)
    if charge <= 0 then
        PS.swap(playerObj, blade, false)
        playerObj:playSound(PS.EXTINGUISH_SOUND)
    else
        syncItemModData(playerObj, blade)
    end
end

local function drainPlayer(playerObj, drain)
    local blades = playerObj:getInventory():getAllTypeRecurse(PS.BLADE_TYPE)
    for i = blades:size() - 1, 0, -1 do
        drainBlade(playerObj, blades:get(i), drain)
    end
end

local function everyOneMinute()
    local drain = PS.getDrainPerMinute()
    if drain <= 0 then return end
    local players = getPlayers()
    for i = 0, players:size() - 1 do
        local playerObj = players:get(i)
        if playerObj and not playerObj:isDead() then
            drainPlayer(playerObj, drain)
        end
    end
end

-- Pure clients don't own the drain; the server (or single-player game) does.
if not isClient() then
    Events.EveryOneMinute.Add(everyOneMinute)
end
