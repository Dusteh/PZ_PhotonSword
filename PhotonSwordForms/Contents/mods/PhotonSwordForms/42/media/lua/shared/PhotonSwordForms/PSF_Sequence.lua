-- Move approval for a photon sword Form. The server (or a single-player game) decides which move
-- a player may play. A requested move must be the move the player's selected Form has at that
-- step, enabled and startable. It must not come faster than the last approved move's clip
-- allows. And it must be a step a combo can start from, or the step straight after the last
-- approved one, made with the same weapons and within the combo window. Each approval gets a
-- serial, which the hits it lands are checked against (W.acceptedStrike). PSF.define installs it
-- on each Form; Senator's arts have their own (SWMK_Sequence.lua for the katana).

local Sequence = {}

function Sequence.install(W)
    local approved = setmetatable({}, { __mode = "k" })   -- player -> the last move approved for them
    local serials = 0

    local function heldSince(player, record)
        return record.weapon == player:getPrimaryHandItem() and record.offhand == player:getSecondaryHandItem()
    end

    local function inWindow(record, now)
        return now - record.time <= W.progression.timingWindow(W, W.comboTimeout)
    end

    -- The Form and step a request names, if the player may play that move now.
    local function requested(player, id, token)
        if isClient() or not (W.eligible(player) and W.allowedMove(player, id) and W.canStartMove(player, id)) then
            return nil
        end
        local form, index = W.parseForm(token)
        if not form or form ~= W.selectedForm(player) or not W.allowedForm(player, form) then return nil end
        if W.forms[form].moves[index] ~= id or not W.isMoveEnabled(player, id) then return nil end
        return form, index
    end

    -- Whether a request comes sooner after the last approval than that move's clip can play.
    local function tooSoon(player, last, now)
        local move = last and W.moves[last.id]
        return move ~= nil and now - last.time < move.minRequestMs / W.progression.attackScale(W, player)
    end

    local function mayFollow(player, last, form, index, now)
        if W.cycleStart(W.forms[form].moves, index, W.forms[form]) then return true end
        return last ~= nil and last.form == form and last.index + 1 == index
            and heldSince(player, last) and inWindow(last, now)
    end

    function W.acceptMove(player, id, token)
        local form, index = requested(player, id, token)
        if not form then return false end
        local now, last = getTimestampMs(), approved[player]
        if tooSoon(player, last, now) or not mayFollow(player, last, form, index, now) then return false end
        serials = serials + 1
        approved[player] = { id = id, form = form, index = index, serial = serials, time = now,
            weapon = player:getPrimaryHandItem(), offhand = player:getSecondaryHandItem() }
        W.progression.beginStrike(W, player, id)
        player:setVariable("PSFForm", token)
        return true
    end

    -- The serial of the move a hit belongs to, while that move still stands.
    function W.acceptedStrike(player)
        local last = approved[player]
        if last and inWindow(last, getTimestampMs()) and heldSince(player, last) and W.allowedForm(player, last.form) then
            return last.serial
        end
        return nil
    end

    function W.resetSequence(player)
        approved[player] = nil
    end

    Events.OnPlayerDeath.Add(W.resetSequence)
end

return Sequence
