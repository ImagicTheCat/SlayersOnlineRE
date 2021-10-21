local LivingEntity = require("app.entities.LivingEntity")
local utils = require("app.utils")

local Event = class("Event", LivingEntity)

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

  if data.position_type == "back" then
    self.draw_order = -1
  elseif data.position_type == "front" then
    self.draw_order = 1
  end
end

-- override
function Event:onPacket(action, data)
  LivingEntity.onPacket(self, action, data)

  if action == "teleport" then
    local atype = self.animation_type
    if atype ~= "character-random" and atype ~= "character-follow" then
      -- Prevent erasing anim_x for moving events.
      self.anim_x = self.animation_number
    end
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
    if self.animation_type == "visual-effect" then -- effect
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
