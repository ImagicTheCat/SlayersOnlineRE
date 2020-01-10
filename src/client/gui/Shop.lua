local Widget = require("ALGUI.Widget")
local Window = require("gui.Window")
local GridInterface = require("gui.GridInterface")
local Text = require("gui.Text")
local TextInput = require("gui.TextInput")

local Shop = class("Shop", Widget)

-- STATICS

function Shop.formatItem(item)
  return "+/- "..(item.amount or 0).." "..item.name
end

function Shop.formatItemInfo(item)
  return item.description.."\nPrice: "..item.price.."\nTotal: "..(item.price*(item.amount or 0))
end

-- METHODS

function Shop:__construct()
  Widget.__construct(self)

  -- menu
  self.w_menu = Window("vertical")
  self.menu = GridInterface(1,3,"vertical")
  self.menu_title = Text("title")
  self.menu:set(0,0, self.menu_title)
  self.menu:set(0,1, Text("Buy"), true)
  self.menu:set(0,2, Text("Sell"), true)
  self.w_menu.content:add(self.menu)
  self.w_menu:setZ(1)
  self:add(self.w_menu)

  -- content
  self.w_content = Window()
  self.content = GridInterface(0,0)
  self.w_content.content:add(self.content)
  self:add(self.w_content)

  -- info
  self.w_info = Window("vertical")
  self.info = Text("info")
  self.w_info.content:add(self.info)
  self:add(self.w_info)

  -- escape chest GUI
  local function control_press(widget, id)
    if id == "menu" then
      self:setVisible(false)
      self.gui:setFocus()
      self:trigger("close")
    end
  end

  self.menu:listen("control-press", control_press)
  self.content:listen("control-press", control_press)

  -- menu select
  self.menu:listen("cell-select", function(grid, cx, cy)
    if cy == 1 then
      self.mode = "buy"
      -- build sell items
      self.content:init(1, #self.sell_items)
      for i, item in ipairs(self.sell_items) do
        self.content:set(0,i-1, Text(Shop.formatItem(item, 0)), true)
      end
    elseif cy == 2 then
      self.mode = "sell"
      -- TODO: sell items
    end

    self.w_menu:setVisible(false)
    self.gui:setFocus(self.content)
  end)

  -- info updates
  self.content:listen("cell-focus", function(grid, cx, cy)
    if self.mode == "buy" then
      local item = self.sell_items[cy+1]
      self.info:set(Shop.formatItemInfo(item))
    end
  end)

  -- buy amount modulation
  self.content:listen("control-press", function(grid, id)
    if self.mode == "buy" then
      local item = self.sell_items[grid.cy+1]

      if id == "left" then
        item.amount = math.max(0, (item.amount or 0)-1)
      elseif id == "right" then
        item.amount = (item.amount or 0)+1
      end

      if id == "left" or id == "right" then
        self.content:set(0,grid.cy, Text(Shop.formatItem(item, 0)), true)
        self.info:set(Shop.formatItemInfo(item))
      end
    end
  end)
end

-- open shop (init)
function Shop:open(title, sell_items)
  self.sell_items = sell_items
  self.menu_title:set(title)
  self.w_menu:setVisible(true)
  self.menu.cy = 1
  self.gui:setFocus(self.menu)
  self.info:set("")
  self.content:init(0,0)
end

-- override
function Shop:updateLayout(w,h)
  self:setSize(w,h)

  self.w_menu:updateLayout(math.floor(w*0.5),0)
  self.w_menu:setPosition(math.floor(w/2-self.w_menu.w/2), math.floor(h/2-self.w_menu.h/2))

  self.w_info:updateLayout(w,h)
  self.w_info:setPosition(0, h-self.w_info.h)

  self.w_content:setPosition(0,0)
  self.w_content:updateLayout(w, h-self.w_info.h)
end

return Shop
