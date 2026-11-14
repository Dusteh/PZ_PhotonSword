-- Constants and item helpers shared by client and server.
-- A photon sword exists as two item types: an inert hilt and an ignited blade.
-- Igniting/extinguishing swaps one for the other, carrying condition and modData across.
-- Power is stored on the item's modData (PS_charge, 0..1); nil means no battery installed.
-- A blade glows in a palette color (PS_color in modData) set from the igniting player's
-- Blade Color option, defaulting to DEFAULT_COLOR.

PhotonSword = PhotonSword or {}
local PS = PhotonSword

PS.HILT_TYPE = "PhotonSword.PhotonSwordHilt"
PS.BLADE_TYPE = "PhotonSword.PhotonSword"
PS.BATTERY_TYPE = "Base.Battery"

-- Blade palette: light color as 0..1 floats (as IsoLightSource expects). Each name has a model
-- (PhotonSword_Blade_<Name>) from tools/gen_models.py, whose
-- PALETTE must list the same names. The first is the default, matching the blade item script.
PS.BLADE_COLORS = { "Blue", "Green", "Red", "Purple", "Yellow", "Orange", "Cyan", "White" }
PS.COLORS = {
    Blue = { r = 0.25, g = 0.5, b = 1.0 },
    Green = { r = 0.3, g = 1.0, b = 0.35 },
    Red = { r = 1.0, g = 0.2, b = 0.15 },
    Purple = { r = 0.7, g = 0.3, b = 1.0 },
    Yellow = { r = 1.0, g = 0.9, b = 0.25 },
    Orange = { r = 1.0, g = 0.55, b = 0.15 },
    Cyan = { r = 0.2, g = 0.95, b = 1.0 },
    White = { r = 0.95, g = 0.95, b = 1.0 },
}

-- Balance comes from sandbox options (media/sandbox-options.txt); these mirror their defaults
-- for when SandboxVars aren't loaded. Light radius is a client mod option (PS_Options.lua).
local DEFAULT_BATTERY_LIFE_HOURS = 8
local DEFAULT_DAMAGE_MULTIPLIER = 1.0

local function sandbox()
    return SandboxVars and SandboxVars.PhotonSword or {}
end

-- Charge lost per in-game minute while ignited; 0 when drain is disabled.
function PS.getDrainPerMinute()
    local hours = sandbox().BatteryLifeHours or DEFAULT_BATTERY_LIFE_HOURS
    if hours <= 0 then return 0 end
    return 1 / (hours * 60)
end

function PS.getDamageMultiplier()
    return sandbox().DamageMultiplier or DEFAULT_DAMAGE_MULTIPLIER
end

-- What a swing of an ignited blade cuts through (server side: PS_Cutting.lua).
function PS.canCutDoorsAndWindows()
    return sandbox().CutDoorsAndWindows ~= false
end

function PS.canCutWalls()
    return sandbox().CutWalls == true
end

function PS.canCutVegetation()
    return sandbox().CutVegetation ~= false
end

function PS.canCutWorldObjects()
    return sandbox().CutWorldObjects ~= false
end

function PS.canCutPlayerBuilt()
    return sandbox().CutPlayerBuilt == true
end

-- Cut Effect (enum): 1 destroys targets like a sledgehammer, 2 sets them on fire.
function PS.isCutEffectFire()
    return sandbox().CutEffect == 2
end

-- Whether running or sprinting puts a lit sword out until the run ends (PS_RunExtinguish.lua).
function PS.extinguishesWhileRunning()
    return sandbox().ExtinguishWhileRunning ~= false
end

function PS.canCutAnything()
    return PS.canCutDoorsAndWindows() or PS.canCutWalls() or PS.canCutVegetation()
        or PS.canCutWorldObjects() or PS.canCutPlayerBuilt()
end

-- Each player's own cutting switch (Toggle Cutting hotkey), kept in player modData so it survives
-- saving. Off until the player turns it on; the sandbox options still decide what can be cut.
function PS.isCuttingOn(playerObj)
    return playerObj:getModData().PS_cutting == true
