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

  self.pseudo = data.pseudo
end

-- overload
function Player:tick(dt)
  LivingEntity.tick(self, dt)

  if self.chat_time > 0 then
    self.chat_time = self.chat_time-dt
  end
end

-- overload
function Player:drawOver()
  -- chat message
  if self.chat_time > 0 then
    local scale = client.gui_scale
    local world_gui_scale = scale/client.world_scale -- world to GUI scale

    love.graphics.push()
    love.graphics.scale(world_gui_scale)

    local w, h = self.chat_text:getWidth()/scale+8, self.chat_text:getHeight()/scale+8
    local x, y = (self.x+8)/world_gui_scale-w/2, (self.y-12)/world_gui_scale-h
    self.chat_window:update(x,y,w,h)
    self.chat_window:draw()
    love.graphics.draw(self.chat_text, x+3, y+3, 0, 1/scale)

    love.graphics.pop()
  end
end

function Player:onMapChat(msg)
  self.chat_time = utils.clamp(utf8.len(msg)/5, 5, 20)
  self.chat_text:setf(msg, 150*client.gui_scale, "left")
end

return Player
