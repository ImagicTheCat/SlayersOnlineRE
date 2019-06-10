local net = require("protocol")

local Client
task(0.001, function() -- deferred modules
  Client = require("Client")
end)

---task(0.001, function() -- deferred
--end)

local Entity = class("Entity")

function Entity:__construct()
  -- .map: map
  -- .id: map id
  -- .nettype

  -- position in pixels
  self.x = 0
  self.y = 0
end

-- client: bound the entity to a specific client (nil to unbound)
-- should be called when the entity is not on a map
function Entity:setClient(client)
  if self.map then error("can't bind/unbind a client when the entity is on a map") end

  self.client = client
end

-- position in pixels
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
    local pdata = {id = self.id, act = action, data = data}

    if self.client then -- bound to client
      client:send(Client.makePacket(net.ENTITY_PACKET, pdata))
    else -- global map
      self.map:broadcastPacket(net.ENTITY_PACKET, pdata)
    end
  end
end

-- called when the entity is added/removed to/from a map (after)
function Entity:onMapChange()
end

return Entity
