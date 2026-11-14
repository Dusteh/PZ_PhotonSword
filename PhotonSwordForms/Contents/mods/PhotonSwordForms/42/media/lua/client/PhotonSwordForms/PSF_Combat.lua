-- Client combat events for photon sword Forms (follows SWMK_Combat.lua and SWMA_GuardPeers.lua):
-- each swing of an eligible local player starts the next move of their active Form and asks the
-- server to approve it; the server's state and remote players' moves arrive as server commands.

local PSF = require "PhotonSwordForms/PSF_Forms"
require "PhotonSwordForms/PSF_Combos"
local RX = require "SWMA_RemoteExpiry"
local SMA = require "SMA_Core"

local function requestSync(player)
    if not isClient() or not player then return end
    sendClientCommand(player, PSF.module, "sync", {})
    for _, W in ipairs(PSF.forms) do sendClientCommand(player, W.module, "sync", {}) end
end

Events.OnCreatePlayer.Add(function(slot, player)
    requestSync(player)
end)

Events.OnGameStart.Add(function()
    for slot = 0, getNumActivePlayers() - 1 do requestSync(getSpecificPlayer(slot)) end
end)

-- Forms share the PSF* variables, so inactive Forms (which clear them once on going inactive)
-- update before the active one sets them.
local function updateHolds(player)
    local active = PSF.activeForm(player)
    for _, W in ipairs(PSF.forms) do
        if W ~= active then W.updateHoldIfNeeded(player) end
    end
    if active then active.updateHoldIfNeeded(player) end
    return active
end

Events.OnPlayerUpdate.Add(function(player)
    local active = updateHolds(player)
    RX.expire(player, "PSF")
    if active then active.updateCombo(player) end
end)

-- Remote players don't get OnPlayerUpdate on this client; keep their stance variables current.
local tick = 0
Events.OnTick.Add(function()
    tick = tick + 1
    if tick % 3 ~= 0 or not isClient() then return end
    local players = getOnlinePlayers()
    if not players then return end
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player and not IsoPlayer.isLocalPlayer(player) then updateHolds(player) end
    end
end)

Events.OnWeaponSwing.Add(function(player, weapon)
    if not IsoPlayer.isLocalPlayer(player) then return end
    local W = PSF.activeForm(player)
    if not W or not W.eligible(player, weapon) then return end
    local id = W.selectComboMove(player, weapon)
    if W.present(player, id) then
        local token = player:getVariableString("PSFForm")
        if isClient() then
            sendClientCommand(player, W.module, "move", { strikeToken = W.progression.presentationToken(W, player),
                id = id, form = token, moving = player:getVariableBoolean("PSFAttackMoving") })
        else
            W.acceptMove(player, id, token)
        end
    end
end)

-- Only the active Form finishes a combo; another Form's reset would clear the shared variables.
Events.OnPlayerAttackFinished.Add(function(player)
    local W = player and PSF.activeForm(player)
    if W then W.finishCombo(player) end
end)

local function onFormCommand(W, command, player, args)
    if command == "state" and type(args.learned) == "boolean" and type(args.enabled) == "boolean"
        and type(args.masteryXP) == "number" and args.masteryXP - args.masteryXP == 0 then
        local state = W.state(player)
        state.learned, state.enabled = args.learned, args.enabled
        if type(args.movePrefs) == "table" then state.movePrefs = args.movePrefs end
        SMA.getState(player).mastery[W.style.id] = math.max(0,
            math.min(SMA.masteryThresholds[#SMA.masteryThresholds], args.masteryXP))
        if args.form == "" or type(args.form) == "string" and W.forms[args.form] then
            state.form = args.form ~= "" and args.form or nil
        end
        -- An inactive Form's variables belong to the active Form; leave them alone.
        if PSF.activeForm(player) == W and not W.eligible(player) then W.clear(player) end
    elseif command == "move" and not IsoPlayer.isLocalPlayer(player) then
        RX.mark(player, "PSF")
        W.present(player, args.id, args.form, true, args.moving)
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if type(args) ~= "table" or type(args.playerID) ~= "number" then return end
    local W
    if module ~= PSF.module then
        for _, form in ipairs(PSF.forms) do
            if module == form.module then W = form; break end
        end
        if not W then return end
    end
    local player = getPlayerByOnlineID(args.playerID)
    if not player then return end
    if W then
        onFormCommand(W, command, player, args)
    elseif command == "active" and (args.id == "" or PSF.byId[args.id]) then
        PSF.state(player).active = args.id ~= "" and args.id or nil
    end
end)
