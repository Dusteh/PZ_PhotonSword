-- The Photon Sword art: Forms (fighting styles) for an ignited photon sword, built on
-- Senator's Martial Arms. Each Form is its own Senator weapon art, made by PSF.define from a
-- definition (see PSF_Form1.lua) and modeled on Senator's katana art (SWMK_Core.lua): its own
-- manual, mastery track, move toggles, and server module. A player fights with one active Form
-- at a time, chosen in the Photon Sword tab, so Forms never compete for a swing.
-- All Forms share this mod's PSF* animation variables, read only by the AnimSets that
-- tools/gen_forms_animsets.py authors from this mod's move data; a move id (PSFMove) picks its node,
-- which plays a clip from Senator's Martial Arms. Senator's katana art and its SWMK* variables
-- are never touched. How the ignited sword is held between moves (the rest, walks, ready stance,
-- and its beckons) is Photon Sword's own stance (PS_Stance.lua), which gives way to the Form's block.
-- Whenever a Form can be used, the photon sword is taken away from Senator's katana art.

require "SMA_Progression"
require "SWMA_Dodge"
require "SMA_Guard"
require "PhotonSword/PS_Core"
local SMA = require "SMA_Core"
local SWMK = require "SWMK_Core"
local Sequence = require "PhotonSwordForms/PSF_Sequence"
local PS = PhotonSword

PhotonSwordForms = PhotonSwordForms or {}
local PSF = PhotonSwordForms

PSF.module = "PhotonSwordForms"
PSF.forms = {}  -- Forms in display order
PSF.byId = {}

local PARRY_MS = 450   -- PSF_BlockParry, less its blend back
local CORE_BLOCK_MS = 300   -- how recent Core's last block must be to parry it

-- Martial Arts Core's block settling a blow itself (another player's, which Photon Sword leaves to
-- it): Core stamps the guard's lastHit as it settles the blow, in the blow's OnWeaponHitCharacter.
-- It also stamps it for a zombie pushed off the guard, and Photon Sword's own drains (bullets,
-- shotgun soaks, NPC strikes) stamp it through PSF_Deflect.lua, which records those stamps in
-- PSF.photonStamps; so a block is a new stamp made as a melee blow struck the player that isn't
-- Photon Sword's. Only where the blow is settled (single player, or the server, which tells the
-- clients: PSF_Server.lua's "parry") can the stamps be told apart: the blocker's own client gets
-- the same stamp from Core for any drain. seen: the caller's own record of the stamps it has read.
PSF.photonStamps = setmetatable({}, { __mode = "k" })
PSF.struckAt = setmetatable({}, { __mode = "k" })   -- when a melee blow last struck each player
if Events.OnWeaponHitCharacter then
    Events.OnWeaponHitCharacter.Add(function(attacker, target, weapon)
        if target and instanceof(target, "IsoPlayer") and weapon and instanceof(weapon, "HandWeapon")
            and not weapon:isRanged() then
            PSF.struckAt[target] = getTimestampMs()
        end
    end)
end

function PSF.newCoreBlock(player, seen)
    local at = SMA.guardState(player).lastHit
    if seen[player] == at then return false end
    seen[player] = at
    if type(at) ~= "number" or at <= 0 or getTimestampMs() - at >= CORE_BLOCK_MS then return false end
    if PSF.photonStamps[player] == at then return false end
    local struck = PSF.struckAt[player]
    return struck ~= nil and math.abs(at - struck) <= 50
end
local seenHere = setmetatable({}, { __mode = "k" })

-- Art-wide player state, saved in player modData: which Form is active.
function PSF.state(player)
    local data = player:getModData()
    data.PSF_art = data.PSF_art or { version = 1 }
    return data.PSF_art
end

-- The Form a player fights with: their chosen Form if learned, otherwise their first learned Form.
function PSF.activeForm(player)
    local chosen = PSF.byId[PSF.state(player).active]
    if chosen and chosen.state(player).learned == true then return chosen end
    for _, W in ipairs(PSF.forms) do
        if W.state(player).learned == true then return W end
    end
    return nil
end

