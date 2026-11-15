-- Photon Sword - Echoes of Humanity dev kit (deploy.sh copies it in; release builds leave it out).
-- In single player, with the debug Lua console:
--   PSEDevKit.spawn()         a hostile EoH NPC with a lit photon sword, 3 tiles east of you
--   PSEDevKit.duel()          two EoH NPCs from rival factions, each with a lit photon sword, either
--                             side of you: they fight each other (NPC vs NPC blocks)
--   PSEDevKit.status()        the Java plugin (has it called the hook?), EoH NPCs near you, armed ones
--   PSEDevKit.arm()           gives the nearest EoH NPC a lit photon sword (and keeps it armed)
--   PSEDevKit.strike()        your held weapon hits the nearest EoH NPC through the game's Hit, so
--                             the Java plugin and PhotonSwordEoHHooks.beforeHit run as for a real hit
--   PSEDevKit.alwaysBlock()   NPC block chances at 100% until clear(); PSEDevKit.clear() puts them back

require "PhotonSword/PS_Core"
require "PhotonSwordEoH/PSE_Core"

local PS = PhotonSword
local PSE = PhotonSwordEoH
PSEDevKit = {}
local saved = nil

local function say(text)
    print("[PSEDevKit] " .. text)
    local player = getPlayer()
    if player then player:Say(text) end
end

-- Spawning, through Echoes of Humanity's own Lua API: KIT definitions are registered once
-- (EchoesOfHumanity.NPC.registerDefinition: a melee loadout, a role and a faction), then spawned
-- beside you (spawnDefinition). EoH builds the body over the next ticks, so new NPCs near the spot
-- are picked up for up to WAIT_MS and handed to then(npc). EoH's refusals are printed with its reason.
local WAIT_MS = 10000
local registered = {}
local pending = {}

local function eoh()
    return EchoesOfHumanity and EchoesOfHumanity.NPC
end

function PSEDevKit.define(id, name, weapon, faction)
    if registered[id] then return true end
    local api = eoh()
    if not api then return say("Echoes of Humanity isn't loaded") end
    local result = api.registerDefinition({
        id = id, displayName = name, role = "RAIDER", factionId = faction,
        loadout = { { itemType = weapon, purpose = "MELEE_FALLBACK", quantity = 1 } },
    })
    local reason = result and result.reason
    if result and (result.accepted or reason == "duplicate_definition_id") then
        registered[id] = true
        return true
    end
    say("EoH refused definition " .. id .. ": " .. tostring(reason))
    return false
end

local function knownIds()
    local ids = {}
    PSE.forEachNpc(function(_, id) ids[id] = true end)
    return ids
end

-- Spawns definitionId dx, dy tiles from you; then(npc) runs once its body appears.
function PSEDevKit.spawnAt(definitionId, dx, dy, name, thenFn)
    local api, player = eoh(), getPlayer()
    if not api then return say("Echoes of Humanity isn't loaded") end
    local x, y, z = player:getX() + dx, player:getY() + dy, player:getZ()
    local before = knownIds()
    local result = api.spawnDefinition({ definitionId = definitionId, x = x, y = y, z = z, displayName = name })
    if not result or not result.accepted then
        return say("EoH refused to spawn " .. definitionId .. ": " .. tostring(result and result.reason))
    end
    pending[#pending + 1] = { x = x, y = y, before = before, until_ = getTimestampMs() + WAIT_MS,
        thenFn = thenFn, what = definitionId }
    print("[PSEDevKit] spawning " .. definitionId .. " (EoH id " .. tostring(result.id) .. ")")
end

Events.OnTick.Add(function()
    if #pending == 0 then return end
    local now = getTimestampMs()
    for i = #pending, 1, -1 do
        local p = pending[i]
        local found = nil
        PSE.forEachNpc(function(npc, id)
            if not found and not p.before[id] and math.abs(npc:getX() - p.x) < 4 and math.abs(npc:getY() - p.y) < 4 then
                found = npc
            end
        end)
        if found then
            table.remove(pending, i)
            if p.thenFn then p.thenFn(found) end
        elseif now > p.until_ then
            table.remove(pending, i)
            say(p.what .. " didn't appear near the spot within " .. (WAIT_MS / 1000) .. " s")
        end
    end
end)

