-- Adds each photon sword Form's manual to the same book and sports containers as Senator's
-- katana manual (SWMK_Loot.lua), at half its weights since photon swords themselves are rare.

if isClient() then return end
require "Items/ProceduralDistributions"
local PSF = require "PhotonSwordForms/PSF_Forms"

local placements = { BookstoreBooks = 0.75, LibraryBooks = 0.5, BookstoreSports = 1,
    LibrarySports = 1, UniversityLibraryBooks = 0.5, UniversityLibrarySports = 1,
    BookstoreMisc = 0.5, LibraryMagazines = 0.5, MagazineRackMixed = 0.25,
    PostOfficeMagazines = 0.25, CrateMagazines = 0.25, GymLockers = 0.15,
    FitnessTrainer = 0.15, BoxingLockers = 0.15, LivingRoomShelf = 0.025,
    LivingRoomShelfClassy = 0.025, LivingRoomShelfRedneck = 0.025, ShelfGeneric = 0.025 }

local function place(book)
    for name, weight in pairs(placements) do
        local list = ProceduralDistributions.list[name]
        if list then
            local exists = false
            for i = 1, #list.items, 2 do
                if list.items[i] == book then exists = true; break end
            end
            if not exists then
                table.insert(list.items, book)
                table.insert(list.items, weight)
            end
        end
    end
end

for _, W in ipairs(PSF.forms) do place(W.book) end