-- Server side (or single player): makes Form id the player's active Form.
function PSF.select(player, id)
    local W = PSF.byId[id]
    if isClient() or not player or player:isDead() or player:isAttacking()
        or not W or W.state(player).learned ~= true then return false end
    local previous = PSF.activeForm(player)
    PSF.state(player).active = id
    if previous and previous ~= W then
        previous.progression.cancel(player)
        if previous.resetCombo then previous.resetCombo(player) end
        if previous.resetSequence then previous.resetSequence(player) end
        previous.clear(player)
    end
    if PSF.syncActive then PSF.syncActive(player) end
    return true
end

-- The Form a player can use with weapon right now, if any.
function PSF.usable(player, weapon)
    local W = PSF.activeForm(player)
    return W and W.canUse(player, weapon) and W or nil
end

-- Builds and registers a Form from its definition:
--   id, number          Form id ("form1") and its number in the Form list
--   book                manual item; finishing it teaches the Form
--   moves, moveOrder    move definitions keyed by clip id (mastery, completionRequired, followThrough)
--   frames              clip length in frames at 180 fps, per move
--   combos, comboOrder, defaultCombos
--                       Senator "forms": move sequences per mastery tier (Senator's AutoCycle
--                       replaces them with a per-move shuffle, as for the katana)
--   stationaryMoves     moves that can only start standing still
--   guard               true if the Form can guard with Senator's Martial Arts block
--   baseAttackSpeed, comboTimeout
function PSF.define(def)
    if PSF.byId[def.id] then return PSF.byId[def.id] end
    local W = {}
    W.id, W.number = def.id, def.number
    W.prefix = "PSF"
    W.module = PSF.module .. "_" .. def.id
    W.book = def.book
    W.guard = def.guard == true
    W.style = { id = "psf_" .. def.id }
    W.baseAttackSpeed = def.baseAttackSpeed or 1
    W.comboTimeout = def.comboTimeout or 3500
    W.moves, W.moveOrder = def.moves, def.moveOrder
    for id, count in pairs(def.frames) do W.moves[id].minRequestMs = math.floor(count * 1000 / 180) end
    W.forms, W.formOrder, W.defaultForms = def.combos, def.comboOrder, def.defaultCombos
    W.chains = {}
    for tier, id in pairs(W.defaultForms) do W.chains[tier] = W.forms[id].moves end
    local stateKey = "PSF_" .. def.id

    -- Per-player Form state, saved in player modData and synced by the server (PSF_Server.lua).
    -- "form" is Senator's selected combo, not a photon sword Form.
    function W.state(player)
        local data = player:getModData()
        data[stateKey] = data[stateKey] or { version = 1, learned = false, enabled = true }
        return data[stateKey]
    end

    function W.mastery(player)
        return SMA.getMastery(player, W.style)
    end

    function W.tier(player)
        return W.mastery(player)
    end

    function W.allowedForm(player, id)
        local form = type(id) == "string" and W.forms[id]
        return type(form) == "table" and not form.disabled and W.state(player).learned == true
            and W.tier(player) >= form.mastery
    end

    function W.selectedForm(player)
        local selected = W.state(player).form
        return W.allowedForm(player, selected) and selected or W.defaultForms[W.tier(player)]
    end

    function W.setForm(player, id)
        if isClient() or not player or player:isDead() or player:isAttacking()
            or not W.allowedForm(player, id) then return false end
        W.state(player).form = id
        if W.resetCombo then W.resetCombo(player) end
        if W.resetSequence then W.resetSequence(player) end
        if W.sync then W.sync(player) end
        return true
    end

    function W.formToken(id, index)
        return id .. ":" .. tostring(index)
    end

    function W.parseForm(token)
        if type(token) ~= "string" or #token > 24 then return nil end
        local id, number = token:match("^([a-z0-9]+):(%d+)$")
        local index, form = tonumber(number), id and W.forms[id]
        if not form or not index or token ~= W.formToken(id, index) or not form.moves[index] then return nil end
        return id, index
    end

    -- Usable by a player whose active Form this is, holding an ignited photon sword in both hands.
    function W.canUse(player, weapon)
        if not player or player:isDead() or player:getVehicle() or player:isSitOnGround()
            or player:isClimbingRope() then return false end
        weapon = weapon or player:getPrimaryHandItem()
        return W.state(player).learned == true and PSF.activeForm(player) == W
            and PS.isIgnited(weapon) and weapon:getCondition() > 0
            and player:getPrimaryHandItem() == weapon and player:getSecondaryHandItem() == weapon
    end

    function W.eligible(player, weapon)
        return W.canUse(player, weapon) and W.state(player).enabled ~= false
    end

    function W.allowedMove(player, id)
        local move = type(id) == "string" and W.moves[id]
        return type(move) == "table" and not move.disabled and W.tier(player) >= move.mastery
    end

    function W.clear(player)
        for _, name in ipairs({ "PSFHolding", "PSFActive", "PSFWalking", "PSFFemale", "PSFBlock", "PSFParry" }) do
            player:setVariable(name, false)
        end
        for _, name in ipairs({ "PSFForm", "PSFMove", "PSFCompleted" }) do player:setVariable(name, "") end
    end

    -- Sets the hold and block variables the move and block AnimSets read; clears them when ineligible.
    function W.updateHold(player)
        if not W.eligible(player) then W.clear(player); return false end
        player:setVariable("PSFHolding", true)
        player:setVariable("PSFFemale", player:isFemale())
        player:setVariable("PSFWalking", player:isPlayerMoving())
        -- SMAGuard is Martial Arts Core's guard (SMA_Guard.lua), raised with its Block key.
        local block = W.guard and player:getVariableBoolean("SMAGuard")
        player:setVariable("PSFBlock", block)
        -- Just after the block stopped a blow: its parry. Photon Sword notes the photon sword strikes
        -- it settles (PS.noteParry); Core's own blocks are noted here in single player, and from
        -- the server's "parry" in multiplayer.
        if block and not isClient() and not isServer() and PSF.newCoreBlock(player, seenHere) then
            PS.noteParry(player)
        end
        player:setVariable("PSFParry", block and PS.parrying(player, PARRY_MS))
        return true
    end

    -- Starts move id's animation. serverApproved marks a remote player's move relayed by the
    -- server, which this client can't check against that player's mastery.
    function W.present(player, id, form, serverApproved)
        local remote = serverApproved == true and isClient() and not IsoPlayer.isLocalPlayer(player)
        local move = type(id) == "string" and W.moves[id]
        if not W.eligible(player) or not move or move.disabled or not remote and not W.allowedMove(player, id) then
            return false
        end
        if form ~= nil then
            local selected, step = W.parseForm(form)
            if not selected or W.forms[selected].disabled or not remote and not W.allowedForm(player, selected)
                or W.forms[selected].moves[step] ~= id then return false end
            player:setVariable("PSFForm", form)
        end
        W.updateHold(player)
        player:setVariable("PSFActive", true)
        player:setVariable("PSFMove", id)
        return true
    end

    -- Learning a Form makes it active if the player had none.
    function W.learn(player)
        if isClient() or not player or player:isDead() then return false end
        W.state(player).learned = true
        if not PSF.state(player).active then PSF.state(player).active = W.id end
        if W.sync then W.sync(player) end
        if PSF.syncActive then PSF.syncActive(player) end
        return true
    end

    -- Senator's shared art machinery. Each installer is keyed by the art's prefix, and some only
    -- know Senator's own prefixes, so a few need help:
    -- DirectionPolicy looks up a table of disabled moves per prefix; photon sword Forms disable none.
    local Direction = require "SWMA_DirectionPolicy"
    Direction.disabled.PSF = Direction.disabled.PSF or {}
    Direction.apply(W, "PSF")
    require("SWMA_Progression").register(W, "PSF")
    -- MovingAttack has no list of standing-only moves for PSF; set the Form's after install.
    require("SWMA_MovingAttack").install(W, "PSF")
    W.stationaryMoves = def.stationaryMoves or {}
    -- AutoCycle only uses the prefix to pick a cycling mode; "SWMK" gives the katana's per-move shuffle.
    require("SWMA_AutoCycle").install(W, "SWMK")
    Sequence.install(W)

    -- No move starts mid-dodge, as SWMA_Dodge.lua does for Senator's arts, or while a local
    -- player's guard is up; Martial Arts Core lowers the guard once attack is held.
    local present = W.present
    W.present = function(player, ...)
        if SMA.dodgeSides[player:getVariableString("SMADodge")] then return false end
        if IsoPlayer.isLocalPlayer(player) and player:getVariableBoolean("SMAGuard") then
            -- cancelAttack clears every PSF* variable; restore them at once so the block's
            -- looping node isn't dropped (and its breath restarted) for a frame.
            W.cancelAttack(player)
            W.updateHold(player)
            return false
        end
        return present(player, ...)
    end

    PSF.forms[#PSF.forms + 1] = W
    PSF.byId[W.id] = W
    return W
end

-- Finishing a Form's manual teaches that Form.
local readComplete = ISReadABook.complete
function ISReadABook:complete(...)
    local results = PS.pack(readComplete(self, ...))
    if results[1] == true and not isClient() and not self.forceStopped and self.item and self.character
        and self.character:getInventory():containsRecursive(self.item)
        and self.item:getNumberOfPages() > 0
        and self.item:getAlreadyReadPages() >= self.item:getNumberOfPages() then
        for _, W in ipairs(PSF.forms) do
            if self.item:getFullType() == W.book then W.learn(self.character) end
        end
    end
    return unpack(results, 1, results.n)
end

-- Weapon dodges: an eligible Form dodges with Pak Mei's sidesteps, as Senator's arts do.
local dodgeStyle = { id = "psf", weaponDodge = true, dodges = SMA.styles.pakmei.dodges }
local weaponDodgeStyle = SMA.weaponDodgeStyle
function SMA.weaponDodgeStyle(player, ...)
    local W = PSF.activeForm(player)
    if W and W.eligible(player) then return dodgeStyle end
    return weaponDodgeStyle(player, ...)
end

-- Guard: Martial Arts Core's block (SMA_Guard.lua) is for unarmed styles only. A Form with
-- guard = true can use it too: hold Block while aiming the ignited sword. Core runs the rest:
-- meter, perfect guard stagger, zombie pushes, guard break, and multiplayer sync.
local function guarding(player)
    local W = PSF.activeForm(player)
    return W and W.guard and W.eligible(player) and W or nil
end
PSF.guardingForm = guarding

local guardEligible = SMA.guardEligible
function SMA.guardEligible(player, ...)
    if player and guarding(player) then
        return not (player:isDead() or player:isOnFloor() or player:hasHitReaction()
            or player:isBeingGrappled() or player:isDoShove())
    end
    return guardEligible(player, ...)
end

-- Core lowers a guard's drain by the defender's Martial Arts level only if they have an unarmed
-- style; give Form users the same reduction.
local guardDrain = SMA.guardDrain
function SMA.guardDrain(attacker, target, weapon, ...)
    local drain = guardDrain(attacker, target, weapon, ...)
    if target and guarding(target) and not SMA.getStyle(target) then
        drain = math.max(5, drain * (1 - SMA.getLevel(target) * .03))
    end
    return drain
end

-- The Form a player fights with right now: their active Form, usable with weapon and enabled.
function PSF.fightingForm(player, weapon)
    local W = PSF.usable(player, weapon)
    return W and W.eligible(player, weapon) and W or nil
end

-- A player's ignited photon sword belongs to their enabled photon sword Form, not the katana art.
-- With no Form enabled (none learned, or the Photon Sword tab's Disable), the katana art has it.
local katanaCanUse = SWMK.canUse
function SWMK.canUse(player, weapon, ...)
    if PSF.fightingForm(player, weapon) then return false end
    return katanaCanUse(player, weapon, ...)
end

-- Photon Sword's stance gives way while a Form's block plays; while a dodge plays (Core sets
-- SMADodge to its side, then "done", and clears it after), since the ready stance's AnimSets
-- outrank Senator's Pak Mei dodge nodes; and to the game's default two-handed katana behavior while
-- the ignited sword is held with no Form enabled: vanilla's (or Senator's katana art's) animations,
-- no ready-stance deflect, and the blade staying lit to run.
local function dodging(player)
    local side = player:getVariableString("SMADodge")
    return side == "done" or SMA.dodgeSides[side] == true
end

PS.addStanceYield(function(player)
    return player:getVariableBoolean("PSFBlock")
        or dodging(player)
        or PS.holdsIgnited(player) and not PSF.fightingForm(player)
end)

return PSF
