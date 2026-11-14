-- Server authority for photon sword Forms (follows SWMK_Server.lua). Each Form's module syncs
-- its state, handles stance, move-toggle, and combo requests, approves moves and relays them to
-- other clients, and awards Martial Arts XP and mastery for its hits. The art's own module
-- syncs and changes which Form each player has active.

if isClient() then return end

local PSF = require "PhotonSwordForms/PSF_Forms"
local SMA = require "SMA_Core"

local requests = {}

-- Rate limits each player's requests of one kind; true if this one may go ahead.
local function allow(player, key, interval)
    local now = getTimestampMs()
    requests[player] = requests[player] or {}
    local last = requests[player][key]
    if last and now - last < interval then return false end
    requests[player][key] = now
    return true
end

function PSF.syncActive(player, recipient)
    if not isServer() then return end
    local args = { playerID = player:getOnlineID(), id = PSF.state(player).active or "" }
    if recipient then sendServerCommand(recipient, PSF.module, "active", args)
    else sendServerCommand(PSF.module, "active", args) end
end

-- Minimum time between requests of each kind from one player, per Form.
local INTERVALS = { sync = 500, move = 50, enabled = 100, moveEnabled = 100, form = 100 }

local function install(W)
    function W.sync(player, recipient)
        if not isServer() then return end
        local state = W.state(player)
        local args = { playerID = player:getOnlineID(), learned = state.learned == true,
            enabled = state.enabled ~= false, masteryXP = SMA.getMasteryXP(player, W.style),
            form = state.form or "", movePrefs = state.movePrefs or {} }
        if recipient then sendServerCommand(recipient, W.module, "state", args)
        else sendServerCommand(W.module, "state", args) end
    end

    local function onCommand(module, command, player, args)
        if module ~= W.module then return end
        if not player or not instanceof(player, "IsoPlayer") or type(args) ~= "table" then return end
        if not INTERVALS[command] or not allow(player, W.module .. command, INTERVALS[command]) then return end
        if command == "sync" then
            local players = getOnlinePlayers()
            for i = 0, players:size() - 1 do W.sync(players:get(i), player) end
        elseif command == "enabled" then
            if not W.setEnabled(player, args.enabled) then W.sync(player) end
        elseif command == "moveEnabled" then
            if not W.setMoveEnabled(player, args.id, args.enabled) then W.sync(player) end
        elseif command == "form" then
            W.setForm(player, args.id)
        elseif command == "move" then
            local moving = W.acceptMovingMode(player, args.id, args.moving)
            if moving ~= nil and W.progression.validClientToken(args.strikeToken)
                and W.acceptMove(player, args.id, args.form) then
                W.progression.bindClientStrike(W, player, args.strikeToken)
                sendServerCommand(W.module, "move", { playerID = player:getOnlineID(), id = args.id,
                    form = player:getVariableString("PSFForm"), moving = moving })
            else
                W.progression.finishStrike(player)
            end
        end
    end

    local function award(player, weapon, zombie)
        W.progression.nativeHit(W, player, weapon, zombie)
    end

    Events.OnClientCommand.Add(onCommand)
    Events.OnWeaponHitXp.Add(function(player, weapon, zombie)
        if isServer() then award(player, weapon, zombie) end
    end)
    Events.OnHitZombie.Add(function(zombie, player, bodyPart, weapon)
        if not isServer() then award(player, weapon, zombie) end
    end)
    Events.OnPlayerDeath.Add(W.clear)
end

for _, W in ipairs(PSF.forms) do install(W) end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= PSF.module then return end
    if not player or not instanceof(player, "IsoPlayer") or type(args) ~= "table" then return end
    if command == "sync" and allow(player, "artsync", 500) then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do PSF.syncActive(players:get(i), player) end
    elseif command == "select" and allow(player, "select", 100) then
        if not PSF.select(player, args.id) then PSF.syncActive(player) end
    end
end)

Events.OnPlayerDeath.Add(function(player)
    requests[player] = nil
end)
Events.EveryOneMinute.Add(function()
    requests = {}
end)
