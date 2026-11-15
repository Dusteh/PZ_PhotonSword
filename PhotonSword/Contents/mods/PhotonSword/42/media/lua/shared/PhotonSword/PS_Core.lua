-- Constants and item helpers shared by client and server.
-- A photon sword exists as two item types: an inert hilt and an ignited blade.
-- Igniting/extinguishing swaps one for the other, carrying condition and modData across.
-- Power is stored on the item's modData (PS_charge, 0..1); nil means no battery installed.
-- A blade glows in the color of the photon crystal fitted in its hilt. Crystals are vanilla weapon
-- parts (PartType Crystal), attached through the game's Add / Remove Weapon Upgrade menu like a
-- gun's scope, so mods that extend that menu handle them too. A hilt needs a crystal to ignite.

PhotonSword = PhotonSword or {}
local PS = PhotonSword

PS.HILT_TYPE = "PhotonSword.PhotonSwordHilt"
PS.BLADE_TYPE = "PhotonSword.PhotonSword"
PS.BATTERY_TYPE = "Base.Battery"
-- One crystal item per palette color: PhotonSword.PhotonCrystal_<Color>, a weapon part that
-- mounts on the hilt in the CRYSTAL_PART slot.
PS.CRYSTAL_PREFIX = "PhotonSword.PhotonCrystal_"
PS.CRYSTAL_PART = "Crystal"

-- Blade palette: light color as 0..1 floats (as IsoLightSource expects). Each name has a model
-- (PhotonSword_Blade_<Name>) and a crystal icon from tools/gen_models.py, whose PALETTE must list
-- the same names, and a crystal item in item_photonsword.txt. The first is the default, matching
-- the blade item script; a blade with no crystal (a debug-spawned one) glows in it.
PS.BLADE_COLORS = { "Blue", "Green", "Red", "Purple", "Yellow", "Orange", "Cyan", "White" }
PS.COLORS = {
    Blue = { r = 0.25, g = 0.5, b = 1.0 },
    Green = { r = 0.3, g = 1.0, b = 0.35 },
    Red = { r = 1.0, g = 0.2, b = 0.15 },
    Purple = { r = 0.7, g = 0.3, b = 1.0 },
    Yellow = { r = 1.0, g = 0.9, b = 0.25 },
    Orange = { r = 1.0, g = 0.55, b = 0.15 },
    Cyan = { r = 0.2, g = 0.95, b = 1.0 },
    White = { r = 0.95, g = 0.95, b = 1.0 },
}

-- Balance comes from sandbox options (media/sandbox-options.txt); these mirror their defaults
-- for when SandboxVars aren't loaded. Light radius is a client mod option (PS_Options.lua).
local DEFAULT_BATTERY_LIFE_HOURS = 8
local DEFAULT_DAMAGE_MULTIPLIER = 1.0
local DEFAULT_CRYSTAL_SPAWN_CHANCE = 25

local function sandbox()
    return SandboxVars and SandboxVars.PhotonSword or {}
end

-- Charge lost per in-game minute while ignited; 0 when drain is disabled.
function PS.getDrainPerMinute()
    local hours = sandbox().BatteryLifeHours or DEFAULT_BATTERY_LIFE_HOURS
    if hours <= 0 then return 0 end
    return 1 / (hours * 60)
end

function PS.getDamageMultiplier()
    return sandbox().DamageMultiplier or DEFAULT_DAMAGE_MULTIPLIER
end

-- Percent chance a hilt found in loot already holds a crystal of a random color (PS_Distributions.lua).
function PS.getCrystalSpawnChance()
    return sandbox().CrystalSpawnChance or DEFAULT_CRYSTAL_SPAWN_CHANCE
end

-- What a swing of an ignited blade cuts through (server side: PS_Cutting.lua).
function PS.canCutDoorsAndWindows()
    return sandbox().CutDoorsAndWindows ~= false
end

function PS.canCutWalls()
    return sandbox().CutWalls == true
end

function PS.canCutVegetation()
    return sandbox().CutVegetation ~= false
end

function PS.canCutWorldObjects()
    return sandbox().CutWorldObjects ~= false
end

function PS.canCutPlayerBuilt()
    return sandbox().CutPlayerBuilt == true
end

-- Cut Effect (enum): 1 destroys targets like a sledgehammer, 2 sets them on fire.
function PS.isCutEffectFire()
    return sandbox().CutEffect == 2
