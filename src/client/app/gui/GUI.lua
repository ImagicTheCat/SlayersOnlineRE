local Base = require("ALGUI.ext.GUI")
local TextInput = require("app.gui.TextInput")

local GUI = class("GUI", Base)

-- wrap: (optional) if true, will wrap/extend on content
function GUI:__construct(wrap)
  Base.__construct(self)
  self.wrap = wrap
end

function GUI:updateLayout(w,h)
  if self.wrap then
    local iw, ih = 0, 0
    for child in pairs(self.widgets) do
      iw = math.max(iw, child.x+child.w)
      ih = math.max(ih, child.y+child.h)
    end
    self:setSize(iw,ih)
  end
end

function GUI:isTyping() return xtype.is(self.focus, TextInput) end

-- Play unspatialized GUI sound.
-- return source
function GUI:playSound(path) return client:playSound(path) end

-- Emit "control-press" on GUI and focused widget.
function GUI:emitControlPress(id)
  self:emit("control-press", id)
  if self.focus then self.focus:emit("control-press", id) end
end

-- Emit "control-release" on GUI and focused widget.
function GUI:emitControlRelease(id)
  self:emit("control-release", id)
  if self.focus then self.focus:emit("control-release", id) end
end

return GUI
