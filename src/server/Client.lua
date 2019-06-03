local msgpack = require("MessagePack")
local net = require("protocol")
local LivingEntity = require("entities/LivingEntity")

-- server-side client
local Client = class("Client", LivingEntity)

-- STATICS

function Client.makePacket(protocol, data)
  return msgpack.pack({protocol, data})
end

-- METHODS

function Client:__construct(server, peer)
  LivingEntity.__construct(self)

  self.server = server
  self.peer = peer

  self:send(Client.makePacket(net.PROTOCOL, net)) -- send protocol

  local map = server:getMap("test")
  self.x = math.random(1,100)
  self.y = math.random(1,100)
  map:addEntity(self)
end

function Client:onPacket(protocol, data)
  if protocol == net.INPUT_ORIENTATION then
    self:setOrientation(tonumber(data) or 0)
  end

  if protocol == net.INPUT_MOVE_FORWARD then
    self:setMoveForward(not not data)
  end
end

-- unsequenced: unsequenced and unreliable if true/passed, reliable otherwise
function Client:send(packet, unsequenced)
  self.peer:send(packet, 0, (unsequenced and "unsequenced" or "reliable"))
end

function Client:onDisconnect()
  if self.map then
    self.map:removeEntity(self)
  end
end

-- overload
function Client:onMapChange()
  LivingEntity.onMapChange(self)

  if self.map then
    self:send(Client.makePacket(net.MAP, {map = self.map:serializeNet(), id = self.id}))
  end
end

return Client
