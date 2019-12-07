local utf8 = require("utf8")
local utils = require("lib.utils")
local LivingEntity = require("entities.LivingEntity")
local GUI = require("gui.GUI")
local Window = require("gui.Window")
local Text = require("gui.Text")

local Player = class("Player", LivingEntity)

-- STATICS

-- METHODS

function Player:__construct(data)
  LivingEntity.__construct(self, data)

  self.chat_gui = GUI(client, true)
  self.chat_w = Window(true)
  self.chat_text = Text("", 400)
  self.chat_w.content:add(self.chat_text)
  self.chat_gui:add(self.chat_w)
  self.chat_time = 1

  self.pseudo = data.pseudo
  self.pseudo_text = love.graphics.newText(client.font)
  self.pseudo_text:set(self.pseudo)
end

-- overload
function Player:tick(dt)
  LivingEntity.tick(self, dt)

  if self.chat_time > 0 then
    self.chat_time = self.chat_time-dt
  end
end

-- override
function Player:drawUnder()
  -- draw pseudo
  local inv_scale = 1/client.world_scale
  local x = (self.x+8)-self.pseudo_text:getWidth()/2*inv_scale
  local y = self.y+16
  love.graphics.draw(self.pseudo_text, x, y, 0, inv_scale)
end

-- override
function Player:drawOver()
  LivingEntity.drawOver(self)

  -- draw chat GUI
  if self.chat_time > 0 then
    self.chat_gui:update()
    local inv_scale = 1/client.world_scale
    love.graphics.push()
    love.graphics.translate(self.x+8-self.chat_gui.w/2*inv_scale, self.y-self.chat_gui.h*inv_scale-12)
    love.graphics.scale(inv_scale)
    client.gui_renderer:render(self.chat_gui) -- render
    love.graphics.pop()
  end
end

function Player:onMapChat(msg)
  self.chat_time = utils.clamp(utf8.len(msg)/5, 5, 20)
  self.chat_text:set(msg)
end

return Player
