local Window = require("gui.Window")
local Text = require("gui.Text")

local ChatHistory = class("ChatHistory", Window)

local function content_update(self)
  local ih = 0
  for child in pairs(self.content.widgets) do
    ih = math.max(ih, child.y+child.h)
  end

  self.content:setInnerShift(0, self.content.h-ih) -- scroll to bottom
end

-- METHODS

function ChatHistory:__construct()
  Window.__construct(self)

  self.messages = {} -- list/queue of Text (newest first)
  self.max = 100 -- maximum messages
  self:listen("content-update", content_update)
end

-- time: (optional) seconds or nil (infinite)
function ChatHistory:show(time)
  self:setVisible(true)
  if time then
    self.timer = scheduler:timer(time, function() self:hide() end)
  end
end

function ChatHistory:hide()
  self:setVisible(false)
  if self.timer then
    self.timer:remove()
    self.timer = nil
  end
end

-- ftext: string or coloredtext (see löve)
function ChatHistory:addMessage(ftext)
  local text = Text()
  text:set(ftext)
  self.content:add(text)
  table.insert(self.messages, 1, text)

  if #self.messages > self.max then
    self.content:remove(table.remove(self.messages))
  end

  self:show(10)
end

return ChatHistory
