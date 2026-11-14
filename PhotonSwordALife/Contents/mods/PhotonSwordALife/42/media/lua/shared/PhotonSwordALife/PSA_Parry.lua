-- Photon Sword - Project A-Life: an NPC whose photon sword blocks a strike parries.
--
-- Photon Sword plays the parry on an NPC by BumpType (PS.playNpcParry: its zombie "bumped" node
-- PS_parry, the ready stance's PS_Parry). A-Life runs its NPCs' animations itself
-- (ProjectALife.Animations: presets played in the same bumped state, synced to the other clients),
-- so here the parry is an A-Life preset, ps_parry, played with Animations.apply. While it plays, the
-- hit reaction A-Life would follow a blocked blow with (hit_react, or HurtAnim's wound reactions) is
-- left out, so the stagger doesn't cut the parry off.

local PS = require "PhotonSword/PS_Deflect"

local PRESET = "ps_parry"
local PARRY_MS = 850   -- PS_Parry, less its blend back

local installed = false
local function install()
    if installed then return end
    local Animations = ProjectALife and ProjectALife.Animations
    if type(Animations) ~= "table" or type(Animations.apply) ~= "function"
            or type(Animations.registerPreset) ~= "function" then
        print("[PhotonSwordALife] ProjectALife.Animations not found; NPC parries play as Photon Sword's own")
        return
    end
    installed = true
    if not Animations.presetOf or not Animations.presetOf(PRESET) then
        local ok, refusal = Animations.registerPreset({ id = PRESET, bumpType = "PSParry", hidden = true,
            combat = true, timeoutMs = 900 })
        if not ok then print("[PhotonSwordALife] A-Life refused the parry preset (" .. tostring(refusal) .. ")") end
    end

    local function actor(npc)
        local data = npc:getModData()
        return data.ProjectALifeActor == true or data.ProjectALifeOwned == true or data.ProjectALifeUID ~= nil
    end

    local play = PS.playNpcParry
    PS.playNpcParry = function(npc)
        if not actor(npc) then return play(npc) end
        PS.noteParry(npc)
        pcall(Animations.apply, npc, PRESET, true)
    end

    local apply = Animations.apply
    Animations.apply = function(shell, id, ...)
        if shell and Animations.reactions and Animations.reactions[id] == true and PS.parrying(shell, PARRY_MS) then
            return true
        end
        return apply(shell, id, ...)
    end

    local Hurt = ProjectALife.HurtAnim
    if type(Hurt) == "table" and type(Hurt.react) == "function" then
        local react = Hurt.react
        Hurt.react = function(shell, ...)
            if shell and PS.parrying(shell, PARRY_MS) then return true end
            return react(shell, ...)
        end
    end
    print("[PhotonSwordALife] NPC parries patched")
end

Events.OnGameStart.Add(install)
if Events.OnServerStarted then Events.OnServerStarted.Add(install) end
