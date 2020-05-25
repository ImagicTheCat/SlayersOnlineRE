local TextureAtlas = require("TextureAtlas")
local Entity = require("Entity")
local utils = require("lib.utils")

local LivingEntity = class("LivingEntity", Entity)

-- STATICS

LivingEntity.atlases = {}

-- get cached texture atlas
function LivingEntity.getTextureAtlas(x, y, tw, th, w, h)
  local key = table.concat({x,y,tw,th,w,h}, ",")

  local atlas = LivingEntity.atlases[key]
  if not atlas then
    atlas = TextureAtlas(x,y,tw,th,w,h)
    LivingEntity.atlases[key] = atlas
  end

  return atlas
end

local ANIM_STEP_LENGTH = 11 -- pixel length for a movement step

-- METHODS

function LivingEntity:__construct(data)
  Entity.__construct(self, data)
  self.afterimage_duration = 2

  self.tx = self.x
  self.ty = self.y

  self.anim_move_traveled = 0 -- distance traveled (pixels) for the movement animation
  self.anim_move_index = 1

  self.anim_x = 1
  self.anim_y = data.orientation

  self.acting = false
  self.ghost = data.ghost

  -- default charaset
  self.charaset = {
    path = "charaset.png",
    x = 0, y = 0,
    w = 24, h = 32,
    is_skin = false
  }

  self.texture = client:loadTexture("resources/textures/sets/"..self.charaset.path)
  self.atlas = LivingEntity.getTextureAtlas(self.charaset.x, self.charaset.y,
    self.texture:getWidth(), self.texture:getHeight(),
    self.charaset.w, self.charaset.h)

  self.attack_sound = data.attack_sound
  self.hurt_sound = data.hurt_sound

  if data.charaset then
    self:setCharaset(data.charaset)
  end

  self.hints = {} -- list of {text, time}
  self.animations = {} -- list of animations
end

-- override
function LivingEntity:onPacket(action, data)
  Entity.onPacket(self, action, data)

  if action == "teleport" then
    self.tx = self.x
    self.ty = self.y
    self.move_to_cell = nil
    self.anim_x = 1
    self.anim_move_index = 0
  elseif action == "ch_orientation" then
    self.anim_y = data
  elseif action == "act" then
    self.acting = data[1]
    self.acting_duration = data[2]
    self.acting_time = 0

    if self.acting == "attack" then
      if self.attack_sound then
        self:emitSound(self.attack_sound)
      end
    end
  elseif action == "damage" then
    local amount = data

    -- sound
    if amount and self.hurt_sound then
      self:emitSound(self.hurt_sound)
    end

    -- hint
    local color = (client.id == self.id and {1,0.5,0} or {1,1,1})
    if not amount then
      self:emitHint({color, "Miss"})
    else
      self:emitHint({color, amount..""})
    end
  elseif action == "ch_charaset" then
    self:setCharaset(data)
  elseif action == "ch_sounds" then
    self.attack_sound, self.hurt_sound = data[1], data[2]
  elseif action == "move_to_cell" then
    data.x = self.x
    data.y = self.y
    data.dx = data.cx*16-data.x
    data.dy = data.cy*16-data.y
    data.dist = math.sqrt(data.dx*data.dx+data.dy*data.dy)
    data.duration = data.dist/data.speed
    data.time = 0

    self.move_to_cell = data
  elseif action == "ch_ghost" then
    self.ghost = data
  elseif action == "emit_sound" then
    self:emitSound(data)
  elseif action == "emit_hint" then
    self:emitHint(data)
  elseif action == "emit_animation" then
    self:emitAnimation(data.path, data.x, data.y, data.w, data.h, data.duration, data.alpha)
  end
end

function LivingEntity:setCharaset(charaset)
  self.charaset = charaset

  async(function()
    -- load texture
    local texture

    if charaset.is_skin then -- skin
      texture = client:loadSkin(charaset.path)
    else -- resource
      if client.net_manager:requestResource("textures/sets/"..charaset.path) then
        texture = client:loadTexture("resources/textures/sets/"..charaset.path)
      end
    end

    if texture then
      self.texture = texture
      self.atlas = LivingEntity.getTextureAtlas(charaset.x, charaset.y, texture:getWidth(), texture:getHeight(), charaset.w, charaset.h)
    else
      print("failed to load charaset "..(charaset.is_skin and "skin" or "resource").." \""..charaset.path.."\"")
    end
  end)
end

function LivingEntity:onUpdatePosition(x,y)
  self.tx = x
  self.ty = y
end

function LivingEntity:emitHint(colored_text)
  local text = love.graphics.newText(client.font)
  text:set(colored_text)
  table.insert(self.hints, {text, 2})
end

-- play spatialized sound on self
-- sound: path (will request resource)
function LivingEntity:emitSound(sound)
  async(function()
    if client.net_manager:requestResource("audio/"..sound) then
      local source = client:playSound("resources/audio/"..sound)
      source:setPosition(self.x+8, self.y+8, 0)
      source:setAttenuationDistances(16, 16*15)
      source:setRelative(false)
    else print("failed to load sound \""..sound.."\"") end
  end)
end

