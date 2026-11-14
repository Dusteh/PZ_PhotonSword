require "TimedActions/ISBaseTimedAction"
require "PhotonSword/PS_Core"

-- Ignites a hilt into a blade, or extinguishes a blade back into a hilt.
-- color (ignite only) is the igniting player's Blade Color choice.
ISPhotonSwordToggle = ISBaseTimedAction:derive("ISPhotonSwordToggle")

function ISPhotonSwordToggle:isValid()
    if not self.item or self.item:isBroken() then return false end
    if PhotonSword.isIgnited(self.item) == self.ignite then return false end
    if self.ignite and PhotonSword.getCharge(self.item) <= 0 then return false end
    return isClient() or self.character:getInventory():contains(self.item)
end

function ISPhotonSwordToggle:start()
    if isClient() then
        self.item = self.character:getInventory():getItemById(self.item:getID())
    end
end

function ISPhotonSwordToggle:stop()
    ISBaseTimedAction.stop(self)
end

function ISPhotonSwordToggle:perform()
    self.character:playSound(self.ignite and PhotonSword.IGNITE_SOUND or PhotonSword.EXTINGUISH_SOUND)
    -- needed to remove from queue / start next.
    ISBaseTimedAction.perform(self)
end

function ISPhotonSwordToggle:complete()
    PhotonSword.swap(self.character, self.item, self.ignite, self.color)
    return true
end

function ISPhotonSwordToggle:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return 15
end

function ISPhotonSwordToggle:new(character, item, ignite, color)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.ignite = ignite
    o.color = color
    o.stopOnWalk = false
    o.stopOnRun = false
    -- Usable from the attack-ready stance, like vanilla's Rack Firearm.
    o.stopOnAim = false
    o.useProgressBar = not character:isAiming()
    o.maxTime = o:getDuration()
    return o
end
