local entities = require("entities.entities")
local TextureAtlas = require("TextureAtlas")
local LivingEntity = require("entities.LivingEntity")

local Map = class("Map")

local function sort_entities(a, b)
  return a.top < b.top
end

-- METHODS

function Map:__construct(data)
  self.tileset = client:loadTexture("resources/textures/sets/tileset.png") -- default
  self:build(data)
  -- load map resources
  async(function()
    if client.rsc_manager:requestResource("textures/sets/"..data.tileset) then
      self.tileset = client:loadTexture("resources/textures/sets/"..data.tileset)
      self:build(data)
    else print("failed to load map tileset \""..data.tileset.."\"") end
    if #data.background > 0 then
      if client.rsc_manager:requestResource("textures/sets/"..data.background) then
        self.background = client:loadTexture("resources/textures/sets/"..data.background)
      else print("failed to load map background \""..data.background.."\"") end
    end
    if data.music then
      if client.rsc_manager:requestResource("audio/"..data.music) then
        client:playMusic("resources/audio/"..data.music)
      else print("failed to load map music \""..data.music.."\"") end
    end
  end)
  -- request preload resources
  for path in pairs(data.preload_resources) do
    async(function() client.rsc_manager:requestResource(path) end)
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
      if entity and class.is(entity, LivingEntity) then
        entity:onUpdatePosition(x,y)
      end
    end
  end
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

  -- sort entities by Y-top position (top-down sorting)
  table.sort(self.back_draw_list, sort_entities)
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
    print("can't instantiate entity, undefined nettype \""..edata.nettype.."\"")
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
