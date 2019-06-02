local net = require("protocol")

local Entity = class("Entity")

function Entity:__construct()
  -- .map: map
  -- .id: map id
  -- .nettype

  -- position in pixels
  self.x = 0
  self.y = 0
end

function Entity:teleport(x,y)
  self.x = x
  self.y = y

  self:broadcastPacket("teleport", {x,y})
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

-- broadcast entity packet
-- action: identifier
function Entity:broadcastPacket(action, data)
  if self.map then
    self.map:broadcastPacket(net.ENTITY_PACKET, {id = self.id, act = action, data = data})
  end
end

-- called when the entity is added/removed to/from a map (after)
function Entity:onMapChange()
end

return Entity
