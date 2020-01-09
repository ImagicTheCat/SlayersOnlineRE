local Widget = require("ALGUI.Widget")
local Window = require("gui.Window")
local GridInterface = require("gui.GridInterface")
local Text = require("gui.Text")
local TextInput = require("gui.TextInput")
local Inventory = require("gui.Inventory")

local Chest = class("Chest", Widget)

-- PRIVATE STATICS

local COLUMNS = 2

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
  self.gold_l:set(0,0,Text("Gold:"))
  self.gold_l:set(0,1,Text("Trade:"))
  self.gold_l:set(1,0,Text("0"))
  self.gold_l:set(1,1,TextInput(), true)
  self.w_gold_l.content:add(self.gold_l)
  self:add(self.w_gold_l)

  -- chest gold
  self.w_gold_r = Window("vertical")
  self.gold_r = GridInterface(2,2,"vertical")
  self.gold_r:set(0,0,Text("Gold:"))
  self.gold_r:set(0,1,Text("Trade:"))
  self.gold_r:set(1,0,Text("0"))
  self.gold_r:set(1,1,TextInput(), true)
  self.w_gold_r.content:add(self.gold_r)
  self:add(self.w_gold_r)

  -- inventory content
  self.content_l = Inventory.Content()
  self:add(self.content_l)

  -- chest content
  self.content_r = Inventory.Content()
  self:add(self.content_r)

  -- info
  self.w_info = Window("vertical")
  self.info = Text("info")
  self.w_info.content:add(self.info)
  self:add(self.w_info)

  -- info updates
  local function selection_update(content)
    local item = content:getSelection()
    self.info:set(item and Inventory.formatItemDescription(item[2]) or "")
  end

  self.content_l:listen("selection-update", selection_update)
  self.content_r:listen("selection-update", selection_update)

  local function control_press(widget, id)
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
end

-- called when closed
function Chest:onClose()
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
