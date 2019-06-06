local entities = require("entities/entities")
local TextureAtlas = require("TextureAtlas")

local Map = class("Map")

local function sort_entities(a, b)
  return a.y < b.y
end

-- METHODS

function Map:__construct(data)
  self.tileset = client:loadTexture("resources/textures/sets/"..data.tileset)
  
  local atlas = TextureAtlas(self.tileset:getWidth(), self.tileset:getHeight(), 16, 16)

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
  self.draw_list = {} -- list of entities

  for _, edata in pairs(data.entities) do
    self:createEntity(edata)
  end
end

function Map:tick(dt)
  -- entities tick
  for id, entity in pairs(self.entities) do
    entity:tick(dt)
  end

  -- sort entities by Y (top-down sorting)
  table.sort(self.draw_list, sort_entities)
end

function Map:draw()
  love.graphics.draw(self.low_layer)

  -- entities
  for _, entity in ipairs(self.draw_list) do
    entity:draw()
  end

  love.graphics.draw(self.high_layer)

  -- entities HUD
  for _, entity in ipairs(self.draw_list) do
    entity:drawHUD()
  end
end

-- return entity or nil on failure
function Map:createEntity(edata)
  local eclass = entities[edata.nettype]
  if eclass then
    local entity = eclass(edata)

    self.entities[edata.id] = entity
    table.insert(self.draw_list, entity)

    return entity
  else
    print("can't instantiate entity, undefined nettype \""..edata.nettype.."\"")
  end
end

function Map:removeEntity(id)
  if self.entities[id] then
    self.entities[id] = nil

    -- remove from draw list
    for i, entity in ipairs(self.draw_list) do
      if id == entity.id then
        table.remove(self.draw_list, i)
        break
      end
    end
  end
end

return Map
