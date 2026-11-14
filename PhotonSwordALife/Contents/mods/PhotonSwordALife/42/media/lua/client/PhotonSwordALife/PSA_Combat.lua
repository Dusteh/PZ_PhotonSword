-- Photon Sword - Project A-Life: tells Photon Sword when an A-Life NPC fights, so its photon sword
-- lights for the fight and goes out after (PS.addNpcCombatSource, client/PhotonSword/PS_NpcBlades.lua).
--
-- A-Life's combat sets each NPC's ALifeCombatPhase animation variable (ALifeCombatCore's setPhase,
-- mirrored to multiplayer clients by ALifeAnimationClient): "approach", "aim", "push", "kite",
-- "cover", and so on while it fights or closes in, and "idle", "none", or "exit" when it doesn't.

require "PhotonSword/PS_Core"

local PS = PhotonSword

local CALM = { [""] = true, idle = true, none = true, exit = true }

local function fighting(zombie)
    local phase = zombie:getVariableString("ALifeCombatPhase")
    return phase ~= nil and not CALM[phase]
end

PS.addNpcCombatSource(fighting)
