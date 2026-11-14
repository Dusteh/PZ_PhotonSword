-- Per-player client options, in their own section of Photon Sword's entry under Options > Mods.
-- Saved by the game in ModOptions.ini. Balance the server decides is in sandbox options
-- (PSF_Settings.lua), which have their own section of the Photon Sword sandbox page.

require "PhotonSword/PS_Options"
local PS = PhotonSword

PS.addSandboxSection(50, "PhotonSwordForms", "^PhotonSwordForms%.")

PhotonSwordFormsOptions = PhotonSwordFormsOptions or {}
local PSFO = PhotonSwordFormsOptions

local options = PZAPI.ModOptions:getOptions("PhotonSword")

options:addTitle("UI_PSF_Options_Dodge")
-- This client animates every player with it, so it sets what this player sees (PSF_Dodging.lua).
PSFO.dodgeAnimation = options:addTickBox("dodgeAnimation", "UI_PSF_Options_DodgeAnimation", true,
    "UI_PSF_Options_DodgeAnimation_tooltip")
PSFO.relightAfterDodge = options:addTickBox("relightAfterDodge", "UI_PSF_Options_RelightAfterDodge", true,
    "UI_PSF_Options_RelightAfterDodge_tooltip")

-- Vanilla only reads ModOptions.ini when the Options screen is built; read the saved values now.
PZAPI.ModOptions:load()
