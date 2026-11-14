-- In-game tests for Photon Sword - Project A-Life (run with PSTest.run(), from Photon Sword's dev
-- kit, PS_DevKitTest.lua). Not part of the mod: deploy.sh copies it into the deployed copy
-- (media/lua/server/PhotonSwordALife/) unless run with --release.
-- The duel tests spawn two real A-Life NPCs with PSDevKit.duel (PSA_DevKit.lua) and remove them
-- at the end; the strike and bullet tests use a plain zombie as the attacker, since A-Life's
-- wound path only needs to know who struck.

if isClient() then return end

require "PhotonSword/PS_Deflect"
local PS = PhotonSword

PSTest = PSTest or {}
PSTest.suites = PSTest.suites or {}
local suite = {
    name = "Photon Sword - Project A-Life", tests = {},
    available = function()
        if not (ProjectALife and ProjectALife.Executor and ProjectALife.HumanDamage) then return false, "Project A-Life not loaded" end
        return true
    end,
}
PSTest.suites[#PSTest.suites + 1] = suite
local function test(name, fn, timeoutMs)
    suite.tests[#suite.tests + 1] = { name = name, fn = fn, timeoutMs = timeoutMs }
end

local function blade(t)
    local item = t.item(PS.BLADE_TYPE)
    PS.issueNpcBlade(item, "Blue")
    return item
end

local function noForms(t)
    local ok, PSF = pcall(require, "PhotonSwordForms/PSF_Settings")
    if ok and type(PSF) == "table" and PSF.guardingForm then t.stub(PSF, "guardingForm", function() return nil end) end
end

-- The duel shared by the duel tests: spawned by the first, removed by the last.
local duel = nil

local function duelists(t)
    if not duel then t.skip("the duel didn't start") end
    local found = PSDevKit.duelists()
    if #found < 2 then t.skip("the duellists are gone") end
    return found[1].shell, found[2].shell
end

test("sandbox options load", function(t)
    local vars = SandboxVars.PhotonSwordALife
    t.need(type(vars) == "table", "no PhotonSwordALife sandbox page")
    t.ok(vars.SpawnChance ~= nil, "SpawnChance not loaded")
    t.ok(vars.BladeColor ~= nil, "BladeColor not loaded")
end)

test("photon swords are kept out of mod loot", function(t)
    local data = ProjectALife.ModLootData
    if not (data and type(data.excludeExact) == "table") then t.skip("A-Life has no mod loot list") end
    t.ok(data.excludeExact[PS.BLADE_TYPE] == true, "the blade isn't excluded")
    t.ok(data.excludeExact[PS.HILT_TYPE] == true, "the hilt isn't excluded")
end)

test("guard blocks an A-Life NPC's sword strike", function(t)
    noForms(t)
    local npc = t.zombie(1.5, 0)
    t.wait(200)
    t.guard(npc)
    t.hurts()
    t.sandbox("PhotonSword", "BlockChanceMin", 100)
    t.sandbox("PhotonSword", "BlockChanceMax", 100)
    local before = t.health()
    ProjectALife.Executor.woundPlayer(t.player, PS.BLADE_TYPE, blade(t), -1, npc)
    t.ok(t.health() >= before, "the blocked strike hurt the player")
end)

test("an unblocked A-Life sword strike lands", function(t)
    noForms(t)
    local npc = t.zombie(1.5, 0)
    t.wait(200)
    t.guard(npc)
    t.hurts()
    t.mortal()
    t.sandbox("PhotonSword", "BlockChanceMin", 0)
    t.sandbox("PhotonSword", "BlockChanceMax", 0)
    local before = t.health()
    ProjectALife.Executor.woundPlayer(t.player, PS.BLADE_TYPE, blade(t), -1, npc)
    t.ok(t.health() < before, "the strike didn't land (is the patch blocking everything?)")
end)

test("guard deflects an A-Life NPC's bullet", function(t)
    noForms(t)
    local npc = t.zombie(2, 0)
    t.wait(200)
    t.guard(npc)
    t.hurts()
    t.sandbox("PhotonSword", "DeflectChanceMin", 100)
    t.sandbox("PhotonSword", "DeflectChanceMax", 100)
    local before = t.health()
    ProjectALife.Executor.woundPlayer(t.player, "Base.Pistol", instanceItem("Base.Pistol"), -1, npc)
    t.ok(t.health() >= before, "the deflected bullet hurt the player")
end)

test("duel: two NPCs spawn with lit photon swords", function(t)
    t.need(PSDevKit and PSDevKit.duel, "PSA_DevKit.lua isn't loaded")
    duel = PSDevKit.duel({ distance = 4 })
    t.need(duel ~= nil, "A-Life refused the duel spawn (see the console)")
    t.need(t.waitFor(function() return #PSDevKit.duelists() >= 2 end, 30000), "the duellists didn't arrive")
    local colors = {}
    for _, duelist in ipairs(PSDevKit.duelists()) do
        local held = duelist.shell:getPrimaryHandItem()
        t.ok(PS.isIgnited(held), "a duellist isn't holding the photon sword")
        if PS.isIgnited(held) then
            t.ok(held:getModData().PS_npcIssued == true, "a duellist's sword wasn't issued")
            colors[PS.getBladeColor(held)] = true
        end
    end
    t.ok(colors.Blue and colors.Red, "the duellists' blades aren't blue and red")
end, 40000)

test("duel: blades light for the fight", function(t)
    local a, b = duelists(t)
    t.ok(t.waitFor(function() return PS.isNpcLit(a) and PS.isNpcLit(b) end, 30000), "the blades didn't light (did they fight?)")
end, 40000)

test("duel: NPCs block each other's strikes", function(t)
    local a, b = duelists(t)
    t.sandbox("PhotonSword", "NpcVsNpcBlockChance", 100)
    local blocks = 0
    local npcBlocks = PS.npcBlocks
    t.stub(PS, "npcBlocks", function(attacker, npc, weapon)
        local blocked = npcBlocks(attacker, npc, weapon)
        if blocked and (npc == a or npc == b) then blocks = blocks + 1 end
        return blocked
    end)
    local healthA, healthB = a:getHealth(), b:getHealth()
    t.ok(t.waitFor(function() return blocks > 0 end, 30000), "no strike was blocked in 30 s")
    t.ok(a:getHealth() >= healthA and b:getHealth() >= healthB, "a duellist was hurt while every strike was blocked")
end, 40000)

test("duel: a block is A-Life's blocked hit", function(t)
    local a, b = duelists(t)
    t.stub(PS, "npcBlocks", function() return true end)
    local applied, dealt, _, outcome = ProjectALife.HumanDamage.apply(a, b, a:getPrimaryHandItem(), 1)
    t.ok(applied, "HumanDamage.apply didn't settle the blow")
    t.eq(outcome, "blocked", "outcome")
    t.eq(dealt, 0, "damage dealt")
end)

test("duel: a blocking NPC plays A-Life's parry, not a stagger", function(t)
    local a = duelists(t)
    local Animations = ProjectALife.Animations
    t.need(Animations and Animations.presetOf, "A-Life's animations aren't there")
    t.need(Animations.presetOf("ps_parry") ~= nil, "the ps_parry preset isn't registered")
    PS.playNpcParry(a)
    t.eq(Animations.current[a], "ps_parry", "A-Life's animation")
    t.ok(PS.parrying(a, 850), "the parry wasn't noted")
    Animations.apply(a, "hit_react")
    t.eq(Animations.current[a], "ps_parry", "A-Life's animation after a stagger")
end)

test("duel: a player's strike can be blocked", function(t)
    local _, b = duelists(t)
    local Fence = ProjectALife.AIFence
    if not (Fence and Fence.weighBlow and Fence.pendingHit) then t.skip("A-Life's hit weighing isn't there") end
    t.stub(PS, "npcBlocks", function() return true end)
    Fence.weighBlow(b, t.player, "Torso_Upper", blade(t), false)
    local pending = Fence.pendingHit[b]
    t.ok(pending and pending.blocked == true, "the blow wasn't weighed as blocked")
end)

test("duel: clean up", function(t)
    if not duel then t.skip("no duel to end") end
    local _, failed = PSDevKit.endDuel()
    t.eq(failed, 0, "duellists A-Life refused to remove")
    duel = nil
    -- A-Life restores a shell that only goes missing; a removed actor stays gone.
    t.wait(3000)
    t.eq(PSDevKit.duelActorCount(), 0, "duel actors A-Life still has")
end, 10000)
