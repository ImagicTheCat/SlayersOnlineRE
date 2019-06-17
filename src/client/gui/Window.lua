
local Window = class("Window")

-- STATICS

local system

function Window.loadSystemBorders(x, y, w, h, margin)
  local borders = {
    x = x,
    y = y,
    w = w,
    h = h,
    margin = margin
  }

  -- corners
  -- top
  borders.ctl = love.graphics.newQuad(x,y,margin,margin,160,80)
  borders.ctr = love.graphics.newQuad(x+w-margin,y,margin,margin,160,80)
  -- bottom
  borders.cbl = love.graphics.newQuad(x,y+h-margin,margin,margin,160,80)
  borders.cbr = love.graphics.newQuad(x+w-margin,y+h-margin,margin,margin,160,80)

  -- middle
  borders.mt = love.graphics.newQuad(x+margin,y,y+h-margin*2,margin,160,80)
  borders.mb = love.graphics.newQuad(x+margin,y+h-margin,w-margin*2,margin,160,80)
  borders.ml = love.graphics.newQuad(x,margin,margin,h-margin*2,160,80)
  borders.mr = love.graphics.newQuad(x+w-margin,margin,margin,h-margin*2,160,80)

  return borders
end

function Window.loadSystem(client)
  if not system then
    system = {}

    system.tex = client:loadTexture("resources/textures/system.png")
    system.background = love.graphics.newQuad(0,0,32,32,160,80)

    system.window_borders = Window.loadSystemBorders(32, 0, 32, 32, 5)
    system.select_borders = Window.loadSystemBorders(64, 0, 32, 32, 5)
  end

  return system
end

-- METHODS

function Window:__construct(client)
  self.client = client

  self.x = 0
  self.y = 0
  self.w = 0
  self.h = 0
  self.system = Window.loadSystem(client)
end

function Window:update(x, y, w, h)
  self.x, self.y, self.w, self.h = x,y,w,h
end

-- draw rect based on borders
function Window:drawBorders(borders, x, y, w, h)
  local b = borders

  -- borders
  --- corners
  love.graphics.draw(self.system.tex, b.ctl, x, y)
  love.graphics.draw(self.system.tex, b.ctr, x+w-b.margin, y)
  love.graphics.draw(self.system.tex, b.cbl, x, y+h-b.margin)
  love.graphics.draw(self.system.tex, b.cbr, x+w-b.margin, y+h-b.margin)
  --- middles
  love.graphics.draw(self.system.tex, b.mt, x+b.margin, y, 0, (w-b.margin*2)/(b.w-b.margin*2), 1)
  love.graphics.draw(self.system.tex, b.mb, x+b.margin, y+h-b.margin, 0, (w-b.margin*2)/(b.w-b.margin*2), 1)
  love.graphics.draw(self.system.tex, b.ml, x, y+b.margin, 0, 1, (h-b.margin*2)/(b.h-b.margin*2))
  love.graphics.draw(self.system.tex, b.mr, x+w-b.margin, y+b.margin, 0, 1, (h-b.margin*2)/(b.h-b.margin*2))
end

function Window:draw()
  local x,y,w,h = self.x, self.y, self.w, self.h

  -- background
  love.graphics.draw(self.system.tex, self.system.background, x+1, y+1, 0, (w-2)/32, (h-2)/32)

  self:drawBorders(self.system.window_borders, x, y, w, h)
end

return Window
