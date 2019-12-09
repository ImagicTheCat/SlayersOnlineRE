local Widget = require("ALGUI.Widget")
local Window = require("gui.Window")
local GridInterface = require("gui.GridInterface")
local Text = require("gui.Text")

local Inventory = class("Inventory", Widget)

-- PRIVATE STATICS

local COLUMNS = 3

-- METHODS

function Inventory:__construct()
  Widget.__construct(self)

  -- inventory content
  self.w_content = Window()
  self.content = GridInterface(0,0)
  self.w_content.content:add(self.content)
  self:add(self.w_content)

  -- info/menu
  self.w_menu = Window("vertical")
  self.description = Text()
  self.menu = GridInterface(3,1,"vertical")
  self.menu:set(0,0, Text("Use"), true)
  self.menu:set(1,0, Text("Equip"), true)
  self.menu:set(2,0, Text("Trash"), true)
  self.w_menu.content:add(self.description)
  self:add(self.w_menu)

  self.content:listen("cell-focus", function(grid, cx, cy)
    local item = self.items[cy*COLUMNS+cx+1]
    self.description:set(item and item.description or "")
  end)

  self.content:listen("cell-select", function(grid, cx, cy)
    local item = self.items[cy*COLUMNS+cx+1]
    if item then
      -- open item action menu
      self.w_menu.content:add(self.menu)
      self.gui:setFocus(self.menu)
    end
  end)

  self.menu:listen("control-press", function(grid, id)
    if id == "menu" then
      -- close item action menu
      self.gui:setFocus(self.content)
      self.w_menu.content:remove(self.menu)
    end
  end)

  self.items = {}
end

-- override
function Inventory:updateLayout(w,h)
  self:setSize(w,h)

  self.w_menu:updateLayout(w,h)
  self.w_menu:setPosition(0, h-self.w_menu.h)
  self.w_content:updateLayout(w,h-self.w_menu.h)
end

-- items: list of item
--- item: table
---- id
---- name
---- description
---- amount
function Inventory:setItems(items)
  self.items = items

  local rows = math.ceil(#items/COLUMNS)
  self.content:init(COLUMNS, rows)

  for i, item in ipairs(items) do
    local cx, cy = (i-1)%COLUMNS, math.floor((i-1)/COLUMNS)
    self.content:set(cx, cy, Text("("..item.amount..") "..item.name), true)
  end

  self.description:set(items[1] and items[1].description or "")
end

return Inventory
