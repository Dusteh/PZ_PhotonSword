-- The stance: how a character holds an ignited photon sword. Sets the animation variables this
-- mod's AnimSets read (tools/gen_animsets.py), for local players every update and for remote
-- players every few ticks, since they get no OnPlayerUpdate on this client:
--   PSHolding    an ignited sword in both hands: the rest, sneak rest, and walks (PS_Rest*, PS_Walk*)
--   PSGuard      holding it aimed: the ready stance (PS_Ready, PS_ReadyWalk while walking)
--   PSBeckon     now and then in the ready stance, standing: the off hand beckons (PS_ReadyBeckon)
--   PSHiltBeckon the same beckon aiming an extinguished hilt, the off hand free (PS_AimBeckon)
--   PSParry      in the ready stance just after its guard blocked a photon sword (PS_Parry)
--   PSFemale, PSWalking
-- Another mod's yield (PS.addStanceYield) keeps the stance out while its own animation plays, and
-- the Default Two-Handed Animations option (PS_Options.lua) keeps it out on this client altogether,
-- leaving the game's two-handed animations.
-- A beckon is a Beckon Chance percent roll (PS_Options.lua) every BECKON_ROLL_MS spent standing in
-- the stance; on a hit it plays for BECKON_MS (the clip, less its blend back). Each client rolls for
-- every player it animates, so other players may see a beckon at a different moment.

require "PhotonSword/PS_Core"
require "PhotonSword/PS_Options"

local PS = PhotonSword
local PSO = PhotonSwordOptions

local BECKON_ROLL_MS, BECKON_MS = 3000, 2200
local PARRY_MS = 850   -- PS_Parry, less its blend back
local beckons = setmetatable({}, { __mode = "k" })
local hiltBeckons = setmetatable({}, { __mode = "k" })
local holding = setmetatable({}, { __mode = "k" })  -- players whose stance variables are set
local hiltBeckoning = setmetatable({}, { __mode = "k" })  -- players with PSHiltBeckon set

local function beckoning(states, playerObj, ready)
    if not ready then states[playerObj] = nil; return false end
    local now = getTimestampMs()
    local state = states[playerObj]
    if not state then
        state = { roll = now + BECKON_ROLL_MS, ends = 0 }
        states[playerObj] = state
    end
    if now < state.ends then return true end
    if now < state.roll then return false end
    state.roll = now + BECKON_ROLL_MS
    if ZombRand(100) >= PSO.beckonChance:getValue() then return false end
    state.ends = now + BECKON_MS
    return true
end

-- Whether playerObj holds the sword in the stance: ignited in both hands, no other mod's animation
-- taking it over, and the stance not turned off for the game's two-handed animations.
function PS.holdsStance(playerObj)
    return not PSO.vanillaStance:getValue() and PS.holdsIgnited(playerObj) and not PS.yieldsStance(playerObj)
end

local HOLD_VARIABLES = { "PSHolding", "PSGuard", "PSBeckon", "PSParry", "PSWalking", "PSFemale" }

local function clear(playerObj)
    holding[playerObj] = nil
    beckons[playerObj] = nil
    for _, name in ipairs(HOLD_VARIABLES) do
        playerObj:setVariable(name, false)
    end
end

local function updateHold(playerObj)
    if not PS.holdsStance(playerObj) then
        if holding[playerObj] then clear(playerObj) end
        return
    end
    holding[playerObj] = true
    local walking = playerObj:isPlayerMoving()
    local guard = PS.readyStance(playerObj)
    playerObj:setVariable("PSHolding", true)
    playerObj:setVariable("PSFemale", playerObj:isFemale())
    playerObj:setVariable("PSWalking", walking)
    playerObj:setVariable("PSGuard", guard)
    playerObj:setVariable("PSParry", guard and PS.parrying(playerObj, PARRY_MS))
    playerObj:setVariable("PSBeckon", beckoning(beckons, playerObj, guard and not walking))
end

-- The beckon over vanilla's one-handed aim, standing with an extinguished hilt and the off hand free.
local function updateHiltBeckon(playerObj)
    local hilt, off = playerObj:getPrimaryHandItem(), playerObj:getSecondaryHandItem()
    local ready = hilt ~= nil and hilt:getFullType() == PS.HILT_TYPE and (off == nil or off == hilt)
        and not playerObj:isDead() and not playerObj:getVehicle()
        and playerObj:isAiming() and not playerObj:isPlayerMoving() and not playerObj:isSneaking()
        and not playerObj:isDoShove() and not playerObj:isAimAtFloor() and not playerObj:isAttacking()
        and not playerObj:getVariableBoolean("PerformingAction") and not PS.yieldsStance(playerObj)
    -- Written only when it changes: most frames, for most players, it stays false.
    local beckon = beckoning(hiltBeckons, playerObj, ready)
    if beckon ~= (hiltBeckoning[playerObj] == true) then
        hiltBeckoning[playerObj] = beckon or nil
        playerObj:setVariable("PSHiltBeckon", beckon)
    end
end

local function update(playerObj)
    updateHold(playerObj)
    updateHiltBeckon(playerObj)
end

Events.OnPlayerUpdate.Add(function(playerObj)
    if IsoPlayer.isLocalPlayer(playerObj) then update(playerObj) end
end)

local function updateRemote(_, playerObj)
    if not IsoPlayer.isLocalPlayer(playerObj) then update(playerObj) end
end

local tick = 0
Events.OnTick.Add(function()
    tick = tick + 1
    if tick % 3 ~= 0 or not isClient() then return end
    PS.forEachPlayer(updateRemote)
end)
