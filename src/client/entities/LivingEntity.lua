local Entity = require("Entity")

local LivingEntity = class("LivingEntity", Entity)

function LivingEntity.lerp(a, b, x)
  return a*(1-x)+b*x
end

function LivingEntity:__construct(data)
  Entity.__construct(self, data)

  self.orientation = 0
  self.tx = self.x
  self.ty = self.y
end

-- overload
function LivingEntity:onPacket(action, data)
  Entity.onPacket(self, action, data)

  if action == "teleport" then
    self.tx = self.x
    self.ty = self.y
  elseif action == "ch_orientation" then
    self.orientation = data
  end
end

function LivingEntity:onUpdatePosition(x,y)
  self.tx = x
  self.ty = y
end

function LivingEntity:tick(dt)
  -- lerp
  self.x = math.floor(LivingEntity.lerp(self.x, self.tx, 0.5))
  self.y = math.floor(LivingEntity.lerp(self.y, self.ty, 0.5))
end

return LivingEntity
