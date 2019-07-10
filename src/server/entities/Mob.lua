local LivingEntity = require("entities/LivingEntity")
local utils = require("lib/utils")

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

-- randomly move the mob
-- (starts a unique loop, will call itself again)
function Mob:moveAI()
  if self.map and not self.move_ai_task then
    self.move_ai_task = task(utils.randf(0.75, 7), function()
      local ok
      local ncx, ncy

      -- search for a passable cell
      local i = 1
      while not ok and i <= 10 do
        local dx, dy = LivingEntity.orientationVector(math.random(0,3))
        ncx, ncy = self.cx+dx, self.cy+dy

        ok = self.map:isCellPassable(self, ncx, ncy)

        i = i+1
      end

      if ok then
        self:moveToCell(ncx, ncy)
      end

      self.move_ai_task = nil

      self:moveAI()
    end)
  end
end

-- overload
function Mob:onMapChange()
  LivingEntity.onMapChange(self)

  if self.map and (self.data.type == Mob.Type.DEFENSIVE or self.data.type == Mob.Type.AGGRESSIVE) then
    self:moveAI()
  end
end

return Mob
