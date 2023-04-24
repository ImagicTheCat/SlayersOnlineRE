-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

local utf8 = require("utf8")
local utils = require("app.utils")
local LivingEntity = require("app.entities.LivingEntity")
local GUI = require("app.gui.GUI")
local Window = require("app.gui.Window")
local Text = require("app.gui.Text")

local Player = class("Player", LivingEntity)

local ALIGN_COLORS = {
  {0,0,0}, -- 0-20
  {1,0,0}, -- 21-40
  {0.42,0.7,0.98}, -- 41-60
  {0.83,0.80,0.68}, -- 61-80
  {1,1,1} -- 81-100
}

function Player:__construct(data)
  LivingEntity.__construct(self, data)
  -- chat
  self.chat_gui = GUI(client, true)
  self.chat_w = Window("both")
  self.chat_text = Text("", 400)
  self.chat_w.content:add(self.chat_text)
  self.chat_gui:add(self.chat_w)
  -- misc
  self.pseudo = data.pseudo
  self.guild = data.guild
  self.alignment = data.alignment
  self.name_tag = love.graphics.newText(client.font)
  self.visible = true
  self.has_group = data.has_group
  self:updateNameTag()
end

function Player:updateNameTag()
  -- text
  local final = self.pseudo
  if #self.guild > 0 then final = final.."["..self.guild.."]" end
  if self.has_group then final = "{"..final.."}" end
  -- color
  local color = ALIGN_COLORS[math.floor(self.alignment/100*5)+1] or ALIGN_COLORS[5]
  self.name_tag:set({color, final})
end

-- override
function Player:onPacket(action, data)
  LivingEntity.onPacket(self, action, data)

  if action == "ch-visible" then
    self.visible = data
  elseif action == "ch-draw-order" then
    client.map:updateEntityDrawOrder(self, data)
  elseif action == "group-update" then
    self.group_data = data
  elseif action == "group-remove" then
    self.group_data = nil
  elseif action == "group-flag" then
    self.has_group = data
    self:updateNameTag()
  elseif action == "update-alignment" then
    self.alignment = data
    self:updateNameTag()
  end
end

-- override
function Player:drawUnder()
  if self.visible then
    -- draw pseudo
    local inv_scale = 1/client.world_scale
    local x = (self.x+8)-self.name_tag:getWidth()/2*inv_scale
    local y = self.y+16
    love.graphics.setColor(0,0,0, 0.50*(self.afterimage or 1))
    love.graphics.draw(self.name_tag, x+2*inv_scale, y+2*inv_scale, 0, inv_scale) -- shadowing
    love.graphics.setColor(1,1,1, self.afterimage)
    love.graphics.draw(self.name_tag, x, y, 0, inv_scale)
    -- draw health (group)
    if self.group_data and self.id ~= client.id then
      local p = self.group_data.health/self.group_data.max_health
      local quad = client.gui_renderer.system.health_qs[math.floor(p*4)+1] or client.gui_renderer.system.health_qs[4]
      love.graphics.draw(client.gui_renderer.system.tex, quad, --
        (self.x+8)-16, self.y+16+self.name_tag:getHeight()*inv_scale, 0, math.floor(p*32)/16, 3/16)
    end
    love.graphics.setColor(1,1,1)
  end
end

-- override
function Player:draw()
  if self.visible then
    LivingEntity.draw(self)
  end
end

-- override
function Player:drawOver()
  if self.visible then
    LivingEntity.drawOver(self)
    -- draw chat GUI
    if self.chat_timer then
      self.chat_gui:tick()
      local inv_scale = 1/client.world_scale
      love.graphics.push()
      love.graphics.translate(self.x+8-self.chat_gui.w/2*inv_scale, self.y-self.chat_gui.h*inv_scale-12)
      love.graphics.scale(inv_scale)
      client.gui_renderer:render(self.chat_gui) -- render
      love.graphics.pop()
    end
  end
end

function Player:onMapChat(msg)
  if self.chat_timer then self.chat_timer:remove() end
  self.chat_timer = scheduler:timer(utils.clamp(utf8.len(msg)/5, 5, 20), function()
    self.chat_timer = nil
  end)
  self.chat_text:set(msg)
end

return Player
