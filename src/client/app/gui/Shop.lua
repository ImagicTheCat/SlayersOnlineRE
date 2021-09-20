local Widget = require("ALGUI.Widget")
local utils = require("app.lib.utils")
local Window = require("app.gui.Window")
local GridInterface = require("app.gui.GridInterface")
local Text = require("app.gui.Text")
local TextInput = require("app.gui.TextInput")
local Inventory = require("app.gui.Inventory")

local Shop = class("Shop", Widget)

-- STATICS

function Shop.formatBuyItem(data)
  local color = {1,1,1}
  if data.req_class and data.req_class ~= client.stats.class then
    color = {0,0,0} -- wrong class
  elseif data.req_level and client.stats.level < data.req_level --
    or data.req_strength and client.stats.strength < data.req_strength --
    or data.req_dexterity and client.stats.dexterity < data.req_dexterity --
    or data.req_constitution and client.stats.constitution < data.req_constitution --
    or data.req_magic and client.stats.magic < data.req_magic then
    color = {1,0,0} -- wrong requirements
  end

  return {"+/- "..(data.amount or 0).." ", color, data.name}
end

function Shop.formatBuyItemInfo(data)
  local desc = Inventory.formatItemDescription("item", data)
  desc = desc.."\n\nPrix: "..utils.fn(data.price).."\nTotal: "..utils.fn(data.price*(data.amount or 0))
  return desc
end

function Shop.formatSellItem(data)
  if data.amount > 0 then
    return Inventory.formatItem("item", data, "")
  else
    return "--"
  end
end

function Shop.formatSellItemInfo(data)
  if data.amount > 0 then
    return Inventory.formatItemDescription("item", data).."\n\nPrix de vente: "..utils.fn(math.ceil(data.price*0.1))
  else
    return ""
  end
end

-- METHODS

function Shop:__construct()
  Widget.__construct(self)

  -- menu
  self.w_menu = Window("vertical")
  self.menu = GridInterface(1,3,"vertical")
  self.menu_title = Text("title")
  self.menu:set(0,0, self.menu_title)
  self.menu:set(0,1, Text("Acheter"), true)
  self.menu:set(0,2, Text("Vendre"), true)
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

  -- escape shop GUI
  local function control_press(widget, id)
    if id == "menu" then
      self:close()
    end
  end

  self.menu:listen("control-press", control_press)
  self.content:listen("control-press", control_press)

  -- mode menu select
  self.menu:listen("cell-select", function(grid, cx, cy)
    if cy == 1 then -- init buy
      self.mode = "buy"
      self.content:init(1, #self.buy_items)
      for i, item in ipairs(self.buy_items) do
        self.content:set(0,i-1, Text(Shop.formatBuyItem(item)), true)
      end
      self.content:moveSelect(0,0) -- actualize
    elseif cy == 2 then -- init sell
      self.mode = "sell"
      self.content:init(1, #self.sell_items)
      for i, item in ipairs(self.sell_items) do
        self.content:set(0,i-1, Text(Shop.formatSellItem(item)), true)
      end
      self.content:moveSelect(0,0) -- actualize
    end

    self.w_menu:setVisible(false)
    self.gui:setFocus(self.content)
  end)

  -- info updates
  self.content:listen("cell-focus", function(grid, cx, cy)
    if self.mode == "buy" then
      local item = self.buy_items[cy+1]
      self.info:set(Shop.formatBuyItemInfo(item).."\nOr: "..utils.fn(client.stats.gold))
    else -- sell
      local item = self.sell_items[cy+1]
      self.info:set(Shop.formatSellItemInfo(item).."\nOr: "..utils.fn(client.stats.gold))
    end
  end)

  self.content:listen("cell-select", function(grid, cx, cy)
    if self.mode == "buy" then
      local item = self.buy_items[cy+1]
      client:buyItem(item.id, item.amount)
    else -- sell
      local item = self.sell_items[cy+1]
      if item.amount > 0 then
        client:sellItem(item.id)
        item.amount = item.amount-1
        self.content:set(0, cy, Text(Shop.formatSellItem(item)), true)
      end
    end

    -- note: info field will be actualized by gold update
  end)
  -- buy amount modulation
  self.content:listen("control-press", function(grid, id)
    if self.mode == "buy" then
      local item = self.buy_items[grid.cy+1]
      -- change amount
      if id == "left" then
        item.amount = (item.amount or 0)-1
      elseif id == "right" then
        item.amount = (item.amount or 0)+1
      end
      -- constrain amount and update infos
      if id == "left" or id == "right" then
        local free_space = client.stats.inventory_size-client.inventory.content.amount
        item.amount = item.amount%(free_space+1)
        self.content:set(0,grid.cy, Text(Shop.formatBuyItem(item)), true)
        self.info:set(Shop.formatBuyItemInfo(item).."\nOr: "..utils.fn(client.stats.gold))
      end
    end
  end)
end

-- open shop (init)
-- buy_items, sell_items: list of {.id, .name, .description, .price}
function Shop:open(title, buy_items, sell_items)
  self.buy_items = buy_items
  self.sell_items = sell_items
  self.menu_title:set(title)
  self.w_menu:setVisible(true)
  self.menu.cy = 1
  self.gui:setFocus(self.menu)
  self.info:set("")
  self.content:init(0,0)
end

function Shop:close()
  self:setVisible(false)
  self.gui:setFocus()
  self:trigger("close")
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
