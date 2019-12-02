
local Window = require("gui.Window")
local Selector = require("gui.Selector")

local Inventory = class("Inventory", Window)

-- PRIVATE STATICS

local COLUMNS = 3

-- PRIVATE METHODS

local function m_all(selector, x, y, selected)
end

-- METHODS

function Inventory:__construct()
  Window.__construct(self)

  self.selector = Selector(1, 1)
  self.items = {}

  self:add(self.selector)
end

-- items: list of item
--- item: table
---- name
---- description
---- amount
function Inventory:setItems(items)
  self.items = items

  local rows = math.ceil(#items/COLUMNS)
  self.selector:init(COLUMNS, rows)

  for i, item in ipairs(items) do
    local cx, cy = (i-1)%COLUMNS, math.floor((i-1)/COLUMNS)
    self.selector:set(cx, cy, "("..item.amount..") "..item.name, m_all)
  end
end

-- override
function Inventory:draw()
  Window.draw(self)

  self.selector:draw()
end

return Inventory
