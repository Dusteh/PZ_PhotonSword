require "PhotonSword/PS_Core"
require "PhotonSword/PS_Options"

-- Blade sounds driven by this client's mod options:
--  * A soft looping hum on every player and NPC (PS.forEachNpcWielder) holding an ignited blade, in the chosen tone and pitch.
--    It fades out while the player is swinging (the swing sound takes over) and back in afterwards.
--  * The swing and hit (spark) sounds of local players' blades, re-pointed to the chosen tone and
--    pitch. The game plays these by name from the weapon, so they can't be re-pitched like the hum.

local PS = PhotonSword
local PSO = PhotonSwordOptions

local FADE_PER_TICK = 0.05   -- full fade in ~20 ticks
local RESTART_AFTER_MS = 1000 -- grace period before treating a silent loop as ended
local hums = {} -- [player key] = { emitter, id, sound, volume, pitch, startMs }

local function stopHum(key)
    local hum = hums[key]
    if hum then
        hum.emitter:stopSound(hum.id)
        hums[key] = nil
    end
end

local function startHum(key, playerObj, sound)
    local emitter = playerObj:getEmitter()
    local id = emitter:playSound(sound)
    if not id or id == 0 then return end
    emitter:setVolume(id, 0)
    hums[key] = { emitter = emitter, id = id, sound = sound, volume = 0, pitch = 1, startMs = getTimestampMs() }
end

-- Sound names are only rebuilt when their options change, not every tick.
local function cachedName(build)
    local lastTone, lastPitch, name
    return function(toneBox, pitchSlider)
        local tone, pitch = PSO.getTone(toneBox), pitchSlider:getValue()
        if tone ~= lastTone or pitch ~= lastPitch then
            lastTone, lastPitch, name = tone, pitch, build(tone, pitch)
        end
        return name
    end
end
local swingName = cachedName(PS.swingSound)
local hitName = cachedName(PS.hitSound)

local humTone, humSound
local function humName(toneBox)
    local tone = PSO.getTone(toneBox)
    if tone ~= humTone then humTone, humSound = tone, PS.humSound(tone) end
    return humSound
end

local function updateWeaponSounds(playerObj, blade)
    if not instanceof(playerObj, "IsoPlayer") or not playerObj:isLocalPlayer() then return end
    local swing = swingName(PSO.swingTone, PSO.swingPitch)
    if blade:getSwingSound() ~= swing then
        blade:setSwingSound(swing)
    end
    -- One spark for every kind of hit: zombies, doors, the floor, and other impacts.
    local hit = hitName(PSO.hitTone, PSO.hitPitch)
    if blade:getZombieHitSound() ~= hit then
        blade:setZombieHitSound(hit)
        blade:setDoorHitSound(hit)
        blade:setHitFloorSound(hit)
        blade:setImpactSound(hit)
    end
end

local function updateHum(key, playerObj)
    local blade = PS.getHeld(playerObj)
    local maxVolume = PSO.humVolume:getValue() / 100
    if not blade or not PS.isIgnited(blade) or playerObj:isDead() then
        stopHum(key)
        return
    end
    updateWeaponSounds(playerObj, blade)
    if maxVolume <= 0 then
        stopHum(key)
        return
    end

    local sound = humName(PSO.humTone)
    local hum = hums[key]
    -- Restart if the tone changed, the player's emitter changed, or the loop was culled.
    if hum and (hum.sound ~= sound or hum.emitter ~= playerObj:getEmitter()
            or (getTimestampMs() - hum.startMs > RESTART_AFTER_MS and not hum.emitter:isPlaying(hum.id))) then
        stopHum(key)
        hum = nil
    end
    if not hum then
        startHum(key, playerObj, sound)
        hum = hums[key]
        if not hum then return end
    end

    local pitch = PSO.humPitch:getValue() / 100
    if hum.pitch ~= pitch then
        hum.pitch = pitch
        hum.emitter:setPitch(hum.id, pitch)
    end

    local target = playerObj:isPerformingAttackAnimation() and 0 or maxVolume
    if hum.volume ~= target then
        if hum.volume < target then
            hum.volume = math.min(target, hum.volume + FADE_PER_TICK)
        else
            hum.volume = math.max(target, hum.volume - FADE_PER_TICK)
        end
        hum.emitter:setVolume(hum.id, hum.volume)
    end
end

local function onTick()
    local seen = PS.forEachWielder(updateHum)
    for key in pairs(hums) do
        if not seen[key] then stopHum(key) end
    end
end

Events.OnTick.Add(onTick)
