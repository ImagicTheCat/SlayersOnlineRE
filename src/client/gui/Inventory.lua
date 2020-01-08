local Widget = require("ALGUI.Widget")
local Window = require("gui.Window")
local GridInterface = require("gui.GridInterface")
local Text = require("gui.Text")

local Inventory = class("Inventory", Widget)

Inventory.Content = class("Inventory.Content", Window)

-- PRIVATE STATICS

local COLUMNS = 3

-- STATICS

function Inventory.formatItem(item_data)
  return "("..item_data.amount..") "..item_data.name
end

function Inventory.formatItemDescription(item_data)
  return item_data.description
end

-- SUBCLASS

function Inventory.Content:__construct()
  Window.__construct(self)

  self.grid = GridInterface(0,0)
  self.content:add(self.grid)

  self.items = {} -- map of id => item data, synced inventory items
  self.dirty = false

  self.grid:listen("cell-focus", function(grid, cx, cy)
    self:trigger("selection-update")
  end)
end

-- items: list of {id, data}
function Inventory.Content:updateItems(items)
  for _, item in ipairs(items) do
    self.items[item[1]] = item[2]
  end

  self.dirty = true
end

function Inventory.Content:updateContent()
  if self.dirty then
    self.dirty = false

    self.display_items = {}
    for id, data in pairs(self.items) do
      table.insert(self.display_items, {id,data})
    end

    -- sort by name
    table.sort(self.display_items, function(a,b) return a[2].name < b[2].name end)

    local rows = math.ceil(#self.display_items/COLUMNS)
    self.grid:init(COLUMNS, rows)

    for i, item in ipairs(self.display_items) do
      local data = item[2]
      local cx, cy = (i-1)%COLUMNS, math.floor((i-1)/COLUMNS)
      self.grid:set(cx, cy, Text(Inventory.formatItem(data)), true)
    end

    self:trigger("selection-update")
  end
end

-- return selected item as {id, data} or nil
function Inventory.Content:getSelection()
  return self.display_items[COLUMNS*self.grid.cy+self.grid.cx+1]
end

-- METHODS

function Inventory:__construct()
  Widget.__construct(self)

  -- inventory content
  self.content = Inventory.Content()
  self:add(self.content)

  -- info/menu
  self.w_menu = Window("vertical")
  self.description = Text()
  self.menu = GridInterface(3,1,"vertical")
  self.menu:set(0,0, Text("Use"), true)
  self.menu:set(1,0, Text("Equip"), true)
  self.menu:set(2,0, Text("Trash"), true)
  self.w_menu.content:add(self.description)
  self:add(self.w_menu)

  self.content.grid:listen("cell-select", function(grid, cx, cy)
    local item = self.content:getSelection()
    if item then
      -- open item action menu
      self.w_menu.content:add(self.menu)
      self.gui:setFocus(self.menu)
    end
  end)

  self.content:listen("selection-update", function(content)
    local item = content:getSelection()
    self.description:set(item and Inventory.formatItemDescription(item[2]) or "")
  end)

  self.menu:listen("control-press", function(grid, id)
    if id == "menu" then
      -- close item action menu
      self.gui:setFocus(self.content.grid)
      self.w_menu.content:remove(self.menu)
    end
  end)
end

-- override
function Inventory:updateLayout(w,h)
  self:setSize(w,h)

  self.w_menu:updateLayout(w,h)
  self.w_menu:setPosition(0, h-self.w_menu.h)
  self.content:updateLayout(w,h-self.w_menu.h)
end

return Inventory
