-- Photon Sword - Bandits: bandits' gunfire meets a photon sword's guard.
--
-- Bandits shoots on the client that runs the bandit, and every shot at a player (a shotgun blast is
-- one) goes through PlayerDamageModel.BulletHit(shooter, item, player). Wrapped, it asks Photon
-- Sword about a shot at a local player (PS.judgeLocalShot, PS_Deflect.lua: the roll, the deflect
-- shown, and in multiplayer a command asking the server to settle the guard). The guard is the ready
-- stance, or with Photon Sword Forms a Form's block. A stopped shot doesn't land;
-- a soaked blast lands and gives back the soaked share (PS.soak). A deflected bullet hits the bandit
-- with the weapon, and its health is synced the way Bandits syncs a hit from a client.

local PS = require "PhotonSword/PS_Deflect"

local strikeBack = PS.strikeBack
function PS.strikeBack(attacker, target, weapon, damage)
    strikeBack(attacker, target, weapon, damage)
    if isClient() and attacker and instanceof(attacker, "IsoZombie") and BanditUtils and BanditUtils.GetCharacterID
            and PS.deflectSetting("DeflectStrikesBack") then
        sendClientCommand(target, "Sync", "Health", { id = BanditUtils.GetCharacterID(attacker), h = attacker:getHealth() })
    end
end

Events.OnGameStart.Add(function()
    if not PlayerDamageModel or type(PlayerDamageModel.BulletHit) ~= "function" then
        print("Photon Sword - Bandits: PlayerDamageModel.BulletHit not found; not patched")
        return
    end
    local bulletHit = PlayerDamageModel.BulletHit
    PlayerDamageModel.BulletHit = function(shooter, item, player, ...)
        local deflected, share = PS.judgeLocalShot(shooter, player, item)
        if deflected or share >= 1 then return end
        if share <= 0 then return bulletHit(shooter, item, player, ...) end
        -- Bandits lands a whole blast as one hit: let it land, then give back the soaked share.
        return PS.soak(player, share, bulletHit, shooter, item, player, ...)
    end
    print("Photon Sword - Bandits: patched")
end)
