-- Development kit for testing the photon sword. Not part of the mod: deploy.sh copies it into the
-- deployed copy (media/lua/server/PhotonSword/) unless run with --release, and the Workshop folder
-- never contains it.
-- Each character gets the kit once, when it spawns: a charged, ignited photon sword in both hands,
-- spare batteries and crystals, and Long Blade at KIT.longBlade (the guard skill that deflects gunfire,
-- PS_Deflect.lua). Photon Sword Forms' kit (its dev/PSF_DevKit.lua) adds the Forms and Martial Arts.
-- Bump KIT.version to hand it out again to existing characters, or run PSDevKit.give(getPlayer())
-- in the debug Lua console.
-- Single player (or the host's own player) only; a dedicated server doesn't get OnCreatePlayer.

if isClient() then return end

require "PhotonSword/PS_Core"
local PS = PhotonSword

local KIT = {
    version = 2,
    color = "Blue",    -- the hilt's crystal (PS.BLADE_COLORS)
    crystals = { "Green", "Red" },    -- spare crystals to try other colors
    batteries = 2,
    longBlade = 10,    -- Long Blade skill, 0-10 (deflect and soak chances; 10 allows a whole blast blocked)
}

PSDevKit = PSDevKit or {}

function PSDevKit.give(player)
    local inv = player:getInventory()
    if player.setPerkLevelDebug then player:setPerkLevelDebug(Perks.LongBlade, KIT.longBlade) end

    local hilt = inv:AddItem(PS.HILT_TYPE)
    PS.setCharge(hilt, 1)
    PS.fitCrystal(hilt, KIT.color)
    player:setPrimaryHandItem(hilt)
    player:setSecondaryHandItem(hilt)
    PS.swap(player, hilt, true)
    for _ = 1, KIT.batteries do inv:AddItem(PS.BATTERY_TYPE) end
    for _, color in ipairs(KIT.crystals) do inv:AddItem(PS.crystalType(color)) end

    player:getModData().PS_devKit = KIT.version
    print("PhotonSword dev kit given to " .. player:getUsername() .. ": an ignited sword, Long Blade "
        .. KIT.longBlade .. "; aim to guard against gunfire")
end

Events.OnCreatePlayer.Add(function(_, player)
    if player and player:getModData().PS_devKit ~= KIT.version then PSDevKit.give(player) end
end)
