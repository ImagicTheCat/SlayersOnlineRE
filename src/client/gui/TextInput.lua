local utf8 = require("utf8")
local Widget = require("ALGUI.Widget")

local TextInput = class("TextInput", Widget)

local function gui_change(self, old_gui)
  if old_gui then old_gui:unlisten("font-update", self.font_update) end
  if self.gui then
    self.gui:listen("font-update", self.font_update)
    self.display_text:setFont(love.graphics.getFont()) -- update font when added
  end
end

local function key_press(self, keycode, scancode, repeated)
  if scancode == "backspace" then
    self:erase(-1)
  end
end

local function control_press(self, id)
  if id == "copy" then
    love.system.setClipboardText(self.text)
  elseif id == "paste" then
    self:set(self.text..love.system.getClipboardText())
  end
end

local function focus_change(self, state)
  love.keyboard.setTextInput(state)
end

-- METHODS

function TextInput:__construct()
  Widget.__construct(self)

  self.text = ""
  self.display_text = love.graphics.newText(love.graphics.getFont())
  self:listen("gui-change", gui_change)
  self:listen("text-input", self.input)
  self:listen("key-press", key_press)
  self:listen("control-press", control_press)
  self:listen("focus-change", focus_change)

  -- GUI events
  function self.font_update(gui)
    self.display_text:setFont(love.graphics.getFont())
  end
end

function TextInput:input(data)
  self.text = self.text..data
  self.display_text:set(self.text)
end

function TextInput:set(text)
  self.text = text
  self.display_text:set(self.text)
end

-- override
function TextInput:updateLayout(w,h)
  self:setSize(w,h)
end

-- erase character
-- offset: like utf8.offset n parameter
function TextInput:erase(offset)
  local offset = utf8.offset(self.text, offset)
  if offset then
    self.text = string.sub(self.text, 1, offset-1)
    self.display_text:set(self.text)
  end
end

return TextInput
