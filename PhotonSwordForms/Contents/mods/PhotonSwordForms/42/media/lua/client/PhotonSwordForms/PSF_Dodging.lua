-- Dodging with a photon sword (Martial Arts Core's dodge key while aiming): the photon sword's own
-- leap, with the blade put out for it and relit on landing.
--
-- The leap: players holding a photon sword (lit or not) get PSFDodgeAnim, which the PSF_dodge_*
-- AnimSets (tools/gen_forms_animsets.py) read to play PSF_Dodge* in place of Senator's Pak Mei dodge,
-- the hilt kept in the sword hand. Set for local players every update and for remote ones every
-- few ticks, under this client's Photon Sword Dodge Animation option.
--
-- The blade: pressing the dodge key with it lit starts the dodge and puts the blade out through
-- Photon Sword's toggle action (ISPhotonSwordToggle), so the swap runs with server authority and
-- plays the extinguish and ignite sounds; the action doesn't stop the dodge. That's the server's
-- Extinguish While Dodging option. The dodge keeps the style it started with (PSF_Dodge.lua). When it
-- ends the blade relights in the color it had (the swap keeps the item's modData), under the
-- player's Relight After Dodge option, and only if it was this that put it out and the battery still
-- holds charge: a sword lit again by hand mid-dodge stays lit, and one put away or dropped isn't relit.

local SMA = require "SMA_Core"
require "SMA_Dodge"
require "PhotonSwordForms/PSF_Dodge"
local PSF = require "PhotonSwordForms/PSF_Settings"
require "PhotonSwordForms/PSF_Options"
require "TimedActions/ISPhotonSwordToggle"

local PS = PhotonSword
local PSFO = PhotonSwordFormsOptions
local doused = setmetatable({}, { __mode = "k" })  -- player -> true while their dodge has the sword out

local function toggling(player)
    local queue = ISTimedActionQueue.queues[player]
    if not queue then return false end
    for _, action in ipairs(queue.queue) do
        if action.Type == "ISPhotonSwordToggle" then return true end
    end
    return false
end

local function toggle(player, item, ignite)
    local action = ISPhotonSwordToggle:new(player, item, ignite)
    action.useProgressBar = false
    ISTimedActionQueue.add(action)
end

local function updateAnim(player)
    player:setVariable("PSFDodgeAnim", PSFO.dodgeAnimation:getValue() and PS.isPhotonSword(player:getPrimaryHandItem()))
end

-- Core only starts a dodge with an empty action queue, so the extinguish is queued once it has.
local requestDodge = SMA.requestDodge
function SMA.requestDodge(player)
    local item = player and player:getPrimaryHandItem()
    local lit = PS.isIgnited(item)
    if player then updateAnim(player) end
    local started = requestDodge(player)
    if started and lit and not doused[player] and PSF.sandbox("ExtinguishWhileDodging") then
        doused[player] = true
        toggle(player, item, false)
    end
    return started
end

local function relight(player)
    if not doused[player] then return end
    if player:isDead() then doused[player] = nil; return end
    if SMA.moveSession(player).dodge or toggling(player) then return end
    doused[player] = nil
    local item = PS.getHeld(player)
    if PSFO.relightAfterDodge:getValue() and item and not PS.isIgnited(item) and PS.getCharge(item) > 0 then
        toggle(player, item, true)
    end
end

Events.OnPlayerUpdate.Add(function(player)
    if not IsoPlayer.isLocalPlayer(player) then return end
    updateAnim(player)
    relight(player)
end)

-- Remote players don't get OnPlayerUpdate on this client.
local tick = 0
Events.OnTick.Add(function()
    tick = tick + 1
    if tick % 3 ~= 0 or not isClient() then return end
    PS.forEachPlayer(function(_, player)
        if not IsoPlayer.isLocalPlayer(player) then updateAnim(player) end
    end)
end)
