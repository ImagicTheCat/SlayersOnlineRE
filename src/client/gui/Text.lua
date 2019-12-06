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
