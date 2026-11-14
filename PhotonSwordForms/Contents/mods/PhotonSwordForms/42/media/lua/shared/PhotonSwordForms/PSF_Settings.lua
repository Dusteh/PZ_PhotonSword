-- Sandbox options (media/sandbox-options.txt, the Photon Sword Forms page): balance the server
-- decides. Deflecting's own options are Photon Sword's (PS_Deflect.lua); GuardDrainMultiplier scales
-- what it costs a Form's guard (PSF_Deflect.lua). ExtinguishWhileDodging: PSF_Dodging.lua.

local PSF = require "PhotonSwordForms/PSF_Core"

-- The sandbox defaults, for when SandboxVars aren't loaded.
local DEFAULTS = {
    FormMasteryDamage = 10,
    ExtinguishWhileDodging = true,
    GuardDrainMultiplier = 1,
}

function PSF.sandbox(name)
    local vars = SandboxVars and SandboxVars.PhotonSwordForms
    local value = vars and vars[name]
    if value == nil then return DEFAULTS[name] end
    return value
end

-- Form mastery adds to a Form's damage: FormMasteryDamage percent a mastery level. Senator's
-- Progression (registered for each Form in PSF_Core.lua) sets the sword's damage for every strike
-- from damageScale, and the Photon Sword tab shows it.
local Progression = require "SWMA_Progression"
local damageScale = Progression.damageScale
function Progression.damageScale(W, player)
    local scale = damageScale(W, player)
    if W and player and PSF.byId[W.id] == W then
        scale = scale * (1 + PSF.sandbox("FormMasteryDamage") / 100 * W.mastery(player))
    end
    return scale
end

return PSF
