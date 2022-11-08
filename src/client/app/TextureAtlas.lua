-- https://github.com/ImagicTheCat/SlayersOnlineRE
-- MIT license (see LICENSE, src/server/main.lua or src/client/main.lua)

-- class to generate texture atlas cells
local TextureAtlas = class("TextureAtlas")

-- x, y: offset
function TextureAtlas:__construct(x, y, w, h, cell_w, cell_h)
  self.quads = {}
  self.x = x
  self.y = y
  self.w = w
  self.h = h
  self.cell_w = cell_w
  self.cell_h = cell_h
  self.wc = (self.w-self.x)/self.cell_w
  self.hc = (self.h-self.y)/self.cell_h
end

-- x,y: atlas cell coordinates (starts at 0)
-- return quad or nil if out of bounds
function TextureAtlas:getQuad(x, y)
  local index = y*self.wc+x
  local quad = self.quads[index]

  if not quad then -- load quad
    if x >= 0 and y >= 0 and x < self.wc and y < self.hc then
      quad = love.graphics.newQuad(self.x+x*self.cell_w, self.y+y*self.cell_h, self.cell_w, self.cell_h, self.w, self.h)
      self.quads[index] = quad
    end
  end

  return quad
end

return TextureAtlas
