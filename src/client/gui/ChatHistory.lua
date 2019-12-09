local Window = require("gui.Window")
local Text = require("gui.Text")

local ChatHistory = class("ChatHistory", Window)

local function gui_change(self, old_gui)
  if old_gui then old_gui:unlisten("tick", self.tick) end
  if self.gui then self.gui:listen("tick", self.tick) end
end

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
  self.timer = 0
  self:listen("gui-change", gui_change)
  self:listen("content-update", content_update)

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
  self.content:add(text)
  table.insert(self.messages, 1, text)

  if #self.messages > self.max then
    self.content:remove(table.remove(self.messages))
  end

  self:show(10)
end

return ChatHistory
