require "PhotonSword/PS_Core"

-- NPCs (Bandits, Project A-Life; zombies underneath) light their photon sword only for a fight.
-- An NPC holding one carries it dark, showing the hilt's model; it ignites, with the ignite sound,
-- as soon as PS.npcInCombat says the NPC is fighting or closing in, and goes out, with the
-- extinguish sound, once CALM_MS passes without a fight. Only the model changes: the item stays the
-- blade, so the NPC mod's AI and damage are untouched. Each client runs this for the NPCs it draws,
-- from what it sees; PS.npcLit then gates the light, hum, and no-blood code (PS.forEachNpcWielder).

local PS = PhotonSword

local UPDATE_MS = 100
local CALM_MS = 4000
local HILT_MODEL = "PhotonSword_Hilt"

local lastFightMs = setmetatable({}, { __mode = "k" }) -- [zombie] = when it last fought
local updatedMs = 0

local function bladeModel(blade)
    return "PhotonSword_Blade_" .. PS.getBladeColor(blade)
end

-- Shows the lit blade or the hilt on the NPC's held sword. Bandits makes a fresh item whenever a
-- bandit draws, so this also catches up a new item to the NPC's state.
local function showModel(zombie, blade, lit)
    local model = lit and bladeModel(blade) or HILT_MODEL
    if blade:getWeaponSprite() ~= model then
        blade:setWeaponSprite(model)
        zombie:resetEquippedHandsModels()
    end
end

local function updateNpc(zombie)
    local blade = zombie:getPrimaryHandItem()
    local now = getTimestampMs()
    local known = lastFightMs[zombie] ~= nil
    if PS.npcInCombat(zombie) then
        lastFightMs[zombie] = now
        if not PS.isNpcLit(zombie) then
            PS.npcLit[zombie] = true
            zombie:playSound(PS.IGNITE_SOUND)
        end
    elseif not known then
        -- First seen out of a fight: dark, without a sound.
        lastFightMs[zombie] = now - CALM_MS
        PS.npcLit[zombie] = nil
    elseif PS.isNpcLit(zombie) and now - lastFightMs[zombie] >= CALM_MS then
        PS.npcLit[zombie] = nil
        zombie:playSound(PS.EXTINGUISH_SOUND)
    end
    showModel(zombie, blade, PS.isNpcLit(zombie))
end

local function onTick()
    local now = getTimestampMs()
    if now - updatedMs < UPDATE_MS then return end
    updatedMs = now
    local seen = PS.forEachNpcHolder(updateNpc)
    -- An NPC that put its sword away, died, or left the cell starts dark next time.
    for zombie in pairs(lastFightMs) do
        if not seen[zombie] then
            lastFightMs[zombie] = nil
            PS.npcLit[zombie] = nil
        end
    end
end

Events.OnTick.Add(onTick)
