local msgpack = require("MessagePack")
local net = require("protocol")
local Player = require("entities.Player")
local Event = require("entities.Event")
local Mob = require("entities.Mob")
local utils = require("lib.utils")
local sha2 = require("sha2")
local client_version = require("client_version")
local Inventory = require("Inventory")

-- server-side client
local Client = class("Client", Player)

-- PRIVATE STATICS

local q_login = "SELECT id, pseudo, config, state FROM users WHERE pseudo = {1} AND password = UNHEX({2})"
local q_get_vars = "SELECT id,value FROM users_vars WHERE user_id = {1}"
local q_get_bool_vars = "SELECT id,value FROM users_bool_vars WHERE user_id = {1}"
local q_set_var = "INSERT INTO users_vars(user_id, id, value) VALUES({1},{2},{3}) ON DUPLICATE KEY UPDATE value = {3}"
local q_set_bool_var = "INSERT INTO users_bool_vars(user_id, id, value) VALUES({1},{2},{3}) ON DUPLICATE KEY UPDATE value = {3}"
local q_set_config = "UPDATE users SET config = UNHEX({2}) WHERE id = {1}"
local q_set_state = "UPDATE users SET state = UNHEX({2}) WHERE id = {1}"

-- STATICS

function Client.makePacket(protocol, data)
  return msgpack.pack({protocol, data})
end

-- METHODS

function Client:__construct(server, peer)
  Player.__construct(self)
  self.nettype = "Player"

  self.server = server
  self.peer = peer
  self.valid = false

  self.entities = {} -- bound map entities, map of entity
  self.events_by_name = {} -- map of name => event entity
  self.event_queue = {} -- waiting event triggers, queue of callbacks

  self.vars = {} -- map of id (number)  => value (number)
  self.var_listeners = {} -- map of id (number) => map of callback
  self.changed_vars = {} -- map of vars id
  self.bool_vars = {} -- map of id (number) => value (number)
  self.bool_var_listeners = {} -- map of id (number) => map of callback
  self.changed_bool_vars = {} -- map of bool vars id
  self.special_var_listeners = {} -- map of id (string) => map of callback

  self.player_config = {} -- stored player config
  self.player_config_changed = false

  self:send(Client.makePacket(net.PROTOCOL, net)) -- send protocol
end

function Client:onPacket(protocol, data)
  -- not logged
  if not self.user_id then
    if not self.valid and protocol == net.VERSION_CHECK then -- check client version
      if type(data) == "string" and data == client_version then
        self.valid = true
        self:send(Client.makePacket(net.MOTD_LOGIN, self.server.motd)) -- send motd (start login)
      else
        self:kick("server/client version mismatch, download the latest client release to fix the issue")
      end
    elseif self.valid and protocol == net.LOGIN then -- login
      if type(data) == "table" and type(data.pseudo) == "string" and type(data.password) == "string" then
        async(function()
          local pass_hash = sha2.sha512("<server_salt>"..data.pseudo..data.password)

          local rows = self.server.db:query(q_login, {data.pseudo, pass_hash})
          if rows and rows[1] then
            local user_row = rows[1]

            self.user_id = tonumber(user_row.id) -- mark as logged

            -- load user data
            self.pseudo = user_row.pseudo

            --- config
            self:applyConfig(user_row.config and msgpack.unpack(user_row.config) or {}, true)

            --- vars
            local rows = self.server.db:query(q_get_vars, {self.user_id})
            if rows then
              for i,row in ipairs(rows) do
                self.vars[tonumber(row.id)] = tonumber(row.value)
              end
            end

            rows = self.server.db:query(q_get_bool_vars, {self.user_id})
            if rows then
              for i,row in ipairs(rows) do
                self.bool_vars[tonumber(row.id)] = tonumber(row.value)
              end
            end

            --- inventories
            self.inventory = Inventory(self.user_id, 1, 100)
            self.chest_inventory = Inventory(self.user_id, 2, 1000)
            self.inventory:load(self.server.db)
            self.chest_inventory:load(self.server.db)

            ---- on item update
            function self.inventory.onItemUpdate(inv, id)
              local data
              local amount = inv.items[id]
              local object = self.server.project.objects[id]
              if object and inv.items[id] then
                data = {
                  amount = inv.items[id],
                  name = object.name,
                  description = object.description
                }
              end
              self:send(Client.makePacket(net.INVENTORY_UPDATE_ITEMS, {{id,data}}))
            end

            ---- send inventory init items
            do
              local objects = self.server.project.objects
              local items = {}
              for id, amount in pairs(self.inventory.items) do
                local object = objects[id]
                if object then
                  table.insert(items, {id, {
                    amount = amount,
                    name = object.name,
                    description = object.description
                  }})
                end
              end

              self:send(Client.makePacket(net.INVENTORY_UPDATE_ITEMS, items))
            end

            --- state
            local state = user_row.state and msgpack.unpack(user_row.state) or {}

            ---- charaset
            if state.charaset then
              self:setCharaset(state.charaset)
            end

            ---- location
            local map
            if state.location then
              map = self.server:getMap(state.location.map)
              self:teleport(state.location.x, state.location.y)
            end

            if state.orientation then
              self:setOrientation(state.orientation)
            end

            -- testing spawn
            if not map then
              map = self.server:getMap(next(self.server.project.maps))
              self:teleport(0,10*16)
            end

            map:addEntity(self)

            self:sendChatMessage("Logged in.")
          else -- login failed
            self:sendChatMessage("Login failed.")
            self:send(Client.makePacket(net.MOTD_LOGIN, self.server.motd)) -- send motd (start login)
          end
        end)
      end
    end
  else -- logged
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
          local args = self.server.parseCommand(string.sub(data, 2))
          if #args > 0 then
            self.server:processCommand(self, args)
          end
        else -- message
          self:mapChat(data)
        end
      end
    elseif protocol == net.EVENT_MESSAGE_SKIP then
      if self.message_r then self.message_r() end
    elseif protocol == net.EVENT_INPUT_QUERY_ANSWER then
      local r = self.input_query_r
      if r and type(data) == "number" then
        self.input_query_r = nil
        r(data)
      end
    elseif protocol == net.EVENT_INPUT_STRING_ANSWER then
      local r = self.input_string_r
      if r and type(data) == "string" then
        self.input_string_r = nil
        r(data)
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

