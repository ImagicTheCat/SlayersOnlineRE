
local Entity = class("Entity")

function Entity:__construct()
  -- .map: map
  -- .id: map id
  -- .nettype

  -- position in pixels
  self.x = 0
  self.y = 0
end

-- should return a net data table
function Entity:serializeNet()
  return {
    nettype = self.nettype,
    id = self.id,
    x = self.x,
    y = self.y
  }
end

-- called when the entity is added/removed to/from a map (after)
function Entity:onMapChange()
end

return Entity
