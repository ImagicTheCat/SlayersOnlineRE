local LivingEntity = require("entities/LivingEntity")

local Player = class("Player", LivingEntity)

-- STATICS

-- METHODS

function Player:__construct(data)
  LivingEntity.__construct(self, data)
end

-- overload
function Player:draw()
  LivingEntity.draw(self)
end

function Player:onMapChat(msg)
end

return Player
