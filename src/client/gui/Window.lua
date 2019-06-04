
local Window = class("Window")

function Window:__construct(client)
  self.client = client

  self.x = 0
  self.y = 0
  self.w = 0
  self.h = 0

  self.system_tex = client:loadTexture("resources/textures/system.png")

  self.system_background = love.graphics.newQuad(0,0,32,32,160,80)

  -- top
  self.system_border_ctl = love.graphics.newQuad(32,0,5,5,160,80)
  self.system_border_ctr = love.graphics.newQuad(64-5,0,5,5,160,80)
  -- bottom
  self.system_border_cbl = love.graphics.newQuad(32,32-5,5,5,160,80)
  self.system_border_cbr = love.graphics.newQuad(64-5,32-5,5,5,160,80)

  self.system_border_mt = love.graphics.newQuad(32+5,0,32-10,5,160,80)
  self.system_border_mb = love.graphics.newQuad(32+5,32-5,32-10,5,160,80)
  self.system_border_ml = love.graphics.newQuad(32,5,5,32-10,160,80)
  self.system_border_mr = love.graphics.newQuad(64-5,5,5,32-10,160,80)
end

function Window:update(x, y, w, h)
  self.x, self.y, self.w, self.h = x,y,w,h
end

function Window:draw()
  local x,y,w,h = self.x, self.y, self.w, self.h

  -- background
  love.graphics.draw(self.system_tex, self.system_background, x+1, y+1, 0, (w-2)/32, (h-2)/32)

  -- borders
  --- corners
  love.graphics.draw(self.system_tex, self.system_border_ctl, x, y)
  love.graphics.draw(self.system_tex, self.system_border_ctr, x+w-5, y)
  love.graphics.draw(self.system_tex, self.system_border_cbl, x, y+h-5)
  love.graphics.draw(self.system_tex, self.system_border_cbr, x+w-5, y+h-5)
  --- middles
  love.graphics.draw(self.system_tex, self.system_border_mt, x+5, y, 0, (w-10)/22, 1)
  love.graphics.draw(self.system_tex, self.system_border_mb, x+5, y+h-5, 0, (w-10)/22, 1)
  love.graphics.draw(self.system_tex, self.system_border_ml, x, y+5, 0, 1, (h-10)/22)
  love.graphics.draw(self.system_tex, self.system_border_mr, x+w-5, y+5, 0, 1, (h-10)/22)
end

return Window
