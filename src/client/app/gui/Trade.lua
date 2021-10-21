local Widget = require("ALGUI.Widget")
local Window = require("app.gui.Window")
local GridInterface = require("app.gui.GridInterface")
local Text = require("app.gui.Text")
local TextInput = require("app.gui.TextInput")
local Inventory = require("app.gui.Inventory")
local utils = require("app.utils")

local Trade = class("Trade", Widget)

-- METHODS

function Trade:__construct()
  Widget.__construct(self)

  self.content_inv = Inventory.Content("item", 1) -- inventory
  self:add(self.content_inv)
  self.content_l = Inventory.Content("item", 1) -- left trade
  self:add(self.content_l)
  self.content_r = Inventory.Content("item", 1) -- right trade
  self:add(self.content_r)

  self.w_title_l = Window("vertical")
  self.title_l = Text("Left")
  self.w_title_l.content:add(self.title_l)
  self:add(self.w_title_l)

  self.w_title_r = Window("vertical")
  self.title_r = Text("Right")
  self.w_title_r.content:add(self.title_r)
  self:add(self.w_title_r)

  self.w_gold_l = Window("vertical")
  self.gold_l = GridInterface(2,1,"vertical")
  self.gold_l:set(0,0, Text("Or:"))
  self.gold_l_input = TextInput()
  self.gold_l_input:set("0")
  self.gold_l:set(1,0, self.gold_l_input, true)
  self.gold_l.cx = 1
  self.w_gold_l.content:add(self.gold_l)
  self:add(self.w_gold_l)

  self.w_gold_r = Window("vertical")
  self.gold_r = GridInterface(2,1,"vertical")
  self.gold_r:set(0,0, Text("Or:"))
  self.w_gold_r.content:add(self.gold_r)
  self:add(self.w_gold_r)

  self.w_menu = Window("vertical")
  self.menu = GridInterface(2,1,"vertical")
  self.w_menu.content:add(self.menu)
  self:add(self.w_menu)

  -- navigation between panels
  self.content_inv.grid:listen("move-select", function(grid, dx, dy)
    if dx == 1 then self.gui:setFocus(self.content_l.grid) end
  end)
  self.content_l.grid:listen("move-select", function(grid, dx, dy)
    if dx == -1 then self.gui:setFocus(self.content_inv.grid)
    elseif dy == 1 and not grid:isSelectable(grid.cx, grid.cy+1) then self.gui:setFocus(self.gold_l) end
  end)
  self.gold_l:listen("move-select", function(grid, dx, dy)
    if dx == -1 then self.gui:setFocus(self.content_inv.grid)
    elseif dy == -1 then self.gui:setFocus(self.content_l.grid)
    elseif dy == 1 then self.gui:setFocus(self.menu) end
  end)
  self.menu:listen("move-select", function(grid, dx, dy)
    if dx == -1 then self.gui:setFocus(self.content_inv.grid)
    elseif dy == -1 then self.gui:setFocus(self.gold_l) end
  end)

  -- gold input handling
  self.gold_l:listen("focus-change", function(grid, state)
    if not self.locked then self.gold_l_input:trigger("focus-change", state) end
  end)
  self.gold_l:listen("text-input", function(grid, text)
    if self.locked then return end -- cancel
    local widget = grid:getSelected()
    widget:trigger("text-input", text)
  end)
  self.gold_l:listen("key-press", function(grid, keycode, scancode, isrepeat)
    if self.locked then return end -- cancel
    local widget = grid:getSelected()
    if class.is(widget, TextInput) then widget:trigger("key-press", keycode, scancode, isrepeat) end
  end)
  self.gold_l:listen("control-press", function(grid, id)
    if self.locked then return end -- cancel
    local widget = grid:getSelected()
    if class.is(widget, TextInput) then widget:trigger("control-press", id) end
  end)

  -- gold input handling (sanitize)
  self.gold_l_input:listen("change", function(input)
    local n = utils.clamp(tonumber(input.text) or 0, 0, client.stats.gold)
    input:set(n)
    client:setTradeGold(n) -- update trade gold
  end)

  -- item transactions
  self.content_inv.grid:listen("cell-select", function()
    if self.locked then return end -- cancel
    local item = self.content_inv:getSelection()
    if item then client:putTradeItem(item[1]) end
  end)
  self.content_l.grid:listen("cell-select", function()
    if self.locked then return end -- cancel
    local item = self.content_l:getSelection()
    if item then client:takeTradeItem(item[1]) end
  end)

  -- accept/lock trade handling
  self.menu:listen("cell-select", function(grid, cx, cy)
    client:lockTrade()
  end)

  -- close handling
  local function control_press_close(widget, id)
    if id == "menu" then client:closeTrade() end
  end
  self.content_inv.grid:listen("control-press", control_press_close)
  self.content_l.grid:listen("control-press", control_press_close)
  self.menu:listen("control-press", control_press_close)
  self.gold_l:listen("control-press", control_press_close)

  self:updateLock(false)
  self:updatePeerLock(false)
end

function Trade:updateLock(locked)
  self.locked = locked
  self.menu:set(0,0, Text(locked and {{0,1,0.5}, "Accepté"} or {{1,1,1}, "Accepter"}), not locked)
end

function Trade:updatePeerLock(locked)
  self.menu:set(1,0, Text(locked and {{0,1,0.5}, "Accepté"} or "En attente"))
end

-- override
function Trade:updateLayout(w,h)
  self:setSize(w,h)

  local panel_size = math.floor(w/3)
  self.content_inv:setPosition(0,0)
  self.content_inv:updateLayout(panel_size, h)

  self.w_title_l:setPosition(panel_size, 0)
  self.w_title_l:updateLayout(panel_size, 0)
  self.w_title_r:setPosition(panel_size*2, 0)
  self.w_title_r:updateLayout(panel_size, 0)
  local max_w_title_h = math.max(self.w_title_l.h, self.w_title_r.h)

  self.w_menu:updateLayout(panel_size*2, 0)
  self.w_menu:setPosition(panel_size, h-self.w_menu.h)

  self.w_gold_l:updateLayout(panel_size, 0)
  self.w_gold_r:updateLayout(panel_size, 0)
  local max_gold_h = math.max(self.w_gold_l.h, self.w_gold_r.h)
  self.w_gold_l:setPosition(panel_size, h-max_gold_h-self.w_menu.h)
  self.w_gold_r:setPosition(panel_size*2, h-max_gold_h-self.w_menu.h)

  self.content_l:setPosition(panel_size, max_w_title_h)
  self.content_l:updateLayout(panel_size, h-max_w_title_h-max_gold_h-self.w_menu.h)
  self.content_r:setPosition(panel_size*2, max_w_title_h)
  self.content_r:updateLayout(panel_size, h-max_w_title_h-max_gold_h-self.w_menu.h)
end

return Trade
