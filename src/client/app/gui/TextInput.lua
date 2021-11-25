local utf8 = require("utf8")
local Widget = require("ALGUI.Widget")

local TextInput = class("TextInput", Widget)

local function key_press(self, event, keycode, scancode, repeated)
  if scancode == "backspace" then self:erase(-1) end
end

local function control_press(self, event, id)
  if id == "copy" then
    love.system.setClipboardText(self.text)
  elseif id == "paste" then
    self:set(self.text..love.system.getClipboardText())
  end
end

local function focus_change(self, event, state)
  if state then
    love.keyboard.setTextInput(true, self.tx, self.ty,
      math.floor(self.w*self.tscale), math.floor(self.h*self.tscale))
  else
    love.keyboard.setTextInput(false)
  end
end

local function text_input(self, event, data) self:input(data) end

local function update_display(self)
  if self.hidden then
    self.display_text:set(string.rep("•", utf8.len(self.text)))
  else
    self.display_text:set(self.text)
  end
end

-- METHODS

function TextInput:__construct()
  Widget.__construct(self)
  self.text = ""
  self.hidden = false
  self.display_text = love.graphics.newText(love.graphics.getFont())
  self:listen("text-input", text_input)
  self:listen("key-press", key_press)
  self:listen("control-press", control_press)
  self:listen("focus-update", focus_change)
  -- GUI events
  function self.font_update(gui)
    self.display_text:setFont(love.graphics.getFont())
  end
end

-- override
function TextInput:postBind()
  self.gui:listen("font-update", self.font_update)
  -- update font when added
  self.display_text:setFont(love.graphics.getFont())
end

-- override
function TextInput:preUnbind()
  self.gui:unlisten("font-update", self.font_update)
end

function TextInput:setHidden(hidden)
  if self.hidden ~= hidden then
    self.hidden = hidden
    update_display(self)
  end
end

-- data: text
function TextInput:input(data)
  self.text = self.text..data
  update_display(self)
  self:emit("change")
end

function TextInput:set(text)
  local changed = (self.text ~= text)
  self.text = text
  update_display(self)
  if changed then self:emit("change") end
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
    update_display(self)
    self:emit("change")
  end
end

return TextInput
