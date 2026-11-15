-- Photon Sword - Echoes of Humanity: which bodies are Echoes of Humanity's NPCs.
--
-- EoH's NPCs are survivors (IsoSurvivor) its Java runs; each body carries its NPC's instance id in
-- its mod data, which stays the same for the NPC.

PhotonSwordEoH = PhotonSwordEoH or {}
local PSE = PhotonSwordEoH

PSE.ID_KEY = "EchoesOfHumanity.Npc.InstanceId"

function PSE.id(character)
    if not character or not instanceof(character, "IsoSurvivor") then return nil end
    local id = character:getModData()[PSE.ID_KEY]
    if id == nil or id == "" then return nil end
    return tostring(id)
end

function PSE.isNpc(character)
    return PSE.id(character) ~= nil
end

-- Calls fn(npc, id) for every EoH NPC in the loaded cell.
function PSE.forEachNpc(fn)
    local cell = getCell()
    local list = cell and cell:getSurvivorList()
    for i = 0, (list and list:size() or 0) - 1 do
        local npc = list:get(i)
        local id = npc and not npc:isDead() and PSE.id(npc)
        if id then fn(npc, id) end
    end
end

function PSE.settings()
    return SandboxVars and SandboxVars.PhotonSwordEoH or {}
end
