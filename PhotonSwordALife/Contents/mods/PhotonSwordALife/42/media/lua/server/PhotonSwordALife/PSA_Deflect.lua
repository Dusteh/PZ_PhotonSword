-- Photon Sword - Project A-Life: A-Life's NPC gunfire meets a photon sword's guard.
--
-- A-Life doesn't shoot players through the game's weapon hits (so Photon Sword's
-- OnWeaponHitCharacter never sees its bullets). Every way it wounds a player ends in
-- ProjectALife.Wounds.damagePlayer(bodyDamage, weapon, part), which doesn't say who fired, so the
-- three callers that lead there are wrapped to note the shooter while they run:
--   Combat.resolveAttack(actor, shell, target, ...)    an NPC's aimed shot (single player, server)
--   ModuleGunner.grazePlayer(shell, weapon, body)       a stray round grazing a player
--   Executor.woundPlayer(victim, ..., attacker)         the server landing a hit a client relayed
-- damagePlayer then asks Photon Sword (PS.judgeShot, PS_Deflect.lua, which also settles the guard
-- and shows the deflect) about a ranged weapon. The guard is the ready stance, or with Photon Sword
-- Forms a Form's block. A stopped shot reports itself landed, so A-Life doesn't
-- fall back to its flat damage, and its pain cry is muted; a soaked blast lands and gives back the
-- soaked share (PS.soak). A deflected bullet strikes the NPC back through A-Life's own human
-- damage (HumanDamage.apply), so its health model and hit reactions apply.
--
-- An NPC's melee strikes land through the same calls, so a photon sword's strike (the NPC's own
-- sword, or the copy A-Life scales its damage on) meets the guard there too (PS.judgeBlow): a
-- blocked strike reports itself landed, deals nothing, and mutes the pain cry. Players' strikes at
-- NPCs are PSA_Block.lua's.
--
-- All of this runs where A-Life wounds players: in single player, or on the multiplayer server.

local PS = require "PhotonSword/PS_Deflect"

local MUTE_MS = 250   -- how long after a stopped shot the player's pain cry is muted
local shooter = nil   -- the NPC shell whose shot A-Life is resolving
local muted = setmetatable({}, { __mode = "k" })   -- player -> until when their pain cry is muted

local function pack(...) return { n = select("#", ...), ... } end

-- Calls fn(...) with attacker noted as the shooter, restoring the previous one even on an error.
local function firing(attacker, fn, ...)
    local previous = shooter
    shooter = attacker
    local result = pack(pcall(fn, ...))
    shooter = previous
    if not result[1] then error(result[2], 0) end
    return unpack(result, 2, result.n)
end

local function ranged(weapon)
    return weapon ~= nil and instanceof(weapon, "HandWeapon") and weapon:isRanged()
end

local function damagePlayer(original, bodyDamage, weapon, part, ...)
    local player = shooter and bodyDamage and bodyDamage:getParentChar()
    if player and instanceof(player, "IsoPlayer") and not ranged(weapon) and PS.judgeBlow(shooter, player, weapon) then
        muted[player] = getTimestampMs() + MUTE_MS
        return true
    end
    if player and instanceof(player, "IsoPlayer") and ranged(weapon) then
        local deflected, share = PS.judgeShot(shooter, player, weapon)
        if deflected or share >= 1 then
            muted[player] = getTimestampMs() + MUTE_MS
            return true
        end
        if share > 0 then return PS.soak(player, share, original, bodyDamage, weapon, part, ...) end
    end
    return original(bodyDamage, weapon, part, ...)
end

local function painCry(source, sound)
    local until_ = source and muted[source]
    return until_ ~= nil and getTimestampMs() < until_ and type(sound) == "string" and sound:find("PainFrom") ~= nil
end

-- A deflected bullet hits the NPC through A-Life's own damage; anything else keeps Photon Sword's
-- handling.
local strikeBack = PS.strikeBack
function PS.strikeBack(attacker, target, weapon, damage)
    local HumanDamage = ProjectALife and ProjectALife.HumanDamage
    if attacker and HumanDamage and HumanDamage.isActor and HumanDamage.isActor(attacker) then
        if not PS.deflectSetting("DeflectStrikesBack") or attacker:isDead() then return end
        local ok, applied, dealt, zone, outcome = pcall(HumanDamage.apply, target, attacker, weapon, 1)
        if ok and applied then
            local Combat = ProjectALife.Combat
            if Combat and Combat.presentHumanHit then
                -- As A-Life presents its own hits: one the NPC's armor stopped lands on the body.
                pcall(Combat.presentHumanHit, attacker, target, dealt, outcome == "blocked" and "body" or zone,
                    true, Combat.nowMs())
            end
            return
        end
    end
    return strikeBack(attacker, target, weapon, damage)
end

local function wrap(owner, key, wrapper)
    if type(owner) ~= "table" or type(owner[key]) ~= "function" then return false end
    local original = owner[key]
    owner[key] = function(...) return wrapper(original, ...) end
    return true
end

local installed = false
local function install()
    if installed or not ProjectALife then return end
    installed = true
    local A = ProjectALife
    local done = {
        wrap(A.Wounds, "damagePlayer", damagePlayer),
        wrap(A.Combat, "resolveAttack", function(original, actor, shell, ...)
            return firing(shell, original, actor, shell, ...)
        end),
        wrap(A.ModuleGunner, "grazePlayer", function(original, shell, ...)
            return firing(shell, original, shell, ...)
        end),
        wrap(A.Executor, "woundPlayer", function(original, victim, weaponType, issuedWeapon, part, attacker, ...)
            return firing(attacker, original, victim, weaponType, issuedWeapon, part, attacker, ...)
        end),
        wrap(A.AudioPolicy, "playFrom", function(original, source, sound, ...)
            if painCry(source, sound) then return end
            return original(source, sound, ...)
        end),
        wrap(A.SoundVolume, "playSource", function(original, category, source, name, ...)
            if painCry(source, name) then return end
            return original(category, source, name, ...)
        end),
    }
    local names = { "Wounds.damagePlayer", "Combat.resolveAttack", "ModuleGunner.grazePlayer",
        "Executor.woundPlayer", "AudioPolicy.playFrom", "SoundVolume.playSource" }
    local missing = {}
    for i, ok in ipairs(done) do
        if not ok then missing[#missing + 1] = names[i] end
    end
    print("[PhotonSwordALife] patched"
        .. (#missing > 0 and ("; not found: " .. table.concat(missing, ", ")) or " everything"))
end

Events.OnGameStart.Add(install)
if Events.OnServerStarted then Events.OnServerStarted.Add(install) end
