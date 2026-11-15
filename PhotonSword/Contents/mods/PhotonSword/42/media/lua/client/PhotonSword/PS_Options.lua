-- Per-player client options shown under Options > Mods. Saved by the game in ModOptions.ini.
-- These only cover controls and visuals; balance values (drain, damage) belong in sandbox options.

require "PhotonSword/PS_Core"

PhotonSwordOptions = PhotonSwordOptions or {}
local PSO = PhotonSwordOptions

local options = PZAPI.ModOptions:create("PhotonSword", "UI_PS_Options_Title")

options:addTitle("UI_PS_Options_Hotkeys")
-- Keybind names must be passed already translated: vanilla MainOptions tags the button with the
-- raw name but finds it again by the label's translated text, and crashes when they differ.
-- Z is vanilla's Switch Seat (vehicles only), which PS_Hotkeys skips.
-- R is vanilla's Reload / Sharpen / Rotate; Swap Battery steps aside whenever one of those applies.
-- X is vanilla's Rack Firearm; Toggle Cutting only claims it while an ignited (two-handed) blade
-- is held, so no gun can be in hand.
PSO.toggleKey = options:addKeyBind("toggleKey", getText("UI_PS_Options_ToggleKey"), Keyboard.KEY_Z, "UI_PS_Options_ToggleKey_tooltip")
PSO.batteryKey = options:addKeyBind("batteryKey", getText("UI_PS_Options_BatteryKey"), Keyboard.KEY_R, "UI_PS_Options_BatteryKey_tooltip")
PSO.cutKey = options:addKeyBind("cutKey", getText("UI_PS_Options_CutKey"), Keyboard.KEY_X, "UI_PS_Options_CutKey_tooltip")
PSO.extinguishOnHolster = options:addTickBox("extinguishOnHolster", "UI_PS_Options_ExtinguishOnHolster", true, "UI_PS_Options_ExtinguishOnHolster_tooltip")

options:addTitle("UI_PS_Options_Visuals")
-- Blade color isn't an option: it comes from the crystal in the hilt.
PSO.bladeLight = options:addTickBox("bladeLight", "UI_PS_Options_BladeLight", true, "UI_PS_Options_BladeLight_tooltip")
PSO.lightRadius = options:addSlider("lightRadius", "UI_PS_Options_LightRadius", 2, 8, 1, 4, "UI_PS_Options_LightRadius_tooltip")
-- This client animates every player with it, so it sets what this player sees (PS_Stance.lua).
PSO.vanillaStance = options:addTickBox("vanillaStance", "UI_PS_Options_VanillaStance", false, "UI_PS_Options_VanillaStance_tooltip")
-- Each client rolls the beckon for every player it animates (PS_Stance.lua), so this sets what this player sees.
PSO.beckonChance = options:addSlider("beckonChance", "UI_PS_Options_BeckonChance", 0, 100, 5, 10, "UI_PS_Options_BeckonChance_tooltip")

options:addTitle("UI_PS_Options_Sound")
PSO.humVolume = options:addSlider("humVolume", "UI_PS_Options_HumVolume", 0, 100, 5, 50, "UI_PS_Options_HumVolume_tooltip")

-- Tone picks one of the generated sound sets (PS.SOUND_TONES); the default is "Classic".
local function addToneBox(id)
    local box = options:addComboBox(id, "UI_PS_Options_" .. id, "UI_PS_Options_" .. id .. "_tooltip")
    for _, tone in ipairs(PhotonSword.SOUND_TONES) do
        box:addItem("UI_PS_Options_Tone_" .. tone, tone == "Classic")
    end
    return box
end

PSO.humTone = addToneBox("HumTone")
PSO.humPitch = options:addSlider("humPitch", "UI_PS_Options_HumPitch", 50, 150, 5, 100, "UI_PS_Options_HumPitch_tooltip")
PSO.swingTone = addToneBox("SwingTone")
PSO.swingPitch = options:addSlider("swingPitch", "UI_PS_Options_SwingPitch", 70, 130, 10, 100, "UI_PS_Options_SwingPitch_tooltip")
PSO.hitTone = addToneBox("HitTone")
PSO.hitPitch = options:addSlider("hitPitch", "UI_PS_Options_HitPitch", 70, 130, 10, 100, "UI_PS_Options_HitPitch_tooltip")

function PSO.getTone(box)
    return PhotonSword.SOUND_TONES[box:getValue()] or "Classic"
end

options:addTitle("UI_PS_Options_Deflect")
PSO.deflectText = options:addTickBox("deflectText", "UI_PS_Options_DeflectText", true, "UI_PS_Options_DeflectText_tooltip")
PSO.deflectSound = options:addTickBox("deflectSound", "UI_PS_Options_DeflectSound", true, "UI_PS_Options_DeflectSound_tooltip")

options:addTitle("UI_PS_Options_Notifications")
PSO.lowPowerWarning = options:addSlider("lowPowerWarning", "UI_PS_Options_LowPower", 0, 50, 5, 15, "UI_PS_Options_LowPower_tooltip")

-- Vanilla only reads ModOptions.ini when the Options screen is built, so until then every option
-- would report its default (Blue, Classic, ...). Read the saved values now; later calls from the
-- Options screen re-read the file, so mods defining options after us are unaffected.
PZAPI.ModOptions:load()
