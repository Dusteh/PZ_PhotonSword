-- Registers each photon sword Form's manual with Senator's illustrated manual window, which adds
-- "View illustrated manual" to the manual's context menu. The window reads its text from
-- UI_<key>_Guide* translations (key = PSF_<form id>), falling back to the strings here.

local PSF = require "PhotonSwordForms/PSF_Forms"
local Manuals = require "SWMA_Manuals"

for _, W in ipairs(PSF.forms) do
    W.manualKey = "PSF_" .. W.id
    Manuals.definitions[W.manualKey] = {
        book = W.book,
        weapon = "PhotonSword.PhotonSword",
        title = "Photon Sword: Form " .. W.number,
        cover = "media/textures/PSF_Manual_" .. W.number .. "_Cover.png",
        equipment = "Ignite a photon sword and hold it in both hands. If you know more than one Form, choose which one you fight with in the Photon Sword tab.",
        training = "Successful hits train Martial Arts and this Form's mastery. Mastery unlocks attacks, which shuffle without repeats. Release aim to cancel.",
    }
end
