-- Dodging with an ignited photon sword puts the blade out for the dodge (PSF_Dodging.lua).
-- The dodge's style is chosen while the blade is lit (a Form's, or Senator's katana art's), but the
-- hilt left in hand fits neither, and Martial Arts Core drops a dodge (and its Lightfoot XP) whose
-- style goes away partway. So a style chosen with a lit photon sword is kept for that dodge, while
-- the player still holds the sword, until Core finishes it.

local SMA = require "SMA_Core"
require "SWMA_Dodge"
require "PhotonSwordForms/PSF_Core"
local PS = PhotonSword

local KEEP_MS = 3000  -- past the longest dodge and Core's XP window (its duration + 1.5 s)
local kept = setmetatable({}, { __mode = "k" })

local weaponDodgeStyle = SMA.weaponDodgeStyle
function SMA.weaponDodgeStyle(player, ...)
    local style = weaponDodgeStyle(player, ...)
    if style then return style end
    local k = player and kept[player]
    if k and getTimestampMs() < k.ends and PS.isPhotonSword(player:getPrimaryHandItem()) then return k.style end
end

-- Remembers the style of a dodge starting with a lit photon sword in hand.
local function keep(player)
    if not player or not PS.isIgnited(player:getPrimaryHandItem()) then return end
    local style = weaponDodgeStyle(player)
    if style then kept[player] = { style = style, ends = getTimestampMs() + KEEP_MS } end
end

-- The local player's dodge (startDodge) and the server's or single player's XP check (beginDodgeXp)
-- each pick the style; keep it at both.
local startDodge = SMA.startDodge
function SMA.startDodge(player, ...)
    keep(player)
    return startDodge(player, ...)
end

local beginDodgeXp = SMA.beginDodgeXp
function SMA.beginDodgeXp(player, ...)
    if not (kept[player] and getTimestampMs() < kept[player].ends) then keep(player) end
    return beginDodgeXp(player, ...)
end

-- The dodge is over once Core settles its XP (the server, or single player) or a multiplayer client
-- stops it. The server checks a "position" result again later, so the style stays for that.
local finishDodgeXp = SMA.finishDodgeXp
function SMA.finishDodgeXp(player, ...)
    local results = PS.pack(finishDodgeXp(player, ...))
    if results[2] ~= "position" then kept[player] = nil end
    return unpack(results, 1, results.n)
end

local stopDodge = SMA.stopDodge
function SMA.stopDodge(player, ...)
    local results = PS.pack(stopDodge(player, ...))
    if isClient() then kept[player] = nil end
    return unpack(results, 1, results.n)
end
