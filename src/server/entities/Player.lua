local net = require("protocol")
local LivingEntity = require("entities/LivingEntity")

local Player = class("Player", LivingEntity)

-- STATICS

-- METHODS

function Player:__construct()
  LivingEntity.__construct(self)
end

function Player:mapChat(msg)
  if self.map then
    self.map:broadcastPacket(net.MAP_CHAT, {id = self.id, msg = msg})
  end
end

return Player
