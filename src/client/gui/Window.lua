local Widget = require("gui/Widget")

local Window = class("Window", Widget)

-- METHODS

function Window:__construct(client)
  Widget.__construct(self, client)

  self.system = Window.loadSystem(client)
end

-- overload
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
