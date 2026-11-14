-- Photon Sword - Project A-Life: an NPC holding a photon sword blocks a player's.
--
-- A-Life weighs a player's hit on its NPC itself (ProjectALife.AIFence's Fence.weighBlow, where the
-- NPC is run: single player, or the client or server with authority over it), setting the NPC's
-- health from its own health model, so stopping the game's damage alone wouldn't stop the hit.
-- Fence.weighBlow asks Fence.shield(shell, bodyPart, weapon) whether armor stopped the blow; wrapped,
-- it also says so when the NPC's sword blocks it (PS.npcBlocks: holding a photon sword, on its feet,
-- facing the player, at Photon Sword's NPC Block Chance). Fence.shield doesn't say who struck, so
-- weighBlow is wrapped to note the wielder while it runs. PS.npcBlocks rolls once per strike, so
-- this agrees with Photon Sword's own check of the same hit (OnWeaponHitCharacter).

local PS = require "PhotonSword/PS_Deflect"

local wielder = nil   -- who struck the blow Fence.weighBlow is weighing

local function pack(...) return { n = select("#", ...), ... } end

local installed = false
local function install()
    if installed then return end
    local Fence = ProjectALife and ProjectALife.AIFence
    if type(Fence) ~= "table" or type(Fence.weighBlow) ~= "function" or type(Fence.shield) ~= "function" then
        print("[PhotonSwordALife] Fence.weighBlow or Fence.shield not found; NPC blocks not patched")
        return
    end
    installed = true

    local weighBlow = Fence.weighBlow
    Fence.weighBlow = function(shell, by, ...)
        local previous = wielder
        wielder = by
        local result = pack(pcall(weighBlow, shell, by, ...))
        wielder = previous
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end

    local shield = Fence.shield
    Fence.shield = function(shell, bodyPart, weapon, ...)
        if wielder and instanceof(wielder, "IsoPlayer") then
            local blade = weapon or (Fence.heldWeapon and Fence.heldWeapon(wielder))
            if PS.npcBlocks(wielder, shell, blade) then return true, true end
        end
        return shield(shell, bodyPart, weapon, ...)
    end
    print("[PhotonSwordALife] NPC blocks patched")
end

Events.OnGameStart.Add(install)
if Events.OnServerStarted then Events.OnServerStarted.Add(install) end
