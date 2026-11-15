-- Photon Sword - Echoes of Humanity: EoH's hits meet a photon sword's guard.
--
-- EoH settles its fights in Java, out of Lua's reach, but lands every NPC attack (melee and
-- ranged) and every player hit on its NPCs through the game's Hit. This mod's Java plugin
-- (java/: PhotonSwordEoHHitMixin) asks PhotonSwordEoHHooks.beforeHit before each hit with a
-- survivor on either side; returning a number settles the hit with that damage instead, and EoH
-- takes a 0 as a hit that did nothing.
--   An NPC's shot at a player: the guard deflects it (struck back at the NPC) or soaks part of a
--     blast (PS.judgeShot: each pellet stopped with the soaked share's chance).
--   An NPC's photon sword strike at a player: the guard blocks it (PS.judgeBlow).
--   A photon sword strike (a player's or another NPC's) at an NPC holding one: it blocks now and
--     then (PS.npcBlocks).
-- EoH lands these where it runs its NPCs: single player, or the multiplayer server.

require "PhotonSword/PS_Core"
require "PhotonSwordEoH/PSE_Core"

local PS = require "PhotonSword/PS_Deflect"
local PSE = PhotonSwordEoH

local function ranged(weapon)
    return weapon ~= nil and instanceof(weapon, "HandWeapon") and weapon:isRanged()
end

PSE.hookCalls = PSE.hookCalls or 0   -- how often the Java plugin has asked (the dev kit shows it)

local function beforeHit(target, attacker, weapon, damage)
    PSE.hookCalls = PSE.hookCalls + 1
    if isClient() or not target or not attacker or not weapon then return nil end
    if instanceof(target, "IsoPlayer") and PSE.isNpc(attacker) then
        if ranged(weapon) then
            local deflected, share = PS.judgeShot(attacker, target, weapon, damage)
            if deflected or share >= 1 or share > 0 and ZombRandFloat(0, 1) < share then return 0 end
        elseif PS.judgeBlow(attacker, target, weapon) then
            return 0
        end
    elseif PSE.isNpc(target) and PS.npcBlocks(attacker, target, weapon) then
        return 0
    end
    return nil
end

-- Photon Sword's NPC parry is a zombie animation; an EoH NPC's block shows its spark and sound only.
local playNpcParry = PS.playNpcParry
function PS.playNpcParry(npc)
    if not PSE.isNpc(npc) then return playNpcParry(npc) end
    PS.noteParry(npc)
end

PhotonSwordEoHHooks = PhotonSwordEoHHooks or {}
PhotonSwordEoHHooks.beforeHit = beforeHit
