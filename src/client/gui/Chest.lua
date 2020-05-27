local Widget = require("ALGUI.Widget")
local Window = require("gui.Window")
local GridInterface = require("gui.GridInterface")
local Text = require("gui.Text")
local TextInput = require("gui.TextInput")
local Inventory = require("gui.Inventory")
local utils = require("lib.utils")

local Chest = class("Chest", Widget)

-- METHODS

function Chest:__construct()
  Widget.__construct(self)

  -- title
  self.w_title = Window("vertical")
  self.title = Text("title")
  self.w_title.content:add(self.title)
  self:add(self.w_title)

  -- player gold
  self.w_gold_l = Window("vertical")
  self.gold_l = GridInterface(2,2,"vertical")
  self.gold_l:set(0,0,Text("Or:"))
  self.gold_l:set(0,1,Text("Échange:"))
  self.gold_l_display = Text("0")
  self.gold_l:set(1,0, self.gold_l_display)
  self.gold_l_input = TextInput()
  self.gold_l_input:set("0")
  self.gold_l:set(1,1, self.gold_l_input, true)
  self.gold_l.cx, self.gold_l.cy = 1,1
  self.w_gold_l.content:add(self.gold_l)
  self:add(self.w_gold_l)

  -- chest gold
  self.w_gold_r = Window("vertical")
  self.gold_r = GridInterface(2,2,"vertical")
  self.gold_r:set(0,0,Text("Or:"))
  self.gold_r:set(0,1,Text("Échange:"))
  self.gold_r_display = Text("0")
  self.gold_r:set(1,0, self.gold_r_display)
  self.gold_r_input = TextInput()
  self.gold_r_input:set("0")
  self.gold_r:set(1,1, self.gold_r_input, true)
  self.gold_r.cx, self.gold_r.cy = 1,1
  self.w_gold_r.content:add(self.gold_r)
  self:add(self.w_gold_r)

  -- inventory content
  self.content_l = Inventory.Content("item", 2)
  self:add(self.content_l)

  -- chest content
  self.content_r = Inventory.Content("item", 2)
  self:add(self.content_r)

  -- info
  self.w_info = Window("vertical")
  self.info = Text("info")
  self.w_info.content:add(self.info)
  self:add(self.w_info)

  -- info updates
  local function selection_update(content)
    local item = content:getSelection()
    self.info:set(item and Inventory.formatItemDescription("item", item[2]) or "")
  end

  self.content_l:listen("selection-update", selection_update)
  self.content_r:listen("selection-update", selection_update)

  local function control_press(widget, id)
    -- escape chest GUI
    if id == "menu" then
      self:setVisible(false)
      self.gui:setFocus()
      self:trigger("close")
    end
  end

  self.gold_l:listen("control-press", control_press)
  self.gold_r:listen("control-press", control_press)
  self.content_l.grid:listen("control-press", control_press)
  self.content_r.grid:listen("control-press", control_press)

  -- navigation between panels
  self.gold_l:listen("move-select", function(grid, dx, dy)
    if dx == 1 then
      self.gui:setFocus(self.gold_r)
    elseif dy == 1 then
      self.gui:setFocus(self.content_l.grid)
    end
  end)

  self.gold_r:listen("move-select", function(grid, dx, dy)
    if dx == -1 then
      self.gui:setFocus(self.gold_l)
    elseif dy == 1 then
      self.gui:setFocus(self.content_r.grid)
    end
  end)

  self.content_l.grid:listen("move-select", function(grid, dx, dy)
    if dx == 1 and grid.cx == grid.wc-1 then
      self.gui:setFocus(self.content_r.grid)
    elseif dy == -1 and grid.cy == 0 then
      self.gui:setFocus(self.gold_l)
    end
  end)

  self.content_r.grid:listen("move-select", function(grid, dx, dy)
    if dx == -1 and grid.cx == 0 then
      self.gui:setFocus(self.content_l.grid)
    elseif dy == -1 and grid.cy == 0 then
      self.gui:setFocus(self.gold_r)
    end
  end)

  -- gold input handlers
  local function gold_text_input(self, text)
    local widget = self:getSelected()
    widget:trigger("text-input", text)
  end

  local function gold_key_press(self, keycode, scancode, isrepeat)
    local widget = self:getSelected()
    if class.is(widget, TextInput) then widget:trigger("key-press", keycode, scancode, isrepeat) end
  end

  local function gold_control_press(self, id)
    local widget = self:getSelected()
    if class.is(widget, TextInput) then widget:trigger("control-press", id) end
  end

  self.gold_l:listen("focus-change", function(grid, state)
    self.gold_l_input:trigger("focus-change", state)
  end)
  self.gold_l:listen("text-input", gold_text_input)
  self.gold_l:listen("key-press", gold_key_press)
  self.gold_l:listen("control-press", gold_control_press)

  self.gold_r:listen("focus-change", function(grid, state)
    self.gold_r_input:trigger("focus-change", state)
  end)
  self.gold_r:listen("text-input", gold_text_input)
  self.gold_r:listen("key-press", gold_key_press)
  self.gold_r:listen("control-press", gold_control_press)

  -- sanitize gold inputs
  self.gold_l_input:listen("change", function(input)
    local n = utils.clamp(tonumber(input.text) or 0, 0, client.stats.gold)
    input:set(n)
  end)

  self.gold_r_input:listen("change", function(input)
    local n = utils.clamp(tonumber(input.text) or 0, 0, client.stats.chest_gold)
    input:set(n)
  end)

  -- gold transactions
  self.gold_l:listen("control-press", function(grid, id)
    if id == "interact" then
      client:storeGold(tonumber(self.gold_l_input.text) or 0)
    end
  end)

  self.gold_r:listen("control-press", function(grid, id)
    if id == "interact" then
      client:withdrawGold(tonumber(self.gold_r_input.text) or 0)
    end
  end)

  -- item transactions
  self.content_l.grid:listen("cell-select", function()
    local item = self.content_l:getSelection()
    if item then client:storeItem(item[1]) end
  end)

  self.content_r.grid:listen("cell-select", function()
    local item = self.content_r:getSelection()
    if item then client:withdrawItem(item[1]) end
  end)
end

-- override
function Chest:updateLayout(w,h)
  self:setSize(w,h)

  self.w_title:updateLayout(w,h)

  self.w_gold_l:setPosition(0, self.w_title.h)
  self.w_gold_l:updateLayout(w/2,h)
  self.w_gold_r:setPosition(w/2, self.w_title.h)
  self.w_gold_r:updateLayout(w/2,h)

  self.w_info:updateLayout(w,h)
  self.w_info:setPosition(0,h-self.w_info.h)

  local content_y = self.w_gold_l.y+math.max(self.w_gold_l.h, self.w_gold_r.h)
  self.content_l:setPosition(0, content_y)
  self.content_l:updateLayout(w/2, h-content_y-self.w_info.h)
  self.content_r:setPosition(w/2, content_y)
  self.content_r:updateLayout(w/2, h-content_y-self.w_info.h)
end

return Chest
