local LivingEntity = require("entities.LivingEntity")
local utils = require("lib.utils")

local Event = class("Event", LivingEntity)

-- STATICS

Event.Position = {
  DYNAMIC = 0,
  FRONT = 1,
  BACK = 2
}

Event.Animation = {
  STATIC = 0,
  STATIC_CHARACTER = 1,
  CHARACTER_RANDOM = 2,
  VISUAL_EFFECT = 3,
  CHARACTER_FOLLOW = 4
}

-- METHODS

function Event:__construct(data)
  LivingEntity.__construct(self, data)
  self.afterimage_duration = 0

  self.animation_type = data.animation_type

  self.animation_number = data.animation_number or 0
  self.anim_x = self.animation_number

  self.anim_wc = data.animation_wc or 0
  self.anim_hc = data.animation_hc or 0
  self.anim_index = 1
  self.anim_interval = 1/3

  self.active = data.active

  if data.position_type == Event.Position.BACK then
    self.draw_order = -1
  elseif data.position_type == Event.Position.FRONT then
    self.draw_order = 1
  end
end

-- override
function Event:onPacket(action, data)
  LivingEntity.onPacket(self, action, data)

  if action == "teleport" then
    self.anim_x = self.animation_number
  elseif action == "ch_active" then
    self.active = data
  elseif action == "ch_animation_type" then
    self.animation_type = data.animation_type

    self.animation_number = data.animation_number or 0
    self.anim_x = self.animation_number

    self.anim_wc = data.animation_wc or 0
    self.anim_hc = data.animation_hc or 0
  elseif action == "ch_animation_number" then
    self.animation_number = data.animation_number
    self.anim_x = self.animation_number
  end
end

-- override
function Event:tick(dt)
  LivingEntity.tick(self, dt)

  if self.active then
    if self.animation_type == Event.Animation.VISUAL_EFFECT then -- effect
      self.anim_index = math.floor(scheduler.time/self.anim_interval)%(self.anim_wc*self.anim_hc)
      self.anim_x = self.anim_index%self.anim_wc
      self.anim_y = math.floor(self.anim_index/self.anim_wc)
    end
  end
end

-- override
function Event:draw()
  if self.active then
    LivingEntity.draw(self)
  end
end

return Event
