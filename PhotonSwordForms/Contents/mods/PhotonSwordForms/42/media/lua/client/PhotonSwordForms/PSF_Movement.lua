-- Footwork during photon sword Form moves. Senator's arts get this from SWMA_PlayerMovement.lua,
-- whose list of arts is closed to other mods, so Forms have their own.
-- While a local player's move plays, the player holds a lease: the clip's root motion is switched
-- off, and a moving attack instead walks the player along their movement input at the Form's
-- footwork speed (SWMAFootworkSpeed, set by Senator's progression). A move started standing
-- keeps them in place. The lease ends a moment after the move does, and puts root motion back as
-- it was.

require "PhotonSword/PS_Core"
local PS = PhotonSword
local PSF = require "PhotonSwordForms/PSF_Forms"

local LINGER_MS = 160   -- the lease outlasts the move by this, so chained moves don't jolt between them

-- Vanilla's walking speeds while aiming (distance per frame at 30 fps), straight ahead, on the
-- diagonal, and sideways, walking and backpedaling, and the scale Senator's arts move at.
local WALK = { ahead = 0.590551, diagonal = 0.393701, side = 0.417323 }
local BACKPEDAL = { ahead = 0.295276, diagonal = 0.208661, side = 0.417323 }
local SCALE = 1.5 * 0.76 * 0.8

local leases = setmetatable({}, { __mode = "k" })   -- player -> { form, deferred, standing, endedAt }
local input = Vector2.new()

-- The speed of a step along the unit direction (x, y) in world space: vanilla's, blended between
-- its straight, diagonal, and sideways speeds by how far the step is from the player's facing.
local function stepSpeed(player, x, y)
    local f = player:getForwardDirection()
    local ahead = x * f:getX() + y * f:getY()
    local across = math.abs(x * f:getY() - y * f:getX())
    local along = math.abs(ahead)
    local speeds = (ahead < 0 and player:getVariableBoolean("SlowingMovement")) and BACKPEDAL or WALK
    local a, b
    if along >= across then
        local w = across / (0.55 * along + 0.45 * across)
        a, b = speeds.diagonal * w, speeds.ahead + (speeds.diagonal - speeds.ahead) * w
    else
        local w = along / (0.55 * across + 0.45 * along)
        a, b = speeds.side + (speeds.diagonal - speeds.side) * w, speeds.diagonal * w
    end
    return math.sqrt(a * a + b * b) * SCALE
end

local function release(player)
    local lease = leases[player]
    if not lease then return end
    player:setDeferredMovementEnabled(lease.deferred)
    leases[player] = nil
end

local function take(player, W)
    local lease = leases[player] or { deferred = player:isDeferredMovementEnabled() }
    leases[player] = lease
    lease.form, lease.endedAt = W, nil
    lease.standing = not player:getVariableBoolean("PSFAttackMoving")
    player:setDeferredMovementEnabled(false)
end

local function leaseOver(player, lease)
    if player:isDead() or player:getVehicle() or not IsoPlayer.isLocalPlayer(player)
            or not lease.form.eligible(player) then
        return true
    end
    if player:isAttacking() then
        lease.endedAt = nil
        return false
    end
    lease.endedAt = lease.endedAt or getTimestampMs()
    return getTimestampMs() - lease.endedAt >= LINGER_MS
end

-- Walks the player one frame along their movement input.
local function step(player)
    player:getInputMoveVector(input)
    -- The input is in screen space; the isometric view turns it 45 degrees from the world's.
    local x, y = input:getY() + input:getX(), input:getY() - input:getX()
    if player:isAnimatingBackwards() then x, y = -x, -y end
    local length = math.sqrt(x * x + y * y)
    if length < 0.0001 then return end
    x, y = x / length, y / length
    local footwork = math.max(0, player:getVariableFloat("SWMAFootworkSpeed", 0))
    local distance = stepSpeed(player, x, y) * footwork * getGameTime():getMultiplier() / 30
    player:moveUnmodded(x * distance, y * distance)
end

local function update(player)
    local lease = leases[player]
    if not lease then return end
    if leaseOver(player, lease) then release(player); return end
    player:setDeferredMovementEnabled(false)
    if not lease.standing and lease.deferred and player:pressedMovement(false) and player:isAiming() then
        step(player)
    end
end

for _, W in ipairs(PSF.forms) do
    -- Called by SWMA_MovingAttack's cancelAttack.
    function W.releaseMovement(player)
        local lease = leases[player]
        if lease and lease.form == W then release(player) end
    end

    local present = W.present
    W.present = function(player, ...)
        local results = PS.pack(present(player, ...))
        if results[1] and IsoPlayer.isLocalPlayer(player) then take(player, W) end
        return unpack(results, 1, results.n)
    end
end

Events.OnPlayerUpdate.Add(update)
Events.OnPlayerDeath.Add(release)
