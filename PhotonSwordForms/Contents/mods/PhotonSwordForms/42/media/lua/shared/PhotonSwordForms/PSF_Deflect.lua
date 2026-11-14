-- Deflecting gunfire with a Form: Photon Sword's deflect (PS_Deflect.lua: the rolls, soaks, striking
-- back, and multiplayer sync) with a Form's guard in place of its ready stance. For a player whose
-- active Form can guard (PSF.guardingForm), the guard is Martial Arts Core's block held with the
-- ignited sword (past Core's startup, not broken, within Core's arc), guard skill is half the
-- Form's mastery and half the Martial Arts level, and each deflection drains the guard meter as
-- Core's block does (SMA.guardDrain, scaled by the GuardDrainMultiplier sandbox option); one the
-- meter can't pay for breaks the guard and the shot lands. Anyone else keeps Photon Sword's rules.

local SMA = require "SMA_Core"
require "SMA_Guard"
require "PhotonSword/PS_Deflect"
local PSF = require "PhotonSwordForms/PSF_Settings"
local PS = PhotonSword

-- Each hook takes the Form's rule for a player with a guarding Form, and Photon Sword's otherwise.
local function formHook(name, rule)
    local base = PS[name]
    PS[name] = function(player, ...)
        if PSF.guardingForm(player) then return rule(player, ...) end
        return base(player, ...)
    end
end

formHook("guardUp", function(player, now)
    local g = SMA.guardState(player)
    return g.active and now >= g.brokenUntil and now >= g.since + SMA.guardConfig.startupMs
end)

formHook("guardFacing", function(player)
    local g = SMA.guardState(player)
    -- The server knows where a client's guard faces from Core's guardFace commands.
    if isServer() and g.fx then return g.fx, g.fy, SMA.guardConfig.arcDot end
    local f = player:getForwardDirection()
    return f:getX(), f:getY(), SMA.guardConfig.arcDot
end)

formHook("guardSkill", function(player)
    local W = PSF.guardingForm(player)
    local top = #SMA.masteryThresholds
    local mastery = math.min(top, W.mastery(player))
    return (mastery / top + SMA.getLevel(player) / 10) / 2, mastery >= top
end)

-- guardDrain's player is the defender, its second argument.
local guardDrain = PS.guardDrain
function PS.guardDrain(attacker, player, weapon)
    if PSF.guardingForm(player) then
        return SMA.guardDrain(attacker, player, weapon) * PSF.sandbox("GuardDrainMultiplier")
    end
    return guardDrain(attacker, player, weapon)
end

-- With authority over the meter: takes drain from it, or breaks the guard if it can't pay.
formHook("drainGuard", function(player, drain, now)
    local g = SMA.guardState(player)
    if g.meter - drain <= 0 then
        SMA.onGuardBreak(player, now)
        if isServer() then sendServerCommand(SMA.module, "guardBreak", { playerID = player:getOnlineID() }) end
        return false
    end
    g.meter, g.lastHit = g.meter - drain, now
    if isServer() then
        sendServerCommand(player, SMA.module, "guardHit",
            { playerID = player:getOnlineID(), meter = math.floor(g.meter), fresh = false })
    else
        SMA.onGuardHit(player, g.meter, false)
    end
    return true
end)

-- On a client, until the server settles the meter: go by this client's copy of it.
formHook("guardPays", function(player, drain)
    local g = SMA.guardState(player)
    if g.meter - drain <= 0 then return false end
    g.meter = g.meter - drain
    return true
end)

return PSF
