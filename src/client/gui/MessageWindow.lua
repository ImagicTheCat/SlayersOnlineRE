local Window = require("gui/Window")

local MessageWindow = class("MessageWindow", Window)

function MessageWindow:__construct(client)
  Window.__construct(self, client)

  self.text = love.graphics.newText(client.font)
  self.message = ""
  self.text_factor = 1
end

function MessageWindow:set(message)
  self.message = message
  self:buildText()
end

function MessageWindow:buildText()
  self.text_factor = self.client.font_target_height/(self.client.font:getHeight()*self.client.gui_scale)

  self.text:setf(self.message, (self.w-6)/self.text_factor, "left")
end

-- overload
function MessageWindow:update(x,y,w,h)
  Window.update(self, x,y,w,h)

  self:buildText()
end

-- overload
function MessageWindow:draw()
  Window.draw(self)

  local scale = self.client.gui_scale
  love.graphics.setScissor((self.x+3)*scale, (self.y+3)*scale, (self.w-6)*scale, (self.h-6)*scale)

  love.graphics.draw(self.text, self.x+3, self.y+3, 0, self.text_factor)

  love.graphics.setScissor()
end

return MessageWindow
