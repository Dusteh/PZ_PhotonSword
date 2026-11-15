-- In-game test suite for Photon Sword and its sub-mods. Not part of the mod: deploy.sh copies it
-- into the deployed copy (media/lua/server/PhotonSword/) unless run with --release, and the
-- Workshop folder never contains it.
--
-- In the debug Lua console (single player, with the dev kits deployed):
--   PSTest.run()            every suite of the mods that are loaded
--   PSTest.run("bandits")   suites whose name contains the text (any case)
--   PSTest.list()           the suites and their tests
-- Results go to the console, to a halo over the player, and to Zomboid/Lua/PhotonSwordTests.log.
--
-- Each mod's dev kit adds its own suite (PS_DevKitTest.lua here, PSF_DevKitTest.lua,
-- PSA_DevKitTest.lua, PSB_DevKitTest.lua), registered in PSTest.suites whatever order they load.
-- A test is a function(t), run as a coroutine on OnTick so it can wait for the game:
--   t.ok(cond, msg) / t.eq(got, want, msg)   check (a failure is recorded, the test goes on)
--   t.need(cond, msg)                        check, ending the test on failure
--   t.skip(reason)                           end the test as skipped
--   t.wait(ms)                               wait real time
--   t.waitFor(fn, ms)                        wait until fn() is true; returns whether it was
--   t.sandbox(page, key, value)              set a sandbox option for this test
--   t.stub(tbl, key, value)                  replace a field for this test
--   t.zombie(dx, dy)                         a docile zombie this many tiles from the player
--   t.item(type)                             a new item in the player's inventory
--   t.guard(toward)                          the player's guard up, facing a character
--   t.health() / t.mortal() / t.hurts()      player health; skip if it can't drop; heal after
--   t.cleanup(fn)                            run after the test
-- Everything a test sets, stubs, spawns, or adds is undone when it ends, and a test that hurt the
-- player (t.hurts()) heals them.

if isClient() then return end

require "PhotonSword/PS_Core"
require "PhotonSword/PS_Deflect"
require "TimedActions/ISPhotonSwordToggle"
local PS = PhotonSword

PSTest = PSTest or {}
PSTest.suites = PSTest.suites or {}

local TEST_TIMEOUT_MS = 90000
local LOG_FILE = "PhotonSwordTests.log"
local ABORT, SKIP = {}, {}

local run = nil   -- the run in progress

