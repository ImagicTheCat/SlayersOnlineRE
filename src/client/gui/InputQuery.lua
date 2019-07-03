local Window = require("gui/Window")
local Selector = require("gui/Selector")

local InputQuery = class("InputQuery", Window)

function InputQuery:__construct(client)
  Window.__construct(self, client)

  self.text = love.graphics.newText(client.font)
  self.title = ""
  self.options = {}
  self.selector = Selector(client, 0, 0)
  self.selected = 0
end

function InputQuery:set(title, options)
  self.title = title
  self.options = options
  self.selected = 0

  self:build()
end

function InputQuery:build()
  self.text:setf(self.title, (self.w-6)*self.client.gui_scale, "left")

  local function cb_selector(selector, x, y, selected)
    if selected then
      self.selected = y+1
    end
  end

  -- options
  local th = self.text:getHeight()/self.client.gui_scale
  self.selector:update(self.x+3,self.y+th+3,self.w-6,self.h-th-6)

  self.selector:init(1, #self.options)
  for i, text in ipairs(self.options) do
    self.selector:set(0, i-1, text, cb_selector)
  end
end

-- overload
function InputQuery:update(x,y,w,h)
  Window.update(self, x,y,w,h)

  self:build()
end

-- overload
function InputQuery:draw()
  Window.draw(self)

  local scale = self.client.gui_scale

  -- draw title
  love.graphics.draw(self.text, self.x+3, self.y+3, 0, 1/scale)

  -- draw options
  self.selector:draw()
end

return InputQuery
