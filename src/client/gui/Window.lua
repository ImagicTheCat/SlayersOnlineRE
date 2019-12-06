local Widget = require("ALGUI.Widget")


local Window = class("Window", Widget)

local MARGIN = 6

local function sort_layout(a,b)
  return a.iz < b.iz
end

-- SUBCLASS: Content
Window.Content = class("Window.Content", Widget)

--- METHODS

function Window.Content:__construct(wrap)
  Widget.__construct(self)

  self.wrap = wrap
end

function Window.Content:updateLayout(w,h)
  local widgets = {}
  for widget in pairs(self.widgets) do table.insert(widgets, widget) end
  table.sort(widgets, sort_layout) -- sort by implicit z (added order)

  if self.wrap then -- vertical flow and wrap
    local y, max_w = 0, 0
    for _, child in ipairs(widgets) do
      child:setPosition(0,y)
      child:updateLayout(max_w, h-y)
      max_w = math.max(max_w, child.w)
      y = y+child.h
    end
    self:setSize(max_w,y)
  else -- vertical flow
    local y = 0
    for _, child in ipairs(widgets) do
      child:setPosition(0,y)
      child:updateLayout(w, h-y)
      y = y+child.h
    end
    self:setSize(w,h)
  end

  -- trigger window event
  self.parent:trigger("content_update")
end

-- METHODS

-- wrap: (optional) if true, will wrap/extend on content (vertically)
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