-- path: set path (will request resource)
-- x,y: world offset
-- w,h: frame dimensions
-- duration: seconds
-- alpha: (optional) 0-1
function LivingEntity:emitAnimation(path, x, y, w, h, duration, alpha)
  async(function()
    if client.net_manager:requestResource("textures/sets/"..path) then
      local texture = client:loadTexture("resources/textures/sets/"..path)
      local anim = {
        texture = texture,
        atlas = LivingEntity.getTextureAtlas(0, 0, texture:getWidth(), texture:getHeight(), w, h),
        x = x,
        y = y,
        time = 0,
        duration = duration,
        alpha = alpha or 1
      }

      table.insert(self.animations, anim)
    else print("failed to load animation \""..path.."\"") end
  end)
end

-- override
function LivingEntity:tick(dt)
  if self.move_to_cell then -- targeted movement
    local mtc = self.move_to_cell
    mtc.time = mtc.time+dt

    -- compute movement animation
    local progress = mtc.time/mtc.duration
    local steps = math.floor((mtc.dist*progress)/ANIM_STEP_LENGTH)
    self.anim_x = math.abs((steps%4+2)%4-2) -- 0,1,2,3... => 0,1,2,1...
    self.x = utils.lerp(mtc.x, mtc.cx*16, progress)
    self.y = utils.lerp(mtc.y, mtc.cy*16, progress)
    self.tx = self.x
    self.ty = self.y

    if mtc.time >= mtc.duration then
      self.move_to_cell = nil
    end
  elseif self.x ~= self.tx or self.y ~= self.ty then -- free movement
    -- lerp
    local x = math.floor(utils.lerp(self.x, self.tx, 0.5))
    local y = math.floor(utils.lerp(self.y, self.ty, 0.5))

    -- compute movement animation
    local dist = math.abs(x-self.x)+math.abs(y-self.y)
    self.anim_move_traveled = self.anim_move_traveled+dist

    local steps = math.floor(self.anim_move_traveled/ANIM_STEP_LENGTH)
    self.anim_move_traveled = self.anim_move_traveled-ANIM_STEP_LENGTH*steps
    self.anim_move_index = (self.anim_move_index+steps)%4
    self.anim_x = math.abs((self.anim_move_index+2)%4-2) -- 0,1,2,3... => 0,1,2,1...

    -- apply new position
    self.x = x
    self.y = y
  end

  if self.acting then
    -- compute acting animation
    self.acting_time = self.acting_time+dt
    local offset = 0
    if self.acting == "attack" then offset = 3
    elseif self.acting == "cast" then offset = 6
    end

    self.anim_x = offset+math.floor(self.acting_time/self.acting_duration*3)%3
    if self.acting_time >= self.acting_duration then -- stop
      self.acting = false
      self.anim_x = 1
    end
  end

  -- hints
  for i=#self.hints,1,-1 do
    local hint = self.hints[i]
    hint[2] = hint[2]-dt
    if hint[2] <= 0 then
      table.remove(self.hints, i)
    end
  end

  -- animations
  for i=#self.animations,1,-1 do
    local anim = self.animations[i]
    anim.time = anim.time+dt
    if anim.time >= anim.duration then -- remove
      table.remove(self.animations, i)
    end
  end
end

-- override
function LivingEntity:drawOver()
  -- draw hints
  if next(self.hints) then
    local scale = 1/client.world_scale -- world to GUI scale

    for _, hint in ipairs(self.hints) do
      local text, time = hint[1], hint[2]

      local w, h = text:getWidth()*scale, text:getHeight()*scale
      local x, y = self.x+8-w/2, self.y-16*(1-time/2)-h
      love.graphics.setColor(0,0,0,math.min(1,time)*0.50)
      love.graphics.draw(text, x+2*scale, y+2*scale, 0, scale) -- shadowing
      love.graphics.setColor(1,1,1,math.min(1,time))
      love.graphics.draw(text, x, y, 0, scale)
      love.graphics.setColor(1,1,1,1)
    end
  end
end

-- override
function LivingEntity:draw()
  -- character
  if self.texture then
    local quad = self.atlas:getQuad(self.anim_x, self.anim_y)

    if quad then
      if self.ghost then love.graphics.setColor(1,1,1,0.60) end
      if self.afterimage then love.graphics.setColor(1,1,1,self.afterimage) end

      love.graphics.draw(
        self.texture,
        quad,
        self.x-math.floor((self.atlas.cell_w-16)/2),
        self.y+16-self.atlas.cell_h)

      if self.afterimage then love.graphics.setColor(1,1,1) end
      if self.ghost then love.graphics.setColor(1,1,1) end
    end
  end

  -- animations
  for _, anim in ipairs(self.animations) do
    local frame = math.floor(anim.time/anim.duration*anim.atlas.wc*anim.atlas.hc)
    local cx, cy = frame%anim.atlas.wc, math.floor(frame/anim.atlas.wc)
    local quad = anim.atlas:getQuad(cx, cy)
    if quad then
      if anim.alpha < 1 or self.afterimage then love.graphics.setColor(1,1,1,anim.alpha*(self.afterimage or 1)) end
      love.graphics.draw(anim.texture, quad,
        self.x+8-math.floor(anim.atlas.cell_w/2)+anim.x,
        self.y-math.floor(anim.atlas.cell_h/2)+anim.y)

      if anim.alpha < 1 or self.afterimage then love.graphics.setColor(1,1,1) end
    end
  end
end

return LivingEntity
