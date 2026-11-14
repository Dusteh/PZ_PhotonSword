-- Development kit for testing Photon Sword - Project A-Life. Not part of the mod: deploy.sh copies
-- it into the deployed copy (media/lua/server/PhotonSwordALife/) unless run with --release.
--
-- In the debug Lua console (single player):
--   PSDevKit.duel()            two A-Life NPCs, a few tiles either side of you, hostile to each
--                              other and neutral to you, each with only a lit photon sword (blue
--                              and red). They fight at once.
--   PSDevKit.duel({ profileId = "...", distance = 4, mode = "hunt" })   pick the NPC profile (both
--                              get it), how far out, and A-Life's spawn mode (default "hunt")
--   PSDevKit.duelists()        the duelling NPCs in the cell
--   PSDevKit.endDuel()         remove them (from A-Life's registry, so they don't come back)
--
-- How: A-Life's own spawner (DebugService.rawSpawn, as its admin console spawns) puts each NPC in a
-- group of its own with group warfare on, which A-Life makes hostile to every other group of the
-- same faction (Relations.status); both come from one profile, so they share a faction. A wrapper
-- on ProfileHydrator.plan then strips the guns from those groups' loadouts and makes the melee
-- weapon the photon sword (after the patch's own roll, so whatever the Photon Sword Chance).

if isClient() then return end

require "ProjectALife/Shells/ALifeProfileHydrator"
require "PhotonSword/PS_Core"
local PS = PhotonSword

PSDevKit = PSDevKit or {}

local duelGroups = {}   -- groupId -> blade color

local Hydrator = ProjectALife and ProjectALife.ProfileHydrator
if Hydrator and type(Hydrator.plan) == "function" then
    local plan = Hydrator.plan
    function Hydrator.plan(actor)
        local result, planError = plan(actor)
        local memory = type(actor) == "table" and actor.memory or nil
        local color = memory and duelGroups[memory.groupId]
        if color and type(result) == "table" and type(result.weapons) == "table" then
            result.weapons.primary, result.weapons.secondary = nil, nil
            result.weapons.melee = PS.BLADE_TYPE
            result.photonSwordColor = color
        end
        return result, planError
    end
end

local function service()
    local S = ProjectALife and ProjectALife.DebugService
    if type(S) ~= "table" or type(S.rawSpawn) ~= "function" then return nil end
    return S
end

local function pickProfile(S, factionId)
    local ok, ids = pcall(S.hostileProfileIds, 1, getTimestampMs(), factionId, true, nil, 1)
    return ok and type(ids) == "table" and ids[1] or nil
end

function PSDevKit.duel(options)
    options = options or {}
    local player = getPlayer()
    local S = service()
    if not player or not S then
        print("[PSDevKit] duel: needs a loaded game with Project A-Life")
        return nil
    end
    local profileId = options.profileId or pickProfile(S, options.factionId)
    if not profileId then
        print("[PSDevKit] duel: no A-Life profile to spawn")
        return nil
    end
    local distance = options.distance or 3
    local stamp = getTimestampMs()
    local spawned = {}
    for i, side in ipairs({ { color = "Blue", dx = distance }, { color = "Red", dx = -distance } }) do
        local result = S.rawSpawn(player, {
            profileIds = { profileId }, count = 1,
            x = math.floor(player:getX() + side.dx), y = math.floor(player:getY()), z = math.floor(player:getZ()),
            mode = options.mode or "hunt", radius = 12,
            playerStance = "neutral", groupWarfare = true, explicit = true,
            requestId = "psdevkit-duel-" .. stamp .. "-" .. i,
        }, true)
        if type(result) == "table" and result.ok and result.groupId then
            duelGroups[result.groupId] = side.color
            spawned[#spawned + 1] = result.groupId
        else
            print("[PSDevKit] duel: spawn " .. i .. " refused: " .. tostring(type(result) == "table" and result.reason or result))
        end
    end
    print("[PSDevKit] duel: " .. #spawned .. " of 2 NPCs (" .. profileId .. ") on their way, blue east, red west")
    return #spawned == 2 and spawned or nil
end

-- The duelling NPCs in the cell, and their group ids.
function PSDevKit.duelists()
    local found, registry = {}, ProjectALife and ProjectALife.ActorRegistry
    if not registry then return found end
    local zombies = getCell():getZombieList()
    for i = 0, zombies:size() - 1 do
        local shell = zombies:get(i)
        local uid = shell:getModData().ProjectALifeUID
        local record = type(uid) == "string" and registry.read(uid) or nil
        local groupId = record and record.memory and record.memory.groupId
        if groupId and duelGroups[groupId] and not shell:isDead() then
            found[#found + 1] = { shell = shell, groupId = groupId, color = duelGroups[groupId] }
        end
    end
    return found
end

-- The registry's actors in the duel's groups (every one, loaded or not).
local function duelActors()
    local found, registry = {}, ProjectALife and ProjectALife.ActorRegistry
    if not (registry and type(registry.list) == "function") then return found end
    for _, actor in ipairs(registry.list()) do
        local memory = type(actor) == "table" and actor.memory or nil
        if memory and duelGroups[memory.groupId] then found[#found + 1] = actor end
    end
    return found
end

-- Removes the duellists the way A-Life's admin squad delete does (DebugService.purgeActor: retired
-- through its spawn service and released by its executor), so A-Life doesn't restore them from its
-- registry as it does a shell that merely goes missing, then their squads. Returns how many
-- actors were removed and how many A-Life refused.
function PSDevKit.endDuel()
    local S = ProjectALife and ProjectALife.DebugService
    local removed, failed = 0, 0
    for _, actor in ipairs(duelActors()) do
        local ok, purged = false, false
        if S and type(S.purgeActor) == "function" then ok, purged = pcall(S.purgeActor, actor, "psdevkit_duel_end") end
        if ok and purged then removed = removed + 1 else failed = failed + 1 end
    end
    local ledger = ProjectALife and ProjectALife.SquadLedger
    for groupId in pairs(duelGroups) do
        pcall(function()
            local squad = ledger and ledger.read(groupId)
            if squad then ledger.remove(squad.id, squad.revision, "psdevkit_duel_end") end
        end)
    end
    if failed == 0 then duelGroups = {} end
    print("[PSDevKit] duel ended: " .. removed .. " NPCs removed"
        .. (failed > 0 and (", " .. failed .. " refused (run PSDevKit.endDuel() again)") or ""))
    return removed, failed
end

-- How many of the duel's actors A-Life still has (loaded or not).
function PSDevKit.duelActorCount()
    return #duelActors()
end
