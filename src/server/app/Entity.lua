-- https://github.com/ImagicTheCat/SlayersOnlineRE
-- MIT license (see LICENSE, src/server/main.lua or src/client/main.lua)

local net = require("app.protocol")

local Client
timer(0.001, function() -- deferred modules
  Client = require("app.Client")
end)

local Entity = class("Entity")

function Entity:__construct()
  -- .map: map
  -- .id: map id
  -- .nettype
  -- position in pixels (top-left origin, the entity body is a 16x16 cell)
  self.x = 0
  self.y = 0
  -- cell coords
  self.cx = 0
  self.cy = 0
  self.obstacle = false
  self:updateCell()
end

-- update cell coords and map space partitioning
function Entity:updateCell()
  local cx, cy = math.floor(self.x/16+0.5), math.floor(self.y/16+0.5)
  if cx ~= self.cx or cy ~= self.cy then
    if self.map then -- map cell reference update
      self.map:removeFromCell(self, self.cx, self.cy)
      self.map:addToCell(self, cx, cy)
    end
    -- update
    self.cx = cx
    self.cy = cy
    self:onCellChange()
  end
end

-- client: bound the entity to a specific client (nil to unbound)
-- should be called when the entity is not on a map
function Entity:setClient(client)
  if self.map then error("can't bind/unbind a client when the entity is on a map") end
  self.client = client
end

-- Check if the entity perceives the target's realm (Client binding).
-- The check is asymmetric. E.g. an Event can dodge a mob, but a mob can't
-- perceive the Event.
function Entity:perceivesRealm(entity)
  if xtype.is(self, Client) then return not entity.client or entity.client == self
  else -- not a client
    if self.client then -- bound
      if xtype.is(entity, Client) then return self.client == entity
      else return not entity.client or self.client == entity.client end
    else return not entity.client end -- unbound
  end
end

-- position in pixels
function Entity:teleport(x,y)
  self.x = x
  self.y = y
  self:broadcastPacket("teleport", {x,y})
  self:updateCell()
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
      self.client:sendPacket(net.ENTITY_PACKET, pdata)
    else -- global map
      self.map:broadcastPacket(net.ENTITY_PACKET, pdata)
    end
  end
end

-- called when the entity is added/removed to/from a map (after)
function Entity:onMapChange()
end

-- called when the entity cell changes
function Entity:onCellChange()
end

return Entity
