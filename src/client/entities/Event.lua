local TextureAtlas = require("TextureAtlas")
local Entity = require("Entity")

local Event = class("Event", Entity)

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
  Entity.__construct(self, data)

  self.animation_type = data.animation_type

  self.anim_x = data.animation_number or 0
  self.anim_y = data.orientation or 0

  self.anim_wc = data.animation_wc or 0
  self.anim_hc = data.animation_hc or 0
  self.anim_index = 1
  self.anim_interval = 1/3
  self.anim_time = 0

  self.set = client:loadTexture("resources/textures/sets/"..data.set)
  self.atlas = TextureAtlas(data.set_x, data.set_y, self.set:getWidth(), self.set:getHeight(), data.w, data.h)

  self.active = data.active

  if data.position_type == Event.Position.BACK then
    self.draw_order = -1
  elseif data.position_type == Event.Position.FRONT then
    self.draw_order = 1
  end
end

-- overload
function Event:onPacket(action, data)
  Entity.onPacket(self, action, data)

  if action == "ch_orientation" then
    self.anim_y = data
  elseif action == "ch_set" then
    self.set = client:loadTexture("resources/textures/sets/"..data.set)
    self.atlas = TextureAtlas(data.x, data.y, self.set:getWidth(), self.set:getHeight(), data.w, data.h)
  elseif action == "ch_active" then
    self.active = data
  elseif action == "ch_animation_type" then
    self.animation_type = data.animation_type

    self.anim_x = data.animation_number or 0
    self.anim_y = data.orientation or 0

    self.anim_wc = data.animation_wc or 0
    self.anim_hc = data.animation_hc or 0
  elseif action == "ch_set_dim" then
    self.atlas = TextureAtlas(data.x, data.y, self.set:getWidth(), self.set:getHeight(), data.w, data.h)
  elseif action == "ch_animation_number" then
    self.anim_x = data.animation_number
  end
end

-- overload
function Event:tick(dt)
  if self.active and self.animation_type == Event.Animation.VISUAL_EFFECT then
    self.anim_time = self.anim_time+dt

    local steps = math.floor(self.anim_time/self.anim_interval)
    self.anim_time = self.anim_time-steps*self.anim_interval

    self.anim_index = (self.anim_index+steps)%(self.anim_wc*self.anim_hc)
    self.anim_x = self.anim_index%self.anim_wc
    self.anim_y = math.floor(self.anim_index/self.anim_wc)
  end
end

-- overload
function Event:draw()
  if self.active then
    local quad = self.atlas:getQuad(self.anim_x, self.anim_y)

    if quad then
      love.graphics.draw(
        self.set, 
        quad,
        self.x-math.floor((self.atlas.cell_w-16)/2), 
        self.y+16-self.atlas.cell_h)
    end
  end
end

return Event
