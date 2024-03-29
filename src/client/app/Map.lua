-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

local entities = require("app.entities.entities")
local LivingEntity = require("app.entities.LivingEntity")
local TextureAtlas = require("app.TextureAtlas")

local Map = class("Map")

local function sort_entities_back(a, b)
  return a.top < b.top or (a.top == b.top and a.id < b.id)
end
local function sort_entities(a, b)
  return a.y < b.y or (a.y == b.y and a.id < b.id)
end

-- METHODS

function Map:__construct(data)
  self.tileset = client:loadTexture("resources/textures/sets/tileset.png") -- default
  self:build(data)
  -- load map resources
  asyncR(function()
    if client.rsc_manager:requestResource("textures/sets/"..data.tileset) then
      local tileset = client:loadTexture("resources/textures/sets/"..data.tileset, "non-fatal")
      if tileset then self.tileset = tileset end
      self:build(data)
    else warn("failed to load map tileset \""..data.tileset.."\"") end
    if #data.background > 0 then
      if client.rsc_manager:requestResource("textures/sets/"..data.background) then
        self.background = client:loadTexture("resources/textures/sets/"..data.background, "non-fatal")
      else warn("failed to load map background \""..data.background.."\"") end
    end
    if data.music then
      if client.rsc_manager:requestResource("audio/"..data.music) then
        client:playMusic("resources/audio/"..data.music)
      else warn("failed to load map music \""..data.music.."\"") end
    end
  end)
  -- request preload resources
  for path in pairs(data.preload_resources) do
    asyncR(function() client.rsc_manager:requestResource(path) end)
  end
  self.data = data
  self.packet_index = data.packet_index
  -- build entities
  self.entities = {} -- map of id => entity
  -- lists of entities
  self.back_draw_list = {}
  self.dynamic_draw_list = {}
  self.front_draw_list = {}
  self.afterimages = {} -- map of entity => time
  self.animations = {} -- list of animations
  -- create/spawn
  for _, edata in pairs(data.entities) do
    self:createEntity(edata)
  end
end

function Map:build(data)
  local atlas = TextureAtlas(0, 0, self.tileset:getWidth(), self.tileset:getHeight(), 16, 16)

  -- build low / high layer sprite batches

  self.low_layer = love.graphics.newSpriteBatch(self.tileset, data.w*data.h, "static")
  self.high_layer = love.graphics.newSpriteBatch(self.tileset, data.w*data.h, "static")

  self.tileset_wc = self.tileset:getWidth()/16
  self.tileset_hc = self.tileset:getHeight()/16

  local tiledata = data.tiledata
  if tiledata then
    for x=0,data.w-1 do
      for y=0,data.h-1 do
        local index = (x*data.h+y)*4+1

        local xl, xh, yl, yh = tiledata[index] or 0, tiledata[index+1] or 0, tiledata[index+2] or 0, tiledata[index+3] or 0

        -- (0 is empty tileset cell)
        local low_quad = atlas:getQuad(xl-1,yl-1)
        local high_quad = atlas:getQuad(xh-1,yh-1)

        if low_quad then
          self.low_layer:add(low_quad, x*16, y*16)
        end

        if high_quad then
          self.high_layer:add(high_quad, x*16, y*16)
        end
      end
    end
  end
end

function Map:onMovementsPacket(data)
  -- check same map and valid packet
  if data.mi == self.data.map_index and data.pi > self.packet_index then
    self.packet_index = data.pi

    -- updates
    for _, entry in ipairs(data.entities) do
      local id, x, y = unpack(entry)
      local entity = self.entities[id]
      if entity and xtype.is(entity, LivingEntity) then
        entity:onUpdatePosition(x,y)
      end
    end
  end
end

-- path: set path (will request resource)
-- x,y: position
-- w,h: frame dimensions
-- duration: seconds
-- alpha: (optional) 0-1
function Map:playAnimation(path, x, y, w, h, duration, alpha)
  asyncR(function()
    if client.rsc_manager:requestResource("textures/sets/"..path) then
      local texture = client:loadTexture("resources/textures/sets/"..path, "non-fatal")
      if texture then
        local anim = {
          texture = texture,
          atlas = client:getTextureAtlas(0, 0, texture:getWidth(), texture:getHeight(), w, h),
          x = x, y = y, time = 0, duration = duration,
          alpha = alpha or 1
        }
        table.insert(self.animations, anim)
      end
    else warn("failed to load animation \""..path.."\"") end
  end)
end

-- path: sound path
-- x,y: pixel position
function Map:playSound(path, x, y)
  asyncR(function()
    if client.rsc_manager:requestResource("audio/"..path) then
      local source = client:playSound("resources/audio/"..path)
      if source then
        source:setPosition(x, y, 0)
        source:setAttenuationDistances(16, 16*15)
        source:setRelative(false)
      end
    else warn("failed to load path \""..path.."\"") end
  end)
