require "TimedActions/ISBaseTimedAction"
require "PhotonSword/PS_Core"

-- Inserts a battery into a hilt (battery is consumed, its charge moves to the hilt), or
-- removes it (a battery holding the remaining charge goes back to the inventory).
-- Inserting into a hilt that already has a battery swaps them in one action.
-- Only inert hilts accept or give up a battery.
ISPhotonSwordBattery = ISBaseTimedAction:derive("ISPhotonSwordBattery")

function ISPhotonSwordBattery:isValid()
    if not self.item or PhotonSword.isIgnited(self.item) then return false end
    if self.isRemove and not PhotonSword.hasBattery(self.item) then return false end
    if isClient() then return true end
    local inv = self.character:getInventory()
    if not inv:contains(self.item) then return false end
    return self.isRemove or inv:contains(self.battery)
end

function ISPhotonSwordBattery:start()
    if isClient() then
        local inv = self.character:getInventory()
        self.item = inv:getItemById(self.item:getID())
        if self.battery then
            self.battery = inv:getItemById(self.battery:getID())
        end
    end
end

function ISPhotonSwordBattery:stop()
    ISBaseTimedAction.stop(self)
end

function ISPhotonSwordBattery:perform()
    -- needed to remove from queue / start next.
    ISBaseTimedAction.perform(self)
end

function ISPhotonSwordBattery:complete()
    local inv = self.character:getInventory()
    if PhotonSword.hasBattery(self.item) then
        local battery = instanceItem(PhotonSword.BATTERY_TYPE)
        battery:setUsedDelta(PhotonSword.getCharge(self.item))
        inv:AddItem(battery)
        sendAddItemToContainer(inv, battery)
        PhotonSword.setCharge(self.item, nil)
    end
    if not self.isRemove then
        PhotonSword.setCharge(self.item, self.battery:getCurrentUsesFloat())
        inv:Remove(self.battery)
        sendRemoveItemFromContainer(inv, self.battery)
    end
    syncItemModData(self.character, self.item)
    return true
end

function ISPhotonSwordBattery:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return 30
end

-- battery is required when inserting and ignored when removing.
function ISPhotonSwordBattery:new(character, item, isRemove, battery)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.isRemove = isRemove
    o.battery = battery
    o.stopOnWalk = false
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end
