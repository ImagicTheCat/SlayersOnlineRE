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

  self.orientation = 0 -- follow charaset directions (0 top, 1 right, 2 bottom, 3 left)
  self.move_forward = false
  self.speed = 50 -- pixels per seconds
  self.move_time = 0

  self.attack_duration = 1 -- seconds
  self.attacking = false

  self.skin = ""
end

-- overload
function LivingEntity:serializeNet()
  local data = Entity.serializeNet(self)

  data.orientation = self.orientation
  data.skin = self.skin

  return data
end

function LivingEntity:setOrientation(orientation)
  if self.orientation ~= orientation and orientation >= 0 and orientation < 4 then
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
          local nx, ny = self.x+dx*dist, self.y+dy*dist
          local dcx, dcy = nx-self.cx*16, ny-self.cy*16
          if dcx ~= 0 then dcx = dcx/math.abs(dcx) end
          if dcy ~= 0 then dcy = dcy/math.abs(dcy) end

          local collision = (self.map and (not self.map:isCellPassable(self, self.cx+dcx, self.cy) or not self.map:isCellPassable(self, self.cx, self.cy+dcy) or not self.map:isCellPassable(self, self.cx+dcx, self.cy+dcy)))

          if collision then
            if dx ~= 0 then -- x movement
              self:updatePosition(self.cx*16, self.y)
            else -- y movement
              self:updatePosition(self.x, self.cy*16)
            end
          else
            self:updatePosition(nx, ny)
          end

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

function LivingEntity:attack()
  if not self.attacking then
    self.attacking = true
    self:broadcastPacket("attack", self.attack_duration)

    task(self.attack_duration, function()
      self.attacking = false
    end)
  end
end

-- skin: skin filename
function LivingEntity:setSkin(skin)
  self.skin = skin
  self:broadcastPacket("ch_skin", skin)
end

-- continuous movement update (should end with a teleport)
function LivingEntity:updatePosition(x, y)
  self.x = x
  self.y = y
  self:updateCell()

  if self.map then -- reference for next net update
    self.map.living_entity_updates[self] = true
  end
end

-- overload
function LivingEntity:onMapChange()
  self:setMoveForward(false)
end

return LivingEntity
