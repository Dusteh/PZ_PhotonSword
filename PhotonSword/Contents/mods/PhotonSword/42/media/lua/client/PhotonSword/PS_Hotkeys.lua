require "PhotonSword/PS_Core"
require "PhotonSword/PS_Options"
require "TimedActions/ISPhotonSwordToggle"
require "TimedActions/ISPhotonSwordBattery"

-- Hotkeys (bound under Options > Mods) and the low-power warning. Keyboard player only,
-- matching how vanilla hotbar keys work.

local PS = PhotonSword
local PSO = PhotonSwordOptions

local function canAct(playerObj)
    if not playerObj or playerObj:isDead() or isGamePaused() then return false end
    -- Mid-swing only: isAttacking() can also be true in the attack-ready stance.
    if playerObj:isPerformingAttackAnimation() or playerObj:getVehicle() then return false end
    if JoypadState.players[1] then return false end
    local queue = ISTimedActionQueue.queues[playerObj]
    return not (queue and #queue.queue > 0)
end

local function sayBad(playerObj, key)
    HaloTextHelper.addBadText(playerObj, getText(key))
end

-- Toggles the held photon sword. With empty hands it does nothing: drawing one is left to the
-- player (and to other mods' equip handling).
local function toggleBlade(playerObj)
    local item = PS.getHeld(playerObj)
    if not item then return end

    local ignite = not PS.isIgnited(item)
    if ignite and not PS.hasCrystal(item) then
        sayBad(playerObj, "IGUI_PS_NoCrystal")
        return
    end
    if ignite and PS.getCharge(item) <= 0 then
        sayBad(playerObj, "IGUI_PS_NoPower")
        return
    end
    ISTimedActionQueue.add(ISPhotonSwordToggle:new(playerObj, item, ignite))
end

-- Loads the fullest battery into the held (or first) hilt, swapping out a weaker one.
local function swapBattery(playerObj)
    -- The default key (R) also reloads guns, sharpens blades, and rotates placement cursors
    -- (ISFirearmRadialMenu.checkKey); leave it to those.
    local primary = playerObj:getPrimaryHandItem()
    if primary and instanceof(primary, "HandWeapon") and primary:isRanged() then return end
    if primary and primary:isSharpenable() then return end
    if getCell():getDrag(0) then return end

    local item = PS.getHeld(playerObj) or PS.findInInventory(playerObj)
    if not item then
        sayBad(playerObj, "IGUI_PS_NoPhotonSword")
        return
    end
    if playerObj:isAiming() then return end
    if PS.isIgnited(item) then
        sayBad(playerObj, "IGUI_PS_ExtinguishFirst")
        return
    end
    local current = PS.hasBattery(item) and PS.getCharge(item) or 0
    local battery = PS.findBestBattery(playerObj, current)
    if not battery then
        sayBad(playerObj, "IGUI_PS_NoBetterBattery")
        return
    end
    ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
    ISInventoryPaneContextMenu.transferIfNeeded(playerObj, battery)
    ISTimedActionQueue.add(ISPhotonSwordBattery:new(playerObj, item, false, battery))
end

-- Flips whether this player's swings cut. Works mid-swing and while aiming.
local function toggleCutting(playerObj)
    if not PS.canCutAnything() then
        sayBad(playerObj, "IGUI_PS_CuttingDisabled")
        return
    end
    local on = not PS.isCuttingOn(playerObj)
    PS.setCuttingOn(playerObj, on)
    if on then
        HaloTextHelper.addGoodText(playerObj, getText("IGUI_PS_CuttingOn"))
    else
        sayBad(playerObj, "IGUI_PS_CuttingOff")
    end
end

local function onKeyPressed(key)
    if key == Keyboard.KEY_NONE then return end
    local playerObj = getSpecificPlayer(0)
    -- The default key (X) also racks firearms, so it's only ours while an ignited blade is in hand.
    if key == PSO.cutKey:getValue() and playerObj and not playerObj:isDead() and not isGamePaused()
            and PS.isIgnited(PS.getHeld(playerObj)) then
        toggleCutting(playerObj)
        return
    end
    if not canAct(playerObj) then return end
    if key == PSO.toggleKey:getValue() then
        toggleBlade(playerObj)
    elseif key == PSO.batteryKey:getValue() then
        swapBattery(playerObj)
    end
end

-- Warns once when the held blade's power drops to the configured threshold. The warning
-- re-arms whenever the blade is re-ignited (igniting creates a new item).
local warnedItemID = {}

local function checkLowPower()
    local threshold = PSO.lowPowerWarning:getValue()
    if threshold <= 0 then return end
    for playerNum = 0, getNumActivePlayers() - 1 do
        local playerObj = getSpecificPlayer(playerNum)
        local blade = playerObj and PS.getHeld(playerObj)
        if blade and PS.isIgnited(blade) and PS.chargePercent(blade) <= threshold then
            if warnedItemID[playerNum] ~= blade:getID() then
                warnedItemID[playerNum] = blade:getID()
                HaloTextHelper.addBadText(playerObj, getText("IGUI_PS_LowPower", PS.chargePercent(blade)))
            end
        end
    end
end

Events.OnKeyPressed.Add(onKeyPressed)
Events.EveryOneMinute.Add(checkLowPower)
