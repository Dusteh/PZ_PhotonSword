-- Photon Sword - Bandits: a bandit's photon sword blocks another NPC's.
--
-- A bandit's swing lands in ZombieActions.Smack.onWorking (ZASmack, on the client running the
-- bandit), once per swing: when the swing's hit frame comes, it looks the victim up in
-- BanditZombie.Cache by the task's eid and hits it through a local function nothing else can reach.
-- Wrapped, a photon sword swing at an NPC holding one (in reach, and an enemy, as Bandits checks)
-- asks Photon Sword whether the victim blocks it (PS.npcBlocks, at NPC vs NPC Block Chance, with
-- the spark at the victim); a blocked swing runs with the victim hidden from the cache for that one
-- call, so Bandits finishes the swing without landing it. Players' strikes at bandits, and
-- bandits' at players, are Photon Sword's and PSB_Deflect.lua's.
-- A blocking bandit parries (PS.playNpcParry sets its BumpType to PSParry, which also ends a swing
-- of its own: Smack.onWorking gives up once the BumpType isn't its swing's). Its next swing waits
-- in Smack.onStart, which Bandits calls again each update until it returns true, until the parry
-- is over, so the swing doesn't cut it off.

require "ZombieActions/ZASmack"
require "PhotonSword/PS_Deflect"

local PS = PhotonSword

-- Whether this onWorking call is the one where the swing lands.
local function hitFrame(bandit, task)
    return type(task) == "table" and not task.hit and bandit:getBumpType() == task.anim
        and bandit:getVariableBoolean("BanditHit")
end

-- The victim of bandit's photon sword swing, if it blocks it.
local function blocker(bandit, task)
    if task.weapon ~= PS.BLADE_TYPE or not BanditZombie or type(BanditZombie.Cache) ~= "table" then return nil end
    local enemy = BanditZombie.Cache[task.eid]
    local blade = bandit:getPrimaryHandItem()
    if not enemy or not PS.isIgnited(blade) or not PS.isIgnited(enemy:getPrimaryHandItem()) then return nil end
    if BanditUtils.AreEnemies and not BanditUtils.AreEnemies(BanditBrain.Get(enemy), BanditBrain.Get(bandit)) then
        return nil
    end
    local dx, dy = enemy:getX() - bandit:getX(), enemy:getY() - bandit:getY()
    if math.sqrt(dx * dx + dy * dy) >= blade:getMaxRange() + 0.1 then return nil end
    if PS.npcBlocks(bandit, enemy, blade) then return enemy end
    return nil
end

local PARRY_MS = 850   -- PS_Parry, less its blend back

local Smack = ZombieActions and ZombieActions.Smack
if Smack and type(Smack.onStart) == "function" then
    local onStart = Smack.onStart
    Smack.onStart = function(bandit, task, ...)
        if bandit:getBumpType() == "PSParry" and PS.parrying(bandit, PARRY_MS) then return false end
        return onStart(bandit, task, ...)
    end
end
if Smack and type(Smack.onWorking) == "function" then
    local onWorking = Smack.onWorking
    Smack.onWorking = function(bandit, task, ...)
        local enemy = hitFrame(bandit, task) and blocker(bandit, task)
        if not enemy then return onWorking(bandit, task, ...) end
        local cache, eid = BanditZombie.Cache, task.eid
        cache[eid] = nil
        local ok, result = pcall(onWorking, bandit, task, ...)
        if cache[eid] == nil then cache[eid] = enemy end
        if not ok then error(result, 0) end
        return result
    end
else
    print("[PhotonSwordBandits] ZombieActions.Smack.onWorking not found; NPC duels not patched")
end
