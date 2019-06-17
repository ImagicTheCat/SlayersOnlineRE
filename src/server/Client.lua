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
  self.special_var_listeners = {} -- map of id (string) => map of callback

  self:send(Client.makePacket(net.PROTOCOL, net)) -- send protocol

  -- testing
  local map = server:getMap(next(server.project.maps))
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
  elseif protocol == net.INPUT_INTERACT then
    self:interact()
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
  elseif protocol == net.EVENT_MESSAGE_SKIP then
    if self.event_message_r then self.event_message_r() end
  elseif protocol == net.EVENT_INPUT_QUERY_ANSWER then
    if self.input_query_r and type(data) == "string" then
      self.input_query_r(data)
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

-- (async) trigger event message box
-- return when the message is skipped by the client
function Client:sendEventMessage(msg)
  self.event_message_r = async()
  self:send(Client.makePacket(net.EVENT_MESSAGE, msg))
  self.event_message_r:wait()
end

function Client:sendInputQuery(title, options)
  self.input_query_r = async()
  self:send(Client.makePacket(net.EVENT_INPUT_QUERY, {title = title, options = options}))
  return self.input_query_r:wait()
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

-- overload
function Client:onCellChange()
  if self.map then
    local cell = self.map:getCell(self.cx, self.cy)
    if cell then
      -- event contact check
      for entity in pairs(cell) do
        if class.is(entity, Event) and entity.client == self and entity.trigger_contact then
          async(function()
            entity:trigger(Event.Condition.CONTACT)
          end)
        end
      end
    end
  end
end

-- overload
function Client:attack()
  Player.attack(self)

  -- event attack check
  local entities = self:raycastEntities(1)
  for _, entity in ipairs(entities) do
    if class.is(entity, Event) and entity.client == self and entity.trigger_attack then
      async(function()
        entity:trigger(Event.Condition.ATTACK)
      end)
    end
  end
end

function Client:interact()
  -- event interact check
  local entities = self:raycastEntities(2)

  for _, entity in ipairs(entities) do
    if class.is(entity, Event) and entity.client == self and entity.trigger_interact then
      async(function()
        entity:trigger(Event.Condition.INTERACT)
      end)
    end
  end
end

-- variables

function Client:setVariable(vtype, id, value)
  if type(id) == "number" and type(value) == "number" then
    local vars = (vtype == "bool" and self.bool_vars or self.vars)
    local var_listeners = (vtype == "bool" and self.bool_var_listeners or self.var_listeners)

    vars[id] = value

    -- call listeners
    local listeners = var_listeners[id]
    if listeners then
      for callback in pairs(listeners) do
        callback()
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

-- special variables

-- trigger change event
function Client:triggerSpecialVariable(id)
  -- call listeners
  local listeners = self.special_var_listeners[id]
  if listeners then
    for callback in pairs(listeners) do
      callback()
    end
  end
end

function Client:listenSpecialVariable(id, callback)
  local listeners = self.special_var_listeners[id]
  if not listeners then
    listeners = {}
    self.special_var_listeners[id] = listeners
  end

  listeners[callback] = true
end

function Client:unlistenSpecialVariable(vtype, id, callback)
  local listeners = self.special_var_listeners[id]
  if listeners then
    listeners[callback] = nil

    if not next(listeners) then
      self.special_var_listeners[id] = nil
    end
  end
end

return Client
