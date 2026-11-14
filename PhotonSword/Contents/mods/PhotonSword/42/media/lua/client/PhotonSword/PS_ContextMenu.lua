require "PhotonSword/PS_Core"
require "PhotonSword/PS_Options"
require "TimedActions/ISPhotonSwordToggle"
require "TimedActions/ISPhotonSwordBattery"

local PS = PhotonSword

local function onToggle(playerObj, item, ignite)
    ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
    ISTimedActionQueue.add(ISPhotonSwordToggle:new(playerObj, item, ignite, PhotonSwordOptions.getBladeColor()))
end

local function onInsertBattery(playerObj, item, battery)
    ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
    ISInventoryPaneContextMenu.transferIfNeeded(playerObj, battery)
    ISTimedActionQueue.add(ISPhotonSwordBattery:new(playerObj, item, false, battery))
end

local function onRemoveBattery(playerObj, item)
    ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
    ISTimedActionQueue.add(ISPhotonSwordBattery:new(playerObj, item, true, nil))
end

local function onFillInventoryObjectContextMenu(player, context, items)
    local playerObj = getSpecificPlayer(player)
    items = ISInventoryPane.getActualItems(items)
    if #items ~= 1 or not PS.isPhotonSword(items[1]) then return end
    local item = items[1]

    if PS.isIgnited(item) then
        context:addOption(getText("ContextMenu_PS_Extinguish"), playerObj, onToggle, item, false)
        return
    end

    if PS.hasBattery(item) then
        local option = context:addOption(getText("ContextMenu_PS_Ignite", PS.chargePercent(item)), playerObj, onToggle, item, true)
        if PS.getCharge(item) <= 0 or item:isBroken() then
            option.notAvailable = true
        end
        local fresher = PS.findBestBattery(playerObj, PS.getCharge(item))
        if fresher then
            context:addOption(getText("ContextMenu_PS_SwapBattery", math.floor(fresher:getCurrentUsesFloat() * 100 + 0.5)), playerObj, onInsertBattery, item, fresher)
        end
        context:addOption(getText("ContextMenu_PS_RemoveBattery", PS.chargePercent(item)), playerObj, onRemoveBattery, item)
    else
        local battery = PS.findBestBattery(playerObj)
        local option = context:addOption(getText("ContextMenu_PS_InsertBattery"), playerObj, onInsertBattery, item, battery)
        if not battery then
            option.notAvailable = true
            local tooltip = ISInventoryPaneContextMenu.addToolTip()
            tooltip.description = getText("ContextMenu_PS_NoBattery")
            option.toolTip = tooltip
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
