-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

local Window = require("app.gui.Window")
local Text = require("app.gui.Text")
local utils = require("app.utils")

local ChatHistory = class("ChatHistory", Window)

local function content_update(self)
  local ih = 0
  for child in pairs(self.content.widgets) do
    ih = math.max(ih, child.y+child.h)
  end
  self.inner_h = ih
  self.content:setInnerOffset(0, self.content.h-ih+self.scroll_h) -- scroll to bottom
end

local function pointer_wheel(self, event, id, x, y, wx, wy)
  self:scroll(wy*50)
end

-- METHODS

function ChatHistory:__construct()
  Window.__construct(self)

  self.messages = {} -- list/queue of Text (newest first)
  self.max = 100 -- maximum messages
  self:listen("content-update", content_update)
  self:listen("pointer-wheel", pointer_wheel)
  self.scroll_h = 0
end

-- amount: widget units, positive/negative
function ChatHistory:scroll(amount)
  self.scroll_h = utils.clamp(self.scroll_h+amount, 0, self.inner_h-self.content.h)
  self.content:setInnerOffset(0, self.content.h-self.inner_h+self.scroll_h) -- scroll to bottom
  self:show(10)
end

-- time: (optional) seconds or nil (infinite)
function ChatHistory:show(time)
  self:setVisible(true)
  if time then
    if self.timer then self.timer:remove() end
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
  -- insert
  local text = Text()
  text:set(ftext)
  self.content:add(text)
  table.insert(self.messages, 1, text)
  -- prune
  if #self.messages > self.max then
    self.content:remove(table.remove(self.messages))
  end
  -- display
  self:show(10)
end

return ChatHistory
