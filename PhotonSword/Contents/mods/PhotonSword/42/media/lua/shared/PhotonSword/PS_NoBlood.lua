require "PhotonSword/PS_Core"

-- An ignited blade cauterizes as it cuts, so it never shows blood. The game raises a held
-- weapon's blood level on hits (IsoGameCharacter.addBlood) with no item-script switch to stop it,
-- so each side keeps its own copy of a held blade clean. Hilts are left alone, and igniting or
-- extinguishing creates a fresh item, so blood never carries across.

local PS = PhotonSword

local function onPlayerUpdate(playerObj)
    local blade = PS.getHeld(playerObj)
    if blade and PS.isIgnited(blade) and blade:getBloodLevel() > 0 then
        blade:setBloodLevel(0)
    end
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
