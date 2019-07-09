local TextureAtlas = require("TextureAtlas")
local Entity = require("Entity")
local utils = require("lib/utils")

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

  self.anim_x = 0
  self.anim_y = data.orientation

  self.attacking = false

  -- default skin
  self:setCharaset({
    path = "charaset.png",
    x = 0, y = 0,
    w = 24, h = 32,
    is_skin = false
  })

  if data.charaset then
    self:setCharaset(data.charaset)
  end
end

-- overload
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

    async(function()
      client.net_manager:requestResource("audio/Sword3.wav")
      local source = client:playSound("resources/audio/Sword3.wav")
      source:setPosition(self.x, self.y, 0)
      source:setVolume(0.75)
      source:setAttenuationDistances(16, 16*15)
    end)
  elseif action == "ch_charaset" then
    self:setCharaset(data)
  elseif action == "move_to_cell" then
    data.x = self.x
    data.y = self.y
    data.dx = data.cx-data.x/16
    data.dy = data.cy-data.y/16
    data.dist = math.sqrt(data.dx*data.dx+data.dy*data.dy)
    data.duration = data.dist/data.speed
    data.time = 0

    self.move_to_cell = data
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

-- overload
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
end

-- overload
function LivingEntity:draw()
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
