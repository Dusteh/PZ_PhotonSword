require "PhotonSword/PS_Core"

-- Crystal migration, server half (client half: client/PhotonSword/PS_Migration.lua). Before
-- crystals, each player picked their blade color in the mod options. A character from then gets
-- one crystal of that color, once, marked in player modData (PS_crystalGiven) so it isn't given
-- twice. Runs on the server, or in the single-player game.

local PS = PhotonSword

function PS.giveMigrationCrystal(playerObj, color)
    local data = playerObj:getModData()
    if data.PS_crystalGiven then return false end
    data.PS_crystalGiven = true
    if not PS.COLORS[color or ""] then color = PS.BLADE_COLORS[1] end
    local inv = playerObj:getInventory()
    local crystal = instanceItem(PS.crystalType(color))
    inv:AddItem(crystal)
    sendAddItemToContainer(inv, crystal)
    print("[PhotonSword] gave " .. tostring(playerObj:getUsername()) .. " a " .. color
        .. " crystal for their old Blade Color option")
    return true
end

-- Characters made after crystals arrived never had the option, so they're marked at once.
function PS.markCrystalGiven(playerObj)
    playerObj:getModData().PS_crystalGiven = true
end

local function onClientCommand(module, command, playerObj, args)
    if module ~= "PhotonSword" or not playerObj then return end
    if command == "migrateCrystal" then
        PS.giveMigrationCrystal(playerObj, type(args) == "table" and args.color or nil)
    elseif command == "crystalNotNeeded" then
        PS.markCrystalGiven(playerObj)
    end
end

Events.OnClientCommand.Add(onClientCommand)