function PSEDevKit.spawn()
    if not PSEDevKit.define("photonsword.dev.blade", "Blade Raider", "Base.Katana", "echoesofhumanity.hostile") then return end
    PSEDevKit.spawnAt("photonsword.dev.blade", 3, 0, "Blade Raider", function(npc) PSEDevKit.arm(npc) end)
end

function PSEDevKit.duel()
    if not PSEDevKit.define("photonsword.dev.duelist_a", "Orchard Duelist", "Base.Katana", "BoneOrchard")
            or not PSEDevKit.define("photonsword.dev.duelist_b", "Ranger Duelist", "Base.Katana", "Rangers") then
        return
    end
    PSEDevKit.spawnAt("photonsword.dev.duelist_a", -3, 0, "Orchard Duelist", function(npc) PSEDevKit.arm(npc) end)
    PSEDevKit.spawnAt("photonsword.dev.duelist_b", 3, 0, "Ranger Duelist", function(npc) PSEDevKit.arm(npc) end)
end

function PSEDevKit.nearest()
    local player, best, bestD = getPlayer(), nil, math.huge
    PSE.forEachNpc(function(npc)
        local d = npc:DistTo(player)
        if d < bestD then best, bestD = npc, d end
    end)
    return best
end

function PSEDevKit.status()
    local count, armed = 0, 0
    PSE.forEachNpc(function(npc)
        count = count + 1
        if npc:getModData().PSE_armed then armed = armed + 1 end
    end)
    say(string.format("Java hook calls: %d. EoH NPCs loaded: %d, armed: %d.", PSE.hookCalls or 0, count, armed))
    if (PSE.hookCalls or 0) == 0 then
        print("[PSEDevKit] No hook calls yet: if NPCs have fought, check ~/Zomboid/FadedJavaLoader/logs/fjl-latest.log for dusteh.photonswordeoh")
    end
end

function PSEDevKit.arm(npc)
    npc = npc or PSEDevKit.nearest()
    if not npc then return say("No EoH NPC loaded") end
    local data = npc:getModData()
    data.PSE_rolled, data.PSE_armed = true, true
    local blade = npc:getInventory():getFirstTypeRecurse(PS.BLADE_TYPE) or npc:getInventory():AddItem(PS.BLADE_TYPE)
    PS.issueNpcBlade(blade, PS.npcBladeColor(PSE.id(npc), PSE.settings().BladeColor))
    npc:setPrimaryHandItem(blade)
    npc:setSecondaryHandItem(blade)
    say("Armed NPC " .. PSE.id(npc))
end

function PSEDevKit.strike(npc)
    npc = npc or PSEDevKit.nearest()
    local player = getPlayer()
    local weapon = player:getPrimaryHandItem()
    if not npc then return say("No EoH NPC loaded") end
    if not weapon or not instanceof(weapon, "HandWeapon") then return say("Hold a weapon first") end
    local before = PSE.hookCalls or 0
    local dealt = npc:Hit(weapon, player, 0.5, false, 1, false)
    say(string.format("Hit dealt %.2f; hook %s", dealt or 0, (PSE.hookCalls or 0) > before and "ran" or "did NOT run"))
end

function PSEDevKit.alwaysBlock()
    local vars = SandboxVars.PhotonSword
    saved = saved or { vars.NpcBlockChance, vars.NpcVsNpcBlockChance }
    vars.NpcBlockChance, vars.NpcVsNpcBlockChance = 100, 100
    say("NPC block chances at 100%")
end

function PSEDevKit.clear()
    if saved then
        SandboxVars.PhotonSword.NpcBlockChance, SandboxVars.PhotonSword.NpcVsNpcBlockChance = saved[1], saved[2]
        saved = nil
    end
    say("Dev kit cleared")
end