end

function PS.setCuttingOn(playerObj, on)
    playerObj:getModData().PS_cutting = on
end

-- Sound script names (media/scripts/sounds_photonsword.txt, audio from tools/gen_sounds.py).
PS.IGNITE_SOUND = "PhotonSwordIgnite"
PS.EXTINGUISH_SOUND = "PhotonSwordExtinguish"
-- Hum, swing, and hit come in these tones, and swings and hits at these pitches (percent); both
-- lists must match TONES and PITCHES in tools/gen_sounds.py.
PS.SOUND_TONES = { "Smooth", "Classic", "Gritty" }
PS.SOUND_PITCHES = { 70, 80, 90, 100, 110, 120, 130 }

function PS.humSound(tone)
    return "PhotonSwordHum_" .. tone
end

-- Swing and hit sounds are pre-rendered per pitch, so snap to the nearest one that exists.
local function nearestPitch(pitchPercent)
    local best = PS.SOUND_PITCHES[1]
    for _, p in ipairs(PS.SOUND_PITCHES) do
        if math.abs(p - pitchPercent) < math.abs(best - pitchPercent) then best = p end
    end
    return best
end

function PS.swingSound(tone, pitchPercent)
    return "PhotonSwordSwing_" .. tone .. "_" .. nearestPitch(pitchPercent)
end

-- The spark played when the blade strikes a zombie, a door, the floor, or anything else.
function PS.hitSound(tone, pitchPercent)
    return "PhotonSwordHit_" .. tone .. "_" .. nearestPitch(pitchPercent)
end

function PS.isIgnited(item)
    return item ~= nil and item:getFullType() == PS.BLADE_TYPE
end

function PS.isPhotonSword(item)
    return item ~= nil and (item:getFullType() == PS.HILT_TYPE or PS.isIgnited(item))
end

function PS.hasBattery(item)
    return item:getModData().PS_charge ~= nil
end

function PS.getCharge(item)
    return item:getModData().PS_charge or 0
end

function PS.setCharge(item, charge)
    if charge == nil then
        item:getModData().PS_charge = nil
    else
        item:getModData().PS_charge = math.max(0, math.min(1, charge))
    end
end

function PS.chargePercent(item)
    return math.floor(PS.getCharge(item) * 100 + 0.5)
end

-- The palette color a blade glows in.
function PS.getBladeColor(item)
    local chosen = item:getModData().PS_color
    if chosen and PS.COLORS[chosen] then return chosen end
    return PS.BLADE_COLORS[1]
end

-- Model for a blade's color; saved with the item. The icon is the hilt's for every color.
local function applyBladeColor(blade)
    blade:setWeaponSprite("PhotonSword_Blade_" .. PS.getBladeColor(blade))
end
PS.applyBladeColor = applyBladeColor

-- Returns the photon sword the character is holding, if any.
function PS.getHeld(character)
    local item = character:getPrimaryHandItem()
    if PS.isPhotonSword(item) then return item end
    item = character:getSecondaryHandItem()
    if PS.isPhotonSword(item) then return item end
    return nil
end

-- Calls fn(key, playerObj) for every player this game knows about: online players on an MP
-- client, local (split-screen) players otherwise. Returns the set of keys visited.
function PS.forEachPlayer(fn)
    local seen = {}
    local players = isClient() and getOnlinePlayers() or IsoPlayer.getPlayers()
    for i = 0, players:size() - 1 do
        local playerObj = players:get(i)
        if playerObj then
            local key = isClient() and playerObj:getOnlineID() or i
            seen[key] = true
            fn(key, playerObj)
        end
    end
    return seen
end

-- Whether playerObj holds an ignited, working sword in both hands, free to stand with it.
function PS.holdsIgnited(playerObj)
    local item = playerObj:getPrimaryHandItem()
    return PS.isIgnited(item) and item:getCondition() > 0 and playerObj:getSecondaryHandItem() == item
        and not playerObj:isDead() and not playerObj:getVehicle() and not playerObj:isSitOnGround()
        and not playerObj:isClimbingRope()
