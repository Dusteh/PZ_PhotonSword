-- Photon Sword - Echoes of Humanity: tells Photon Sword when an EoH NPC fights, so its photon sword
-- lights for the fight and goes out after (PS.addNpcCombatSource, client/PhotonSword/PS_NpcBlades.lua).
-- Beyond striking (which Photon Sword sees itself), an EoH NPC is fighting while it aims, or for a
-- moment after it's hit.

require "PhotonSword/PS_Core"
require "PhotonSwordEoH/PSE_Core"

local PS = PhotonSword
local PSE = PhotonSwordEoH

local function fighting(npc)
    if not PSE.isNpc(npc) then return false end
    return npc:isAiming() or npc:getAttackedBy() ~= nil
end

PS.addNpcCombatSource(fighting)

