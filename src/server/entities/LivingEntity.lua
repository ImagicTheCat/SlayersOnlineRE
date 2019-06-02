local Entity = require("Entity")

local LivingEntity = class("LivingEntity", Entity)

function LivingEntity:__construct()
  Entity.__construct(self)

  itask(2, function()
    if self.map then
      self:teleport(math.random(0,16*self.map.w), math.random(0,16*self.map.h))
    end
  end)
end

function LivingEntity:setOrientation(orientation)
end

function LivingEntity:setMoveForward(move_forward)
end

return LivingEntity
