local TextureAtlas = require("TextureAtlas")
local Entity = require("Entity")
local utils = require("lib/utils")

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

  self.attacking = false
  self.anim_step_length = 15 -- pixel length for a movement step

  self.set = client:loadTexture("resources/textures/sets/charaset.png") -- default
  async(function()
    if client.net_manager:requestResource("textures/sets/"..data.set) then
      self.set = client:loadTexture("resources/textures/sets/"..data.set)
      self.atlas = TextureAtlas(data.set_x, data.set_y, self.set:getWidth(), self.set:getHeight(), data.w, data.h)
    end
  end)

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
    async(function()
      if client.net_manager:requestResource("textures/sets/"..data.set) then
        self.set = client:loadTexture("resources/textures/sets/"..data.set)
        self.atlas = TextureAtlas(data.x, data.y, self.set:getWidth(), self.set:getHeight(), data.w, data.h)
      end
    end)
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
  elseif action == "move_to_cell" then
    data.x = self.x
    data.y = self.y
    data.dx = data.cx-data.x/16
    data.dy = data.cy-data.y/16
    data.dist = math.sqrt(data.dx*data.dx+data.dy*data.dy)
    data.duration = data.dist/data.speed
    data.time = 0

    self.move_to_cell = data
  elseif action == "teleport" then
    self.move_to_cell = nil
  end
end

-- overload
function Event:tick(dt)
  if self.active then
    if self.animation_type == Event.Animation.VISUAL_EFFECT then -- effect
      self.anim_time = self.anim_time+dt

      local steps = math.floor(self.anim_time/self.anim_interval)
      self.anim_time = self.anim_time-steps*self.anim_interval

      self.anim_index = (self.anim_index+steps)%(self.anim_wc*self.anim_hc)
      self.anim_x = self.anim_index%self.anim_wc
      self.anim_y = math.floor(self.anim_index/self.anim_wc)
    else
      if self.attacking then
        -- compute attack animation
        self.attack_time = self.attack_time+dt
        self.anim_index = 3+math.floor(self.attack_time/self.attack_duration*3)%3
        if self.attack_time >= self.attack_duration then -- stop
          self.attacking = false
          self.anim_index = 1
        end
      elseif self.move_to_cell then
        local mtc = self.move_to_cell
        mtc.time = mtc.time+dt

        -- compute movement animation
        local progress = mtc.time/mtc.duration
        local steps = math.floor((mtc.dist*progress)/self.anim_step_length)
        self.anim_index = steps%3
        self.x = utils.lerp(mtc.x, mtc.cx*16, progress)
        self.y = utils.lerp(mtc.y, mtc.cy*16, progress)

        if mtc.time >= mtc.duration then
          self.move_to_cell = nil
        end
      end
    end
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
