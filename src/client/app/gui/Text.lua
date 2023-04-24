-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

local Widget = require("ALGUI.Widget")

local Text = class("Text", Widget)

local function gui_change(self, old_gui)
end

-- METHODS

-- ftext: (optional) set() shortcut
-- wrap_w: (optional) wrap width (will use the layout width if nil)
function Text:__construct(ftext, wrap_w)
  Widget.__construct(self)
  self.ftext = ftext or ""
  self.wrap_w = wrap_w
  self.display_text = love.graphics.newText(love.graphics.getFont())
  -- GUI events
  function self.font_update(gui)
    self.display_text:setFont(love.graphics.getFont())
    self:markDirty("layout")
  end
end

-- override
function Text:postBind()
  self.gui:listen("font-update", self.font_update)
  self.font_update(self.gui) -- trigger update when bound
end

-- override
function Text:preUnbind()
  self.gui:unlisten("font-update", self.font_update)
end

-- ftext: löve text (colored or string)
function Text:set(ftext)
  self.ftext = ftext
  self:markDirty("layout")
end

-- override
function Text:updateLayout(w,h)
  self.display_text:setf(self.ftext, self.wrap_w or w, "left")
  self:setSize((self.wrap_w and self.display_text:getWidth() or w), self.display_text:getHeight())
end

return Text
