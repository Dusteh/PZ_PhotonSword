-- Defines every photon sword Form, in the order the Photon Sword tab lists them.
-- Client and server code requires this before looping over PSF.forms.

local PSF = require "PhotonSwordForms/PSF_Core"
require "PhotonSwordForms/PSF_Form1"

-- Lists each Form in Senator's table of arts (SWMA_TrainingStyles), which its admin window
-- (SWMA_Admin.lua) reads to show and set each art's learned state and mastery. The Forms are added
-- after SWMA_TrainingDefinition has registered an Exercise for every art in the table, so they get
-- no Exercise; Form practice isn't implemented.
local Training = require "SWMA_TrainingStyles"
require "SWMA_TrainingDefinition"
for _, W in ipairs(PSF.forms) do
    local id = W.style.id
    if not Training.byID[id] then
        local e = { id = id, prefix = W.prefix, nameKey = "UI_PSF_Form" .. W.number .. "_Admin", W = W, clips = {} }
        Training.entries[#Training.entries + 1], Training.byID[id] = e, e
    end
end

return PSF
