local Base = require("ALGUI.ext.GUI")
local TextInput = require("gui.TextInput")

local GUI = class("GUI", Base)

-- wrap: (optional) if true, will wrap/extend on content
function GUI:__construct(client, wrap)
  Base.__construct(self)

  self.client = client
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

function GUI:isTyping()
  return class.is(self.focus, TextInput)
end

-- play unspatialized GUI sound
-- return source
function GUI:playSound(path)
  local source = self.client:playSound(path)
  source:setRelative(true)

  return source
end

-- trigger "control_press" on GUI and focused widget
function GUI:triggerControlPress(id)
  local focus = self.focus
  self:trigger("control-press", id)
  if focus then focus:trigger("control-press", id) end
end

-- trigger "control_release" on GUI and focused widget
function GUI:triggerControlRelease(id)
  local focus = self.focus
  self:trigger("control-release", id)
  if focus then focus:trigger("control-release", id) end
end

return GUI
