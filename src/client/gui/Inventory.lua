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
    local item = self.display_items[cy*COLUMNS+cx+1]
    self.description:set(item and item[2].description or "")
  end)

  self.content:listen("cell-select", function(grid, cx, cy)
    local item = self.display_items[cy*COLUMNS+cx+1]
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

  self.items = {} -- map of id => item data, synced inventory items
  self.dirty = false
end

-- items: list of {id, data}
function Inventory:updateItems(items)
  for _, item in ipairs(items) do
    self.items[item[1]] = item[2]
  end

  self.dirty = true
  if self.visible then self:updateContent() end
end

function Inventory:updateContent()
  self.dirty = false

  self.display_items = {}
  for id, data in pairs(self.items) do
    table.insert(self.display_items, {id,data})
  end

  -- sort by name
  table.sort(self.display_items, function(a,b) return a[2].name < b[2].name end)

  local rows = math.ceil(#self.display_items/COLUMNS)
  self.content:init(COLUMNS, rows)

  for i, item in ipairs(self.display_items) do
    local data = item[2]
    local cx, cy = (i-1)%COLUMNS, math.floor((i-1)/COLUMNS)
    self.content:set(cx, cy, Text("("..data.amount..") "..data.name), true)
  end

  self.description:set(self.display_items[1] and self.display_items[1].description or "")
end

-- override
function Inventory:updateLayout(w,h)
  self:setSize(w,h)

  self.w_menu:updateLayout(w,h)
  self.w_menu:setPosition(0, h-self.w_menu.h)
  self.w_content:updateLayout(w,h-self.w_menu.h)
end

return Inventory
