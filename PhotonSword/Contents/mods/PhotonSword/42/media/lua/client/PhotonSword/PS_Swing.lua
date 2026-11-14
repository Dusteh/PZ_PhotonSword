require "PhotonSword/PS_Core"

-- When a local player's ignited blade reaches the hit point of a swing, ask the server to cut
-- through whatever is in front of them (PS_Cutting.lua decides what, per the sandbox options).
-- Players can switch this off for their own swings with the Toggle Cutting hotkey.

local PS = PhotonSword

local function onWeaponSwingHitPoint(character, weapon)
    if not instanceof(character, "IsoPlayer") or not character:isLocalPlayer() then return end
    if not PS.isIgnited(weapon) or not PS.canCutAnything() or not PS.isCuttingOn(character) then return end
    sendClientCommand(character, "PhotonSword", "cut", { dir = tostring(character:getDir()) })
end

Events.OnWeaponSwingHitPoint.Add(onWeaponSwingHitPoint)
