-- Photon Sword - Bandits: tells Photon Sword when a bandit fights, so its photon sword lights for
-- the fight and goes out after (PS.addNpcCombatSource, client/PhotonSword/PS_NpcBlades.lua).
--
-- Bandits picks its targets inside BanditUpdate's ManageCombat without keeping them, so a bandit
-- counts as fighting, or about to, when:
--   * it has a melee attack queued or running (a "Smack" task on its brain), or
--   * on its floor and within ENGAGE tiles there's a zombie, a player while it's hostile to players
--     (brain.hostileP), or a bandit on the other side (brain.hostile differs).
-- It reads Bandits' client caches (BanditZombie), which every client keeps for the bandits it runs.

require "PhotonSword/PS_Core"

local PS = PhotonSword

local ENGAGE = 6
local ENGAGE_SQ = ENGAGE * ENGAGE

local function within(x, y, z, ox, oy, oz)
    local dx, dy = x - ox, y - oy
    return math.floor(z) == math.floor(oz) and dx * dx + dy * dy <= ENGAGE_SQ
end

local function fighting(zombie)
    if not zombie:getVariableBoolean("Bandit") or BanditBrain == nil or BanditZombie == nil then return false end
    local brain = BanditBrain.Get(zombie)
    if type(brain) ~= "table" then return false end
    for _, task in ipairs(brain.tasks or {}) do
        if task.action == "Smack" then return true end
    end

    local x, y, z = zombie:getX(), zombie:getY(), zombie:getZ()
    for _, other in pairs(BanditZombie.GetAllZ()) do
        if within(x, y, z, other.x, other.y, other.z) then return true end
    end
    for _, other in pairs(BanditZombie.GetAllB()) do
        local otherBrain = other.brain
        if otherBrain and otherBrain ~= brain and otherBrain.hostile ~= brain.hostile
                and within(x, y, z, other.x, other.y, other.z) then
            return true
        end
    end
    if brain.hostileP then
        local players = BanditPlayer and BanditPlayer.GetPlayers()
        for i = 0, (players and players:size() or 0) - 1 do
            local player = players:get(i)
            if player and not player:isDead() and within(x, y, z, player:getX(), player:getY(), player:getZ()) then
                return true
            end
        end
    end
    return false
end

PS.addNpcCombatSource(fighting)
