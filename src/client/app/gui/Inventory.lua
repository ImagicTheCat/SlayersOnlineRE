-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

local Widget = require("ALGUI.Widget")
local Window = require("app.gui.Window")
local GridInterface = require("app.gui.GridInterface")
local Text = require("app.gui.Text")

local Inventory = class("Inventory", Widget)

Inventory.Content = class("Inventory.Content", Window)

function Inventory.formatItem(itype, data, prefix)
  local color = {1,1,1}
  if itype == "item" then
    if data.req_class and data.req_class ~= client.stats.class then
      color = {0,0,0} -- wrong class
    elseif data.req_level and client.stats.level < data.req_level --
      or data.req_strength and client.stats.strength < data.req_strength --
      or data.req_dexterity and client.stats.dexterity < data.req_dexterity --
      or data.req_constitution and client.stats.constitution < data.req_constitution --
      or data.req_magic and client.stats.magic < data.req_magic then
      color = {1,0,0} -- wrong requirements
    end
  end
  return {color, prefix.." ("..data.amount..") "..data.name}
end

function Inventory.formatItemDescription(itype, data)
  local desc = data.description
  if itype == "item" then
    -- requirements
    local reqs = {"\nRequis:"}
    if data.req_level then table.insert(reqs, "Niveau "..data.req_level) end
    if data.req_strength then table.insert(reqs, "Force "..data.req_strength) end
    if data.req_dexterity then table.insert(reqs, "Dextérité "..data.req_dexterity) end
    if data.req_constitution then table.insert(reqs, "Constitution "..data.req_constitution) end
    if data.req_magic then table.insert(reqs, "Magie "..data.req_magic) end
    if #reqs > 1 then desc = desc..table.concat(reqs, " ") end
    if data.req_class then desc = desc.."\n"..data.req_class.." uniquement." end
  end
  return desc
end

-- Inventory.Content

-- move_mode: see GridInterface
function Inventory.Content:__construct(itype, columns, move_mode)
  Window.__construct(self)
  self.columns = columns
  self.grid = GridInterface(0, 0, nil, move_mode)
  self.content:add(self.grid)
  self.itype = itype
  self.items = {} -- map of id => item data, synced inventory items
  self.amount = 0
  self.dirty = false
  self.grid:listen("cell-focus", function(grid, event, cx, cy)
    self:emit("selection-update")
  end)
end

-- items: list of {id, data}
-- clear: (optional) flag, if truthy, will clear the inventory first
function Inventory.Content:updateItems(items, clear)
  self.dirty = true
  if clear then self.items = {} end
  for _, item in ipairs(items) do
    self.items[item[1]] = item[2]
  end
  -- compute total amount
  local amount = 0
  for item, data in pairs(self.items) do
    amount = amount+data.amount
  end
  self.amount = amount
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
    -- update
    local rows = math.ceil(#self.display_items/self.columns)
    local old_cx, old_cy = self.grid.cx, self.grid.cy
    self.grid:init(self.columns, rows)
    for i, item in ipairs(self.display_items) do
      local id = item[1]
      local data = item[2]
      -- quick action prefixes
      local prefix = ""
      if client:isQuickAction(1, self.itype, id) then prefix = prefix.."[Q1]" end
      if client:isQuickAction(2, self.itype, id) then prefix = prefix.."[Q2]" end
      if client:isQuickAction(3, self.itype, id) then prefix = prefix.."[Q3]" end
      -- set
      local cx, cy = (i-1)%self.columns, math.floor((i-1)/self.columns)
      self.grid:set(cx, cy, Text(Inventory.formatItem(self.itype, data, prefix)), true)
    end
    self.grid:setSelect(old_cx, old_cy)
  end
end

-- return selected item as {id, data} or nil
function Inventory.Content:getSelection()
  return self.display_items[self.columns*self.grid.cy+self.grid.cx+1]
end

-- Inventory

-- itype: inventory item type (string)
--- "item"
--- "spell"
function Inventory:__construct(itype)
  Widget.__construct(self)
  -- inventory content
  self.content = Inventory.Content(itype, 3)
  self:add(self.content)
  self.itype = itype
  -- info/menu
  self.w_menu = Window("vertical")
  self.description = Text()
  self.menu = GridInterface(3,1,"vertical")
  if self.itype == "item" then
    self.menu:set(0,0, Text("Utiliser"), true)
    self.menu:set(1,0, Text("Équiper"), true)
    self.menu:set(2,0, Text("Jeter"), true)
  end
  self.w_menu.content:add(self.description)
  self:add(self.w_menu)
  -- events
  self.content.grid:listen("cell-select", function(grid, event, cx, cy)
    local item = self.content:getSelection()
    if item then
      -- open item action menu
      self.w_menu.content:add(self.menu)
      self.gui:setFocus(self.menu)
    end
  end)
  self.content.grid:listen("control-press", function(grid, event, id)
    -- quick action binding
    local item = self.content:getSelection()
    local q_id = tonumber(string.match(id, "quick(%d+)"))
    if item and q_id then
      if client:isQuickAction(q_id, self.itype, item[1]) then -- unbind
        client:bindQuickAction(q_id, self.itype, nil)
      else -- bind
        client:bindQuickAction(q_id, self.itype, item[1])
      end
    end
  end)
  self.content:listen("selection-update", function(content)
    local item = content:getSelection()
    self.description:set(item and Inventory.formatItemDescription(self.itype, item[2]) or "")
    if item and self.itype == "item" then
      self.menu:set(0,0, Text({item[2].usable and {1,1,1} or {0,0,0}, "Utiliser"}), true)
      self.menu:set(1,0, Text({item[2].equipable and {1,1,1} or {0,0,0}, "Équiper"}), true)
      self.menu:set(2,0, Text({item[2].trashable and {1,1,1} or {0,0,0}, "Jeter"}), true)
    end
  end)
  self.menu:listen("control-press", function(grid, event, id)
    if id == "menu" then
      -- close item action menu
      self.gui:setFocus(self.content.grid)
      self.w_menu.content:remove(self.menu)
    end
  end)
  -- actions
  self.menu:listen("cell-select", function(grid, event, cx, cy)
    local item = self.content:getSelection()
    if item then
      if self.itype == "item" then
        if cx == 0 then -- use
          client:useItem(item[1])
        elseif cx == 1 then -- equip
          client:equipItem(item[1])
        elseif cx == 2 then -- trash
          client:trashItem(item[1])
        end
      end
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
