local msgpack = require("MessagePack")
local net = require("protocol")
local Player = require("entities/Player")
local Event = require("entities/Event")
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

  self.entities = {} -- bound map entities, map of entity
  self.events_by_name = {} -- map of name => event entity
  self.vars = {} -- map of id (number)  => value (number)
  self.var_listeners = {} -- map of id (number) => map of callback
  self.bool_vars = {} -- map of id (number) => value (number)
  self.bool_var_listeners = {} -- map of id (number) => map of callback

  self:send(Client.makePacket(net.PROTOCOL, net)) -- send protocol

  local map = server:getMap(next(server.project.maps))
  print("map:", map.id)
  self:teleport(0,10*16)
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
          local ok = self.server:processCommand(self, args)
          if not ok then
            self:sendChatMessage("unknown command \""..args[1].."\"")
          end
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

function Client:sendChatMessage(msg)
  self:send(Client.makePacket(net.CHAT_MESSAGE_SERVER, msg))
end

function Client:onDisconnect()
  if self.map then
    self.map:removeEntity(self)
  end
end

-- overload
function Client:onMapChange()
  Player.onMapChange(self)

  if self.map then -- join map
    -- send map
    self:send(Client.makePacket(net.MAP, {map = self.map:serializeNet(self), id = self.id}))

    -- build events
    for _, event_data in ipairs(self.map.data.events) do
      self.map:addEntity(Event(self, event_data))
    end
  end
end

function Client:setVariable(vtype, id, value)
  if type(id) == "number" and type(value) == "number" then
    local vars = (vtype == "bool" and self.bool_vars or self.vars)
    local var_listeners = (vtype == "bool" and self.bool_var_listeners or self.var_listeners)

    vars[id] = value

    -- call listeners
    local listeners = var_listeners[id]
    if listeners then
      for callback in pairs(listeners) do
        callback(id, value)
      end
    end
  end
end

function Client:getVariable(vtype, id)
  local vars = (vtype == "bool" and self.bool_vars or self.vars)
  return vars[id] or 0
end

function Client:listenVariable(vtype, id, callback)
  local var_listeners = (vtype == "bool" and self.bool_var_listeners or self.var_listeners)

  local listeners = var_listeners[id]
  if not listeners then
    listeners = {}
    var_listeners[id] = listeners
  end

  listeners[callback] = true
end

function Client:unlistenVariable(vtype, id, callback)
  local var_listeners = (vtype == "bool" and self.bool_var_listeners or self.var_listeners)

  local listeners = var_listeners[id]
  if listeners then
    listeners[callback] = nil

    if not next(listeners) then
      var_listeners[id] = nil
    end
  end
end

return Client
