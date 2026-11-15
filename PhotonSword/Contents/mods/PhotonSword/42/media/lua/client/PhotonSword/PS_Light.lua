require "PhotonSword/PS_Core"
require "PhotonSword/PS_Options"

-- Casts colored light around every visible player, and every NPC (PS.forEachNpcWielder),
-- holding an ignited blade.
-- Lights are client-side only: each client draws them for the players it can see.
-- Radius and on/off come from this client's mod options.

local PS = PhotonSword
local PSO = PhotonSwordOptions

local UPDATE_EVERY_TICKS = 5
local tickCounter = 0
local lights = {} -- [player onlineID or index, or NPC zombie] = { source, blade, x, y, z, color, radius }

local function removeLight(key)
    local entry = lights[key]
    if entry then
        getCell():removeLamppost(entry.source)
        lights[key] = nil
    end
end

local function updateLight(key, playerObj)
    local blade = PS.getHeld(playerObj)
    if not PS.isIgnited(blade) or playerObj:isDead() or not PSO.bladeLight:getValue() then
        removeLight(key)
        return
    end

    local entry = lights[key]
    -- A lit blade's color can't change (its crystal stays in, and relighting makes a new item),
    -- so it's only read from the crystal for a blade not seen before.
    local color = entry and entry.blade == blade and entry.color or PS.getBladeColor(blade)
    local x, y, z = math.floor(playerObj:getX()), math.floor(playerObj:getY()), math.floor(playerObj:getZ())
    local radius = PSO.lightRadius:getValue()
    if entry and entry.x == x and entry.y == y and entry.z == z and entry.color == color and entry.radius == radius then
        entry.blade = blade
        return
    end

    removeLight(key)
    local rgb = PS.COLORS[color]
    local source = IsoLightSource.new(x, y, z, rgb.r, rgb.g, rgb.b, radius)
    getCell():addLamppost(source)
    lights[key] = { source = source, blade = blade, x = x, y = y, z = z, color = color, radius = radius }
end

local function onTick()
    tickCounter = tickCounter + 1
    if tickCounter < UPDATE_EVERY_TICKS then return end
    tickCounter = 0

    local seen = PS.forEachWielder(updateLight)
    for key in pairs(lights) do
        if not seen[key] then removeLight(key) end
    end
end

Events.OnTick.Add(onTick)
