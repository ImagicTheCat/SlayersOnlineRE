local Entity = require("Entity")
local utils = require("lib.utils")
local cfg = require("config")
-- deferred
local Client
task(0.01, function()
  Client = require("Client")
end)

local LivingEntity = class("LivingEntity", Entity)

-- STATICS

-- return dx,dy (direction) or nil on invalid orientation (0-3)
function LivingEntity.orientationVector(orientation)
  if orientation == 0 then return 0,-1
  elseif orientation == 1 then return 1,0
  elseif orientation == 2 then return 0,1
  elseif orientation == 3 then return -1,0 end
end

-- return orientation
function LivingEntity.vectorOrientation(dx, dy)
  local g_x = (math.abs(dx) > math.abs(dy))
  dx = dx/math.abs(dx)
  dy = dy/math.abs(dy)

  if dy < 0 and not g_x then return 0
  elseif dx > 0 and g_x then return 1
  elseif dy > 0 and not g_x then return 2
  else return 3 end
end

-- convert game speed to px/s
function LivingEntity.pixelSpeed(speed)
  return speed*4*16
end

-- METHODS

function LivingEntity:__construct()
  Entity.__construct(self)

  self.orientation = 0 -- follow charaset directions (0 top, 1 right, 2 bottom, 3 left)
  self.move_forward = false
  self.speed = 1 -- game speed
  self.move_time = 0
  self.ghost = false

  self.acting = false

  self.health, self.max_health = 100, 100
  self.mana, self.max_mana = 100, 100
  self.ch_attack, self.ch_defense = 0, 0 -- attack/defense characteristics
  self.min_damage, self.max_damage = 0, 0

  -- self.charaset {.path, .x, .y, .w, .h, .is_skin}
  -- self.attack_sound
  -- self.hurt_sound
end

-- override
function LivingEntity:serializeNet()
  local data = Entity.serializeNet(self)

  data.orientation = self.orientation
  data.charaset = self.charaset
  data.attack_sound = self.attack_sound
  data.hurt_sound = self.hurt_sound
  data.ghost = self.ghost

  return data
end

function LivingEntity:setGhost(flag)
  self.ghost = flag
  self:broadcastPacket("ch_ghost", flag)
end

function LivingEntity:setSounds(attack_sound, hurt_sound)
  self.attack_sound = attack_sound
  self.hurt_sound = hurt_sound

  self:broadcastPacket("ch_sounds", {self.attack_sound, self.hurt_sound})
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

      if self.move_task then self.move_task:remove() end

      self.move_task = itask(1/cfg.tickrate, function()
        local dt = clock()-self.move_time

        local speed = LivingEntity.pixelSpeed(self.speed)
        if self.acting then speed = speed/2 end -- slow movement when acting

        -- move following the orientation
        local dx, dy = LivingEntity.orientationVector(self.orientation)
        local dist = math.floor(speed*dt) -- pixels traveled
        if dist > 0 and self.map then
          local nx, ny = self.x+dx*dist, self.y+dy*dist
          local dcx, dcy = nx-self.cx*16, ny-self.cy*16
          if dcx ~= 0 then dcx = dcx/math.abs(dcx) end
          if dcy ~= 0 then dcy = dcy/math.abs(dcy) end

          -- check collision with the 3 cells in the movement direction
          local col_x = dcx ~= 0 and not self.map:isCellPassable(self, self.cx+dcx, self.cy)
          local col_y = dcy ~= 0 and not self.map:isCellPassable(self, self.cx, self.cy+dcy)
          local col_xy = (dcx ~= 0 or dcy ~= 0) and not self.map:isCellPassable(self, self.cx+dcx, self.cy+dcy)
          if col_x or col_y or col_xy then -- collision
            -- stop/snap on current cell for the movement axis / orthogonal movement axis
            --- stop: prevent moving into blocking cells
            --- snap: allow easier movements at the edges of cells
            if dx ~= 0 then -- x movement
              if not col_x then -- snap
                self:updatePosition(self.x, self.cy*16)
              else -- stop
                self:updatePosition(self.cx*16, self.y)
              end
            else -- y movement
              if not col_y then -- snap
                self:updatePosition(self.cx*16, self.y)
              else -- stop
                self:updatePosition(self.x, self.cy*16)
              end
            end
          else
            self:updatePosition(nx, ny)
          end

          self.move_time = self.move_time+dist/speed -- sub traveled time
        end
      end)
    else
      self.move_task:remove()
      self.move_task = nil
      self:teleport(self.x, self.y) -- end movement
    end
  end
