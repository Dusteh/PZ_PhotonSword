-- Deflecting gunfire: a raised guard has a chance to turn a bullet back on whoever fired it, and
-- soaks part of a shotgun blast (too wide to send back). Both go by the defender's guard skill
-- (PS.guardSkill, 0-1): a bullet's chance slides between the sandbox's DeflectChanceMin and Max with
-- it, a blast's soaked share between SoakMin and SoakMax, and at full skill there's a SoakFullChance
-- percent chance the guard takes the whole blast. The shooter must be in front of the guard. A
-- blast's pellets arrive together and count as one shot (VOLLEY_MS).
--
-- The guard is the ready stance (aiming the ignited sword in both hands; PS.readyStance), skill is
-- the Long Blade level, and nothing drains. Another mod can change what the guard is with the hooks
-- below (Photon Sword Forms makes it a Form's Martial Arts Core block, with mastery for skill and
-- Core's meter to drain):
--   PS.guardUp(player, now)                 whether player's guard is raised
--   PS.guardFacing(player)                  where it faces (x, y) and how wide (the cosine of its half-arc)
--   PS.guardSkill(player)                   skill 0-1, and whether it's full
--   PS.guardDrain(attacker, player, weapon) what a deflection costs the guard
--   PS.drainGuard(player, drain, now)       with authority: pay it; false if the guard broke instead
--   PS.guardPays(player, drain)             on a client, before the server answers: whether it could
--
-- Players' fire (vanilla firearms, multiplayer) is decided on the server (or in single player) from
-- OnWeaponHitCharacter: the bullet's damage is avoided, and the shooter takes a bullet wound, synced
-- with sendDamage. Clients hear and see it from a server command. Other mods' gunfire comes in
-- through PS.judgeShot (where the guard is settled: single player or the server), PS.judgeLocalShot
-- (a client firing at its own player, asking the server to settle with a "deflect" command), PS.soak,
-- and PS.strikeBack. The patch mods Photon Sword - Bandits and Photon Sword - Project A-Life do.

require "PhotonSword/PS_Core"
local PS = PhotonSword

local VOLLEY_MS = 150
local ARC = .25   -- the guard takes shots within about 75 degrees either side of where it faces
-- Where a deflected bullet strikes a shooting player.
local WOUND_PARTS = { "Torso_Upper", "Torso_Lower", "UpperArm_L", "UpperArm_R", "ForeArm_L", "ForeArm_R",
    "UpperLeg_L", "UpperLeg_R" }
local AUTH = not isClient()
local volleys = setmetatable({}, { __mode = "k" })

-- The sandbox defaults (media/sandbox-options.txt), for when SandboxVars aren't loaded.
local DEFAULTS = {
    DeflectBullets = true, DeflectChanceMin = 10, DeflectChanceMax = 80, DeflectStrikesBack = true,
    SoakShotgunBlasts = true, SoakMin = 10, SoakMax = 50, SoakFullChance = 60,
}

-- A deflect sandbox option's value.
function PS.deflectSetting(name)
    local vars = SandboxVars and SandboxVars.PhotonSword
    local value = vars and vars[name]
    if value == nil then return DEFAULTS[name] end
    return value
end

-- A low/high pair of percent options as fractions, low no higher than high.
local function range(low, high)
    local a, b = PS.deflectSetting(low) / 100, PS.deflectSetting(high) / 100
    return math.min(a, b), math.max(a, b)
end

function PS.guardUp(player, now)
    return PS.holdsIgnited(player) and PS.readyStance(player) and not PS.yieldsStance(player)
end

function PS.guardFacing(player)
    local f = player:getForwardDirection()
    return f:getX(), f:getY(), ARC
end

function PS.guardSkill(player)
    local level = player:getPerkLevel(Perks.LongBlade)
    return level / 10, level >= 10
end

function PS.guardDrain(attacker, player, weapon)
    return 0
end

function PS.drainGuard(player, drain, now)
    return true
end

function PS.guardPays(player, drain)
    return true
end

-- Percent chance player's guard deflects a bullet.
function PS.deflectChance(player)
    local low, high = range("DeflectChanceMin", "DeflectChanceMax")
    return 100 * (low + (high - low) * PS.guardSkill(player))
end

-- How much of a shotgun blast player's guard soaks (0-1): a share by guard skill, or all of it on a
-- lucky roll at full skill.
function PS.spreadShare(player)
    local skill, full = PS.guardSkill(player)
    if full and ZombRand(100) < PS.deflectSetting("SoakFullChance") then return 1 end
    local low, high = range("SoakMin", "SoakMax")
    return low + (high - low) * skill
end

local function ranged(weapon)
    return weapon ~= nil and instanceof(weapon, "HandWeapon") and weapon:isRanged()
end

local function spread(weapon)
    return weapon:getProjectileCount() > 1
end

-- Whether target's raised guard can take a shot from attacker now: raised and facing the shooter.
local function guardFaces(target, attacker, now)
    if not target or not attacker or target == attacker or not instanceof(target, "IsoPlayer") then return false end
    if target:isOnFloor() or not PS.guardUp(target, now) then return false end
    local dx, dy = attacker:getX() - target:getX(), attacker:getY() - target:getY()
    local d = math.sqrt(dx * dx + dy * dy)
    if d < .01 then return false end
    local fx, fy, arc = PS.guardFacing(target)
    return (dx * fx + dy * fy) / d >= arc
end

-- The earlier result for this shot, if a pellet of it was already settled.
local function volley(target, attacker, now)
    local v = volleys[target]
    if v and v.attacker == attacker and now - v.at <= VOLLEY_MS then return v end
    return nil
end

-- The deflected bullet strikes the shooter: a bullet wound on a player, the weapon's hit on a zombie
-- (or an NPC built on one). Patches wrap this for shooters that take damage their own way.
function PS.strikeBack(attacker, target, weapon, damage)
    if not attacker or attacker:isDead() or not PS.deflectSetting("DeflectStrikesBack") then return end
    if instanceof(attacker, "IsoPlayer") then
        local part = attacker:getBodyDamage():getBodyPart(BodyPartType[WOUND_PARTS[ZombRand(#WOUND_PARTS) + 1]])
        part:AddDamage(math.max(5, math.min(40, damage * 10)))
        part:setHaveBullet(true, 0)
        if isServer() then sendDamage(attacker) end
    elseif instanceof(attacker, "IsoZombie") then
        attacker:setAttackedBy(target)
        attacker:Hit(weapon, target, damage, false, 1, false)
    end
end

-- share: nil for a deflected bullet, else how much of a shotgun blast the guard soaked.
local function announce(target, share, echo)
    if isServer() then
        sendServerCommand("PhotonSword", "deflect", { playerID = target:getOnlineID(), share = share, echo = echo == true })
    elseif PS.showDeflect then
        PS.showDeflect(target, share)
    end
end

-- Rolls the guard against a shot (once per volley): for a bullet, whether it's deflected; for a
-- blast, the share soaked. pay(drain, share) settles the guard and returns whether it held.
local function judge(attacker, target, weapon, now, pay)
    if not guardFaces(target, attacker, now) then return false, 0 end
    local drain = PS.guardDrain(attacker, target, weapon)
    if spread(weapon) then
        if not PS.deflectSetting("SoakShotgunBlasts") then return false, 0 end
        local share = PS.spreadShare(target)
        return false, share > 0 and pay(drain * share, share) and share or 0
    end
    return PS.deflectSetting("DeflectBullets") and ZombRand(100) < PS.deflectChance(target) and pay(drain), 0
end

-- With authority over target's guard (the server, or single player): settles a shot at target from
-- attacker with weapon (damage: what it would deal, for striking back). Returns whether it was
-- deflected (the shot is stopped and already struck back) and the share (0-1) of a blast soaked (the
-- caller cuts the blast's damage by it, as with PS.soak). Repeats within a volley return the first
-- pellet's result without rolling again.
function PS.judgeShot(attacker, target, weapon, damage)
    if not ranged(weapon) or not target or not instanceof(target, "IsoPlayer") then return false, 0 end
    local now = getTimestampMs()
    local v = volley(target, attacker, now)
    if v then return v.deflected, v.share end
    local deflected, share = judge(attacker, target, weapon, now,
        function(drain) return PS.drainGuard(target, drain, now) end)
    volleys[target] = { attacker = attacker, at = now, deflected = deflected, share = share }
    if deflected then
        PS.strikeBack(attacker, target, weapon, damage or ZombRandFloat(weapon:getMinDamage(), weapon:getMaxDamage()))
        announce(target)
    elseif share > 0 then
        announce(target, share)
    end
    return deflected, share
end

-- Runs fn(...), which damages player, and gives back share of the health each body part lost to it.
function PS.soak(player, share, fn, ...)
    local parts = player:getBodyDamage():getBodyParts()
    local before = {}
    for i = 0, parts:size() - 1 do before[i] = parts:get(i):getHealth() end
    local result = { fn(...) }
    for i = 0, parts:size() - 1 do
        local lost = before[i] - parts:get(i):getHealth()
        if lost > 0 then parts:get(i):AddHealth(lost * share) end
    end
    return unpack(result)
end

-- Player fire: the server (or single player) settles each bullet that hits a player.
if AUTH and Events.OnWeaponHitCharacter then
    Events.OnWeaponHitCharacter.Add(function(attacker, target, weapon, damage)
        if not ranged(weapon) or not target or not instanceof(target, "IsoPlayer") then return end
        local deflected, share = PS.judgeShot(attacker, target, weapon, damage)
        -- Each pellet of a soaked blast is stopped with the soaked share's chance, so the blast's
        -- damage drops by that share on average (all of it at a share of 1).
        if deflected or share >= 1 or share > 0 and ZombRandFloat(0, 1) < share then
            target:setAvoidDamage(true)
        end
    end)
end

-- On a client, for gunfire it runs itself (another mod's NPCs) at one of its local players: settles a
-- shot at player from attacker with weapon, as PS.judgeShot does where the guard is settled. The roll
-- goes by this client's view of the guard (PS.guardPays), and a "deflect" command asks the server to
-- settle it (in single player it's settled here). Returns whether it was deflected (stopped and
-- already struck back) and the share (0-1) of a blast soaked.
function PS.judgeLocalShot(attacker, player, weapon, damage)
    if not player or not IsoPlayer.isLocalPlayer(player) or not ranged(weapon) then return false, 0 end
    local now = getTimestampMs()
    local v = volley(player, attacker, now)
    if v then return v.deflected, v.share end
    local deflected, share = judge(attacker, player, weapon, now, function(drain, soaked)
        if AUTH then return PS.drainGuard(player, drain, now) end
        sendClientCommand(player, "PhotonSword", "deflect", { drain = drain, share = soaked })
        return PS.guardPays(player, drain)
    end)
    volleys[player] = { attacker = attacker, at = now, deflected = deflected, share = share }
    if deflected then
        PS.strikeBack(attacker, player, weapon, damage or ZombRandFloat(weapon:getMinDamage(), weapon:getMaxDamage()))
    end
    if (deflected or share > 0) and PS.showDeflect then PS.showDeflect(player, not deflected and share or nil) end
    return deflected, share
end

-- The server's side of PS.judgeLocalShot: settle the guard and let the other clients see it.
local function settle(player, drain, share)
    if type(drain) ~= "number" or drain ~= drain or drain < 0 or drain > 300 then return end
    if share ~= nil and (type(share) ~= "number" or share ~= share or share <= 0 or share > 1) then return end
    local now = getTimestampMs()
    if not PS.guardUp(player, now) then return end
    if PS.drainGuard(player, drain, now) then announce(player, share, true) end
end

local lastDeflect = setmetatable({}, { __mode = "k" })
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "PhotonSword" or command ~= "deflect" or not player or type(args) ~= "table" then return end
    local now = getTimestampMs()
    if lastDeflect[player] and now - lastDeflect[player] < 100 then return end
    lastDeflect[player] = now
    settle(player, args.drain, args.share)
end)

return PS
