-- Footwork during photon sword Form moves (follows SWMA_PlayerMovement.lua, whose list of arts
-- is closed to other mods). While a local player's move plays, the clip's root motion is
-- switched off; a moving attack instead walks the player along their movement input at the
-- art's footwork speed. Standing-only moves (or any move started standing) keep them in place.

local PSF = require "PhotonSwordForms/PSF_Forms"

local leases = setmetatable({}, { __mode = "k" })
local delta = Vector2.new()
local motionScale = 0.76

local function restore(player, lease)
    player:setDeferredMovementEnabled(lease.enabled)
    leases[player] = nil
end

-- Distance per frame for movement input (x, y), matching vanilla strafing speeds.
local function inputSpeed(player, x, y)
    local f = player:getForwardDirection()
    local forward = x * f:getX() + y * f:getY()
    local side = math.abs(x * f:getY() - y * f:getX())
    local along = math.abs(forward)
    local slow = forward < 0 and player:getVariableBoolean("SlowingMovement")
    local straight = slow and 0.295276 or 0.590551
    local diagonal = slow and 0.208661 or 0.393701
    local weight, sx, sy
    if along >= side then
        weight = side / (0.55 * along + 0.45 * side)
        sx, sy = diagonal * weight, straight * (1 - weight) + diagonal * weight
    else
        weight = along / (0.55 * side + 0.45 * along)
        sx, sy = 0.417323 * (1 - weight) + diagonal * weight, diagonal * weight
    end
    return math.sqrt(sx * sx + sy * sy) * 1.5 * motionScale * 0.8
end

local function update(player)
    local lease = leases[player]
    if not lease then return end
    if player:isDead() or player:getVehicle() or not IsoPlayer.isLocalPlayer(player) or not lease.form.eligible(player) then
        restore(player, lease); return
    end
    if not player:isAttacking() then
        if not lease.ending then lease.ending = getTimestampMs() end
        if getTimestampMs() - lease.ending >= 160 then restore(player, lease); return end
    else
        lease.ending = nil
    end
    player:setDeferredMovementEnabled(false)
    if lease.stationary or not lease.enabled or not player:pressedMovement(false) or not player:isAiming() then return end
    player:getInputMoveVector(delta)
    local x, y = delta:getY() + delta:getX(), delta:getY() - delta:getX()
    if player:isAnimatingBackwards() then x, y = -x, -y end
    local length = math.sqrt(x * x + y * y)
    if length < 0.0001 then return end
    x, y = x / length, y / length
    local footwork = math.max(0, player:getVariableFloat("SWMAFootworkSpeed", 0))
    local distance = inputSpeed(player, x, y) * footwork * getGameTime():getMultiplier() / 30
    player:moveUnmodded(x * distance, y * distance)
end

local function install(W)
    -- Called by SWMA_MovingAttack's cancelAttack.
    function W.releaseMovement(player)
        local lease = leases[player]
        if lease and lease.form == W then restore(player, lease) end
    end

    local present = W.present
    W.present = function(player, ...)
        local accepted = present(player, ...)
        if accepted and IsoPlayer.isLocalPlayer(player) then
            local lease = leases[player]
            if not lease then
                lease = { enabled = player:isDeferredMovementEnabled() }
                leases[player] = lease
            end
            lease.form, lease.ending = W, nil
            lease.stationary = not player:getVariableBoolean("PSFAttackMoving")
            player:setDeferredMovementEnabled(false)
        end
        return accepted
    end
end

for _, W in ipairs(PSF.forms) do install(W) end

Events.OnPlayerUpdate.Add(update)
Events.OnPlayerDeath.Add(function(player)
    if leases[player] then restore(player, leases[player]) end
end)
