require "PhotonSword/PS_Core"

-- Crystal migration, client half (server half: server/PhotonSword/PS_Migration.lua). The old
-- Blade Color mod option was this client's, so only the client knows what each player picked.
-- Vanilla keeps the lines of options no mod defines any more in ModOptions.ini (and writes them
-- back on every save), so the pick is still there as "combobox|PhotonSword|bladeColor|<n>", n
-- indexing PS.BLADE_COLORS as the option's entries did. No line means it was never changed from
-- the default, Blue.

local PS = PhotonSword

local function oldBladeColor()
    local file = getFileReader("ModOptions.ini", false)
    if not file then return PS.BLADE_COLORS[1] end
    local color = nil
    while true do
        local line = file:readLine()
        if line == nil then break end
        local index = line:match("^combobox|PhotonSword|bladeColor|(%d+)")
        if index then color = PS.BLADE_COLORS[tonumber(index)] end
    end
    file:close()
    return color or PS.BLADE_COLORS[1]
end

-- A character that has already lived a while was made before crystals; a new one starts at 0
-- hours (its save, if any, was made after this file shipped and holds the mark).
local function existedBefore(playerObj)
    return playerObj:getHoursSurvived() > 0
end

local function onCreatePlayer(playerNum, playerObj)
    if not playerObj or not playerObj:isLocalPlayer() then return end
    local data = playerObj:getModData()
    if data.PS_crystalGiven then return end
    local migrate = existedBefore(playerObj)
    if not isClient() then
        if migrate then
            PS.giveMigrationCrystal(playerObj, oldBladeColor())
        else
            PS.markCrystalGiven(playerObj)
        end
    else
        sendClientCommand(playerObj, "PhotonSword", migrate and "migrateCrystal" or "crystalNotNeeded",
            { color = migrate and oldBladeColor() or nil })
        -- Marked here too, so it isn't asked again this session before the server's mark comes back.
        data.PS_crystalGiven = true
    end
    if migrate then
        HaloTextHelper.addGoodText(playerObj, getText("IGUI_PS_CrystalMigrated"))
    end
end

Events.OnCreatePlayer.Add(onCreatePlayer)
