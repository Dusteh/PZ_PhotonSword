-- Running or sprinting with a lit photon sword extinguishes it, and it relights when the run ends,
-- unless the Extinguish While Running sandbox option is off or another mod's stance yield holds
-- (PS.addStanceYield); then the run is vanilla's, sword lit.
-- Both go through the toggle action (ISPhotonSwordToggle), so the swap runs with server authority
-- and plays the ignite and extinguish sounds; the action doesn't stop a run. A run's hilt plays
-- vanilla's one-handed run. The blade relights in the color it had (the swap keeps the item's
-- modData), and only if it was this that put it out: a sword lit again by hand mid-run stays lit,
-- and one put away or dropped mid-run isn't relit.

require "PhotonSword/PS_Core"
require "TimedActions/ISPhotonSwordToggle"

local PS = PhotonSword
local doused = setmetatable({}, { __mode = "k" })  -- player -> true while their run has the sword out

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

Events.OnPlayerUpdate.Add(function(player)
    if not IsoPlayer.isLocalPlayer(player) or player:isDead() then return end
    local item = PS.getHeld(player)
    if player:isRunning() or player:isSprinting() then
        -- A sword this put out relights after the run even if the option is turned off mid-run.
        if not doused[player] and PS.isIgnited(item) and PS.extinguishesWhileRunning()
            and not PS.yieldsStance(player) and not toggling(player) then
            doused[player] = true
            toggle(player, item, false)
        end
    elseif doused[player] and not toggling(player) then
        doused[player] = nil
        if item and not PS.isIgnited(item) and PS.getCharge(item) > 0 then toggle(player, item, true) end
    end
end)
