-- Photon Sword and its patch mods share one sandbox page (page = PhotonSword in each mod's
-- sandbox-options.txt), split into titled sections. The sandbox screens draw a title above any
-- setting that has one (setting.title, shown as the translation of Sandbox_Title_<title>), but
-- the game only titles its own settings. So this sorts the page's settings into the sections mods
-- register with PS.addSandboxSection, and titles the first setting of each. It does this to the
-- pages ServerSettingsScreen.getSandboxSettingsTable hands out, which the new-game sandbox
-- screen and the in-game admin sandbox window are built from. (The admin window draws no titles,
-- but keeps the order.)

require "PhotonSword/PS_Core"
local PS = PhotonSword

PS.addSandboxSection(10, "PhotonSword_General",
    "^PhotonSword%.BatteryLifeHours$", "^PhotonSword%.DamageMultiplier$", "^PhotonSword%.ExtinguishWhileRunning$")
PS.addSandboxSection(20, "PhotonSword_Cutting", "^PhotonSword%.Cut")
PS.addSandboxSection(30, "PhotonSword_Deflect", "^PhotonSword%.Deflect", "^PhotonSword%.Soak")
PS.addSandboxSection(40, "PhotonSword_Block", "^PhotonSword%.Block", "^PhotonSword%.Npc")

local function byOrder()
    local sections = {}
    for _, section in ipairs(PS.sandboxSections) do sections[#sections + 1] = section end
    table.sort(sections, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.title < b.title
    end)
    return sections
end

local function sectionOf(name, sections)
    for i, section in ipairs(sections) do
        for _, pattern in ipairs(section.patterns) do
            if name:match(pattern) then return i end
        end
    end
end

-- Sorts a page's settings by section, keeping each section's settings in their own order, with
-- any setting no section claims at the end. Pages with no Photon Sword setting are left alone.
local function arrange(page, sections)
    local members, rest, ours = {}, {}, false
    for _, setting in ipairs(page.settings) do
        local i = type(setting.name) == "string" and sectionOf(setting.name, sections)
        if i then
            members[i] = members[i] or {}
            table.insert(members[i], setting)
            ours = true
        else
            table.insert(rest, setting)
        end
    end
    if not ours then return end
    local settings = {}
    for i, section in ipairs(sections) do
        for j, setting in ipairs(members[i] or {}) do
            setting.title = j == 1 and section.title or nil
            settings[#settings + 1] = setting
        end
    end
    for _, setting in ipairs(rest) do settings[#settings + 1] = setting end
    page.settings = settings
end

local function install()
    local screen = ServerSettingsScreen
    if type(screen) ~= "table" or type(screen.getSandboxSettingsTable) ~= "function" or screen.psSections then
        return
    end
    screen.psSections = true
    local get = screen.getSandboxSettingsTable
    screen.getSandboxSettingsTable = function(...)
        local results = PS.pack(get(...))
        if type(results[1]) == "table" then
            local sections = byOrder()
            for _, page in ipairs(results[1]) do
                if type(page) == "table" and type(page.settings) == "table" then arrange(page, sections) end
            end
        end
        return unpack(results, 1, results.n)
    end
end

install()
