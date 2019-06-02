
local Map = class("Map")
local entities = require("entities/entities")

function Map:__construct(data)
  self.tileset = love.graphics.newImage("resources/textures/sets/"..data.tileset)
  self.quads = {} -- quad pool

  -- build low / high layer sprite batches

  self.low_layer = love.graphics.newSpriteBatch(self.tileset, data.w*data.h, "static")
  self.high_layer = love.graphics.newSpriteBatch(self.tileset, data.w*data.h, "static")

  self.tileset_wc = self.tileset:getWidth()/16
  self.tileset_hc = self.tileset:getHeight()/16

  local tiledata = data.tiledata
  if tiledata then
    for y=0,data.h-1 do
      for x=0,data.w-1 do
        local index = (y*data.w+x)*4+1
        local xl, xh, yl, yh = tiledata[index] or 0, tiledata[index+1] or 0, tiledata[index+2] or 0, tiledata[index+3] or 0

        local low_quad = self:getQuad(xl,yl)
        local high_quad = self:getQuad(xh,yh)

        if low_quad then
          self.low_layer:add(low_quad, x*16, y*16)
        end

        if high_quad then
          self.high_layer:add(high_quad, x*16, y*16)
        end
      end
    end
  end

  self.quads = {} -- empty quad references

  -- build entities
  self.entities = {}

  for _, edata in pairs(data.entities) do
    self:createEntity(edata)
  end
end

-- get tileset quad
-- x,y: tileset cell coordinates (start at 1)
-- return nil if invalid
function Map:getQuad(x, y)
  local index = y*self.tileset_wc+x
  local quad = self.quads[index]

  if not quad then -- load quad
    if x > 0 and y > 0 and x <= self.tileset_wc and y <= self.tileset_hc then
      quad = love.graphics.newQuad((x-1)*16, (y-1)*16, 16, 16, self.tileset:getDimensions())
      self.quads[index] = quad
    end
  end

  return quad
end

function Map:draw()
  love.graphics.draw(self.low_layer)

  -- entities
  for id, entity in pairs(self.entities) do
    entity:draw()
  end

  love.graphics.draw(self.high_layer)
end

-- return entity or nil on failure
function Map:createEntity(edata)
  local eclass = entities[edata.nettype]
  if eclass then
    local entity = eclass(edata)
    self.entities[edata.id] = entity
    return entity
  else
    print("can't instantiate entity, undefined nettype \""..edata.nettype.."\"")
  end
end

function Map:removeEntity(id)
  if self.entities[id] then
    self.entities[id] = nil
  end
end

return Map
