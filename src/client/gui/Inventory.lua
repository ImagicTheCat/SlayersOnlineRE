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
  self.w_grid = Window()
  self.grid = GridInterface(0,0)
  self.w_grid.content:add(self.grid)
  self:add(self.w_grid)

  -- info/menu
  self.w_menu = Window("vertical")
  self.description = Text()
  self.w_menu.content:add(self.description)
  self:add(self.w_menu)

  self.grid:listen("cell_focus", function(grid, cx, cy)
    local item = self.items[cy*COLUMNS+cx+1]
    self.description:set(item and item.description or "")
  end)

  self.items = {}
end

-- override
function Inventory:updateLayout(w,h)
  self:setSize(w,h)

  self.w_menu:updateLayout(w,h)
  self.w_menu:setPosition(0, h-self.w_menu.h)
  self.w_grid:updateLayout(w,h-self.w_menu.h)
end

-- items: list of item
--- item: table
---- name
---- description
---- amount
function Inventory:setItems(items)
  self.items = items

  local rows = math.ceil(#items/COLUMNS)
  self.grid:init(COLUMNS, rows)

  for i, item in ipairs(items) do
    local cx, cy = (i-1)%COLUMNS, math.floor((i-1)/COLUMNS)
    self.grid:set(cx, cy, Text("("..item.amount..") "..item.name), true)
  end
end

return Inventory
