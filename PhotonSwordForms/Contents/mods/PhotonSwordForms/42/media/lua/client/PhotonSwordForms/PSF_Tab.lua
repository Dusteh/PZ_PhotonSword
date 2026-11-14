-- The Photon Sword tab in Senator's martial arts window, next to its Unarmed and Weapons tabs.
-- A copy of Senator's Weapons page (SWMA_WeaponWindow.lua), whose list of arts is closed to other
-- mods, listing photon sword Forms instead: the same layout, buttons, strings, Martial Arts card,
-- footer, and admin button. Its choice button (Senator's spear/staff choice) picks the active
-- Form once two or more are learned.
-- Senator builds the tabbed window in two places (the character info panel and the standalone
-- window) and rebuilds it on resolution changes; attach() adds this tab to each one it makes.

require "ISUI/ISPanelJoypad"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "SWMA_Window"
require "SWMA_AdminWindow"
local SMA = require "SMA_Core"
local Admin = require "SWMA_Admin"
local Manuals = require "SWMA_Manuals"
local PSF = require "PhotonSwordForms/PSF_Forms"
require "PhotonSwordForms/PSF_Manual"

-- One entry per Form, shaped like Senator's: prefix is the Form's key in SWMA_Manuals.definitions.
local entries = {}
for _, W in ipairs(PSF.forms) do
    entries[#entries + 1] = { id = W.id, prefix = W.manualKey, name = "UI_PSF_Form" .. W.number, W = W }
end

local SMALL, MEDIUM, LARGE = UIFont.Small, UIFont.Medium, UIFont.Large
local WHITE, GREY, DIM, GOLD, ORANGE = {1,1,1}, {.7,.7,.7}, {.52,.52,.52}, {1,.89,.38}, {.95,.6,.3}

local function tr(key, fallback, ...) return Manuals.tr(key, fallback, ...) end
local function width(font, value) return getTextManager():MeasureStringX(font, value) end
local function fit(font, value, limit)
    if limit <= 0 then return "" end
    if width(font, value) <= limit then return value end
    while #value > 0 and width(font, value .. "...") > limit do value = value:sub(1, -2) end
    return #value > 0 and value .. "..." or ""
end
local function text(ui, value, x, y, color, font)
    ui:drawText(value, x, y, color[1], color[2], color[3], 1, font or SMALL)
end
local function right(ui, value, x, y, color)
    ui:drawTextRight(value, x, y, color[1], color[2], color[3], 1, SMALL)
end
local function image(ui, path, x, y, w, h, color)
    local texture = getTexture(path)
    if texture then ui:drawTextureScaled(texture, x, y, w, h, 1, color[1], color[2], color[3]) end
end
local function panel(ui, x, y, w, h)
    ui:drawRect(x, y, w, h, .8, 0, 0, 0)
    ui:drawRectBorder(x, y, w, h, .9, .4, .4, .4)
end
local function units(ui, x, y, size, gap, count, level, progress)
    for i = 0, count - 1 do
        local color = i < level and GOLD or i == level and {.4,.4,.4} or {.2,.2,.2}
        local at = x + i * (size + gap)
        if i < level then image(ui, "media/ui/SkillPanel/SkillUnit_Fill.png", at, y, size, size, GOLD)
        elseif i == level and progress and progress > 0 then
            image(ui, "media/ui/SkillPanel/SkillUnit_Fill.png", at, y, size * progress, size, color)
        end
        image(ui, "media/ui/SkillPanel/SkillUnit_Border.png", at, y, size, size, color)
    end
end
local function name(e) return tr(e.name, Manuals.definitions[e.prefix].title) end
local function book(e) return getItemNameFromFullType(e.W.book) end
local function selected(page) return entries[page.selected or 1] end
local function moveTitle(e, id) return tr("UI_" .. e.prefix .. "_Move_" .. id, id) end

local Styles = ISScrollingListBox:derive("PSF_WeaponStyles")

function Styles:doDrawItem(y, item, alt)
    local page, k, e = self.window, self.window.k, item.item
    local learned = e.W.state(page.player).learned
    if e == selected(page) then self:drawRect(1, y, self.width - 2, item.height - 1, .3, .7, .35, .15)
    elseif self.mouseoverselected == item.index and self:isMouseOver() then
        self:drawRect(1, y, self.width - 2, item.height - 1, .1, 1, 1, 1)
    end
    local icon = math.floor(40 * k.u)
    local cover = getTexture(Manuals.definitions[e.prefix].cover)
    if cover then
        self:drawTextureScaledAspect(cover, 10, y + 5, icon, icon, 1, learned and 1 or .4, learned and 1 or .4, learned and 1 or .4)
    end
    local x = 18 + icon
    text(self, fit(MEDIUM, name(e), self.width - x - 20), x, y + 4, learned and WHITE or DIM, MEDIUM)
    local line = y + 4 + k.M
    text(self, getText(learned and (e.W.eligible(page.player) and "UI_SMA_MenuActive" or "UI_SMA_MenuLearned")
        or "UI_SMA_MenuNotLearned"), x, line, learned and GREY or DIM)
    if learned then
        local level, progress = SMA.masteryProgress(page.player, e.W.style)
        local pip = math.floor(8 * k.u)
        units(self, self.width - 10 - (5 * pip + 8), line + math.floor((k.S - pip) / 2), pip, 2, 5, level, progress)
    else
        text(self, fit(SMALL, book(e), self.width - x - 15), x, line + k.S, {.75,.66,.42})
    end
    self:drawRect(1, y + item.height - 1, self.width - 2, 1, .5, .4, .4, .4)
    return y + item.height
end

local Unlocks = ISScrollingListBox:derive("PSF_WeaponUnlocks")

function Unlocks:doDrawItem(y, item, alt)
    if y + self:getYScroll() + item.height < 0 or y + self:getYScroll() >= self.height then return y + item.height end
    local page, k, row = self.window, self.window.k, item.item
    local w = self.width - 2 - (self:isVScrollBarVisible() and self.vscroll:getWidth() or 0)
    local state = row.state
    local color = state == "unlocked" and WHITE or state == "next" and {.85,.85,.85} or DIM
    local ty = y + math.floor((item.height - k.S) / 2)
    if row.kind == "header" then
        self:drawRect(1, y, w, item.height - 1, state == "locked" and .12 or .3, state == "next" and .7 or .4,
            state == "next" and .35 or .4, state == "next" and .15 or .4)
        if state == "next" then self:drawRect(1, y, 3, item.height - 1, 1, .95, .6, .3) end
        local folded = page.collapsed[selected(page).id][row.mastery]
        image(self, "media/ui/inventoryPanes/Button_Tree" .. (folded and "Collapsed" or "Expanded") .. ".png",
            9, y + math.floor((item.height - 15 * k.u) / 2), 15 * k.u, 15 * k.u, color)
        text(self, getText("UI_SMA_Mastery", tostring(row.mastery)), 18 + math.floor(15 * k.u), ty, color)
        right(self, getText(state == "unlocked" and "UI_SMA_MenuUnlocked" or state == "next" and "UI_SMA_MenuNextUnlock"
            or "UI_SMA_MenuLocked"), w - 9, ty, state == "unlocked" and GOLD or state == "next" and ORANGE or DIM)
    else
        local e = selected(page)
        local enabled = row.selectable and e.W.isMoveEnabled(page.player, row.id)
        local marker = state == "unlocked" and (row.selectable and not enabled and "inventoryPanes/Tickbox_Cross.png"
            or "inventoryPanes/Tickbox_Tick.png") or state == "next" and "ArrowRight.png" or "lock.png"
        image(self, "media/ui/" .. marker, 11, y + math.floor((item.height - k.icon) / 2), k.icon, k.icon,
            state == "unlocked" and GOLD or state == "next" and ORANGE or DIM)
        local tag = row.selectable and (state == "unlocked" and tr(enabled and "UI_SWMA_MoveEnabled" or "UI_SWMA_MoveDisabled",
            enabled and "Enabled" or "Disabled") or "") or row.disabled and tr("UI_SWMA_UnavailableShort", "Unavailable")
            or getText("UI_SMA_MenuHits", tostring(#row.move.moves))
        local title = moveTitle(e, row.id)
        if row.selectable and e.W.stationaryMoves and e.W.stationaryMoves[row.id] then
            title = title .. " (" .. tr("UI_SWMA_StationaryOnly", "Standing still") .. ")"
        end
        local tx = 18 + k.icon
        text(self, fit(SMALL, title, w - tx - 15 - width(SMALL, tag)), tx, ty, color)
        if tag ~= "" then right(self, tag, w - 9, ty, DIM) end
    end
    return y + item.height
end

function Unlocks:onMouseDown(x, y)
    if self:isMouseOverScrollBar() then return ISScrollingListBox.onMouseDown(self, x, y) end
    local item = self.items[self:rowAt(x, y)]
    if item then self.window:onUnlockClick(item.item) end
    return true
end

function Unlocks:onJoypadDown(button, joypadData)
    if button == Joypad.AButton then
        local item = self.items[self.selected]
        if item then self.window:onUnlockClick(item.item) end
        return
    end
    ISScrollingListBox.onJoypadDown(self, button, joypadData)
end

local Page = ISPanelJoypad:derive("PSF_WeaponWindow")

-- reference is Senator's Unarmed view, whose metrics and mastery/unlock bars this page shares.
function Page:new(playerNum, reference, w, h)
    local o = ISPanelJoypad.new(self, 0, 0, w, h)
    o.playerNum, o.player, o.reference = playerNum, getSpecificPlayer(playerNum), reference
    o.k = reference.k
    o.backgroundColor = { r = 0, g = 0, b = 0, a = .8 }
    o.selected, o.collapsed, o.followActive = 1, {}, true
    return o
end

function Page:createChildren()
    ISPanelJoypad.createChildren(self)
    self.styleList = Styles:new(10, 10, 280, 100)
    self.styleList:initialise(); self.styleList:instantiate()
    self.styleList.window, self.styleList.drawBorder = self, true
    self.styleList:setOnMouseDownFunction(self, Page.onPickStyle)
    self.styleList:setOnMouseDoubleClick(self, Page.onDoubleClickStyle)
    for _, e in ipairs(entries) do self.styleList:addItem(name(e), e) end
    self:addChild(self.styleList)
    self.unlockList = Unlocks:new(300, 180, 500, 300)
    self.unlockList:initialise(); self.unlockList:instantiate()
    self.unlockList.window, self.unlockList.drawBorder, self.unlockList.joypadParent = self, true, self
    self:addChild(self.unlockList)
    self.useButton = ISButton:new(0, 0, 150, 26, "", self, Page.onUse)
    self.useButton:initialise(); self:addChild(self.useButton)
    self.manualButton = ISButton:new(0, 0, 150, 26, tr("UI_SWMA_ManualButton", "Manual"), self, Page.onManual)
    self.manualButton:initialise(); self:addChild(self.manualButton)
    self.choiceButton = ISButton:new(0, 0, 150, 26, "", self, Page.onChoice)
    self.choiceButton:initialise(); self:addChild(self.choiceButton)
    self.adminButton = ISButton:new(0, 0, 150, 26, getText("UI_SMA_Admin"), self, Page.onAdmin)
    self.adminButton:initialise(); self:addChild(self.adminButton)
    self.manualButton.tooltip = tr("UI_SWMA_PracticeHint", "Practice through Health > Exercise with the weapon equipped.")
end

function Page:onAdmin() Admin.openAdminWindow(self.playerNum) end

-- The learned Forms, when there are two or more to choose between; nil otherwise.
local function choices(page)
    local learned = {}
    for _, e in ipairs(entries) do
        if e.W.state(page.player).learned == true then learned[#learned + 1] = e end
    end
    return #learned > 1 and learned or nil
end

-- Makes the next learned Form active, as Senator's choice button switches spear styles.
function Page:onChoice()
    local p = self.player
    local learned = choices(self)
    if not learned or not p or p:isDead() or p:isAttacking() then return end
    local active = PSF.activeForm(p)
    local index = 0
    for i, e in ipairs(learned) do if e.W == active then index = i; break end end
    local nextForm = learned[index % #learned + 1].W
    if isClient() then sendClientCommand(p, PSF.module, "select", { id = nextForm.id })
    else PSF.select(p, nextForm.id) end
end

function Page:onPickStyle(e)
    for i, v in ipairs(entries) do if e == v then self.selected = i; break end end
    self.followActive = false
    self.signature = nil
end

function Page:onDoubleClickStyle(e) self:onPickStyle(e); self:onUse() end

function Page:onUse()
    local e, p = selected(self), self.player
    if not p or p:isDead() or p:isAttacking() or not e.W.state(p).learned then return end
    local enabled = e.W.state(p).enabled == false
    if isClient() then sendClientCommand(p, e.W.module, "enabled", { enabled = enabled }) else e.W.setEnabled(p, enabled) end
end

function Page:onManual()
    local e = selected(self)
    local item = self.player and self.player:getInventory():getFirstTypeRecurse(e.W.book)
    Manuals.open(self.playerNum, e.prefix, item)
end

function Page:onUnlockClick(row)
    local e, p = selected(self), self.player
    if row.kind == "header" then
        self.collapsed[e.id][row.mastery] = not self.collapsed[e.id][row.mastery] or nil
        self.signature = nil
    elseif row.selectable and row.state == "unlocked" and p and not p:isDead() and not p:isAttacking() then
        local enabled = not e.W.isMoveEnabled(p, row.id)
        if isClient() then sendClientCommand(p, e.W.module, "moveEnabled", { id = row.id, enabled = enabled })
        else e.W.setMoveEnabled(p, row.id, enabled) end
        self.signature = nil
    end
end

function Page:layout()
    local k = self.k
    self.top = k.pad
    self.leftW = math.min(self.reference.leftW, math.floor(self.width * .34))
    self.rightX = k.pad + self.leftW + k.pad; self.rightW = self.width - self.rightX - k.pad
    self.listY = self.top + k.headerH + 8 + k.masteryH + 8 + k.barH + 2
    self.listH = math.max(k.row * 3, self.height - self.listY - 15 - k.S - k.pad)
    local rows = 2
    for i, e in ipairs(entries) do
        self.styleList.items[i].height = e.W.state(self.player).learned and k.learnedRow or k.unlearnedRow
        rows = rows + self.styleList.items[i].height
    end
    rows = math.min(rows, math.max(k.unlearnedRow, self.listY + self.listH - self.top - 8 - k.cardNeed))
    self.styleList:setX(k.pad); self.styleList:setY(self.top); self.styleList:setWidth(self.leftW); self.styleList:setHeight(rows)
    self.styleList.vscroll:setAnchorBottom(false); self.styleList.vscroll:setHeight(rows)
    self.styleList.vscroll:setX(self.leftW - self.styleList.vscroll:getWidth())
    self.unlockList:setX(self.rightX); self.unlockList:setY(self.listY)
    self.unlockList:setWidth(self.rightW); self.unlockList:setHeight(self.listH)
    self.unlockList.vscroll:setAnchorBottom(false); self.unlockList.vscroll:setHeight(self.listH)
    self.unlockList.vscroll:setX(self.rightW - self.unlockList.vscroll:getWidth())
    local bw = math.min(math.floor(150 * k.u), math.floor(self.rightW * .29))
    self.adminButton:setX(self.width - k.pad - bw); self.adminButton:setY(self.listY + self.listH + 12)
    self.adminButton:setWidth(bw); self.adminButton:setHeight(k.S + 6)
    self.adminButton:setVisible(Admin.canAdmin(self.player))
    self.choiceButton:setX(self.adminButton:getX() - 10 - bw - 30); self.choiceButton:setY(self.adminButton.y)
    self.choiceButton:setWidth(bw + 30); self.choiceButton:setHeight(k.S + 6)
    for i, b in ipairs({ self.useButton, self.manualButton }) do
        b:setX(self.rightX + self.rightW - 10 - bw); b:setY(self.top + 10 + (i - 1) * (k.S + 10)); b:setWidth(bw); b:setHeight(k.S + 6)
    end
end

function Page:refresh()
    if self.followActive then
        for i, e in ipairs(entries) do if e.W.canUse(self.player) then self.selected = i; break end end
    end
    local e, p = selected(self), self.player
    self.learned = e.W.state(p).learned
    self.mastery, self.progress = SMA.masteryProgress(p, e.W.style)
    if not self.learned then self.mastery, self.progress = 0, nil end
    self.activeId = e.W.eligible(p) and e.id or nil
    self.selectedId = e.id
    if not self.collapsed[e.id] then
        self.collapsed[e.id] = {}
        for level = 0, self.mastery - 1 do self.collapsed[e.id][level] = true end
    end
    local picks = {}
    for _, id in ipairs((e.W.toggleView(p))) do picks[#picks + 1] = tostring(e.W.isMoveEnabled(p, id)) end
    local active = PSF.activeForm(p)
    local signature = table.concat({ e.id, tostring(self.learned), self.mastery, SMA.getLevel(p), tostring(e.W.state(p).enabled),
        active and active.id or "", self.width, self.height, table.concat(picks, ",") }, "|")
    if self.signature == signature then return end
    self.signature = signature
    local scroll = self.unlockList:getYScroll()
    if self.shownId ~= e.id then scroll = 0 end
    self.shownId = e.id
    self.unlockList:clear(); self.groups = {}
    local order, moves = e.W.toggleView(p)
    local content = 0
    for level = 0, 5 do
        local available = self.learned and self.mastery >= level
        local state = available and "unlocked" or level == (self.learned and self.mastery + 1 or 0) and "next" or "locked"
        local group = { mastery = level, state = state, combos = {}, heavy = {} }
        self.groups[#self.groups + 1] = group
        self.unlockList:addItem("", { kind = "header", mastery = level, state = state }).height = self.k.group
        content = content + self.k.group
        for _, id in ipairs(order) do
            local move = moves[id]
            if move.mastery == level then
                if not move.disabled then group.combos[#group.combos + 1] = { id = id } end
                if not self.collapsed[e.id][level] then
                    local row = { kind = "move", id = id, move = move, state = move.disabled and "locked" or state,
                        disabled = move.disabled, selectable = e.W.isMoveToggleable(self.player, id) }
                    local tip = row.selectable and state == "unlocked"
                        and tr("UI_SWMA_MoveToggleHint", "Click to enable or disable. Keep at least one unlocked move enabled.")
                        or tr("UI_SWMA_WeaponMasteryGate", "Requires weapon mastery %1", tostring(level))
                    self.unlockList:addItem("", row, tip).height = self.k.row; content = content + self.k.row
                end
            end
        end
    end
    self.unlockList.smoothScrollTargetY, self.unlockList.smoothScrollY = nil, nil
    self.unlockList:setYScroll(math.max(-math.max(0, content - self.listH + 2), math.min(0, scroll)))
end

function Page:drawHeader()
    local e, k, p = selected(self), self.k, self.player
    local x, y, w = self.rightX, self.top, self.rightW
    panel(self, x, y, w, k.headerH)
    local icon = math.floor(60 * k.u)
    local cover = getTexture(Manuals.definitions[e.prefix].cover)
    if cover then self:drawTextureScaledAspect(cover, x + 10, y + 6, icon, k.headerH - 12, 1, 1, 1, 1) end
    local tx = x + 22 + icon
    text(self, fit(LARGE, name(e), self.useButton.x - tx - 10), tx, y + 6, WHITE, LARGE)
    local line = y + 6 + k.L + 2
    local color = GREY
    if self.activeId then
        local c = getCore():getGoodHighlitedColor(); color = { c:getR(), c:getG(), c:getB() }
        image(self, "media/ui/inventoryPanes/Tickbox_Tick.png", tx, line + math.floor((k.S - k.icon) / 2), k.icon, k.icon, color)
    end
    local sx = self.activeId and tx + k.icon + 6 or tx
    text(self, fit(SMALL, getText(self.activeId and "UI_SMA_MenuActiveStyle" or self.learned and "UI_SMA_MenuLearned"
        or "UI_SMA_MenuNotLearned"), self.useButton.x - sx - 10), sx, line, color)
    -- A learned Form that isn't the active one points at the choice button instead of the weapon.
    local hint
    if not self.learned then hint = getText("UI_SMA_MenuRead", book(e))
    elseif PSF.activeForm(p) ~= e.W then hint = tr("UI_PSF_ChoiceHint", "Choose this Form with the button below to fight with it.")
    elseif e.W.canUse(p) then hint = tr("UI_SWMA_WeaponReady", "Attacks shuffle without repeats. Release aim to cancel.")
    else hint = tr("UI_" .. e.prefix .. "_EquipStaff", "Equip the required weapons.") end
    text(self, fit(SMALL, hint, w - (tx - x) - 10), tx, line + k.S, DIM)
    local enabled = self.learned and e.W.state(p).enabled ~= false
    self.useButton:setTitle(tr(enabled and "UI_SWMA_DisableShort" or "UI_SWMA_EnableShort", enabled and "Disable" or "Enable"))
    self.useButton:setEnable(self.learned and not p:isDead() and not p:isAttacking())
    self.useButton.tooltip = hint
    local learned = choices(self)
    self.choiceButton:setVisible(learned ~= nil)
    if learned then
        local active = PSF.activeForm(p)
        local current = active and tr("UI_PSF_Form" .. active.number, "Form %1", tostring(active.number)) or ""
        self.choiceButton:setTitle(tr("UI_SWMA_ChoiceButton", "%1: %2", tr("UI_PSF_ChoiceLabel", "Form"), current))
        self.choiceButton.tooltip = tr("UI_PSF_ChoiceTip", "You know more than one Form. Click to choose which one you fight with.")
        self.choiceButton:setEnable(not p:isDead() and not p:isAttacking())
    end
end

function Page:drawCard()
    local e, k, p = selected(self), self.k, self.player
    local x, y, w = k.pad, self.styleList:getBottom() + 8, self.leftW
    panel(self, x, y, w, self.listY + self.listH - y)
    local level = SMA.getLevel(p)
    local perk = PerkFactory.getPerk(Perks[SMA.perkID])
    text(self, perk:getName(), x + 10, y + 6, WHITE, MEDIUM)
    right(self, getText("UI_SMA_Level", tostring(level)), x + w - 10, y + 6 + k.baseline, GOLD)
    local progress
    if level < 10 then
        local xp = p:getXp():getXP(Perks[SMA.perkID]) - ISSkillProgressBar.getPreviousXpLvl(perk, level)
        progress = math.max(0, math.min(1, xp / ISSkillProgressBar.getXpForLvl(perk, level)))
    end
    local uy = y + 6 + k.M + 6
    units(self, x + 10, uy, k.unit, k.unitGap, 10, level, progress)
    if progress then
        text(self, getText("UI_SMA_MenuToLevel", tostring(math.floor(progress * 100)), tostring(level + 1)), x + 10, uy + k.unit + 6, DIM)
    end
    local line = uy + k.unit + 6 + k.S + 16
    self:drawRect(x + 1, line - 8, w - 2, 1, .4, .4, .4, .4)
    local nowX, nextX = x + w - 10 - math.floor(64 * k.u), x + w - 10
    right(self, getText("UI_SMA_MenuNow"), nowX, line, DIM)
    if level < 10 then right(self, getText("UI_SMA_Level", tostring(level + 1)), nextX, line, DIM) end
    local speed = SMA.attackSpeedScale(p, { id = "boxing" }) / SMA.attackSpeedScale(p, { id = "boxing" }, 0) - 1
    local damage = e.W.progression.damageScale(e.W, p) - 1
    local speedNext = SMA.attackSpeedScale(p, { id = "boxing" }, math.min(10, level + 1)) / SMA.attackSpeedScale(p, { id = "boxing" }, 0) - 1
    for i, row in ipairs({ { "UI_SMA_MenuDamage", damage, damage },
        { "UI_SMA_MenuStamina", SMA.strikeEfficiency(level) - 1, SMA.strikeEfficiency(math.min(10, level + 1)) - 1 },
        { "UI_SMA_MenuSpeed", speed, speedNext } }) do
        local ry = line + i * (k.S + 4)
        text(self, getText(row[1]), x + 10, ry, GREY)
        right(self, (row[2] < 0 and "-" or "+") .. tostring(math.abs(math.floor(row[2] * 100 + .5))) .. "%", nowX, ry, GOLD)
        if level < 10 then
            right(self, (row[3] < 0 and "-" or "+") .. tostring(math.abs(math.floor(row[3] * 100 + .5))) .. "%", nextX, ry, DIM)
        end
    end
    text(self, fit(SMALL, tr("UI_SWMA_WeaponBonuses", "Selected weapon bonuses"), w - 20), x + 10, line + 4 * (k.S + 4), DIM)
end

function Page:prerender()
    self:setWidthAndParentWidth(self.width); self:setHeightAndParentHeight(self.height)
    ISPanelJoypad.prerender(self)
    if not self.player or self.player:isDead() then return end
    self:layout(); self:refresh(); self:drawHeader()
    self.reference.drawMastery(self)
    self.reference.drawUnlockBar(self)
    self:drawCard()
    local key = getCore():getKey("SMA_NextStyle")
    local binding = key and key > 0 and getKeyName(key) or "-"
    local footer = getText("UI_SMA_MenuKeyCycle") .. " " .. (binding or "-") .. "   " .. tr("UI_SWMA_WeaponCancel", "Release aim to cancel")
    local y = self.listY + self.listH + 15
    self:drawRect(self.k.pad, y - 7, self.width - 2 * self.k.pad, 1, .35, .4, .4, .4)
    local footerW = self.width - 2 * self.k.pad - (Admin.canAdmin(self.player) and self.adminButton.width + 10 or 0)
        - (self.choiceButton:isVisible() and self.choiceButton.width + 10 or 0)
    text(self, fit(SMALL, footer, footerW), self.k.pad, y, GREY)
end

function Page:onJoypadDirLeft()
    self:onPickStyle(entries[(self.selected - 2) % #entries + 1])
end

function Page:onJoypadDirRight()
    self:onPickStyle(entries[self.selected % #entries + 1])
end

function Page:onJoypadDown(button, joypadData)
    if button == Joypad.AButton then
        if #self.unlockList.items == 0 then return end
        if not self.unlockList.selected or self.unlockList.selected < 1 or self.unlockList.selected > #self.unlockList.items then
            self.unlockList.selected = 1
        end
        setJoypadFocus(self.playerNum, self.unlockList)
        return
    end
    self.reference.onJoypadDown(self, button, joypadData)
end

-- Adds the Photon Sword tab to one of Senator's tab panels, once.
local function attach(tabs, reference, playerNum)
    if not tabs or not reference or tabs.psfPage then return end
    local page = Page:new(playerNum, reference, reference.width, reference.height)
    page:initialise()
    tabs:addView(tr("UI_PSF_Tab", "Photon Sword"), page)
    tabs.psfPage = page
end

-- The character info panel's martial arts view, built by SWMA_Window's createChildren wrapper.
if ISCharacterInfoWindow and ISCharacterInfoWindow.createChildren then
    local createChildren = ISCharacterInfoWindow.createChildren
    function ISCharacterInfoWindow:createChildren()
        createChildren(self)
        attach(self.swmaTabs, self.smaStyleView, self.playerNum)
    end
end

-- The standalone martial arts window, built by SWMA_Window's toggleStyleWindow wrapper.
local toggleStyleWindow = SMA.toggleStyleWindow
function SMA.toggleStyleWindow(playerNum)
    toggleStyleWindow(playerNum)
    local frame = SMA.styleWindows and SMA.styleWindows[playerNum or 0]
    if frame then attach(frame.swmaTabs, frame.smaStyleView, playerNum or 0) end
end

-- SWMA_Window rebuilds the info panel's tabs on resolution changes; its handler runs first.
Events.OnResolutionChange.Add(function()
    for slot = 0, getNumActivePlayers() - 1 do
        local info = getPlayerInfoPanel(slot)
        if info then attach(info.swmaTabs, info.smaStyleView, slot) end
    end
end)

return Page
