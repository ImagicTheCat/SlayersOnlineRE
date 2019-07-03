local Widget = require("gui/Widget")

local Window = class("Window", Widget)

-- METHODS

function Window:__construct(client)
  Widget.__construct(self, client)

  self.system = Window.loadSystem(client)
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

function Window:clip()
  local scale = self.client.gui_scale
  love.graphics.setScissor((self.x+3)*scale, (self.y+3)*scale, (self.w-6)*scale, (self.h-6)*scale)
end

return Window
