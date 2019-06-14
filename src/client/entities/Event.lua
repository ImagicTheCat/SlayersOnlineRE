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

  self.anim_x = data.animation_number or 0
  self.anim_y = data.orientation or 0

  self.set = client:loadTexture("resources/textures/sets/"..data.set)
  self.atlas = TextureAtlas(data.set_x, data.set_y, self.set:getWidth(), self.set:getHeight(), data.w, data.h)

  if data.position_type == Event.Position.BACK then
    self.draw_order = -1
  elseif data.position_type == Event.Position.BACK then
    self.draw_order = 1
  end
end

-- overload
function Event:onPacket(action, data)
  Entity.onPacket(self, action, data)

  if action == "ch_orientation" then
    self.anim_y = data
  end
end

-- overload
function Event:tick(dt)
end

-- overload
function Event:draw()
  local quad = self.atlas:getQuad(self.anim_x, self.anim_y)

  if quad then
    love.graphics.draw(
      self.set, 
      quad,
      self.x-math.floor((self.atlas.cell_w-16)/2), 
      self.y+16-self.atlas.cell_h)
  end
end

return Event
