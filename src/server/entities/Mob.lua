local LivingEntity = require("entities/LivingEntity")
local utils = require("lib/utils")
local Player = require("entities/Player")

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

  -- self.target -- player aggro
end

-- randomly move the mob
-- (starts a unique loop, will call itself again)
function Mob:moveAI()
  if not self.move_ai_task then
    local aggro = (self.target and self.target.map == self.map)

    self.move_ai_task = task(utils.randf(0.75, (aggro and 1.5 or 7)), function()
      if self.map then
        local ok
        local ncx, ncy

        -- search for a passable cell
        local i = 1
        while not ok and i <= 10 do
          local orientation
          if aggro then
            orientation = LivingEntity.vectorOrientation(self.target.x-self.x, self.target.y-self.y)
          else
            orientation = math.random(0,3)
          end

          local dx, dy = LivingEntity.orientationVector(orientation)
          ncx, ncy = self.cx+dx, self.cy+dy

          ok = self.map:isCellPassable(self, ncx, ncy)

          i = i+1
        end

        if ok then
          self:moveToCell(ncx, ncy)
        end

        self.move_ai_task = nil

        self:moveAI()
      end
    end)
  end
end

-- overload
function Mob:onAttack(attacker)
  if class.is(attacker, Player) then
    self.target = attacker
    return true
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
