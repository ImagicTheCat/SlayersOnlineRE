local LivingEntity = require("entities/LivingEntity")

local Mob = class("Mob", LivingEntity)

-- STATICS

Mob.Type = {
  DEFENSIVE = 0,
  AGGRESSIVE = 1,
  STATIC = 2,
  BREAKABLE = 3
}

-- METHODS

function Mob:__construct(data)
  LivingEntity.__construct(self)

  self.nettype = "Mob"
  self.data = data

  self:setOrientation(2)

  self:setCharaset({
    path = string.sub(data.charaset, 9), -- remove Chipset\ part
    x = 0, y = 0,
    w = data.w,
    h = data.h,
    is_skin = false
  })

  self.speed = data.speed
  self.obstacle = data.obstacle
end

return Mob
