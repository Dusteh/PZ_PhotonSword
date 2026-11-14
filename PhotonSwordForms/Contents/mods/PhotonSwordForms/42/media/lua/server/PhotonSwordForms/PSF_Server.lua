-- Server authority for photon sword Forms. Each Form's module sends its state to clients,
-- handles their requests (state, Enable/Disable, move toggles, combo choice, and moves), approves
-- moves (PSF_Sequence.lua) and relays them to the other clients, and awards Martial Arts XP and
-- mastery for its hits. The art's own module sends and changes which Form each player has
-- active. Every request kind is rate limited per player.

if isClient() then return end

local PSF = require "PhotonSwordForms/PSF_Forms"
local SMA = require "SMA_Core"

local lastRequest = {}   -- player -> request key -> time

local function allow(player, key, ms)
    local now = getTimestampMs()
    local times = lastRequest[player] or {}
    lastRequest[player] = times
    if times[key] and now - times[key] < ms then return false end
    times[key] = now
    return true
end

-- To one client (recipient), or to every client.
local function send(module, command, args, recipient)
    if recipient then
        sendServerCommand(recipient, module, command, args)
    else
        sendServerCommand(module, command, args)
    end
end

-- Sends the requester every online player's state, through sync(player, recipient).
local function sendEveryone(sync, requester)
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do sync(players:get(i), requester) end
end

-- An OnClientCommand handler for module. commands maps each command name to { ms, handle };
-- handle(player, args) runs unless the player sent that command less than ms ago.
local function commandHandler(module, commands)
    return function(from, command, player, args)
        if from ~= module then return end
        local entry = commands[command]
        if not entry or not player or not instanceof(player, "IsoPlayer") or type(args) ~= "table" then return end
        if allow(player, module .. "/" .. command, entry.ms) then entry.handle(player, args) end
    end
end

function PSF.syncActive(player, recipient)
    if not isServer() then return end
    send(PSF.module, "active", { playerID = player:getOnlineID(), id = PSF.state(player).active or "" }, recipient)
end

local function install(W)
    function W.sync(player, recipient)
        if not isServer() then return end
        local state = W.state(player)
        send(W.module, "state", {
            playerID = player:getOnlineID(),
            learned = state.learned == true,
            enabled = state.enabled ~= false,
            masteryXP = SMA.getMasteryXP(player, W.style),
            form = state.form or "",
            movePrefs = state.movePrefs or {},
        }, recipient)
    end

    -- A change the server refuses is answered with the player's actual state.
    local function change(apply)
        return function(player, args)
            if not apply(player, args) then W.sync(player) end
        end
    end

    -- Approves a move and relays it to every client; otherwise ends the strike the client began.
    local function requestMove(player, args)
        local moving = W.acceptMovingMode(player, args.id, args.moving)
        local approved = moving ~= nil and W.progression.validClientToken(args.strikeToken)
            and W.acceptMove(player, args.id, args.form)
        if not approved then
            W.progression.finishStrike(player)
            return
        end
        W.progression.bindClientStrike(W, player, args.strikeToken)
        send(W.module, "move", { playerID = player:getOnlineID(), id = args.id, moving = moving,
            form = player:getVariableString("PSFForm") })
    end

    Events.OnClientCommand.Add(commandHandler(W.module, {
        sync = { ms = 500, handle = function(player) sendEveryone(W.sync, player) end },
        enabled = { ms = 100, handle = change(function(player, args) return W.setEnabled(player, args.enabled) end) },
        moveEnabled = { ms = 100, handle = change(function(player, args)
            return W.setMoveEnabled(player, args.id, args.enabled)
        end) },
        form = { ms = 100, handle = function(player, args) W.setForm(player, args.id) end },
        move = { ms = 50, handle = requestMove },
    }))

    -- XP and mastery for the Form's hits: from the server's hit XP in multiplayer, and from the
    -- hit itself in single player.
    Events.OnWeaponHitXp.Add(function(player, weapon, zombie)
        if isServer() then W.progression.nativeHit(W, player, weapon, zombie) end
    end)
    Events.OnHitZombie.Add(function(zombie, player, _, weapon)
        if not isServer() then W.progression.nativeHit(W, player, weapon, zombie) end
    end)
    Events.OnPlayerDeath.Add(W.clear)
end

for _, W in ipairs(PSF.forms) do install(W) end

Events.OnClientCommand.Add(commandHandler(PSF.module, {
    sync = { ms = 500, handle = function(player) sendEveryone(PSF.syncActive, player) end },
    select = { ms = 100, handle = function(player, args)
        if not PSF.select(player, args.id) then PSF.syncActive(player) end
    end },
}))

-- Core's blocks (PSF.newCoreBlock), which only the server can tell from Photon Sword's drains: every
-- client, the blocker's own too, gets a "parry" to play on that player.
local seenCoreBlocks = setmetatable({}, { __mode = "k" })
local tick = 0
Events.OnTick.Add(function()
    tick = tick + 1
    if not isServer() or tick % 3 ~= 0 then return end
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if PSF.newCoreBlock(player, seenCoreBlocks) and PSF.guardingForm(player) then
            send(PSF.module, "parry", { playerID = player:getOnlineID() })
        end
    end
end)

Events.OnPlayerDeath.Add(function(player)
    lastRequest[player] = nil
end)
Events.EveryOneMinute.Add(function()
    lastRequest = {}
end)
