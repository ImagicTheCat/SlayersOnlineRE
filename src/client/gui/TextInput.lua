local utf8 = require("utf8")

local Window = require("gui/Window")

local TextInput = class("TextInput", Window)

function TextInput:__construct(client)
  Window.__construct(self, client)

  self.text = ""
  self.display_text = love.graphics.newText(client.font)
end

-- overload
function TextInput:draw()
  Window.draw(self)

  local scale = self.client.gui_scale
  love.graphics.setScissor((self.x+3)*scale, (self.y+3)*scale, (self.w-6)*scale, (self.h-6)*scale)

  -- height
  local factor = 1
  local th = self.display_text:getHeight()
  if th > 0 then
    factor = (self.h-6)/th
  end

  -- scroll
  local x = math.min(self.x+4, self.w-6-self.display_text:getWidth()*factor)

  love.graphics.draw(self.display_text, x, self.y+3, 0, factor)
  love.graphics.setScissor()
end

function TextInput:input(data)
  self.text = self.text..data
  self.display_text:set(self.text)
end

function TextInput:set(text)
  self.text = text
  self.display_text:set(self.text)
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
