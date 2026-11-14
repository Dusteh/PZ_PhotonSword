-- MP clients load server/ too; this file is only for the server (or a single-player game).
if isClient() then return end

require "PhotonSword/PS_Core"
require "TimedActions/ISDestroyStuffAction"

-- Server authority for what an ignited blade cuts through when it swings. Clients send a "cut"
-- command on each swing (PS_Swing.lua); in single player it arrives here locally. Each swing cuts
-- at most one object per edge the player faces, plus one object in the square in front:
--  * Map doors and windows, map walls, and map furniture/fences each have a sandbox option.
--  * Anything a player built (IsoThumpable) follows Destroy Player-Built Objects instead.
--  * Trees, bushes, and tall grass follow Instant Chop / Clear Vegetation.
-- The Cut Effect option picks what happens to a target: destroyed outright (like a sledgehammer)
-- or set on fire. Fires start on the far side of the edge or in the square in front, never on the
-- player's own square, and then burn and spread like any other fire.

local PS = PhotonSword

-- Sprites vanilla's sledgehammer refuses (ISDestroyCursor:canDestroy): billboard and street-light
-- bases, water, ground overlays, curbs, and litter.
local PROTECTED_SPRITES = { advertising_01_14 = true, lighting_outdoor_01_16 = true, lighting_outdoor_01_17 = true }
local PROTECTED_PREFIXES = { "blends_natural_02", "blends_grassoverlays", "d_", "e_", "f_", "trash_01", "street_curbs" }

local function isProtectedSprite(obj)
    local name = obj:getSprite() and obj:getSprite():getName()
    if not name then return false end
    if PROTECTED_SPRITES[name] then return true end
    for _, prefix in ipairs(PROTECTED_PREFIXES) do
        if luautils.stringStarts(name, prefix) then return true end
    end
    return luautils.stringStarts(name, "vegetation_") and not (luautils.stringStarts(name, "vegetation_indoor")
        or luautils.stringStarts(name, "vegetation_drying"))
end

-- Player-built objects follow their own option; everything else follows its category's option.
local function allowed(obj, worldOption)
    if not obj or obj:getObjectIndex() < 0 then return false end
    if instanceof(obj, "IsoThumpable") then return PS.canCutPlayerBuilt() end
    return worldOption()
end

-- Multiplayer: never cut inside a safehouse the player doesn't belong to.
local function canCutAt(playerObj, square)
    local safe = SafeHouse.isSafeHouse(square, nil, false)
    return not safe or safe:playerAllowed(playerObj)
end

-- Plays a sound at a square for everyone nearby: broadcast to clients from a server, played
-- directly in single player (where playServerSound does nothing).
local function playAt(sound, square)
    if not sound or sound == "" or not square then return end
    if isServer() then
        playServerSound(sound, square)
    else
        square:playSound(sound)
    end
end

-- The sound an object makes breaking, as vanilla picks it for a sledgehammer
-- (ISDestroyStuffAction:perform): doors and player-built objects have their own, windows smash,
-- and everything else gets a furniture break matched to its material (wood, metal, ceramic, plant).
local function breakSound(obj)
    if instanceof(obj, "IsoWindow") then return "SmashWindow" end
    if instanceof(obj, "IsoDoor") or instanceof(obj, "IsoThumpable") then return obj:getBreakSound() end
    return IsoThumpable.GetBreakFurnitureSound(obj:getSprite())
end

-- Removes an object the way a sledgehammer does, which also takes care of container contents,
-- barricades, curtains, sheet ropes, wall attachments, corner walls, and multi-tile doors and
-- stairs. That code wears down the held weapon, so the blade's condition is put back afterwards.
local function destroy(playerObj, blade, obj)
    local sound, square = breakSound(obj), obj:getSquare()
    local action = ISDestroyStuffAction:new(playerObj, obj)
    action.hasSledgehammerInRange = function() return true end
    local condition = blade:getCondition()
    action:complete()
    playAt(sound, square)
    if blade:getCondition() ~= condition then
        blade:setCondition(condition)
        syncItemFields(playerObj, blade)
    end
