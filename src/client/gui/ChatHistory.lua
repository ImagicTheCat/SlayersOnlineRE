local Window = require("gui.Window")
local Text = require("gui.Text")

local ChatHistory = class("ChatHistory", Window)

local function gui_change(self, old_gui)
  if old_gui then old_gui:unlisten("tick", self.tick) end
  if self.gui then self.gui:listen("tick", self.tick) end
end

-- METHODS

function ChatHistory:__construct()
  Window.__construct(self)

  self.messages = {} -- list/queue of Text (newest first)
  self.max = 100 -- maximum messages
  self.timer = 0
  self:listen("gui_change", gui_change)

  -- GUI events
  function self.tick(gui, dt)
    if self.timer and self.timer > 0 then
      self.timer = self.timer-dt
      if self.timer <= 0 then
        self:setVisible(false)
      end
    end
  end
end

-- time: (optional) seconds or nil (infinite)
function ChatHistory:show(time)
  self:setVisible(true)
  self.timer = time
end

function ChatHistory:hide()
  self:setVisible(false)
  self.timer = 0
end

-- ftext: string or coloredtext (see löve)
function ChatHistory:addMessage(ftext)
  local text = Text()
  text:set(ftext)
  self:add(text)
  table.insert(self.messages, 1, text)

  if #self.messages > self.max then
    self:remove(table.remove(self.messages))
  end

  self:show(10)
end

-- override
function ChatHistory:updateLayout(w,h)
  Window.updateLayout(self, w,h)

  local ih = 0
  for child in pairs(self.widgets) do
    ih = math.max(ih, child.y+child.h)
  end

  self:setInnerShift(self.ix, self.h-ih-3) -- scroll to bottom
end

-- override
function ChatHistory:draw()
  Window.draw(self)

  local scale = self.client.gui_scale
  love.graphics.setScissor((self.x+3)*scale, (self.y+3)*scale, (self.w-6)*scale, (self.h-6)*scale)

  love.graphics.draw(self.text, self.x+3, self.y+self.h-self.text:getHeight()/scale-3, 0, 1/scale)

  love.graphics.setScissor()
end

return ChatHistory
