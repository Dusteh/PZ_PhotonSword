-- In-game tests for Photon Sword Forms (run with PSTest.run(), from Photon Sword's dev kit,
-- PS_DevKitTest.lua). Not part of the mod: deploy.sh copies it into the deployed copy
-- (media/lua/server/PhotonSwordForms/) unless run with --release.
-- The Form's guard is put up by stubbing PSF.guardingForm and PS.guardUp, so these check the
-- Form's rules (block chance, meter, who settles player blows), not Martial Arts Core's key handling.

if isClient() then return end

local PSF = require "PhotonSwordForms/PSF_Forms"
local SMA = require "SMA_Core"
require "PhotonSwordForms/PSF_Deflect"
local PS = PhotonSword

PSTest = PSTest or {}
PSTest.suites = PSTest.suites or {}
local suite = { name = "Photon Sword Forms", tests = {} }
PSTest.suites[#PSTest.suites + 1] = suite
local function test(name, fn, timeoutMs)
    suite.tests[#suite.tests + 1] = { name = name, fn = fn, timeoutMs = timeoutMs }
end

local function guardingForm()
    for _, W in ipairs(PSF.forms) do
        if W.guard then return W end
    end
    return nil
end

-- The player's Form guard up, facing who, with a full meter (restored after).
local function formGuard(t, who)
    local W = guardingForm()
    t.need(W ~= nil, "no Form guards")
    t.stub(PSF, "guardingForm", function(player) return player == t.player and W or nil end)
    t.guard(who)
    local g = SMA.guardState(t.player)
    local meter, brokenUntil = g.meter, g.brokenUntil
    g.meter = 100
    t.cleanup(function() g.meter, g.brokenUntil = meter, brokenUntil end)
    return W, g
end

local function blade(t)
    local item = t.item(PS.BLADE_TYPE)
    PS.issueNpcBlade(item, "Blue")
    return item
end

test("Form 1 is registered and guards", function(t)
    t.need(#PSF.forms >= 1, "no Forms registered")
    t.ok(guardingForm() ~= nil, "no Form has guard = true")
    t.ok(getScriptManager():FindItem(PSF.forms[1].book) ~= nil, "the Form 1 manual item is missing")
end)

test("sandbox options load", function(t)
    local vars = SandboxVars.PhotonSwordForms
    t.need(type(vars) == "table", "no PhotonSwordForms sandbox page")
    t.ok(vars.GuardDrainMultiplier ~= nil, "GuardDrainMultiplier not loaded")
end)

test("a Form's block always holds against a photon sword", function(t)
    local npc = t.zombie(1.5, 0)
    t.wait(200)
    formGuard(t, npc)
    t.sandbox("PhotonSword", "BlockChanceMin", 0)
    t.sandbox("PhotonSword", "BlockChanceMax", 0)
    t.eq(PS.blockChance(t.player), 100, "Form block chance")
    t.ok(PS.judgeBlow(npc, t.player, blade(t)), "an NPC's strike wasn't blocked by the Form")
end)

test("blocks drain the guard meter", function(t)
    local npc = t.zombie(1.5, 0)
    t.wait(200)
    local _, g = formGuard(t, npc)
    t.sandbox("PhotonSwordForms", "GuardDrainMultiplier", 1)
    local sword = blade(t)
    t.ok(PS.guardDrain(npc, t.player, sword) > 0, "a block costs nothing")
    t.ok(PS.judgeBlow(npc, t.player, sword), "the block didn't hold")
    t.ok(g.meter < 100, "the meter didn't drain")
    t.sandbox("PhotonSwordForms", "GuardDrainMultiplier", 0)
    t.eq(PS.guardDrain(npc, t.player, sword), 0, "drain with Guard Drain at 0")
end)

test("an empty meter breaks the guard", function(t)
    local npc = t.zombie(1.5, 0)
    t.wait(200)
    local _, g = formGuard(t, npc)
    t.sandbox("PhotonSwordForms", "GuardDrainMultiplier", 1)
    g.meter = 1
    t.ok(not PS.judgeBlow(npc, t.player, blade(t)), "a meter that can't pay still blocked")
end)

test("players' blows are left to Martial Arts Core", function(t)
    local npc = t.zombie(1.5, 0)
    t.wait(200)
    formGuard(t, npc)
    t.ok(PS.meleeGuardHandled(t.player, t.player), "a player's blow isn't left to Core")
    t.ok(not PS.meleeGuardHandled(npc, t.player), "an NPC's blow is left to Core")
end)

test("without a guarding Form, Photon Sword's rules apply", function(t)
    t.stub(PSF, "guardingForm", function() return nil end)
    t.sandbox("PhotonSword", "BlockChanceMin", 30)
    t.sandbox("PhotonSword", "BlockChanceMax", 30)
    t.eq(PS.blockChance(t.player), 30, "block chance without a Form")
    t.ok(not PS.meleeGuardHandled(t.player, t.player), "Core settles blows without a Form")
end)

test("Martial Arts Core's blocks parry, its other drains don't", function(t)
    t.need(PSF.newCoreBlock and PSF.photonStamps and PSF.struckAt, "PSF_Core.lua has no Core block parry")
    local g = SMA.guardState(t.player)
    local lastHit, struck, stamp = g.lastHit, PSF.struckAt[t.player], PSF.photonStamps[t.player]
    t.cleanup(function()
        g.lastHit, PSF.struckAt[t.player], PSF.photonStamps[t.player] = lastHit, struck, stamp
    end)
    local seen = {}
    local now = getTimestampMs()
    PSF.struckAt[t.player], g.lastHit = now, now
    t.ok(PSF.newCoreBlock(t.player, seen), "Core's block of a blow wasn't seen")
    t.ok(not PSF.newCoreBlock(t.player, seen), "the same block was seen twice")
    g.lastHit = now + 1
    PSF.photonStamps[t.player] = g.lastHit
    t.ok(not PSF.newCoreBlock(t.player, seen), "Photon Sword's drain was taken for Core's block")
    PSF.struckAt[t.player], g.lastHit = now - 1000, now + 2
    t.ok(not PSF.newCoreBlock(t.player, seen), "a push (no blow struck) was taken for a block")
    PSF.struckAt[t.player], g.lastHit = now - 2000, now - 1000
    t.ok(not PSF.newCoreBlock(t.player, seen), "a stale block parried")
end)

test("a Form's block parries Photon Sword's blocks", function(t)
    if isServer() then t.skip("the parry is noted on the clients") end
    local npc = t.zombie(1.5, 0)
    t.wait(200)
    formGuard(t, npc)
    PS.parries[t.player] = nil
    t.ok(PS.judgeBlow(npc, t.player, blade(t)), "the Form's block didn't hold")
    t.ok(PS.parrying(t.player, 450), "the block wasn't noted as a parry")
end)
