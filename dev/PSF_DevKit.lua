-- Development kit for testing photon sword Forms. Not part of the mod: deploy.sh copies it into
-- the deployed copy (media/lua/server/PhotonSwordForms/) unless run with --release, and the
-- Workshop folder never contains it.
-- Each character gets the kit once, when it spawns: every Form learned at KIT.mastery (and its
-- manual, to test reading) and Martial Arts at KIT.martialArts. The sword itself (ignited, in both
-- hands, with spare batteries) comes from Photon Sword's kit (its dev/PS_DevKit.lua), deployed by
-- Photon Sword's deploy.sh. Bump KIT.version to hand it out again to existing characters, or run
-- PSFDevKit.give(getPlayer()) in the debug Lua console.
-- Single player (or the host's own player) only; a dedicated server doesn't get OnCreatePlayer.

if isClient() then return end

local PSF = require "PhotonSwordForms/PSF_Forms"
local SMA = require "SMA_Core"

local KIT = {
    version = 1,
    mastery = 5,       -- each Form's mastery, 0-5 (5 unlocks every move)
    martialArts = 10,  -- Martial Arts skill, 0-10 (attack speed, footwork, guard drain, deflect chances)
}

PSFDevKit = {}

function PSFDevKit.give(player)
    local inv = player:getInventory()
    local state = SMA.getState(player)
    for _, W in ipairs(PSF.forms) do
        inv:AddItem(W.book)
        W.learn(player)
        state.mastery[SMA.masteryStyleID(W.style)] = SMA.masteryThresholds[KIT.mastery] or 0
        if W.sync then W.sync(player) end
    end

    local perk = Perks[SMA.perkID]
    if perk and player.setPerkLevelDebug then player:setPerkLevelDebug(perk, KIT.martialArts) end

    player:getModData().PSF_devKit = KIT.version
    print("PhotonSwordForms dev kit given to " .. player:getUsername()
        .. ": Forms at mastery " .. KIT.mastery .. "; hold Block (Caps Lock by default) while aiming to guard")
end

Events.OnCreatePlayer.Add(function(_, player)
    if player and player:getModData().PSF_devKit ~= KIT.version then PSFDevKit.give(player) end
end)
