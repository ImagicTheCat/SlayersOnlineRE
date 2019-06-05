local msgpack = require("MessagePack")
local net = require("protocol")
local Player = require("entities/Player")
local utils = require("lib/utils")

-- server-side client
local Client = class("Client", Player)

-- STATICS

function Client.makePacket(protocol, data)
  return msgpack.pack({protocol, data})
end

-- METHODS

function Client:__construct(server, peer)
  Player.__construct(self)

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
  elseif protocol == net.INPUT_MOVE_FORWARD then
    self:setMoveForward(not not data)
  elseif protocol == net.INPUT_ATTACK then
    self:attack()
  elseif protocol == net.INPUT_CHAT then
    if type(data) == "string" and string.len(data) > 0 and string.len(data) < 1000 then
      if string.sub(data, 1, 1) == "/" then -- parse command
        local args = utils.split(string.sub(data, 2), " ")
        if #args > 0 then
          self.server:processCommand(self, args)
        end
      else -- message
        self:mapChat(data)
      end
    end
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
  Player.onMapChange(self)

  if self.map then
    self:send(Client.makePacket(net.MAP, {map = self.map:serializeNet(), id = self.id}))
  end
end

return Client
