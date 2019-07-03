local Window = require("gui/Window")

local InputQuery = class("InputQuery", Window)

function InputQuery:__construct(client)
  Window.__construct(self, client)

  self.text = love.graphics.newText(client.font)
  self.title = ""
  self.options = {}
  self.text_options = {}

  self.selected = 1
end

function InputQuery:set(title, options)
  self.title = title
  self.options = options
  self.selected = 1
  self:buildText()
end

function InputQuery:moveSelect(mod)
  local size = #self.options

  self.selected = self.selected+mod
  if self.selected > size then
    self.selected = 1
  elseif self.selected < 1 then
    self.selected = size
  end
end

function InputQuery:buildText()
  self.text:setf(self.title, (self.w-6)*self.client.gui_scale, "left")

  self.text_options = {}
  for _, option in ipairs(self.options) do
    local text = love.graphics.newText(self.client.font)
    text:setf(option, (self.w-6)*self.client.gui_scale, "left")
    table.insert(self.text_options, text)
  end
end

-- overload
function InputQuery:update(x,y,w,h)
  Window.update(self, x,y,w,h)

  self:buildText()
end

-- overload
function InputQuery:draw()
  Window.draw(self)

  self:clip()
  local scale = self.client.gui_scale

  -- draw title
  love.graphics.draw(self.text, self.x+3, self.y+3, 0, 1/scale)

  -- draw options
  local shift_y = self.y+3+self.text:getHeight()*1/scale
  for i, text in ipairs(self.text_options) do
    love.graphics.draw(text, self.x+3, shift_y, 0, 1/scale)

    if self.selected == i then -- draw selection
      self:drawBorders(self.system.select_borders, self.x+2, shift_y, self.w-4, text:getHeight()/scale)
    end

    shift_y = shift_y+text:getHeight()/scale
  end

  love.graphics.setScissor()
end

return InputQuery
