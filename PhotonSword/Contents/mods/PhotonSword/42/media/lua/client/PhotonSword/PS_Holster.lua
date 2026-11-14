require "PhotonSword/PS_Core"
require "PhotonSword/PS_Options"
require "TimedActions/ISPhotonSwordToggle"
require "TimedActions/ISUnequipAction"
require "TimedActions/ISAttachItemHotbar"

-- Auto-extinguish: a blade that goes back on the hotbar (holstered from the hands, or attached
-- to a slot while out of the hands) queues a normal extinguish action, so the swap still runs
-- with server authority and keeps the hotbar binding (see PS.swap).

local PS = PhotonSword
local PSO = PhotonSwordOptions

local function queueExtinguish(character, item)
    if not PSO.extinguishOnHolster:getValue() then return end
    if not PS.isIgnited(item) or item:getAttachedSlot() < 0 then return end
    ISTimedActionQueue.add(ISPhotonSwordToggle:new(character, item, false))
end

-- perform() runs before complete() takes the item out of the hands, so don't check hands here:
-- an unequip that reaches perform() always finishes, and the extinguish queues right after it.
local unequipPerform = ISUnequipAction.perform
function ISUnequipAction:perform(...)
    local character, item = self.character, self.item
    local results = PS.pack(unequipPerform(self, ...))
    queueExtinguish(character, item)
    return unpack(results, 1, results.n)
end

-- Attaching doesn't change hands, so a blade still held here stays lit until it's put away.
local attachPerform = ISAttachItemHotbar.perform
function ISAttachItemHotbar:perform(...)
    local character, item = self.character, self.item
    local results = PS.pack(attachPerform(self, ...))
    if not character:isHandItem(item) then
        queueExtinguish(character, item)
    end
    return unpack(results, 1, results.n)
end
