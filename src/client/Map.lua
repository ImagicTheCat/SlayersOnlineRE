
local Map = class("Map")

function Map:__construct(data)
  self.tileset = love.graphics.newImage("resources/textures/sets/"..data.tileset)
  self.quads = {} -- quad pool

  if self.tileset then
    -- build low / high layer sprite batches

    self.low_layer = love.graphics.newSpriteBatch(self.tileset, data.w*data.h, "static")
    self.high_layer = love.graphics.newSpriteBatch(self.tileset, data.w*data.h, "static")

    self.tileset_wc = self.tileset:getWidth()/16
    self.tileset_hc = self.tileset:getHeight()/16

    local tiledata = data.tiledata
    for y=0,data.h-1 do
      for x=0,data.w-1 do
        local index = y*data.w+x
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
end

-- get tileset quad
-- x,y: tileset cell coordinates (start at 1)
-- return nil if invalid
function Map:getQuad(x, y)
  local index = y*self.tileset_w+x
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
  love.graphics.draw(self.low_layer, 0, 0)
  love.graphics.draw(self.high_layer, 0, 0)
end

return Map
