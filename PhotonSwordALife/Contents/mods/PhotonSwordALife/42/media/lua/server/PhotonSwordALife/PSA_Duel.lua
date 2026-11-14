-- Photon Sword - Project A-Life: an A-Life NPC's photon sword blocks another NPC's.
--
-- A-Life lands an NPC's blow on another NPC through ProjectALife.HumanDamage.apply(attacker, target,
-- weapon, scale), which asks HumanDamage.shielded(target, zone, weapon) whether armor stops it and,
-- if so, settles it as blocked (no damage, no hurt cry, shown as A-Life shows an armor block).
-- Wrapped, shielded also says so when the target's photon sword blocks an NPC's photon sword strike
-- (PS.npcBlocks, at NPC vs NPC Block Chance); shielded doesn't say who struck, so apply is wrapped
-- to note the attacker while it runs. A-Life settles these where it runs NPCs: single player, or the
-- multiplayer server.

local PS = require "PhotonSword/PS_Deflect"

local striker = nil   -- the attacker of the blow HumanDamage.apply is settling

local function pack(...) return { n = select("#", ...), ... } end

local installed = false
local function install()
    if installed then return end
    local HumanDamage = ProjectALife and ProjectALife.HumanDamage
    if type(HumanDamage) ~= "table" or type(HumanDamage.apply) ~= "function" or type(HumanDamage.shielded) ~= "function" then
        print("[PhotonSwordALife] HumanDamage.apply or HumanDamage.shielded not found; NPC duels not patched")
        return
    end
    installed = true

    local apply = HumanDamage.apply
    HumanDamage.apply = function(attacker, ...)
        local previous = striker
        striker = attacker
        local result = pack(pcall(apply, attacker, ...))
        striker = previous
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end

    local shielded = HumanDamage.shielded
    HumanDamage.shielded = function(target, zone, weapon, ...)
        if striker and instanceof(striker, "IsoZombie") and PS.npcBlocks(striker, target, weapon) then return true end
        return shielded(target, zone, weapon, ...)
    end
    print("[PhotonSwordALife] NPC duels patched")
end

Events.OnGameStart.Add(install)
if Events.OnServerStarted then Events.OnServerStarted.Add(install) end