end

-- (async)
-- blocking: if passed/true, async and wait until it reaches the destination
function LivingEntity:moveToCell(cx, cy, blocking)
  local r
  if blocking then r = async() end

  -- basic implementation
  local dx, dy = cx-self.x/16, cy-self.y/16
  local speed = LivingEntity.pixelSpeed(self.speed)/16 -- cells per second
  self:setOrientation(LivingEntity.vectorOrientation(dx,dy))
  self:broadcastPacket("move_to_cell", {cx = cx, cy = cy, speed = speed})

  local dist = math.sqrt(dx*dx+dy*dy)
  local duration = dist/speed
  local time = clock()
  local x, y = self.x, self.y

  if self.move_task then self.move_task:remove() end

  self.move_task = itask(1/cfg.tickrate, function()
    local progress = (clock()-time)/duration
    if progress <= 1 then
      self.x = utils.lerp(x, cx*16, progress)
      self.y = utils.lerp(y, cy*16, progress)
      self:updateCell()
    else -- end
      self:teleport(cx*16, cy*16)
      self.move_task:remove()
      self.move_task = nil

      if blocking then
        r()
      end
    end
  end)

  if blocking then r:wait() end
end

-- action: string
--- "attack"
--- "defend"
--- "cast"
--- "use"
function LivingEntity:act(action, duration)
  if not self.acting then
    self.acting = action

    if action == "attack" then
      -- attack check
      local client = (class.is(self, Client) and self or self.client)
      local entities = self:raycastEntities(1)
      for _, entity in ipairs(entities) do
        if class.is(entity, LivingEntity) and (not entity.client or entity.client == client) then
          if entity:onAttack(self) then break end
        end
      end
    end

    -- TODO: defend and cast effects

    -- do animation
    self:broadcastPacket("act", {self.acting, duration})
    task(duration, function() self.acting = false end)
  end
end

function LivingEntity:setHealth(health)
  local old_health = self.health
  self.health = utils.clamp(health, 0, self.max_health)
  if old_health > 0 and self.health == 0 then self:onDeath() end
end

function LivingEntity:setMana(mana)
  self.mana = utils.clamp(mana, 0, self.max_mana)
end

function LivingEntity:onDeath()
end

-- amount: nil for miss event
function LivingEntity:damage(amount)
  self:broadcastPacket("damage", amount)
  if amount then
    self:setHealth(self.health-amount)
  end
end

-- attacker: living entity attacking
-- should return true on hit
function LivingEntity:onAttack(attacker)
end

-- compute attack damages against another living entity
-- target: LivingEntity
-- return damages on hit or nil if missed
function LivingEntity:computeAttack(target)
  if math.random(self.ch_attack) > math.random(target.ch_defense) then
    return math.random(self.min_damage, self.max_damage)
  end
end

-- get all entities in sight (nearest first)
-- dist: ray distance in cells
-- return list of entities
function LivingEntity:raycastEntities(dist)
  local entities = {}

  if self.map then
    local dx, dy = LivingEntity.orientationVector(self.orientation)

    if dx ~= 0 then -- x axis
      local dc = self.y-self.cy*16
      if dc ~= 0 then dc = dc/math.abs(dc) end

      for i=self.cx, self.cx+dist*dx, dx do
        for j=self.cy,self.cy+dc,(dc ~= 0 and dc or 1) do
          local cell = self.map:getCell(i,j)
          if cell then
            for entity in pairs(cell) do
              table.insert(entities, entity)
            end
          end
        end
      end
    else -- y axis
      local dc = self.x-self.cx*16
      if dc ~= 0 then dc = dc/math.abs(dc) end

      for i=self.cy, self.cy+dist*dy, dy do
        for j=self.cx,self.cx+dc,(dc ~= 0 and dc or 1) do
          local cell = self.map:getCell(j,i)
          if cell then
            for entity in pairs(cell) do
              table.insert(entities, entity)
            end
          end
        end
      end
    end
  end

  return entities
end

-- charaset: {.path, .x, .y, .w, .h, .is_skin}
--- x,y: atlas origin
--- w,h: cell dimensions
--- is_skin: if true, use remote skin repository instead of resources
function LivingEntity:setCharaset(charaset)
  self.charaset = charaset
  self:broadcastPacket("ch_charaset", self.charaset)
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

-- override
function LivingEntity:onMapChange()
  self:setMoveForward(false)
end

return LivingEntity