end

-- Starts a vanilla fire on a square (once per swing, and not where one is already burning).
local function ignite(ctx, square)
    if not square or ctx.lit[square] or not canCutAt(ctx.playerObj, square) then return end
    ctx.lit[square] = true
    if square:getProperties():has(IsoFlagType.burning) then return end
    IsoFireManager.StartFire(getCell(), square, true, 100)
end

-- Applies the Cut Effect to a target: destroys it, or sets fire to fireSquare.
local function strike(ctx, obj, fireSquare)
    if ctx.burn then
        ignite(ctx, fireSquare)
    else
        destroy(ctx.playerObj, ctx.blade, obj)
    end
end

local function isBasementVoidWall(wall, north)
    if north then return IsoCell.isBasementWallAdjacentToTheVoid_North(wall) end
    return IsoCell.isBasementWallAdjacentToTheVoid_West(wall)
end

-- Doors, windows, walls, and fences sit on a square's north or west edge, so the edge between two
-- neighbours belongs to whichever of them is further south or east. A door or window blocks the
-- wall around it, so the wall (if allowed) comes out on a later swing. When burning, the fire
-- goes on the far side of the edge (`to`), never the player's own square.
local function cutEdge(ctx, from, dx, dy)
    local to = getCell():getGridSquare(from:getX() + dx, from:getY() + dy, from:getZ())
    if not to then return end
    local owner = (dx > 0 or dy > 0) and to or from
    local north = dy ~= 0
    if not canCutAt(ctx.playerObj, owner) then return end

    local opening = owner:getDoorOrWindow(north) or owner:getGarageDoor(north)
    if opening then
        if allowed(opening, PS.canCutDoorsAndWindows) then strike(ctx, opening, to) end
        return
    end
    local wall = owner:getWall(north) or owner:getThumpableWall(north)
    if wall then
        if allowed(wall, PS.canCutWalls) and not isBasementVoidWall(wall, north) then
            strike(ctx, wall, to)
        end
        return
    end
    local fence = owner:getHoppable(north)
    if fence and allowed(fence, PS.canCutWorldObjects) and not isProtectedSprite(fence) then
        strike(ctx, fence, to)
    end
end

-- Furniture, appliances, containers, and the like standing in a square. Edges (walls, doors,
-- windows, fences) are cutEdge's job; floors, vegetation, and sheet ropes are never cut here.
local function isLooseObject(obj)
    if not obj:getSprite() or isProtectedSprite(obj) then return false end
    if instanceof(obj, "IsoWorldInventoryObject") or instanceof(obj, "IsoTree") or instanceof(obj, "IsoDoor")
            or instanceof(obj, "IsoWindow") or instanceof(obj, "IsoBarricade") or instanceof(obj, "IsoFire") then
        return false
    end
    if instanceof(obj, "IsoThumpable") and (obj:isDoor() or obj:isWindow()) then return false end
    if obj:isWall() or obj:isHoppable() then return false end
    local type = obj:getType()
    if type == IsoObjectType.doorFrW or type == IsoObjectType.doorFrN then return false end
    local props = obj:getProperties()
    if not props then return false end
    for _, flag in ipairs({ IsoFlagType.solidfloor, IsoFlagType.vegitation, IsoFlagType.cutN, IsoFlagType.cutW,
            IsoFlagType.canBeCut, IsoFlagType.canBeRemoved }) do
        if props:has(flag) then return false end
    end
    return not (props:has(IsoFlagType.climbSheetN) or props:has(IsoFlagType.climbSheetW)
        or props:has(IsoFlagType.climbSheetE) or props:has(IsoFlagType.climbSheetS)
        or props:has(IsoFlagType.climbSheetTopN) or props:has(IsoFlagType.climbSheetTopW)
        or props:has(IsoFlagType.climbSheetTopE) or props:has(IsoFlagType.climbSheetTopS))
