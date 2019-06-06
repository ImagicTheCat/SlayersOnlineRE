local utf8 = require("utf8")
local utils = require("lib/utils")
local LivingEntity = require("entities/LivingEntity")
local Window = require("gui/Window")

local Player = class("Player", LivingEntity)

-- STATICS

-- METHODS

function Player:__construct(data)
  LivingEntity.__construct(self, data)

  self.chat_window = Window(client)
  self.chat_text = love.graphics.newText(client.font)
  self.chat_time = 0
end

-- overload
function Player:tick(dt)
  LivingEntity.tick(self, dt)

  if self.chat_time > 0 then
    self.chat_time = self.chat_time-dt
  end
end

-- overload
function Player:drawHUD()
  if self.chat_time > 0 then
    local text_factor = client.font_target_height/(client.font:getHeight()*client.world_scale)

    local w, h = self.chat_text:getWidth()*text_factor+8, self.chat_text:getHeight()*text_factor+6
    local x, y = self.x+8-w/2, self.y-16-h
    self.chat_window:update(x,y,w,h)
    self.chat_window:draw()
    love.graphics.draw(self.chat_text, x+4, y+3, 0, text_factor)
  end
end

function Player:onMapChat(msg)
  local text_factor = client.font_target_height/(client.font:getHeight()*client.world_scale)

  self.chat_time = utils.clamp(utf8.len(msg)/5, 5, 20)
  self.chat_text:setf(msg, 150/text_factor, "left")
end

return Player