end

function Map:tick(dt)
  -- entities tick
  for id, entity in pairs(self.entities) do
    entity:tick(dt)
  end
  -- afterimages tick
  for entity, time in pairs(self.afterimages) do
    entity:tick(dt)

    local ntime = time-dt
    if ntime >= 0 then
      self.afterimages[entity] = ntime
      entity.afterimage = ntime/entity.afterimage_duration
    else -- remove
      self.afterimages[entity] = nil
      entity.afterimage = nil

      -- remove from draw list
      local draw_list
      if entity.draw_order < 0 then
        draw_list = self.back_draw_list
      elseif entity.draw_order > 0 then
        draw_list = self.front_draw_list
      else
        draw_list = self.dynamic_draw_list
      end

      for i, f_entity in ipairs(draw_list) do
        if entity == f_entity then
          table.remove(draw_list, i)
          break
        end
      end
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
  -- sort entities by Y-top position (top-down sorting)
  table.sort(self.back_draw_list, sort_entities_back)
  table.sort(self.dynamic_draw_list, sort_entities)
  table.sort(self.front_draw_list, sort_entities)
end

function Map:draw()
  love.graphics.draw(self.low_layer)
  love.graphics.draw(self.high_layer)

  -- under
  --- back entities
  for _, entity in ipairs(self.back_draw_list) do
    entity:drawUnder()
  end
  --- dynamic entities
  for _, entity in ipairs(self.dynamic_draw_list) do
    entity:drawUnder()
  end
  --- front entities
  for _, entity in ipairs(self.front_draw_list) do
    entity:drawUnder()
  end
  -- base
  --- back entities
  for _, entity in ipairs(self.back_draw_list) do
    entity:draw()
  end
  --- dynamic entities
  for _, entity in ipairs(self.dynamic_draw_list) do
    entity:draw()
  end
  --- front entities
  for _, entity in ipairs(self.front_draw_list) do
    entity:draw()
  end
  -- animations
  for _, anim in ipairs(self.animations) do
    local frame = math.floor(anim.time/anim.duration*anim.atlas.wc*anim.atlas.hc)
    local cx, cy = frame%anim.atlas.wc, math.floor(frame/anim.atlas.wc)
    local quad = anim.atlas:getQuad(cx, cy)
    if quad then
      if anim.alpha < 1 then love.graphics.setColor(1,1,1,anim.alpha) end
      love.graphics.draw(anim.texture, quad, anim.x, anim.y)
      if anim.alpha < 1 then love.graphics.setColor(1,1,1) end
    end
  end
  -- over
  --- back entities
  for _, entity in ipairs(self.back_draw_list) do
    entity:drawOver()
  end
  --- dynamic entities
  for _, entity in ipairs(self.dynamic_draw_list) do
    entity:drawOver()
  end
  --- front entities
  for _, entity in ipairs(self.front_draw_list) do
    entity:drawOver()
  end
end

-- return entity or nil on failure
function Map:createEntity(edata)
  local eclass = entities[edata.nettype]
  if eclass then
    local entity = eclass(edata)

    self.entities[edata.id] = entity

    -- add to draw list
    local draw_list
    if entity.draw_order < 0 then
      draw_list = self.back_draw_list
    elseif entity.draw_order > 0 then
      draw_list = self.front_draw_list
    else
      draw_list = self.dynamic_draw_list
    end
    table.insert(draw_list, entity)

    return entity
  else
    warn("can't instantiate entity, undefined nettype \""..edata.nettype.."\"")
  end
end

function Map:removeEntity(id)
  local entity = self.entities[id]
  if entity then -- remove entity / add to afterimages
    self.entities[id] = nil
    self.afterimages[entity] = entity.afterimage_duration
    entity.afterimage = 1
  end
end

function Map:updateEntityDrawOrder(entity, draw_order)
  if self.entities[entity.id] == entity then
    -- remove from draw list
    local draw_list
    if entity.draw_order < 0 then
      draw_list = self.back_draw_list
    elseif entity.draw_order > 0 then
      draw_list = self.front_draw_list
    else
      draw_list = self.dynamic_draw_list
    end

    for i, f_entity in ipairs(draw_list) do
      if entity == f_entity then
        table.remove(draw_list, i)
        break
      end
    end

    entity.draw_order = draw_order

    -- add to draw list
    local draw_list
    if entity.draw_order < 0 then
      draw_list = self.back_draw_list
    elseif entity.draw_order > 0 then
      draw_list = self.front_draw_list
    else
      draw_list = self.dynamic_draw_list
    end
    table.insert(draw_list, entity)
  end
end

return Map
