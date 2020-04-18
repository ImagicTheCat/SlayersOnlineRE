local LivingEntity = require("entities.LivingEntity")
local utils = require("lib.utils")
-- deferred
local Player
task(0.01, function()
  Player = require("entities.Player")
end)

local Mob = class("Mob", LivingEntity)

-- STATICS

Mob.Type = {
  DEFENSIVE = 0,
  AGGRESSIVE = 1,
  STATIC = 2,
  BREAKABLE = 3
}

-- METHODS

-- data: mob data
-- area: (optional) bound mob area
function Mob:__construct(data, area)
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
  self.max_health = data.health
  self.health = self.max_health
  self.ch_attack = data.attack
  self.ch_defense = data.defense
  self.min_damage = data.damage
  self.max_damage = data.damage

  self.area = area

  -- remove Sound\ parts
  self:setSounds(string.sub(data.attack_sound, 7), string.sub(data.hurt_sound, 7))

  -- self.target -- player aggro
end

-- randomly move the mob
-- (starts a unique loop, will call itself again)
function Mob:moveAI()
  if not self.move_ai_task then
    if self.target and self.target.ghost then self.target = nil end -- lose target if ghost

    local aggro = (self.target and self.target.map == self.map)
    self.move_ai_task = task(utils.randf(0.75, (aggro and 1.5 or 7)), function()
      if self.map then
        if aggro then -- aggro
          local dcx, dcy = self.target.cx-self.cx, self.target.cy-self.cy
          if math.abs(dcx)+math.abs(dcy) > 1 then -- too far, move to target
            local orientation = LivingEntity.vectorOrientation(dcx, dcy)
            local dx, dy = LivingEntity.orientationVector(orientation)
            local ncx, ncy = self.cx+dx, self.cy+dy

            if self:isCellPassable(ncx, ncy) then
              self:moveToCell(ncx, ncy)
            end
          else -- try attack
            self:setOrientation(LivingEntity.vectorOrientation(self.target.x-self.x, self.target.y-self.y))
            self:attack()
          end
        else -- random movement
          local ok
          local ncx, ncy

          -- search for a passable cell
          local i = 1
          while not ok and i <= 10 do
            local orientation = math.random(0,3)

            local dx, dy = LivingEntity.orientationVector(orientation)
            ncx, ncy = self.cx+dx, self.cy+dy

            ok = self:isCellPassable(ncx, ncy)

            i = i+1
          end

          if ok then
            self:moveToCell(ncx, ncy)
          end
        end

        self.move_ai_task = nil

        self:moveAI()
      end
    end)
  end
end

function Mob:isCellPassable(cx,cy)
  if self.map and self.map:isCellPassable(self, cx, cy) then
    -- prevent mob stacking
    local cell = self.map:getCell(cx,cy)
    for entity in pairs(cell or {}) do
      if class.is(entity, Mob) then return false end
    end

    return true
  else
    return false
  end
end

-- override
function Mob:onAttack(attacker)
  if class.is(attacker, Player) then
    self.target = attacker
    self:damage(attacker:computeAttack(self)) -- test
    return true
  end
end

-- override
function Mob:onDeath()
  self.map:removeEntity(self)
  if self.area then self.area.mob_count = self.area.mob_count-1 end
end

-- override
function Mob:onMapChange()
  LivingEntity.onMapChange(self)

  if self.map and (self.data.type == Mob.Type.DEFENSIVE or self.data.type == Mob.Type.AGGRESSIVE) then
    self:moveAI()
  end
end

return Mob