end

-- Cuts the topmost allowed object standing in the square.
local function cutObject(ctx, square)
    if not (PS.canCutWorldObjects() or PS.canCutPlayerBuilt()) or not canCutAt(ctx.playerObj, square) then return end
    local objects = square:getObjects()
    for i = objects:size() - 1, 0, -1 do
        local obj = objects:get(i)
        if isLooseObject(obj) and allowed(obj, PS.canCutWorldObjects) then
            strike(ctx, obj, square)
            return
        end
    end
end

local function hasVegetation(square)
    if square:getTree() then return true end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local props = objects:get(i):getProperties()
        if props and (props:has(IsoFlagType.canBeCut) or props:has(IsoFlagType.canBeRemoved)) then
            return true
        end
    end
    return false
end

-- Fells the tree and removes bushes (canBeCut) and tall grass (canBeRemoved) on a square. A
-- falling tree plays its own sound; bushes and grass get vanilla's, once per square.
local function clearVegetation(playerObj, square)
    if not canCutAt(playerObj, square) then return end
    local tree = square:getTree()
    if tree then
        tree:toppleTree(playerObj)
    end
    local cutBush, cutGrass = false, false
    local objects = square:getObjects()
    for i = objects:size() - 1, 0, -1 do
        local obj = objects:get(i)
        local props = obj:getProperties()
        if props and props:has(IsoFlagType.canBeCut) then
            square:transmitRemoveItemFromSquare(obj)
            cutBush = true
        elseif props and props:has(IsoFlagType.canBeRemoved) then
            square:transmitRemoveItemFromSquare(obj)
            cutGrass = true
        end
    end
    if cutBush then
        playAt("BreakPlant", square)
    elseif cutGrass then
        playAt("RemovePlant", square)
    end
end

local function cut(playerObj, dir)
    local blade = PS.getHeld(playerObj)
    if not blade or not PS.isIgnited(blade) or playerObj:isDead() then return end
    local square = playerObj:getCurrentSquare()
    if not square then return end
    local dx, dy = dir:dx(), dir:dy()
    local ctx = { playerObj = playerObj, blade = blade, burn = PS.isCutEffectFire(), lit = {} }

    -- Diagonal swings reach both edges the player is facing.
    if dx ~= 0 then cutEdge(ctx, square, dx, 0) end
    if dy ~= 0 then cutEdge(ctx, square, 0, dy) end

    -- Only reach into the square in front if nothing (left) stands between it and the player.
    local front = getCell():getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
    local reachable = front and not square:isBlockedTo(front)
    if reachable then
        cutObject(ctx, front)
    end
    if PS.canCutVegetation() then
        if ctx.burn then
            -- Only the square in front: setting the player's own square alight would burn them.
            if reachable and hasVegetation(front) then ignite(ctx, front) end
        else
            clearVegetation(playerObj, square)
            if reachable then
                clearVegetation(playerObj, front)
            end
        end
    end
end

-- A swing takes well over this long, so faster "cut" commands can only come from a modified client.
local MIN_CUT_INTERVAL_MS = 300
local lastCutMs = {} -- [username] = timestamp of the last accepted cut

local function onClientCommand(module, command, playerObj, args)
    if module ~= "PhotonSword" or command ~= "cut" or not playerObj then return end
    local now, key = getTimestampMs(), playerObj:getUsername()
    if lastCutMs[key] and now - lastCutMs[key] < MIN_CUT_INTERVAL_MS then return end
    lastCutMs[key] = now
    local dir = args and args.dir and IsoDirections.fromString(args.dir)
    if dir then
        cut(playerObj, dir)
    end
end

Events.OnClientCommand.Add(onClientCommand)
