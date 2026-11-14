-- How a deflection looks and sounds (PS_Deflect.lua): the blade's hit spark (in this player's chosen
-- tone) at the defender, and a word over a local defender, as the Deflect Text and Deflect Spark Sound
-- options allow. The server announces each one to every client with a "deflect" command; echo marks
-- one the defender's own client already showed.

require "PhotonSword/PS_Deflect"
require "PhotonSword/PS_Options"

local PS = PhotonSword
local PSO = PhotonSwordOptions

-- share: nil for a deflected bullet, else how much of a shotgun blast the guard soaked (0-1).
-- parry: a photon sword's strike blocked, which the stance answers with its parry.
function PS.showDeflect(playerObj, share, parry)
    if parry then PS.noteParry(playerObj) end
    if PSO.deflectSound:getValue() then
        playerObj:getEmitter():playSound(PS.hitSound(PSO.getTone(PSO.hitTone), PSO.hitPitch:getValue()))
    end
    if IsoPlayer.isLocalPlayer(playerObj) and HaloTextHelper and PSO.deflectText:getValue() then
        local text = not share and getText("UI_PS_Deflected") or share >= 1 and getText("UI_PS_Blocked")
            or getText("UI_PS_Absorbed", math.floor(share * 100 + .5))
        HaloTextHelper.addGoodText(playerObj, text)
    end
end

-- An NPC's photon sword blocking a player's strike: the spark at the NPC.
function PS.showNpcBlock(npc)
    if PSO.deflectSound:getValue() then
        npc:getEmitter():playSound(PS.hitSound(PSO.getTone(PSO.hitTone), PSO.hitPitch:getValue()))
    end
end

-- An NPC's block the server settled (Project A-Life's NPCs in multiplayer).
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PhotonSword" or command ~= "npcBlock" or type(args) ~= "table" or type(args.id) ~= "number" then
        return
    end
    for npc in pairs(PS.forEachNpcHolder(function() end)) do
        if npc:getOnlineID() == args.id then return PS.showNpcBlock(npc) end
    end
end)

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PhotonSword" or command ~= "deflect" or type(args) ~= "table" or type(args.playerID) ~= "number" then
        return
    end
    local playerObj = getPlayerByOnlineID(args.playerID)
    if not playerObj or args.echo and IsoPlayer.isLocalPlayer(playerObj) then return end
    local share = type(args.share) == "number" and math.max(0, math.min(1, args.share)) or nil
    PS.showDeflect(playerObj, share, args.parry == true)
end)
