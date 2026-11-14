-- Client combo driver for photon sword Forms. Each swing with a Form plays the next move of the
-- selected Form's combo. Pressing attack again during a move queues the one after, which plays
-- when the move ends; a move that runs to its end flows on into the next by itself, unless the
-- Form breaks the combo there. The combo is dropped when the player lets go of aim, shoves, aims
-- at the floor, turns away, changes what's in their hands, or can no longer fight with the Form.
-- Senator's arts call these from their Combat files (W.selectComboMove, W.updateCombo,
-- W.finishCombo); PSF_Combat.lua does the same for Forms, and the timings match Senator's so
-- Forms chain like Senator's arts. Installed on every Form.

local PSF = require "PhotonSwordForms/PSF_Forms"

local QUEUE_AFTER_MS = 120   -- a press this soon after a move starts doesn't queue the next one
local CHAIN_MS = 300         -- how long the next move has to start once a move ends
local IDLE_MS = 1000         -- a combo with no move playing this long is dropped

local function facingSame(player, combo)
    return player:getForwardDirectionX() * combo.fx + player:getForwardDirectionY() * combo.fy > 0.5
end

-- The same weapon (the one being swung, or the one in hand), off hand, and facing the combo began with.
local function gripSame(player, combo, weapon)
    return combo.weapon == (weapon or player:getPrimaryHandItem())
        and combo.offhand == player:getSecondaryHandItem() and facingSame(player, combo)
end

local function stillAiming(player)
    return player:isAnyAimKeyDown() and not player:isDoShove() and not player:isAimAtFloor()
end

local function install(W)
    -- A player's combo: what they held and faced when it began, the Form, the move playing (its
    -- index in the Form's moves, and id), the attack button's state, and once the move has ended
    -- and the next is on its way, chainBy (the time it has to start by).
    local combos = setmetatable({}, { __mode = "k" })

    local function begin(player, weapon, form)
        local combo = { weapon = weapon, offhand = player:getSecondaryHandItem(), form = form, index = 0,
            fx = player:getForwardDirectionX(), fy = player:getForwardDirectionY() }
        combos[player] = combo
        return combo
    end

    -- The combo this swing carries on, if one is waiting for it.
    local function waiting(player, weapon, form, now)
        local combo = combos[player]
        if combo and combo.chainBy and now <= combo.chainBy and combo.form == form
                and combo.index < #W.forms[form].moves and W.allowedForm(player, form)
                and gripSame(player, combo, weapon) then
            return combo
        end
    end

    local function holds(player, combo)
        return gripSame(player, combo) and stillAiming(player) and W.eligible(player)
            and W.allowedForm(player, combo.form) and W.selectedForm(player) == combo.form
    end

    -- Whether the move that just ended chains on: the next was queued, or the move ran to its end
    -- and the Form flows on from it. A move marked completionRequired must have run to its end.
    local function chainsOn(player, combo)
        local form, move = W.forms[combo.form], W.moves[combo.id]
        if not form then return false end
        local completed = player:getVariableString("PSFCompleted") == combo.id
        local flows = completed and form.moves[combo.index + 1] ~= nil and not (form.breaks and form.breaks[combo.index])
        if not (combo.queued or flows) then return false end
        if move and move.completionRequired == true and not completed then return false end
        return not W.progression.pending[player] and holds(player, combo)
    end

    function W.resetCombo(player)
        if not player then return end
        combos[player] = nil
        player:setVariable("PSFActive", false)
        player:setVariable("PSFMove", "")
        player:setVariable("PSFForm", "")
        player:setVariable("PSFCompleted", "")
        W.updateHold(player)
    end

    function W.selectComboMove(player, weapon)
        local now, selected = getTimestampMs(), W.selectedForm(player)
        local combo = waiting(player, weapon, selected, now) or begin(player, weapon, selected)
        local form = W.forms[combo.form]
        local index = W.cycleAdvance(player, form.moves, combo.index, form)
        if not index then W.cancelAttack(player); return nil end
        W.cycleRemember(player, form.moves, index, form)
        combo.index, combo.id, combo.started = index, form.moves[index], now
        combo.queued, combo.chainBy, combo.released, combo.cut = false, nil, false, false
        combo.pressed = player:isAttackButtonDown()
        player:setVariable("PSFCompleted", "")
        player:setVariable("PSFForm", W.formToken(combo.form, index))
        return combo.id
    end

    function W.queueCombo(player)
        local combo = combos[player]
        if not combo or getTimestampMs() - combo.started < QUEUE_AFTER_MS or not gripSame(player, combo)
                or not W.eligible(player) or not W.allowedForm(player, combo.form) then
            return false
        end
        local form = W.forms[combo.form]
        if combo.index < #form.moves and not W.cycleStart(form.moves, combo.index + 1, form) then return false end
        combo.queued = true
        return true
    end

    function W.finishCombo(player)
        if not player then return end
        local combo = combos[player]
        if combo and combo.chainBy then return end
        if combo and chainsOn(player, combo) then
            combo.chainBy = getTimestampMs() + CHAIN_MS
            player:DoAttack(0)
        else
            W.resetCombo(player)
        end
    end

    function W.updateCombo(player)
        if not IsoPlayer.isLocalPlayer(player) then return end
        local combo = combos[player]
        if not combo then return end
        if not holds(player, combo) then W.resetCombo(player); return end

        -- A fresh press (after letting go since the move started) queues the next move.
        local down = player:isAttackButtonDown()
        if not down then
            combo.released = true
        elseif not combo.pressed and combo.released then
            W.queueCombo(player)
        end
        combo.pressed = down

        -- A move's clip sets PSFCompleted near its end; cut the remaining recovery there.
        local move = W.moves[combo.id]
        if move and move.completionRequired and not combo.cut and player:isAttacking()
                and player:getVariableString("PSFCompleted") == combo.id then
            combo.cut = true
            player:setVariable("AttackAnim", false)
            player:reportEvent("ActiveAnimFinishing")
            if combos[player] ~= combo then return end
        end

        local now = getTimestampMs()
        if not combo.chainBy then
            if not player:isAttacking() and now - combo.started > IDLE_MS then W.resetCombo(player) end
        elseif now > combo.chainBy then
            W.resetCombo(player)
        elseif not player:isAttacking() then
            player:DoAttack(0)
        end
    end

    Events.OnPlayerDeath.Add(W.resetCombo)
end

for _, W in ipairs(PSF.forms) do install(W) end
