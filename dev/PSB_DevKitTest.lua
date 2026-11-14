-- In-game tests for Photon Sword - Bandits (run with PSTest.run(), from Photon Sword's dev kit,
-- PS_DevKitTest.lua). Not part of the mod: deploy.sh copies it into the deployed copy
-- (media/lua/server/PhotonSwordBandits/) unless run with --release.
-- Bandits' hits on players are called directly with a plain zombie as the bandit, which is all
-- PlayerDamageModel needs. Not covered here: arming bandits as Bandits spawns them, and a bandit's
-- swing at another NPC (ZASmack), which need a live bandit fight; see docs/NPC_PATCHES.md.

if isClient() then return end

require "PhotonSword/PS_Deflect"
local PS = PhotonSword

PSTest = PSTest or {}
PSTest.suites = PSTest.suites or {}
local suite = {
    name = "Photon Sword - Bandits", tests = {},
    available = function()
        if not (PlayerDamageModel and BanditCompatibility) then return false, "Bandits not loaded" end
        return true
    end,
}
PSTest.suites[#PSTest.suites + 1] = suite
local function test(name, fn, timeoutMs)
    suite.tests[#suite.tests + 1] = { name = name, fn = fn, timeoutMs = timeoutMs }
end

local function noForms(t)
    local ok, PSF = pcall(require, "PhotonSwordForms/PSF_Settings")
    if ok and type(PSF) == "table" and PSF.guardingForm then t.stub(PSF, "guardingForm", function() return nil end) end
end

-- A sword the way Bandits makes one (BanditCompatibility.InstanceItem, which the patch issues).
local function banditSword(t)
    local item = BanditCompatibility.InstanceItem(PS.BLADE_TYPE)
    t.need(item ~= nil, "Bandits couldn't make the sword")
    return item
end

test("sandbox options load", function(t)
    local vars = SandboxVars.PhotonSwordBandits
    t.need(type(vars) == "table", "no PhotonSwordBandits sandbox page")
    t.ok(vars.SpawnChance ~= nil, "SpawnChance not loaded")
    t.ok(vars.BladeColor ~= nil, "BladeColor not loaded")
end)

test("swords Bandits makes are issued", function(t)
    local item = banditSword(t)
    t.ok(item:getModData().PS_npcIssued == true, "BanditCompatibility.InstanceItem didn't issue the sword")
    local plain = instanceItem(PS.BLADE_TYPE)
    t.ok(math.abs(item:getMaxDamage() - plain:getMaxDamage() * PS.getDamageMultiplier()) < .001,
        "the damage multiplier wasn't applied")
end)

test("guard blocks a bandit's sword strike", function(t)
    noForms(t)
    local bandit = t.zombie(1.5, 0)
    t.wait(200)
    t.guard(bandit)
    t.hurts()
    t.sandbox("PhotonSword", "BlockChanceMin", 100)
    t.sandbox("PhotonSword", "BlockChanceMax", 100)
    local before = t.health()
    PlayerDamageModel.MeleeHit(bandit, t.player, banditSword(t))
    t.ok(t.health() >= before, "the blocked strike hurt the player")
end)

test("an unblocked bandit strike lands", function(t)
    noForms(t)
    local bandit = t.zombie(1.5, 0)
    t.wait(200)
    t.guard(bandit)
    t.hurts()
    t.mortal()
    t.sandbox("PhotonSword", "BlockChanceMin", 0)
    t.sandbox("PhotonSword", "BlockChanceMax", 0)
    local before = t.health()
    PlayerDamageModel.MeleeHit(bandit, t.player, banditSword(t))
    t.ok(t.health() < before, "the strike didn't land (is the patch blocking everything?)")
end)

test("guard deflects a bandit's bullet back", function(t)
    noForms(t)
    local bandit = t.zombie(2, 0)
    t.wait(200)
    t.guard(bandit)
    t.hurts()
    t.sandbox("PhotonSword", "DeflectChanceMin", 100)
    t.sandbox("PhotonSword", "DeflectChanceMax", 100)
    t.sandbox("PhotonSword", "DeflectStrikesBack", true)
    local before, banditBefore = t.health(), bandit:getHealth()
    PlayerDamageModel.BulletHit(bandit, instanceItem("Base.Pistol"), t.player)
    t.ok(t.health() >= before, "the deflected bullet hurt the player")
    t.ok(bandit:isDead() or bandit:getHealth() < banditBefore, "the bandit wasn't struck back")
end)

test("a parrying bandit's next swing waits", function(t)
    local Smack = ZombieActions and ZombieActions.Smack
    t.need(Smack and Smack.onStart, "Bandits' Smack isn't there")
    local bandit = t.zombie(1.5, 0)
    t.wait(200)
    bandit:setPrimaryHandItem(banditSword(t))
    PS.playNpcParry(bandit)
    t.eq(bandit:getBumpType(), "PSParry", "the bandit's BumpType")
    t.ok(not Smack.onStart(bandit, { weapon = PS.BLADE_TYPE, eid = "none" }), "the swing started during the parry")
end)
