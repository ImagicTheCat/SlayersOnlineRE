local Widget = require("ALGUI.Widget")

local Text = class("Text", Widget)

local function gui_change(self, old_gui)
  if old_gui then old_gui:unlisten("font_update", self.font_update) end
  if self.gui then self.gui:listen("font_update", self.font_update) end
end

-- METHODS

-- wrap_w: (optional) wrap width (will use the layout width if nil)
function Text:__construct(wrap_w)
  Widget.__construct(self)

  self.wrap_w = wrap_w
  self.ftext = ""
  self.display_text = love.graphics.newText(love.graphics.getFont())
  self:listen("gui_change", gui_change)

  -- GUI events
  function self.font_update(gui)
    self.display_text:setFont(love.graphics.getFont())
    self:markLayoutDirty()
  end
end

-- override
function Text:draw()
  Window.draw(self)

  local scale = self.client.gui_scale
  love.graphics.setScissor((self.x+3)*scale, (self.y+3)*scale, (self.w-6)*scale, (self.h-6)*scale)

  -- scroll
  local x = math.min(self.x+4, self.w-6-self.display_text:getWidth()/scale)

  love.graphics.draw(self.display_text, x, self.y+3, 0, 1/scale)
  love.graphics.setScissor()
end

-- ftext: löve text (colored or string)
function Text:set(ftext)
  self.ftext = ftext
  self:markLayoutDirty()
end

-- override
function Text:updateLayout(w,h)
  self.display_text:setf(self.ftext, self.wrap_w or w, "left")
  self:setSize((self.wrap_w and self.display_text:getWidth() or w), self.display_text:getHeight())
end

return Text
