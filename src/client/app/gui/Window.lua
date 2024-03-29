-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

local Widget = require("ALGUI.Widget")

local Window = class("Window", Widget)
local MARGIN = 6

Window.Content = class("Window.Content", Widget)

-- Window.Content

function Window.Content:__construct(wrap)
  Widget.__construct(self)
  self.wrap = wrap
end

local function sort_layout(a,b) return a.iz < b.iz end

function Window.Content:updateLayout(w,h)
  local widgets = {}
  for widget in pairs(self.widgets) do table.insert(widgets, widget) end
  table.sort(widgets, sort_layout) -- sort by implicit z (added order)
  -- flow
  if self.wrap == "both" then -- vertical flow and wrap
    local y, max_w = 0, 0
    for _, child in ipairs(widgets) do
      child:setPosition(0,y)
      child:updateLayout(max_w, h-y)
      max_w = math.max(max_w, child.w)
      y = y+child.h
    end
    self:setSize(max_w,y)
  elseif self.wrap == "vertical" then -- vertical flow and vertical wrap
    local y = 0
    for _, child in ipairs(widgets) do
      child:setPosition(0,y)
      child:updateLayout(w, h-y)
      y = y+child.h
    end
    self:setSize(w,y)
  else -- vertical flow
    local y = 0
    for _, child in ipairs(widgets) do
      child:setPosition(0,y)
      child:updateLayout(w, h-y)
      y = y+child.h
    end
    self:setSize(w,h)
  end
  -- emit window event
  self.parent:emit("content-update")
end

-- Window

-- wrap: (optional)
--- nil: no wrapping (fixed size)
--- "both": wrap/extend on content
--- "vertical": wrap/extend on content (only vertically)
function Window:__construct(wrap)
  Widget.__construct(self)
  self.content = Window.Content(wrap)
  self:add(self.content)
end

function Window:updateLayout(w,h)
  self.content:setPosition(MARGIN, MARGIN)
  self.content:updateLayout(w-MARGIN*2, h-MARGIN*2)
  self:setSize(self.content.w+MARGIN*2, self.content.h+MARGIN*2)
end

return Window
