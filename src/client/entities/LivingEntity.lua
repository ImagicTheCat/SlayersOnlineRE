local TextureAtlas = require("TextureAtlas")
local Entity = require("Entity")

local LivingEntity = class("LivingEntity", Entity)

-- STATICS

function LivingEntity.lerp(a, b, x)
  return a*(1-x)+b*x
end

LivingEntity.charaset_atlas = TextureAtlas(9*24, 32*4, 24, 32)

-- METHODS

function LivingEntity:__construct(data)
  Entity.__construct(self, data)

  self.orientation = 0
  self.tx = self.x
  self.ty = self.y

  self.anim_traveled = 0 -- distance traveled (pixels) for the movement animation
  self.anim_index = 0 -- movement animation frame index
  self.anim_step_length = 15 -- pixel length for a movement step

  self.charaset = love.graphics.newImage("resources/textures/sets/charaset.png")
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

-- overload
function LivingEntity:tick(dt)
  -- lerp
  local x = math.floor(LivingEntity.lerp(self.x, self.tx, 0.5))
  local y = math.floor(LivingEntity.lerp(self.y, self.ty, 0.5))

  -- compute movement animation
  local dist = math.abs(x-self.x)+math.abs(y-self.y)
  self.anim_traveled = self.anim_traveled+dist

  local steps = math.floor(self.anim_traveled/self.anim_step_length)
  self.anim_traveled = self.anim_traveled-self.anim_step_length*steps
  self.anim_index = (self.anim_index+steps)%3

  -- apply new position
  self.x = x
  self.y = y
end

-- overload
function LivingEntity:draw()
  love.graphics.draw(self.charaset, LivingEntity.charaset_atlas:getQuad(self.anim_index,self.orientation), self.x, self.y)
end

return LivingEntity