end

-- Whether running or sprinting puts a lit sword out until the run ends (PS_RunExtinguish.lua).
function PS.extinguishesWhileRunning()
    return sandbox().ExtinguishWhileRunning ~= false
end

function PS.canCutAnything()
    return PS.canCutDoorsAndWindows() or PS.canCutWalls() or PS.canCutVegetation()
        or PS.canCutWorldObjects() or PS.canCutPlayerBuilt()
end

-- Each player's own cutting switch (Toggle Cutting hotkey), kept in player modData so it survives
-- saving. Off until the player turns it on; the sandbox options still decide what can be cut.
function PS.isCuttingOn(playerObj)
    return playerObj:getModData().PS_cutting == true
end

function PS.setCuttingOn(playerObj, on)
    playerObj:getModData().PS_cutting = on
end

-- Sound script names (media/scripts/sounds_photonsword.txt, audio from tools/gen_sounds.py).
PS.IGNITE_SOUND = "PhotonSwordIgnite"
PS.EXTINGUISH_SOUND = "PhotonSwordExtinguish"
-- Hum, swing, and hit come in these tones, and swings and hits at these pitches (percent); both
-- lists must match TONES and PITCHES in tools/gen_sounds.py.
PS.SOUND_TONES = { "Smooth", "Classic", "Gritty" }
PS.SOUND_PITCHES = { 70, 80, 90, 100, 110, 120, 130 }

function PS.humSound(tone)
    return "PhotonSwordHum_" .. tone
end

-- Swing and hit sounds are pre-rendered per pitch, so snap to the nearest one that exists.
local function nearestPitch(pitchPercent)
    local best = PS.SOUND_PITCHES[1]
    for _, p in ipairs(PS.SOUND_PITCHES) do
        if math.abs(p - pitchPercent) < math.abs(best - pitchPercent) then best = p end
    end
    return best
end

function PS.swingSound(tone, pitchPercent)
    return "PhotonSwordSwing_" .. tone .. "_" .. nearestPitch(pitchPercent)
end

-- The spark played when the blade strikes a zombie, a door, the floor, or anything else.
function PS.hitSound(tone, pitchPercent)
    return "PhotonSwordHit_" .. tone .. "_" .. nearestPitch(pitchPercent)
end

function PS.isIgnited(item)
    return item ~= nil and item:getFullType() == PS.BLADE_TYPE
end

function PS.isPhotonSword(item)
    return item ~= nil and (item:getFullType() == PS.HILT_TYPE or PS.isIgnited(item))
end

function PS.hasBattery(item)
    return item:getModData().PS_charge ~= nil
end

function PS.getCharge(item)
    return item:getModData().PS_charge or 0
end

function PS.setCharge(item, charge)
    if charge == nil then
        item:getModData().PS_charge = nil
    else
        item:getModData().PS_charge = math.max(0, math.min(1, charge))
    end
end

function PS.chargePercent(item)
    return math.floor(PS.getCharge(item) * 100 + 0.5)
end