-- (async) trigger event message box
-- return when the message is skipped by the client
function Client:requestMessage(msg)
  self.message_r = async()
  self:send(Client.makePacket(net.EVENT_MESSAGE, msg))
  self.message_r:wait()
end

-- (async)
-- return option index (may be invalid)
function Client:requestInputQuery(title, options)
  self.input_query_r = async()
  self:send(Client.makePacket(net.EVENT_INPUT_QUERY, {title = title, options = options}))
  return self.input_query_r:wait()
end

function Client:requestInputString(title)
  self.input_string_r = async()
  self:send(Client.makePacket(net.EVENT_INPUT_STRING, {title = title}))
  return self.input_string_r:wait()
end

function Client:kick(reason)
  self:sendChatMessage("Kicked: "..reason)
  self.peer:disconnect_later()
end

-- (async)
function Client:onDisconnect()
  self:save()

  if self.map then
    self.map:removeEntity(self)
  end

  self.user_id = nil
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

function Client:isRunningEvent()
  return self.event_queue[1] ~= nil
end

function Client:interact()
  -- event interact check
  local entities = self:raycastEntities(2)

  for _, entity in ipairs(entities) do
    if class.is(entity, Event) and entity.client == self and entity.trigger_interact then
      async(function()
        entity:trigger(Event.Condition.INTERACT)
      end)

      break
    end
  end
end

-- modify player config
-- no_save: if passed/true, will not trigger a DB save
function Client:applyConfig(config, no_save)
  utils.mergeInto(config, self.player_config)
  if not no_save then
    self.player_config_changed = true
  end
  self:send(Client.makePacket(net.PLAYER_CONFIG, config))
end

-- (async) save check
function Client:save()
  if self.user_id then
    -- vars
    for var in pairs(self.changed_vars) do
      self.server.db:query(q_set_var, {self.user_id, var, self.vars[var]})
    end
    self.changed_vars = {}

    -- bool vars
    for var in pairs(self.changed_bool_vars) do
      self.server.db:query(q_set_bool_var, {self.user_id, var, self.bool_vars[var]})
    end
    self.changed_bool_vars = {}

    -- inventories
    self.inventory:save(self.server.db)
    self.chest_inventory:save(self.server.db)

    -- config
    if self.player_config_changed then
      self.server.db:query(q_set_config, {self.user_id, utils.hex(msgpack.pack(self.player_config))})
      self.player_config_changed = false
    end

    -- state
    local state = {}
    if self.map then
      state.location = {
        map = self.map.id,
        x = self.x,
        y = self.y
      }

      state.orientation = self.orientation
    end

    state.charaset = self.charaset
    self.server.db:query(q_set_state, {self.user_id, utils.hex(msgpack.pack(state))})
  end
end

-- variables

function Client:setVariable(vtype, id, value)
  if type(id) == "number" and type(value) == "number" then
    local vars = (vtype == "bool" and self.bool_vars or self.vars)
    local var_listeners = (vtype == "bool" and self.bool_var_listeners or self.var_listeners)
    local changed_vars = (vtype == "bool" and self.changed_bool_vars or self.changed_vars)

    vars[id] = value
    changed_vars[id] = true

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
