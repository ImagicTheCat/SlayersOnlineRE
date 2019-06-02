local Entity = require("Entity")
local cfg = require("config")

local LivingEntity = class("LivingEntity", Entity)

-- STATICS

-- return dx,dy (direction)
function LivingEntity.orientationVector(orientation)
  if orientation == 0 then return 0,-1
  elseif orientation == 1 then return 1,0
  elseif orientation == 2 then return 0,1
  elseif orientation == 3 then return -1,0 end
end

-- METHODS

function LivingEntity:__construct()
  Entity.__construct(self)

  self.nettype = "LivingEntity"

  itask(2, function()
    if self.map then
      self:teleport(math.random(0,16*self.map.w), math.random(0,16*self.map.h))
    end
  end)

  self.orientation = 0 -- follow charaset directions (0 top, 1 right, 2 bottom, 3 left)
  self.move_forward = false
  self.speed = math.random(30,50) -- pixels per seconds
  self.move_time = 0
end

function LivingEntity:setOrientation(orientation)
  if self.orientation ~= orientation then
    self.orientation = orientation

    self:broadcastPacket("ch_orientation", orientation)
  end
end

function LivingEntity:setMoveForward(move_forward)
  if self.move_forward ~= move_forward then
    self.move_forward = move_forward

    if self.move_forward then
      self.move_time = clock()

      self.move_task = itask(1/cfg.tickrate, function()
        local dt = clock()-self.move_time

        -- move following the orientation
        local dx, dy = LivingEntity.orientationVector(self.orientation)
        local dist = math.floor(self.speed*dt) -- pixels traveled
        if dist > 0 then
          self:updatePosition(self.x+dx*dist, self.y+dy*dist)
          self.move_time = self.move_time+dist/self.speed -- sub traveled time
        end
      end)
    else
      self.move_task:remove()
      self.move_task = nil
      self:teleport(self.x, self.y) -- end movement
    end
  end
end

-- continuous movement update (should end with a teleport)
function LivingEntity:updatePosition(x, y)
  self.x = x
  self.y = y

  if self.map then -- reference for next net update
    self.map.living_entity_updates[self] = true
  end
end

return LivingEntity