local function log(line)
    print("[PSTest] " .. line)
    if run then run.lines[#run.lines + 1] = line end
end

-- The test context.
local function context(test)
    local t = { player = getPlayer(), failures = {}, undo = {}, test = test }

    function t.cleanup(fn) table.insert(t.undo, 1, fn) end

    function t.ok(cond, msg)
        if not cond then t.failures[#t.failures + 1] = msg or "check failed" end
        return cond and true or false
    end

    function t.eq(got, want, msg)
        return t.ok(got == want, (msg or "values differ") .. ": got " .. tostring(got) .. ", want " .. tostring(want))
    end

    -- These end the test by yielding to the runner, not by error(): an error inside a coroutine
    -- leaves the game's Lua (Kahlua) unable to resume it or report it.
    function t.need(cond, msg)
        if not t.ok(cond, msg) then coroutine.yield(ABORT) end
    end

    function t.skip(reason)
        t.skipped = reason or "skipped"
        coroutine.yield(SKIP)
    end

    function t.wait(ms)
        local untilMs = getTimestampMs() + ms
        coroutine.yield(function() return getTimestampMs() >= untilMs end)
    end

    function t.waitFor(fn, ms)
        local untilMs = getTimestampMs() + (ms or 10000)
        local met = false
        coroutine.yield(function()
            met = fn() and true or false
            return met or getTimestampMs() >= untilMs
        end)
        return met
    end

    function t.stub(tbl, key, value)
        local old = tbl[key]
        tbl[key] = value
        t.cleanup(function() tbl[key] = old end)
    end

    function t.sandbox(page, key, value)
        SandboxVars[page] = SandboxVars[page] or {}
        t.stub(SandboxVars[page], key, value)
    end

    function t.zombie(dx, dy)
        local p = t.player
        local x, y = math.floor(p:getX() + dx), math.floor(p:getY() + dy)
        local zombie = nil
        for _, outfit in ipairs({ "Generic01", "Tourist" }) do
            local ok, list = pcall(addZombiesInOutfit, x, y, p:getZ(), 1, outfit, 50)
            if ok and list and list:size() > 0 then zombie = list:get(0); break end
        end
        t.need(zombie ~= nil, "couldn't spawn a test zombie")
        pcall(zombie.setUseless, zombie, true)
        zombie:setX(p:getX() + dx)
        zombie:setY(p:getY() + dy)
        t.cleanup(function()
            zombie:removeFromWorld()
            zombie:removeFromSquare()
        end)
        return zombie
    end

    function t.item(fullType)
        local inv = t.player:getInventory()
        local item = inv:AddItem(fullType)
        t.need(item ~= nil, "couldn't make " .. fullType)
        t.cleanup(function()
            -- The item may have been swapped for another (ignite, extinguish); remove what's left.
            if item:getContainer() then item:getContainer():Remove(item) end
        end)
        return item
    end

    -- The player's guard up and facing who, without the stance or a Form's block: the tests check
    -- the guard's rules, not the animation that raises it.
    function t.guard(who)
        t.stub(PS, "guardUp", function() return true end)
        t.stub(PS, "guardFacing", function(player)
            local dx, dy = who:getX() - player:getX(), who:getY() - player:getY()
            local d = math.max(.01, math.sqrt(dx * dx + dy * dy))
            return dx / d, dy / d, .25
        end)
    end

    -- With Photon Sword Forms, a player whose Form guards gets the Form's rules (always blocks,
    -- the meter). The core tests want Photon Sword's own.
    function t.noForms()
        local ok, PSF = pcall(require, "PhotonSwordForms/PSF_Settings")
        if ok and type(PSF) == "table" and PSF.guardingForm then
            t.stub(PSF, "guardingForm", function() return nil end)
        end
    end

    -- The player's health now: the body parts' sum (the overall figure only catches up on the
    -- body's next update).
    function t.health()
        local parts, total = t.player:getBodyDamage():getBodyParts(), 0
        for i = 0, parts:size() - 1 do total = total + parts:get(i):getHealth() end
        return total
    end

    -- For a test that needs the player to take damage.
    function t.mortal()
        local p = t.player
        if (p.isGodMod and p:isGodMod()) or (p.isInvincible and p:isInvincible()) then
            t.skip("the player is in god mode or invincible")
        end
    end

    function t.hurts()
        t.cleanup(function()
            local body = t.player:getBodyDamage()
            body:RestoreToFullHealth()
        end)
    end

    return t
end

local function finish(entry, status, detail)
    local t = entry.t
    for _, fn in ipairs(t.undo) do
        local ok, err = pcall(fn)
        if not ok then t.failures[#t.failures + 1] = "cleanup: " .. tostring(err) end
    end
    if status == "PASS" and #t.failures > 0 then status = "FAIL" end
    if status == "FAIL" and #t.failures == 0 and detail then t.failures[1] = detail end
    run.counts[status] = run.counts[status] + 1
    local line = status .. "  " .. entry.suite.name .. ": " .. entry.test.name
    if status == "SKIP" then line = line .. "  (" .. tostring(t.skipped) .. ")" end
    log(line)
    if status == "FAIL" then
        for _, msg in ipairs(t.failures) do log("        - " .. msg) end
    end
end

local function report()
    local c = run.counts
    local summary = string.format("%d passed, %d failed, %d skipped", c.PASS, c.FAIL, c.SKIP)
    log("Done: " .. summary .. " (" .. math.floor((getTimestampMs() - run.started) / 100) / 10 .. " s)")
    local ok, writer = pcall(getFileWriter, LOG_FILE, true, false)
    if ok and writer then
        for _, line in ipairs(run.lines) do writer:write(line .. "\n") end
        writer:close()
        print("[PSTest] Log: Zomboid/Lua/" .. LOG_FILE)
    end
    local player = getPlayer()
    if player and HaloTextHelper then
        local say = c.FAIL > 0 and HaloTextHelper.addBadText or HaloTextHelper.addGoodText
        say(player, "Photon Sword tests: " .. summary)
    end
    run = nil
end

local function start(entry)
    entry.t = context(entry.test)
    entry.co = coroutine.create(entry.test.fn)
    entry.deadline = getTimestampMs() + (entry.test.timeoutMs or TEST_TIMEOUT_MS)
    entry.waiting = nil
end

-- Runs the current test until it waits or ends.
local function step()
    local entry = run.queue[run.index]
    if not entry then return report() end
    if not entry.co then start(entry) end
    if entry.waiting and not entry.waiting() then
        if getTimestampMs() < entry.deadline then return end
        finish(entry, "FAIL", "timed out")
        run.index = run.index + 1
        return
    end
    -- A test that hit an error is left unresumable ("normal") or dead; the error is in console.txt.
    if coroutine.status(entry.co) ~= "suspended" then
        finish(entry, "FAIL", "the test stopped on an error (see console.txt)")
        run.index = run.index + 1
        return
    end
    local resumed, ok, result = pcall(coroutine.resume, entry.co, entry.t)
    if not resumed or not ok then
        finish(entry, "FAIL", "error: " .. tostring(resumed and result or ok))
        run.index = run.index + 1
    elseif result == SKIP or result == ABORT then
        finish(entry, result == SKIP and "SKIP" or "FAIL")
        run.index = run.index + 1
    elseif coroutine.status(entry.co) == "dead" then
        finish(entry, "PASS")
        run.index = run.index + 1
    else
        entry.waiting = result
    end
end

Events.OnTick.Add(function()
    if run then step() end
end)

local function matches(suite, filter)
    return filter == nil or string.find(string.lower(suite.name), string.lower(filter), 1, true) ~= nil
end

function PSTest.run(filter)
    if run then return print("[PSTest] A run is already going") end
    if not getPlayer() then return print("[PSTest] Load into a game first") end
    run = { queue = {}, index = 1, lines = {}, started = getTimestampMs(), counts = { PASS = 0, FAIL = 0, SKIP = 0 } }
    local ok, stamp = pcall(os.date, "%Y-%m-%d %H:%M:%S")
    log("Photon Sword tests" .. (ok and stamp and (", " .. stamp) or ""))
    for _, suite in ipairs(PSTest.suites) do
        if matches(suite, filter) then
            local available, why = true, nil
            if suite.available then available, why = suite.available() end
            if available then
                for _, test in ipairs(suite.tests) do run.queue[#run.queue + 1] = { suite = suite, test = test } end
            else
                log("SKIP  " .. suite.name .. " (" .. tostring(why or "not loaded") .. ")")
            end
        end
    end
    log(#run.queue .. " tests queued")
end

function PSTest.list()
    for _, suite in ipairs(PSTest.suites) do
        print("[PSTest] " .. suite.name .. " (" .. #suite.tests .. ")")
        for _, test in ipairs(suite.tests) do print("[PSTest]     " .. test.name) end
    end
end

-- Adds a suite: PSTest.suite(name, available) returns a function test(name, fn, timeoutMs).
-- (Suites in other mods' dev kits may load before this file, so they add themselves directly.)
function PSTest.suite(name, available)
    local suite = { name = name, tests = {}, available = available }
    PSTest.suites[#PSTest.suites + 1] = suite
    return function(testName, fn, timeoutMs)
        suite.tests[#suite.tests + 1] = { name = testName, fn = fn, timeoutMs = timeoutMs }
    end
end

---------------------------------------------------------------------------------------------------
-- Photon Sword
---------------------------------------------------------------------------------------------------

local test = PSTest.suite("Photon Sword")

local function blade(t, color)
    local item = t.item(PS.BLADE_TYPE)
    PS.issueNpcBlade(item, color or "Blue")
    return item
end

test("items exist", function(t)
    local types = { PS.HILT_TYPE, PS.BLADE_TYPE }
    for _, color in ipairs(PS.BLADE_COLORS) do types[#types + 1] = PS.crystalType(color) end
    for _, fullType in ipairs(types) do
        t.ok(getScriptManager():FindItem(fullType) ~= nil, fullType .. " is missing")
    end
end)

test("hilt recipe loads", function(t)
    local recipe = getScriptManager():getCraftRecipe("PhotonSword.MakePhotonSwordHilt")
    t.need(recipe ~= nil, "PhotonSword.MakePhotonSwordHilt is missing")
    t.eq(recipe:getOutputs():size(), 1, "outputs")
    t.ok(recipe:getTranslationName() ~= "MakePhotonSwordHilt", "recipe name isn't translated")
end)

test("sandbox options load", function(t)
    local vars = SandboxVars.PhotonSword
    t.need(type(vars) == "table", "no PhotonSword sandbox page")
    for _, key in ipairs({ "DamageMultiplier", "DeflectBullets", "DeflectChanceMin", "DeflectChanceMax",
            "DeflectStrikesBack", "SoakShotgunBlasts", "SoakMin", "SoakMax", "SoakFullChance",
            "BlockPhotonSwords", "BlockChanceMin", "BlockChanceMax", "NpcBlockChance", "NpcVsNpcBlockChance",
            "CrystalSpawnChance" }) do
        t.ok(vars[key] ~= nil, "option " .. key .. " not loaded (a save made before it existed?)")
    end
end)

test("ignite and extinguish keep charge and crystal", function(t)
    local hilt = t.item(PS.HILT_TYPE)
    PS.setCharge(hilt, .5)
    PS.fitCrystal(hilt, "Red")
    local lit = PS.swap(t.player, hilt, true)
    t.need(lit ~= nil and PS.isIgnited(lit), "ignite didn't make a blade")
    t.cleanup(function() if lit:getContainer() then lit:getContainer():Remove(lit) end end)
    t.eq(PS.getBladeColor(lit), "Red", "blade color")
    t.eq(PS.getCharge(lit), .5, "charge after igniting")
    local mult = PS.getDamageMultiplier()
    local plain = instanceItem(PS.BLADE_TYPE)
    t.ok(math.abs(lit:getMaxDamage() - plain:getMaxDamage() * mult) < .001, "damage multiplier not applied")
    local dark = PS.swap(t.player, lit, false)
    t.need(dark ~= nil and not PS.isIgnited(dark), "extinguish didn't make a hilt")
    t.cleanup(function() if dark:getContainer() then dark:getContainer():Remove(dark) end end)
    t.eq(PS.getCharge(dark), .5, "charge after extinguishing")
    t.eq(PS.getCrystal(dark), "Red", "crystal after extinguishing")
end)

test("crystals fit the hilt as weapon parts", function(t)
    local hilt = t.item(PS.HILT_TYPE)
    PS.setCharge(hilt, 1)
    local crystal = t.item(PS.crystalType("Cyan"))
    t.need(instanceof(crystal, "WeaponPart"), "crystal isn't a weapon part")
    t.eq(PS.crystalColor(crystal), "Cyan", "crystal color")
    t.ok(crystal:canAttach(t.player, hilt), "vanilla won't attach it to a hilt")
    t.ok(not PS.hasCrystal(hilt), "fresh hilt already has a crystal")
    t.ok(not ISPhotonSwordToggle:new(t.player, hilt, true):isValid(), "ignites without a crystal")
    hilt:attachWeaponPart(t.player, crystal)
    t.eq(PS.getBladeColor(hilt), "Cyan", "color from the fitted part")
    t.ok(crystal:canDetach(t.player, hilt), "can't detach from an inert hilt")
    local blade = t.item(PS.BLADE_TYPE)
    PS.fitCrystal(blade, "Red")
    t.ok(not blade:getWeaponPart(PS.CRYSTAL_PART):canDetach(t.player, blade), "detaches from a lit blade")
end)

test("old Blade Color pick becomes one crystal", function(t)
    t.need(PS.giveMigrationCrystal, "server/PhotonSword/PS_Migration.lua isn't loaded (single player only)")
    local data = t.player:getModData()
    local was = data.PS_crystalGiven
    t.cleanup(function() data.PS_crystalGiven = was end)
    local inv = t.player:getInventory()
    local fullType = PS.crystalType("Orange")
    local before = inv:getCountTypeRecurse(fullType)
    t.cleanup(function()
        while inv:getCountTypeRecurse(fullType) > before do inv:RemoveOneOf(fullType) end
    end)
    data.PS_crystalGiven = nil
    t.ok(PS.giveMigrationCrystal(t.player, "Orange"), "first call gave nothing")
    t.ok(not PS.giveMigrationCrystal(t.player, "Orange"), "second call gave another")
    t.eq(inv:getCountTypeRecurse(fullType) - before, 1, "crystals given")
end)

test("NPC blades are issued once", function(t)
    local item = t.item(PS.BLADE_TYPE)
    local base = item:getMaxDamage()
    PS.issueNpcBlade(item, "Green")
    PS.issueNpcBlade(item, "Red")
    t.ok(item:getModData().PS_npcIssued == true, "not marked issued")
    t.eq(PS.getBladeColor(item), "Green", "first color kept")
    t.ok(math.abs(item:getMaxDamage() - base * PS.getDamageMultiplier()) < .001, "multiplier applied more than once")
end)

test("NPC blade colors are stable", function(t)
    t.eq(PS.npcBladeColor("npc-a", 1), PS.npcBladeColor("npc-a", 1), "random color changes between calls")
    t.eq(PS.npcBladeColor("npc-a", 2), PS.BLADE_COLORS[1], "chosen color")
end)

test("guard deflects a bullet back at the shooter", function(t)
    t.noForms()
    local zombie = t.zombie(2, 0)
    t.wait(200)
    t.guard(zombie)
    t.sandbox("PhotonSword", "DeflectChanceMin", 100)
    t.sandbox("PhotonSword", "DeflectChanceMax", 100)
    t.sandbox("PhotonSword", "DeflectStrikesBack", true)
    local before = zombie:getHealth()
    local deflected = PS.judgeShot(zombie, t.player, instanceItem("Base.Pistol"), 1)
    t.ok(deflected, "a sure deflect didn't deflect")
    t.ok(zombie:isDead() or zombie:getHealth() < before, "the shooter wasn't struck back")
end)

test("guard misses at 0% and from behind", function(t)
    t.noForms()
    local zombie = t.zombie(2, 0)
    t.wait(200)
    t.guard(zombie)
    t.sandbox("PhotonSword", "DeflectChanceMin", 0)
    t.sandbox("PhotonSword", "DeflectChanceMax", 0)
    t.ok(not PS.judgeShot(zombie, t.player, instanceItem("Base.Pistol"), 1), "deflected at 0%")
    t.wait(200)
    t.sandbox("PhotonSword", "DeflectChanceMin", 100)
    t.sandbox("PhotonSword", "DeflectChanceMax", 100)
    local behind = t.zombie(-2, 0)
    t.wait(200)
    t.ok(not PS.judgeShot(behind, t.player, instanceItem("Base.Pistol"), 1), "deflected a shot from behind")
end)

test("guard soaks a shotgun blast", function(t)
    t.noForms()
    local zombie = t.zombie(2, 0)
    t.wait(200)
    t.guard(zombie)
    t.sandbox("PhotonSword", "SoakMin", 40)
    t.sandbox("PhotonSword", "SoakMax", 40)
    t.sandbox("PhotonSword", "SoakFullChance", 0)
    local shotgun = instanceItem("Base.Shotgun")
    t.need(shotgun and shotgun:getProjectileCount() > 1, "Base.Shotgun isn't a spread weapon")
    local deflected, share = PS.judgeShot(zombie, t.player, shotgun, 1)
    t.ok(not deflected, "a blast was deflected")
    t.ok(math.abs(share - .4) < .001, "soaked share " .. tostring(share) .. ", want 0.4")
end)

test("guard blocks a photon sword strike", function(t)
    t.noForms()
    local zombie = t.zombie(1.5, 0)
    t.wait(200)
    t.guard(zombie)
    local sword = blade(t)
    t.sandbox("PhotonSword", "BlockChanceMin", 100)
    t.sandbox("PhotonSword", "BlockChanceMax", 100)
    t.ok(PS.judgeBlow(zombie, t.player, sword), "a sure block didn't block")
    t.ok(PS.judgeLocalBlow(zombie, t.player, sword), "a sure block didn't block (client path)")
    t.ok(not PS.judgeBlow(zombie, t.player, instanceItem("Base.Axe")), "blocked an axe")
    t.sandbox("PhotonSword", "BlockPhotonSwords", false)
    t.ok(not PS.judgeBlow(zombie, t.player, sword), "blocked with Guard Blocks Photon Swords off")
    t.sandbox("PhotonSword", "BlockPhotonSwords", true)
    t.sandbox("PhotonSword", "BlockChanceMin", 0)
    t.sandbox("PhotonSword", "BlockChanceMax", 0)
    t.ok(not PS.judgeBlow(zombie, t.player, sword), "blocked at 0%")
end)

test("a sword block plays the parry", function(t)
    if isServer() then t.skip("the parry is noted on the clients") end
    t.noForms()
    local zombie = t.zombie(1.5, 0)
    t.wait(200)
    t.guard(zombie)
    t.sandbox("PhotonSword", "BlockChanceMin", 100)
    t.sandbox("PhotonSword", "BlockChanceMax", 100)
    PS.parries[t.player] = nil
    t.ok(PS.judgeBlow(zombie, t.player, blade(t)), "a sure block didn't block")
    t.ok(PS.parrying(t.player, 850), "the block wasn't noted as a parry")
    t.wait(900)
    t.ok(not PS.parrying(t.player, 850), "the parry didn't end")
end)

test("NPC with a lit sword blocks a player's strike", function(t)
    local npc = t.zombie(1.5, 0)
    t.wait(200)
    local npcSword, sword = blade(t, "Red"), blade(t)
    npc:setPrimaryHandItem(npcSword)
    t.sandbox("PhotonSword", "NpcBlockChance", 100)
    npc:faceThisObject(t.player)
    t.ok(not PS.npcBlocks(t.player, npc, sword), "blocked with a dark blade")
    t.wait(400)
    PS.npcLit[npc] = true
    t.cleanup(function() PS.npcLit[npc] = nil end)
    npc:faceThisObject(t.player)
    t.ok(PS.npcBlocks(t.player, npc, sword), "a sure NPC block didn't block")
    t.ok(PS.npcBlocks(t.player, npc, sword), "the same strike asked twice got another answer")
    t.wait(400)
    t.sandbox("PhotonSword", "NpcBlockChance", 0)
    npc:faceThisObject(t.player)
    t.ok(not PS.npcBlocks(t.player, npc, sword), "blocked at 0%")
end)

test("an NPC's block plays the parry", function(t)
    local npc = t.zombie(1.5, 0)
    t.wait(200)
    npc:setPrimaryHandItem(blade(t, "Red"))
    PS.npcLit[npc] = true
    t.cleanup(function() PS.npcLit[npc] = nil end)
    t.sandbox("PhotonSword", "NpcBlockChance", 100)
    local played = nil
    local play = PS.playNpcParry
    t.stub(PS, "playNpcParry", function(who) played = who; return play(who) end)
    npc:faceThisObject(t.player)
    t.need(PS.npcBlocks(t.player, npc, blade(t)), "a sure NPC block didn't block")
    t.ok(played == npc, "the block didn't play the parry")
    t.ok(PS.parrying(npc, 850), "the NPC's parry wasn't noted")
    t.eq(npc:getBumpType(), "PSParry", "the NPC's BumpType")
end)

test("NPC vs NPC block uses its own chance", function(t)
    local npc, other = t.zombie(1.5, 0), t.zombie(3, 0)
    t.wait(200)
    npc:setPrimaryHandItem(blade(t, "Red"))
    PS.npcLit[npc] = true
    t.cleanup(function() PS.npcLit[npc] = nil end)
    local sword = blade(t)
    t.sandbox("PhotonSword", "NpcBlockChance", 0)
    t.sandbox("PhotonSword", "NpcVsNpcBlockChance", 100)
    npc:faceThisObject(other)
    t.ok(PS.npcBlocks(other, npc, sword), "an NPC's strike wasn't blocked at 100%")
    t.wait(400)
    t.sandbox("PhotonSword", "NpcVsNpcBlockChance", 0)
    npc:faceThisObject(other)
    t.ok(not PS.npcBlocks(other, npc, sword), "an NPC's strike was blocked at 0%")
end)

test("a player's strike on a blocking NPC is avoided", function(t)
    local npc = t.zombie(1.5, 0)
    t.wait(200)
    npc:setPrimaryHandItem(blade(t, "Red"))
    PS.npcLit[npc] = true
    t.cleanup(function() PS.npcLit[npc] = nil end)
    t.sandbox("PhotonSword", "NpcBlockChance", 100)
    -- The game can't read avoidDamage back, so watch Photon Sword's handler ask PS.npcBlocks about
    -- this hit; it avoids the damage whenever the answer is yes.
    local asked, answer = false, nil
    local npcBlocks = PS.npcBlocks
    t.stub(PS, "npcBlocks", function(attacker, target, weapon)
        local blocked = npcBlocks(attacker, target, weapon)
        if attacker == t.player and target == npc then asked, answer = true, blocked end
        return blocked
    end)
    npc:faceThisObject(t.player)
    triggerEvent("OnWeaponHitCharacter", t.player, npc, blade(t), 1)
    npc:setAvoidDamage(false)
    t.ok(asked, "OnWeaponHitCharacter didn't ask whether the NPC blocks")
    t.ok(answer == true, "the NPC didn't block the hit")
end)

test("NPC blade lights for a fight and goes out after", function(t)
    local npc = t.zombie(2, 0)
    t.wait(200)
    npc:setPrimaryHandItem(blade(t, "Purple"))
    local fighting = true
    PSTest.combat = PSTest.combat or setmetatable({}, { __mode = "k" })
    PSTest.combat[npc] = function() return fighting end
    t.cleanup(function() PSTest.combat[npc] = nil end)
    t.ok(t.waitFor(function() return PS.isNpcLit(npc) end, 3000), "didn't ignite for a fight")
    t.ok(npc:getPrimaryHandItem():getWeaponSprite() == "PhotonSword_Blade_Purple", "lit model isn't the blade")
    fighting = false
    t.ok(t.waitFor(function() return not PS.isNpcLit(npc) end, 8000), "didn't go out after the fight")
    t.ok(npc:getPrimaryHandItem():getWeaponSprite() == "PhotonSword_Hilt", "dark model isn't the hilt")
end)

test("a held blade stays clean", function(t)
    local held = PS.getHeld(t.player)
    if not held or not PS.isIgnited(held) then t.skip("hold an ignited sword (the dev kit gives one)") end
    held:setBloodLevel(.5)
    t.ok(t.waitFor(function() return held:getBloodLevel() == 0 end, 2000), "blood stayed on the blade")
end)

test("a found blade gets a part-drained battery", function(t)
    local item = t.item(PS.BLADE_TYPE)
    item:getModData().PS_charge = nil
    t.need(PS.getDrainPerMinute() > 0, "battery drain is off in the sandbox")
    t.ok(t.waitFor(function() return PS.hasBattery(item) end, 30000), "no battery within an in-game minute")
    local charge = PS.getCharge(item)
    t.ok(charge > 0 and charge <= .6, "charge " .. tostring(charge) .. " outside 20-60%")
end, 40000)

test("a lit blade drains its battery", function(t)
    local item = t.item(PS.BLADE_TYPE)
    PS.setCharge(item, 1)
    t.need(PS.getDrainPerMinute() > 0, "battery drain is off in the sandbox")
    t.ok(t.waitFor(function() return PS.getCharge(item) < 1 end, 30000), "charge didn't drop within an in-game minute")
end, 40000)

-- Lets the lit/dark test report combat for its own zombie.
PS.addNpcCombatSource(function(zombie)
    local fn = PSTest.combat and PSTest.combat[zombie]
    return fn ~= nil and fn()
end)
