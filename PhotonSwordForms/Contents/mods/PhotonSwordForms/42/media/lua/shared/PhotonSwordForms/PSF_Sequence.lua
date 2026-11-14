-- Authoritative move sequence for a photon sword Form (follows SWMK_Sequence.lua): the server,
-- or a single-player game, accepts each requested move only if it's the next step of the
-- player's selected combo, arrives in time, and isn't spammed faster than its clip runs.
-- PSF.define installs it on each Form.

local Sequence = {}

function Sequence.install(W)
    local moves = setmetatable({}, { __mode = "k" })
    local serial = 0

    function W.resetSequence(player)
        moves[player] = nil
    end

    function W.acceptedStrike(player)
        local move = moves[player]
        if move and getTimestampMs() - move.time <= W.progression.timingWindow(W, W.comboTimeout)
            and move.weapon == player:getPrimaryHandItem() and move.offhand == player:getSecondaryHandItem()
            and W.allowedForm(player, move.form) then return move.serial end
        return nil
    end

    function W.acceptMove(player, id, token)
        if isClient() or not W.eligible(player) or not W.allowedMove(player, id) or not W.canStartMove(player, id) then
            return false
        end
        local form, index = W.parseForm(token)
        if not form or not W.allowedForm(player, form) or form ~= W.selectedForm(player)
            or W.forms[form].moves[index] ~= id or not W.isMoveEnabled(player, id) then return false end
        local now = getTimestampMs()
        local prior = moves[player]
        if prior and W.moves[prior.id]
            and now - prior.time < W.moves[prior.id].minRequestMs / W.progression.attackScale(W, player) then
            return false
        end
        if not W.cycleStart(W.forms[form].moves, index, W.forms[form])
            and (not prior or prior.form ~= form or prior.index + 1 ~= index
                or prior.weapon ~= player:getPrimaryHandItem() or prior.offhand ~= player:getSecondaryHandItem()
                or now - prior.time > W.progression.timingWindow(W, W.comboTimeout)) then
            return false
        end
        serial = serial + 1
        moves[player] = { id = id, index = index, form = form, serial = serial, time = now,
            weapon = player:getPrimaryHandItem(), offhand = player:getSecondaryHandItem() }
        W.progression.beginStrike(W, player, id)
        player:setVariable("PSFForm", token)
        return true
    end

    Events.OnPlayerDeath.Add(W.resetSequence)
end

return Sequence
