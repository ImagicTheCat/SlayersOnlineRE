local Window = require("gui/Window")

local ChatHistory = class("ChatHistory", Window)

function ChatHistory:__construct(client)
  Window.__construct(self, client)

  self.text = love.graphics.newText(client.font)
  self.messages = {}
  self.max = 100 -- maximum messages
  self.text_factor = 1
  self.max_display = self.max
end

function ChatHistory:buildText()
  self.text_factor = self.client.font_target_height/(self.client.font:getHeight()*self.client.gui_scale)
  self.max_display = math.ceil((self.h-6)*self.client.gui_scale/(self.client.font_target_height))

  local coloredtext = {}

  for i=math.min(#self.messages, self.max_display),1,-1 do
    for _, entry in ipairs(self.messages[i]) do
      table.insert(coloredtext, entry)
    end
    table.insert(coloredtext, "\n")
  end

  self.text:setf(coloredtext, (self.w-6)/self.text_factor, "left")
end

-- coloredtext: see LÖVE
function ChatHistory:add(coloredtext)
  table.insert(self.messages, 1, coloredtext)

  if #self.messages > self.max then
    table.remove(self.messages)
  end

  self:buildText()
end

-- overload
function ChatHistory:update(x,y,w,h)
  Window.update(self, x,y,w,h)

  self:buildText()
end

-- overload
function ChatHistory:draw()
  Window.draw(self)

  local scale = self.client.gui_scale
  love.graphics.setScissor((self.x+3)*scale, (self.y+3)*scale, (self.w-6)*scale, (self.h-6)*scale)

  love.graphics.draw(self.text, self.x+3, self.y+self.h-self.text:getHeight()*self.text_factor-3, 0, self.text_factor)

  love.graphics.setScissor()
end

return ChatHistory
