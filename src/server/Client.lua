local msgpack = require("MessagePack")
local net = require("protocol")

-- server-side client
local Client = class("Client")

function Client:__construct(server, peer)
  self.server = server
  self.peer = peer

  self:sendPacket(net.PROTOCOL, net) -- send protocol
end

function Client:onPacket(protocol, data)
end

-- unsequenced: unsequenced and unreliable if true/passed, reliable otherwise
function Client:sendPacket(protocol, data, unsequenced)
  self.peer:send(msgpack.pack({protocol, data}), 0, (unsequenced and "unsequenced" or "reliable"))
end

function Client:onDisconnect()
end

return Client
