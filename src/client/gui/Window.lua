local Widget = require("ALGUI.Widget")

local Window = class("Window", Widget)

local MARGIN = 6

local function sort_layout(a,b)
  return a.iz < b.iz
end

-- METHODS

-- wrap: (optional) if true, will wrap/extend on content (vertically)
function Window:__construct(wrap)
  Widget.__construct(self)

  self.wrap = wrap
end

function Window:updateLayout(w,h)
  local widgets = {}
  for widget in pairs(self.widgets) do table.insert(widgets, widget) end
  table.sort(widgets, sort_layout) -- sort by implicit z (added order)

  if self.wrap then -- vertical flow and wrap
    local y, max_w = MARGIN, 0
    for _, child in ipairs(widgets) do
      child:setPosition(MARGIN,y)
      child:updateLayout(max_w, h-y-MARGIN)
      max_w = math.max(max_w, child.w)
      y = y+child.h
    end
    self:setSize(max_w+MARGIN*2,y+MARGIN)
  else -- vertical flow
    local y = MARGIN
    for _, child in ipairs(widgets) do
      child:setPosition(MARGIN,y)
      child:updateLayout(w-MARGIN*2, h-y-MARGIN)
      y = y+child.h
    end
    self:setSize(w,h)
  end
end

return Window