end

-- Whether playerObj aims as the ready stance does: not running, sneaking, shoving, aiming at the
-- floor, or busy with an action.
function PS.readyStance(playerObj)
    return playerObj:isAiming() and not playerObj:isRunning() and not playerObj:isSprinting()
        and not playerObj:isSneaking() and not playerObj:isDoShove() and not playerObj:isAimAtFloor()
        and not playerObj:getVariableBoolean("PerformingAction")
end

-- The stance (client/PhotonSword/PS_Stance.lua): how a character holds an ignited sword. Another
-- mod whose own animation takes the sword over (a block, a weapon art's stance) adds a yield:
-- while fn(playerObj) returns true, the stance stays out of that player's animation, the ready
-- stance doesn't guard (PS_Deflect.lua), and running doesn't put the blade out (PS_RunExtinguish.lua).
PS.stanceYields = PS.stanceYields or {}

function PS.addStanceYield(fn)
    table.insert(PS.stanceYields, fn)
end

function PS.yieldsStance(playerObj)
    for _, fn in ipairs(PS.stanceYields) do
        if fn(playerObj) then return true end
    end
    return false
end

-- Finds a photon sword to draw: one bound to the hotbar first, then any in the inventory.
function PS.findInInventory(character)
    local fallback = nil
    local items = character:getInventory():getAllEvalRecurse(PS.isPhotonSword)
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getAttachedSlot() > -1 then return item end
        fallback = fallback or item
    end
    return fallback
end

-- Highest-charge battery in the character's inventory holding more than minCharge.
function PS.findBestBattery(character, minCharge)
    local batteries = character:getInventory():getAllTypeRecurse(PS.BATTERY_TYPE)
    local best = nil
    local bestCharge = minCharge or 0
    for i = 0, batteries:size() - 1 do
        local battery = batteries:get(i)
        if battery:getCurrentUsesFloat() > bestCharge then
            best = battery
            bestCharge = battery:getCurrentUsesFloat()
        end
    end
    return best
end

-- Replaces a hilt with its blade (or vice versa) in whatever container holds it (the main
-- inventory or a bag), keeping it in the same hands. Must run with authority: a timed action's
-- complete() or server code. color (ignite only) is a palette name for the blade; nil keeps the
-- color the hilt last had.
function PS.swap(character, item, ignite, color)
    if not PS.isPhotonSword(item) then return nil end
    local inv = item:getContainer() or character:getInventory()
    local newItem = instanceItem(ignite and PS.BLADE_TYPE or PS.HILT_TYPE)
    if not newItem then return nil end

    -- Weapons save their own damage, so scale the fresh blade rather than the item script.
    if ignite then
        local mult = PS.getDamageMultiplier()
        newItem:setMinDamage(newItem:getMinDamage() * mult)
        newItem:setMaxDamage(newItem:getMaxDamage() * mult)
    end
    newItem:setCondition(item:getCondition())
    newItem:copyModData(item:getModData())
    newItem:setFavorite(item:isFavorite())
    if ignite then
        if PS.COLORS[color or ""] then newItem:getModData().PS_color = color end
        applyBladeColor(newItem)
    end
    -- Keep the hotbar binding. Hilt and blade share an AttachmentType so they fit the same slots.
    newItem:setAttachedSlot(item:getAttachedSlot())
    newItem:setAttachedSlotType(item:getAttachedSlotType())
    newItem:setAttachedToModel(item:getAttachedToModel())

    local wasHeld = character:getPrimaryHandItem() == item or character:getSecondaryHandItem() == item
    if wasHeld then
        character:removeFromHands(item)
    end

    inv:Remove(item)
    sendRemoveItemFromContainer(inv, item)
    inv:AddItem(newItem)
    sendAddItemToContainer(inv, newItem)
    syncItemFields(character, newItem)

    if wasHeld then
        character:setPrimaryHandItem(newItem)
        if newItem:isTwoHandWeapon() then
            character:setSecondaryHandItem(newItem)
        end
        sendEquip(character)
    end
    return newItem
end