-- Photon crystals: a crystal item's color, or nil for any other item.
function PS.crystalColor(item)
    if not item then return nil end
    local fullType = item:getFullType()
    if fullType:sub(1, #PS.CRYSTAL_PREFIX) ~= PS.CRYSTAL_PREFIX then return nil end
    local color = fullType:sub(#PS.CRYSTAL_PREFIX + 1)
    return PS.COLORS[color] and color or nil
end

function PS.crystalType(color)
    return PS.CRYSTAL_PREFIX .. color
end

-- The color of the crystal fitted in a hilt or blade, or nil when it has none.
function PS.getCrystal(item)
    return PS.crystalColor(item:getWeaponPart(PS.CRYSTAL_PART))
end

function PS.hasCrystal(item)
    return PS.getCrystal(item) ~= nil
end

-- Fits a fresh crystal of color (a palette name) into a hilt or blade, replacing any it holds.
-- Must run with authority, before the item is sent to clients (or followed by a sync).
function PS.fitCrystal(item, color)
    if not PS.COLORS[color or ""] then return end
    local old = item:getWeaponPart(PS.CRYSTAL_PART)
    if old then item:detachWeaponPart(old) end
    item:attachWeaponPart(instanceItem(PS.crystalType(color)), true)
end

-- Crystal items' CanDetach (item_photonsword.txt): a crystal only comes out of an inert hilt.
function PS.crystalCanDetach(character, weapon, part)
    return not PS.isIgnited(weapon)
end

-- The palette color a blade glows in: its crystal's.
function PS.getBladeColor(item)
    return PS.getCrystal(item) or PS.BLADE_COLORS[1]
end

-- Model for a blade's color; saved with the item. The icon is the hilt's for every color.
local function applyBladeColor(blade)
    blade:setWeaponSprite("PhotonSword_Blade_" .. PS.getBladeColor(blade))
end
PS.applyBladeColor = applyBladeColor

-- Returns the photon sword the character is holding, if any.
function PS.getHeld(character)
    local item = character:getPrimaryHandItem()
    if PS.isPhotonSword(item) then return item end
    item = character:getSecondaryHandItem()
    if PS.isPhotonSword(item) then return item end
    return nil
end

-- Calls fn(key, playerObj) for every player this game knows about: online players on an MP
-- client, local (split-screen) players otherwise. Returns the set of keys visited.
function PS.forEachPlayer(fn)
    local seen = {}
    local online = isClient()
    local players = online and getOnlinePlayers() or IsoPlayer.getPlayers()
    for i = 0, players:size() - 1 do
        local playerObj = players:get(i)
        if playerObj then
            local key = online and playerObj:getOnlineID() or i
            seen[key] = true
            fn(key, playerObj)
        end
    end
    return seen
end

-- Whether playerObj holds an ignited, working sword in both hands, free to stand with it.
function PS.holdsIgnited(playerObj)
    local item = playerObj:getPrimaryHandItem()
    return PS.isIgnited(item) and item:getCondition() > 0 and playerObj:getSecondaryHandItem() == item
        and not playerObj:isDead() and not playerObj:getVehicle() and not playerObj:isSitOnGround()
        and not playerObj:isClimbingRope()
end

-- Whether playerObj aims as the ready stance does: not running, sneaking, shoving, aiming at the
-- floor, or busy with an action.
function PS.readyStance(playerObj)
    return playerObj:isAiming() and not playerObj:isRunning() and not playerObj:isSprinting()
        and not playerObj:isSneaking() and not playerObj:isDoShove() and not playerObj:isAimAtFloor()
        and not playerObj:getVariableBoolean("PerformingAction")
end

-- A function's results, kept with their count (nils too), for a wrapper that runs code after the
-- function it wraps and returns everything it did: unpack(results, 1, results.n).
function PS.pack(...)
    return { n = select("#", ...), ... }
end

-- Sections of the Photon Sword sandbox page, which this mod and its patch mods share
-- (client/PhotonSword/PS_SandboxPage.lua). Each section has a title (shown as the translation of
-- Sandbox_Title_<title>), a place on the page (order, lowest first), and the patterns of the
-- option names it holds.
PS.sandboxSections = PS.sandboxSections or {}

function PS.addSandboxSection(order, title, ...)
    PS.sandboxSections[#PS.sandboxSections + 1] = { order = order, title = title, patterns = { ... } }
end

-- Parries: when a character last blocked a photon sword's strike, so its parry plays while it's
-- fresh. A player's guard is noted on each client that shows the block (PS_DeflectShow.lua) and
-- read by the stances (PS_Stance.lua, and Photon Sword Forms' block, which also notes Martial Arts
-- Core's blocks); an NPC's where its block is decided (PS.playNpcParry, PS_Deflect.lua).
PS.parries = PS.parries or setmetatable({}, { __mode = "k" })

function PS.noteParry(playerObj)
    PS.parries[playerObj] = getTimestampMs()
end

-- Whether playerObj blocked a photon sword's strike in the last ms milliseconds.
function PS.parrying(playerObj, ms)
    local at = PS.parries[playerObj]
    return at ~= nil and getTimestampMs() - at < ms
end

-- The stance (client/PhotonSword/PS_Stance.lua): how a character holds an ignited sword. Another
-- mod whose own animation takes the sword over (a block, a weapon art's stance) adds a yield:
-- while fn(playerObj) returns true, the stance stays out of that player's animation, the ready
-- stance doesn't guard (PS_Deflect.lua), and running doesn't put the blade out (PS_RunExtinguish.lua).
PS.stanceYields = PS.stanceYields or {}

function PS.addStanceYield(fn)
    table.insert(PS.stanceYields, fn)
end

function PS.yieldsStance(playerObj)
    for _, fn in ipairs(PS.stanceYields) do
        if fn(playerObj) then return true end
    end
    return false
end

-- Finds a photon sword to draw: one bound to the hotbar first, then any in the inventory.
function PS.findInInventory(character)
    local fallback = nil
    local items = character:getInventory():getAllEvalRecurse(PS.isPhotonSword)
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getAttachedSlot() > -1 then return item end
        fallback = fallback or item
    end
    return fallback
end

-- Highest-charge battery in the character's inventory holding more than minCharge.
function PS.findBestBattery(character, minCharge)
    local batteries = character:getInventory():getAllTypeRecurse(PS.BATTERY_TYPE)
    local best = nil
    local bestCharge = minCharge or 0
    for i = 0, batteries:size() - 1 do
        local battery = batteries:get(i)
        if battery:getCurrentUsesFloat() > bestCharge then
            best = battery
            bestCharge = battery:getCurrentUsesFloat()
        end
    end
    return best
end

-- Replaces a hilt with its blade (or vice versa) in whatever container holds it (the main
-- inventory or a bag), keeping it in the same hands. Must run with authority: a timed action's
-- complete() or server code. The crystal moves across with the condition and modData.
function PS.swap(character, item, ignite)
    if not PS.isPhotonSword(item) then return nil end
    local inv = item:getContainer() or character:getInventory()
    local newItem = instanceItem(ignite and PS.BLADE_TYPE or PS.HILT_TYPE)
    if not newItem then return nil end

    -- Weapons save their own damage, so scale the fresh blade rather than the item script.
    if ignite then
        local mult = PS.getDamageMultiplier()
        newItem:setMinDamage(newItem:getMinDamage() * mult)
        newItem:setMaxDamage(newItem:getMaxDamage() * mult)
    end
    newItem:setCondition(item:getCondition())
    newItem:copyModData(item:getModData())
    local crystal = item:getWeaponPart(PS.CRYSTAL_PART)
    if crystal then
        item:detachWeaponPart(crystal)
        newItem:attachWeaponPart(crystal, true)
    end
    newItem:setFavorite(item:isFavorite())
    if ignite then
        applyBladeColor(newItem)
    end
    -- Keep the hotbar binding. Hilt and blade share an AttachmentType so they fit the same slots.
    newItem:setAttachedSlot(item:getAttachedSlot())
    newItem:setAttachedSlotType(item:getAttachedSlotType())
    newItem:setAttachedToModel(item:getAttachedToModel())

    local wasHeld = character:getPrimaryHandItem() == item or character:getSecondaryHandItem() == item
    if wasHeld then
        character:removeFromHands(item)
    end

    inv:Remove(item)
    sendRemoveItemFromContainer(inv, item)
    inv:AddItem(newItem)
    sendAddItemToContainer(inv, newItem)
    syncItemFields(character, newItem)

    if wasHeld then
        character:setPrimaryHandItem(newItem)
        if newItem:isTwoHandWeapon() then
            character:setSecondaryHandItem(newItem)
        end
        sendEquip(character)
    end
    return newItem
end

-- NPCs from other mods (Bandits, Project A-Life) are zombies underneath. Their patch mods arm
-- them through these helpers, so every NPC mod gets the same rarity roll, blade colors, and blade.

-- A stable roll in [0, 100) from a string, the same on every machine and every time that NPC is
-- rebuilt, so an NPC keeps (or never gets) its sword.
function PS.stableRoll(key)
    local hash = 0
    key = tostring(key)
    for i = 1, #key do
        hash = (hash * 31 + string.byte(key, i)) % 2147483647
    end
    return hash % 10000 / 100
end

-- An NPC's blade color from a patch's NPC Blade Color sandbox option: 1 is Random (stable per
-- NPC), 2 and up pick PS.BLADE_COLORS in order.
function PS.npcBladeColor(key, choice)
    local fixed = PS.BLADE_COLORS[(tonumber(choice) or 1) - 1]
    if fixed then return fixed end
    return PS.BLADE_COLORS[math.floor(PS.stableRoll(tostring(key) .. ":color")) % #PS.BLADE_COLORS + 1]
end

-- Readies a fresh blade an NPC holds, swings, or drops, as igniting readies a player's: the
-- damage multiplier, and a crystal of its color, which stays in the hilt it leaves. No battery: one is fitted when a player picks it up
-- (PS_PowerDrain.lua). Calling it again on the same blade does nothing.
function PS.issueNpcBlade(blade, color)
    if not PS.isIgnited(blade) then return blade end
    local data = blade:getModData()
    if data.PS_npcIssued then return blade end
    data.PS_npcIssued = true
    local mult = PS.getDamageMultiplier()
    blade:setMinDamage(blade:getMinDamage() * mult)
    blade:setMaxDamage(blade:getMaxDamage() * mult)
    PS.fitCrystal(blade, color)
    applyBladeColor(blade)
    return blade
end

-- NPCs hold their sword dark (the hilt's model) and light it only for a fight: client/PhotonSword/
-- PS_NpcBlades.lua lights it while PS.npcInCombat(zombie) and puts it out once the fight is over.
-- The item stays the blade throughout, so the NPC mod's own AI never sees its weapon change.
-- PS.npcLit[zombie] is true while lit, on each client (the server never lights one).
PS.npcLit = PS.npcLit or setmetatable({}, { __mode = "k" })
PS.npcCombatSources = PS.npcCombatSources or {}

-- A patch tells Photon Sword when its NPCs fight: fn(zombie) returns true while that NPC is in, or
-- closing in on, a fight.
function PS.addNpcCombatSource(fn)
    table.insert(PS.npcCombatSources, fn)
end

-- Whether an NPC is fighting: attacking now, or any patch's combat source says so.
function PS.npcInCombat(zombie)
    if zombie:isAttacking() or zombie:isPerformingAttackAnimation() then return true end
    for _, fn in ipairs(PS.npcCombatSources) do
        if fn(zombie) then return true end
    end
    return false
end

function PS.isNpcLit(zombie)
    return PS.npcLit[zombie] == true
end

-- Whether character is an NPC's body: a zombie (Bandits, Project A-Life) or a survivor (Echoes of
-- Humanity).
function PS.isNpcBody(character)
    return character ~= nil and (instanceof(character, "IsoZombie") or instanceof(character, "IsoSurvivor"))
end

-- Calls fn(zombie, zombie) for every NPC in the loaded cell holding a photon sword, lit or not.
-- The zombie and survivor lists are rescanned at most every NPC_SCAN_MS, and only once an NPC
-- patch has registered a combat source (PS.addNpcCombatSource): without one, nothing arms NPCs, so
-- the whole zombie list isn't walked for nothing.
local NPC_SCAN_MS = 500
local npcHolders, npcScannedMs = {}, 0

local function scanList(list)
    if not list then return end
    for i = 0, list:size() - 1 do
        local npc = list:get(i)
        if npc and PS.isIgnited(npc:getPrimaryHandItem()) then
            npcHolders[#npcHolders + 1] = npc
        end
    end
end

local function refreshNpcHolders()
    local now = getTimestampMs()
    if now - npcScannedMs < NPC_SCAN_MS then return end
    npcScannedMs = now
    npcHolders = {}
    local cell = getCell()
    if not cell or #PS.npcCombatSources == 0 then return end
    scanList(cell:getZombieList())
    scanList(cell:getSurvivorList())
end

-- Calls fn for each held, lit-or-not NPC sword; with litOnly, only for NPCs whose sword is lit.
local function forEachNpc(fn, litOnly)
    refreshNpcHolders()
    local seen = {}
    for _, zombie in ipairs(npcHolders) do
        if not zombie:isDead() and PS.isIgnited(zombie:getPrimaryHandItem())
                and (not litOnly or PS.isNpcLit(zombie)) then
            seen[zombie] = true
            fn(zombie, zombie)
        end
    end
    return seen
end

function PS.forEachNpcHolder(fn)
    return forEachNpc(fn, false)
end

-- Calls fn(zombie, zombie) for every NPC whose sword is lit (client effects: light, hum, no blood).
function PS.forEachNpcWielder(fn)
    return forEachNpc(fn, true)
end

-- PS.forEachPlayer, then PS.forEachNpcWielder; returns every key visited.
function PS.forEachWielder(fn)
    local seen = PS.forEachPlayer(fn)
    for key in pairs(PS.forEachNpcWielder(fn)) do
        seen[key] = true
    end
    return seen
end
