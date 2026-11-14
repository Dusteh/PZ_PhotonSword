-- Per-player client options shown under Options > Mods > Photon Sword Forms. Saved by the game in
-- ModOptions.ini. Balance the server decides is in sandbox options (PSF_Settings.lua).

PhotonSwordFormsOptions = PhotonSwordFormsOptions or {}
local PSFO = PhotonSwordFormsOptions

local options = PZAPI.ModOptions:create("PhotonSwordForms", "UI_PSF_Options_Title")

options:addTitle("UI_PSF_Options_Dodge")
-- This client animates every player with it, so it sets what this player sees (PSF_Dodging.lua).
PSFO.dodgeAnimation = options:addTickBox("dodgeAnimation", "UI_PSF_Options_DodgeAnimation", true,
    "UI_PSF_Options_DodgeAnimation_tooltip")
PSFO.relightAfterDodge = options:addTickBox("relightAfterDodge", "UI_PSF_Options_RelightAfterDodge", true,
    "UI_PSF_Options_RelightAfterDodge_tooltip")

-- Vanilla only reads ModOptions.ini when the Options screen is built; read the saved values now.
PZAPI.ModOptions:load()
