local Entity = require("Entity")

local Event = class("Event", Entity)

-- STATICS

Event.Position = {
  DYNAMIC = 0,
  FRONT = 1,
  BACK = 2
}

Event.Animation = {
  STATIC = 0,
  STATIC_CHARACTER = 1,
  CHARACTER_RANDOM = 2,
  VISUAL_EFFECT = 3,
  CHARACTER_FOLLOW = 4
}

-- METHODS

function Event:__construct(client, data, page_index)
  Entity.__construct(self)

  self:setClient(client)
  self.data = data -- event data
  self.page = self.data.pages[page_index or self:selectPage()]

  -- TODO: listen to conditions of all previous and current page

--  self.nettype = "Event"
end

-- check if the page conditions are valid
-- return bool
function Event:checkConditions(page)
  -- TODO
  return true
end

-- search for a valid page
-- return page index
function Event:selectPage()
  for i, page in ipairs(self.data.pages) do
    if self:checkConditions(page) then
      return i
    end

    return #self.data.pages
  end
end

-- overload
function Event:serializeNet()
  local data = Entity.serializeNet(self)

  return data
end

-- overload
function Event:onMapChange()
  if not self.map then -- removed from map
    -- TODO: unlisten to conditions of all previous and current page
  end
end

return Event
