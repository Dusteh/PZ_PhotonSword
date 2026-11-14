-- Client combo driver for photon sword Forms (follows SWMK_Combos.lua): picks the next move of
-- the selected combo on each swing, queues a follow-up when attack is pressed again during a
-- move, and plays it when the move finishes. Releasing aim, turning away, shoving, or changing
-- weapons drops the combo. Installed on every Form.

local PSF = require "PhotonSwordForms/PSF_Forms"

local function sameFacing(player, state)
    return player:getForwardDirectionX() * state.fx + player:getForwardDirectionY() * state.fy > 0.5
end

local function install(W)
    local sessions = {}

    function W.resetCombo(player)
        if player then
            sessions[player:getPlayerNum()] = nil
            player:setVariable("PSFActive", false)
            player:setVariable("PSFMove", "")
            player:setVariable("PSFForm", "")
            player:setVariable("PSFCompleted", "")
            W.updateHold(player)
        end
    end

    function W.selectComboMove(player, weapon)
        local slot, now = player:getPlayerNum(), getTimestampMs()
        local state = sessions[slot]
        local selected = W.selectedForm(player)
        if not state or not state.ready or state.player ~= player or state.weapon ~= weapon
            or state.offhand ~= player:getSecondaryHandItem() or state.form ~= selected
            or now > state.ready or not W.allowedForm(player, state.form)
            or state.index >= #W.forms[state.form].moves or not sameFacing(player, state) then
            state = { player = player, weapon = weapon, offhand = player:getSecondaryHandItem(), index = 0,
                form = selected, fx = player:getForwardDirectionX(), fy = player:getForwardDirectionY() }
            sessions[slot] = state
        end
        local chain = W.forms[state.form].moves
        state.index = W.cycleAdvance(player, chain, state.index, W.forms[state.form])
        if not state.index then W.cancelAttack(player); return nil end
        W.cycleRemember(player, chain, state.index, W.forms[state.form])
        state.last, state.queued, state.ready, state.released, state.finished = now, false, false, false, false
        state.endpointReported = false
        state.down = player:isAttackButtonDown()
        state.id = chain[state.index]
        player:setVariable("PSFCompleted", "")
        player:setVariable("PSFForm", W.formToken(state.form, state.index))
        return state.id
    end

    function W.queueCombo(player)
        local state = sessions[player:getPlayerNum()]
        if not state or state.player ~= player or state.weapon ~= player:getPrimaryHandItem()
            or state.offhand ~= player:getSecondaryHandItem()
            or not W.eligible(player) or not sameFacing(player, state)
            or not W.allowedForm(player, state.form)
            or (state.index < #W.forms[state.form].moves
                and not W.cycleStart(W.forms[state.form].moves, state.index + 1, W.forms[state.form]))
            or getTimestampMs() - state.last < 120 then return false end
        state.queued = true
        return true
    end

    function W.finishCombo(player)
        if not player then return end
        local state = sessions[player:getPlayerNum()]
        if state and state.finished then return end
        local move = state and W.moves[state.id]
        local sourceStage = move and move.completionRequired == true
        local completed = state and player:getVariableString("PSFCompleted") == state.id
        local form = state and W.forms[state.form]
        local followThrough = completed and form and form.moves[state.index + 1]
            and not (form.breaks and form.breaks[state.index])
        if state and not W.progression.pending[player] and state.player == player and (state.queued or followThrough)
            and state.weapon == player:getPrimaryHandItem() and state.offhand == player:getSecondaryHandItem()
            and (not sourceStage or completed) and W.eligible(player)
            and W.allowedForm(player, state.form) and W.selectedForm(player) == state.form
            and not state.finished
            and not player:isDoShove() and sameFacing(player, state)
            and not player:isAimAtFloor() and player:isAnyAimKeyDown() then
            state.finished = true
            state.ready = getTimestampMs() + 300
            player:DoAttack(0)
        else
            W.resetCombo(player)
        end
    end

    function W.updateCombo(player)
        if not IsoPlayer.isLocalPlayer(player) then return end
        local state = sessions[player:getPlayerNum()]
        if not state then return end
        if not W.eligible(player) or state.weapon ~= player:getPrimaryHandItem()
            or state.offhand ~= player:getSecondaryHandItem()
            or not W.allowedForm(player, state.form) or W.selectedForm(player) ~= state.form
            or not sameFacing(player, state) or player:isDoShove()
            or player:isAimAtFloor()
            or not player:isAnyAimKeyDown() then
            W.resetCombo(player)
            return
        end
        local down = player:isAttackButtonDown()
        if not down then state.released = true end
        if down and not state.down and state.released then W.queueCombo(player) end
        state.down = down
        -- A move's clip sets PSFCompleted near its end; cut the remaining recovery there.
        if W.moves[state.id].completionRequired and not state.endpointReported
            and player:getVariableString("PSFCompleted") == state.id and player:isAttacking() then
            state.endpointReported = true
            player:setVariable("AttackAnim", false)
            player:reportEvent("ActiveAnimFinishing")
            if sessions[player:getPlayerNum()] ~= state then return end
        end
        if not state.ready and not state.finished and not player:isAttacking()
            and getTimestampMs() - state.last > 1000 then
            W.resetCombo(player)
            return
        end
        if state.ready then
            if getTimestampMs() > state.ready then
                W.resetCombo(player); player:setVariable("PSFMove", "")
            elseif not player:isAttacking() then
                player:DoAttack(0)
            end
        end
    end

    Events.OnCreatePlayer.Add(function(slot) sessions[slot] = nil end)
    Events.OnGameStart.Add(function() sessions = {} end)
    Events.OnPlayerDeath.Add(W.resetCombo)
end

for _, W in ipairs(PSF.forms) do install(W) end
