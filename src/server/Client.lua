local msgpack = require("MessagePack")
local net = require("protocol")
local Entity = require("Entity")

-- server-side client
local Client = class("Client", Entity)

-- STATICS

function Client.makePacket(protocol, data)
  return msgpack.pack({protocol, data})
end

-- METHODS

function Client:__construct(server, peer)
  Entity.__construct(self)

  self.server = server
  self.peer = peer

  self:send(Client.makePacket(net.PROTOCOL, net)) -- send protocol
end

function Client:onPacket(protocol, data)
end

-- unsequenced: unsequenced and unreliable if true/passed, reliable otherwise
function Client:send(packet, unsequenced)
  self.peer:send(packet, 0, (unsequenced and "unsequenced" or "reliable"))
end

function Client:onDisconnect()
end

-- overload
function Client:onMapChange()
  if self.map then
    self:send(Client.makePacket(net.MAP), self.map:serializeNet())
  end
end

return Client
