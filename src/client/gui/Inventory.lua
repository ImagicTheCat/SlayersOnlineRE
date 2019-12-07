local Window = require("gui.Window")
local GridInterface = require("gui.GridInterface")
local Text = require("gui.Text")

local Inventory = class("Inventory", Window)

-- PRIVATE STATICS

local COLUMNS = 3

-- METHODS

function Inventory:__construct()
  Window.__construct(self)

  self.grid = GridInterface(0,0)
  self.content:add(self.grid)

  self.items = {}
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
