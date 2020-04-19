local TextureAtlas = require("TextureAtlas")
local Entity = require("Entity")
local utils = require("lib.utils")

local LivingEntity = class("LivingEntity", Entity)

-- STATICS

LivingEntity.atlases = {}

function LivingEntity.getTextureAtlas(x, y, tw, th, w, h)
  local key = table.concat({x,y,tw,th,w,h}, ",")

  local atlas = LivingEntity.atlases[key]
  if not atlas then
    atlas = TextureAtlas(x,y,tw,th,w,h)
    LivingEntity.atlases[key] = atlas
  end

  return atlas
end

-- METHODS

function LivingEntity:__construct(data)
  Entity.__construct(self, data)

  self.tx = self.x
  self.ty = self.y

  self.anim_traveled = 0 -- distance traveled (pixels) for the movement animation
  self.anim_step_length = 15 -- pixel length for a movement step

  self.anim_x = 1
  self.anim_y = data.orientation

  self.attacking = false
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
end

-- override
function LivingEntity:onPacket(action, data)
  Entity.onPacket(self, action, data)

  if action == "teleport" then
    self.tx = self.x
    self.ty = self.y
    self.move_to_cell = nil
    self.anim_x = 1
  elseif action == "ch_orientation" then
    self.anim_y = data
  elseif action == "attack" then
    self.attacking = true
    self.attack_duration = data
    self.attack_time = 0

    if self.attack_sound then
      async(function()
        if client.net_manager:requestResource("audio/"..self.attack_sound) then
          local source = client:playSound("resources/audio/"..self.attack_sound)
          source:setPosition(self.x, self.y, 0)
          source:setVolume(0.75)
          source:setAttenuationDistances(16, 16*15)
        end
      end)
    end
  elseif action == "damage" then
    local amount = data

    -- sound
    if amount and self.hurt_sound then
      async(function()
        if client.net_manager:requestResource("audio/"..self.hurt_sound) then
          local source = client:playSound("resources/audio/"..self.hurt_sound)
          source:setPosition(self.x, self.y, 0)
          source:setVolume(0.75)
          source:setAttenuationDistances(16, 16*15)
        end
      end)
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
    data.dx = data.cx-data.x/16
    data.dy = data.cy-data.y/16
    data.dist = math.sqrt(data.dx*data.dx+data.dy*data.dy)
    data.duration = data.dist/data.speed
    data.time = 0

    self.move_to_cell = data
  elseif action == "ch_ghost" then
    self.ghost = data
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

-- override
function LivingEntity:tick(dt)
  if self.move_to_cell then
    local mtc = self.move_to_cell
    mtc.time = mtc.time+dt

    -- compute movement animation
    local progress = mtc.time/mtc.duration
    local steps = math.floor((mtc.dist*progress)/self.anim_step_length)
    self.anim_x = steps%3
    self.x = utils.lerp(mtc.x, mtc.cx*16, progress)
    self.y = utils.lerp(mtc.y, mtc.cy*16, progress)

    if mtc.time >= mtc.duration then
      self.move_to_cell = nil
    end
  else
    -- lerp
    local x = math.floor(utils.lerp(self.x, self.tx, 0.5))
    local y = math.floor(utils.lerp(self.y, self.ty, 0.5))

    -- compute movement animation
    local dist = math.abs(x-self.x)+math.abs(y-self.y)
    self.anim_traveled = self.anim_traveled+dist

    local steps = math.floor(self.anim_traveled/self.anim_step_length)
    self.anim_traveled = self.anim_traveled-self.anim_step_length*steps
    self.anim_x = (self.anim_x+steps)%3

    -- apply new position
    self.x = x
    self.y = y
  end

  if self.attacking then
    -- compute attack animation
    self.attack_time = self.attack_time+dt
    self.anim_x = 3+math.floor(self.attack_time/self.attack_duration*3)%3
    if self.attack_time >= self.attack_duration then -- stop
      self.attacking = false
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
      love.graphics.setColor(1,1,1,math.min(1,time))
      love.graphics.draw(text, x, y, 0, scale)
      love.graphics.setColor(1,1,1,1)
    end
  end
end

-- override
function LivingEntity:draw()
  if self.texture then
    local quad = self.atlas:getQuad(self.anim_x, self.anim_y)

    if quad then
      if self.ghost then love.graphics.setColor(1,1,1,0.60) end

      love.graphics.draw(
        self.texture,
        quad,
        self.x-math.floor((self.atlas.cell_w-16)/2),
        self.y+16-self.atlas.cell_h)

      if self.ghost then love.graphics.setColor(1,1,1) end
    end
  end
end

-- override
function LivingEntity:drawAfterimage()
  if self.texture then
    local quad = self.atlas:getQuad(self.anim_x, self.anim_y)
    if quad then
      love.graphics.draw(
        self.texture,
        quad,
        self.x-math.floor((self.atlas.cell_w-16)/2),
        self.y+16-self.atlas.cell_h)
    end
  end
end

return LivingEntity
