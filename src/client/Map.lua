local entities = require("entities/entities")
local TextureAtlas = require("TextureAtlas")

local Map = class("Map")

local function sort_entities(a, b)
  return a.y < b.y
end

-- METHODS

function Map:__construct(data)
  self.tileset = client:loadTexture("resources/textures/sets/"..data.tileset)
  
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

  -- build entities
  self.entities = {} -- map of id => entity

  -- lists of entities
  self.back_draw_list = {}
  self.dynamic_draw_list = {}
  self.front_draw_list = {}

  for _, edata in pairs(data.entities) do
    self:createEntity(edata)
  end
end

function Map:tick(dt)
  -- entities tick
  for id, entity in pairs(self.entities) do
    entity:tick(dt)
  end

  -- sort dynamic entities by Y (top-down sorting)
  table.sort(self.dynamic_draw_list, sort_entities)
end

function Map:draw()
  love.graphics.draw(self.low_layer)
  love.graphics.draw(self.high_layer)

  -- back entities
  for _, entity in ipairs(self.back_draw_list) do
    entity:draw()
  end

  -- dynamic entities
  for _, entity in ipairs(self.dynamic_draw_list) do
    entity:draw()
  end

  -- front entities
  for _, entity in ipairs(self.front_draw_list) do
    entity:draw()
  end

  -- HUD

  -- back entities
  for _, entity in ipairs(self.back_draw_list) do
    entity:drawHUD()
  end

  -- dynamic entities
  for _, entity in ipairs(self.dynamic_draw_list) do
    entity:drawHUD()
  end

  -- front entities
  for _, entity in ipairs(self.front_draw_list) do
    entity:drawHUD()
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
  if entity then
    self.entities[id] = nil

    -- remove from draw list
    local draw_list
    if entity.draw_order < 0 then
      draw_list = self.back_draw_list
    elseif entity.draw_order > 0 then
      draw_list = self.front_draw_list
    else
      draw_list = self.dynamic_draw_list
    end

    for i, entity in ipairs(draw_list) do
      if id == entity.id then
        table.remove(draw_list, i)
        break
      end
    end
  end
end

return Map
