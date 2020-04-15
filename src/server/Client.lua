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

local q_login = "SELECT * FROM users WHERE pseudo = {1} AND password = UNHEX({2})"
local q_get_vars = "SELECT id,value FROM users_vars WHERE user_id = {1}"
local q_get_bool_vars = "SELECT id,value FROM users_bool_vars WHERE user_id = {1}"
local q_set_var = "INSERT INTO users_vars(user_id, id, value) VALUES({1},{2},{3}) ON DUPLICATE KEY UPDATE value = {3}"
local q_set_bool_var = "INSERT INTO users_bool_vars(user_id, id, value) VALUES({1},{2},{3}) ON DUPLICATE KEY UPDATE value = {3}"
local q_set_config = "UPDATE users SET config = UNHEX({2}) WHERE id = {1}"
local q_set_state = "UPDATE users SET state = UNHEX({2}) WHERE id = {1}"
local q_set_data = [[UPDATE users SET
level = {level},
alignment = {alignment},
reputation = {reputation},
gold = {gold},
chest_gold = {chest_gold},
xp = {xp},
strength_pts = {strength_pts},
dexterity_pts = {dexterity_pts},
constitution_pts = {constitution_pts},
magic_pts = {magic_pts},
remaining_pts = {remaining_pts},
weapon_slot = {weapon_slot},
shield_slot = {shield_slot},
helmet_slot = {helmet_slot},
armor_slot = {armor_slot}
WHERE id = {user_id}]]

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
            self.class = tonumber(user_row.class)
            self.level = tonumber(user_row.level)
            self.alignment = tonumber(user_row.alignment)
            self.reputation = tonumber(user_row.reputation)
            self.gold = tonumber(user_row.gold)
            self.chest_gold = tonumber(user_row.chest_gold)
            self.xp = tonumber(user_row.xp)
            self.strength_pts = tonumber(user_row.strength_pts)
            self.dexterity_pts = tonumber(user_row.dexterity_pts)
            self.constitution_pts = tonumber(user_row.constitution_pts)
            self.magic_pts = tonumber(user_row.magic_pts)
            self.remaining_pts = tonumber(user_row.remaining_pts)
            self.weapon_slot = tonumber(user_row.weapon_slot)
            self.shield_slot = tonumber(user_row.shield_slot)
            self.helmet_slot = tonumber(user_row.helmet_slot)
            self.armor_slot = tonumber(user_row.armor_slot)

            local class_data = self.server.project.classes[self.class]
            self:setSounds(string.sub(class_data.attack_sound, 7), string.sub(class_data.hurt_sound, 7))

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

            ---- on chest item update
            function self.chest_inventory.onItemUpdate(inv, id)
              if not self.chest_task then return end -- chest isn't open

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
              self:send(Client.makePacket(net.CHEST_UPDATE_ITEMS, {{id,data}}))
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

            ---- misc
            self.res_point = state.res_point

            -- testing spawn
            if not map then
              map = self.server:getMap(next(self.server.project.maps))
              self:teleport(0,10*16)
            end

            map:addEntity(self)

            -- compute characteristics, send/init stats
            self:updateCharacteristics()

            self:send(Client.makePacket(net.STATS_UPDATE, {
              gold = self.gold,
              alignment = self.alignment,
              name = self.pseudo,
              class = class_data.name,
              level = self.level,
              points = self.remaining_pts,
              reputation = self.reputation,
              xp = self.xp,
              max_xp = self.xp*2
            }))

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
      local r = self.message_task
      if r then
        self.message_task = nil
        r()
      end
    elseif protocol == net.EVENT_INPUT_QUERY_ANSWER then
      local r = self.input_query_task
      if r and type(data) == "number" then
        self.input_query_task = nil
        r(data)
      end
    elseif protocol == net.EVENT_INPUT_STRING_ANSWER then
      local r = self.input_string_task
      if r and type(data) == "string" then
        self.input_string_task = nil
        r(data)
      end
    elseif protocol == net.CHEST_CLOSE then
      local r = self.chest_task
      if r then
        self.chest_task = nil
        r()
      end
    elseif protocol == net.SHOP_CLOSE then
      local r = self.shop_task
      if r then
        self.shop_task = nil
        r()
      end
    elseif protocol == net.GOLD_STORE then
      local amount = tonumber(data) or 0
      if self.chest_task and amount <= self.gold then
        self.chest_gold = self.chest_gold+amount
        self.gold = self.gold-amount
        self:send(Client.makePacket(net.STATS_UPDATE, {gold = self.gold, chest_gold = self.chest_gold}))
      end
    elseif protocol == net.GOLD_WITHDRAW then
      local amount = tonumber(data) or 0
      if self.chest_task and amount <= self.chest_gold then
        self.chest_gold = self.chest_gold-amount
        self.gold = self.gold+amount
        self:send(Client.makePacket(net.STATS_UPDATE, {gold = self.gold, chest_gold = self.chest_gold}))
      end
    elseif protocol == net.ITEM_STORE then
      local id = tonumber(data) or 0
      if self.chest_task and self.inventory:take(id, true) and self.chest_inventory:put(id) then
        self.inventory:take(id)
      end
    elseif protocol == net.ITEM_WITHDRAW then
      local id = tonumber(data) or 0
      if self.chest_task and self.chest_inventory:take(id, true) and self.inventory:put(id) then
        self.chest_inventory:take(id)
      end
    elseif protocol == net.ITEM_BUY then
      if self.shop_task and type(data) == "table" then
        local id, amount = tonumber(data[1]) or 0, tonumber(data[2]) or 0
        local item = self.server.project.objects[id]
        if item and amount > 0 then
          if item.price*amount <= self.gold then
            for i=1,amount do -- buy one by one
              if self.inventory:put(id) then
                self.gold = self.gold-item.price
              else break end
            end
            self:send(Client.makePacket(net.STATS_UPDATE, {gold = self.gold}))
          end
        end
      end
    elseif protocol == net.ITEM_SELL then
      local id = tonumber(data) or 0
      local item = self.server.project.objects[id]
      if self.shop_task and item then
        if self.inventory:take(id) then
          self.gold = self.gold+math.ceil(item.price*0.1)
          self:send(Client.makePacket(net.STATS_UPDATE, {gold = self.gold}))
        end
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
  self.message_task = async()
  self:send(Client.makePacket(net.EVENT_MESSAGE, msg))
  self.message_task:wait()
end

-- (async)
-- return option index (may be invalid)
function Client:requestInputQuery(title, options)
  self.input_query_task = async()
  self:send(Client.makePacket(net.EVENT_INPUT_QUERY, {title = title, options = options}))
  return self.input_query_task:wait()
end

function Client:requestInputString(title)
  self.input_string_task = async()
  self:send(Client.makePacket(net.EVENT_INPUT_STRING, {title = title}))
  return self.input_string_task:wait()
end

-- (async) open chest GUI
function Client:openChest(title)
  self.chest_task = async()
  -- send init items
  local objects = self.server.project.objects
  local items = {}
  for id, amount in pairs(self.chest_inventory.items) do
    local object = objects[id]
    if object then
      table.insert(items, {id, {
        amount = amount,
        name = object.name,
        description = object.description
      }})
    end
  end
  self:send(Client.makePacket(net.CHEST_OPEN, {title, items}))
  self:send(Client.makePacket(net.STATS_UPDATE, {chest_gold = self.chest_gold}))

  self.chest_task:wait()
end

-- (async) open shop GUI
-- items: list of item ids to buy from the shop
function Client:openShop(title, items)
  self.shop_task = async()

  local objects = self.server.project.objects

  local buy_items = {}
  for _, id in ipairs(items) do
    local object = objects[id]
    if object then
      table.insert(buy_items, {
        id = id,
        name = object.name,
        description = object.description,
        price = object.price
      })
    end
  end

  local sell_items = {}
  for id, amount in pairs(self.inventory.items) do
    local object = objects[id]
    if object then
      table.insert(sell_items, {
        id = id,
        name = object.name,
        amount = amount,
        description = object.description,
        price = object.price
      })
    end
  end

  self:send(Client.makePacket(net.SHOP_OPEN, {title, buy_items, sell_items}))

  self.shop_task:wait()
end

function Client:kick(reason)
  self:sendChatMessage("Kicked: "..reason)
  self.peer:disconnect_later()
end

function Client:onDisconnect()
  self:save()
  if self.map then
    self.map:removeEntity(self)
  end
  self.user_id = nil
end

-- override
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

-- override
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

function Client:playMusic(path)
  self:send(Client.makePacket(net.PLAY_MUSIC, path))
end

function Client:stopMusic()
  self:send(Client.makePacket(net.STOP_MUSIC))
end

function Client:playSound(path)
  self:send(Client.makePacket(net.PLAY_SOUND, path))
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

-- update characteristics based on gears/effects/etc
function Client:updateCharacteristics()
  local class_data = self.server.project.classes[self.class]

  self.strength = self.strength_pts+class_data.strength
  self.dexterity = self.dexterity_pts+class_data.dexterity
  self.constitution = self.constitution_pts+class_data.constitution
  self.magic = self.magic_pts+class_data.magic
  self.max_health = 100
  self.max_mana = 100
  self.ch_attack = 100
  self.ch_defense = 100

  -- gears
  local gears = {self.weapon_slot, self.shield_slot, self.helmet_slot, self.armor_slot}
  for _, slot in ipairs(gears) do
    local object = self.server.project.objects[slot]
    if object then
      self.strength = self.strength+object.mod_strength
      self.dexterity = self.dexterity+object.mod_dexterity
      self.constitution = self.constitution+object.mod_constitution
      self.magic = self.magic+object.mod_magic
      self.max_health = self.max_health+object.mod_hp
      self.max_mana = self.max_mana+object.mod_mp
      self.ch_defense = self.ch_defense+object.mod_defense
    end
  end

  -- clamp
  self.health = math.min(self.health, self.max_health)
  self.mana = math.min(self.mana, self.max_mana)

  self:send(Client.makePacket(net.STATS_UPDATE, {
    health = self.health,
    max_health = self.max_health,
    mana = self.mana,
    max_mana = self.max_mana,
    strength = self.strength,
    dexterity = self.dexterity,
    constitution = self.constitution,
    magic = self.magic,
    attack = self.ch_attack,
    defense = self.ch_defense
  }))
end

function Client:save()
  if self.user_id then
    -- base data
    self.server.db:_query(q_set_data, {
      user_id = self.user_id,

      level = self.level,
      alignment = self.alignment,
      reputation = self.reputation,
      gold = self.gold,
      chest_gold = self.chest_gold,
      xp = self.xp,
      strength_pts = self.strength_pts,
      dexterity_pts = self.dexterity_pts,
      constitution_pts = self.constitution_pts,
      magic_pts = self.magic_pts,
      remaining_pts = self.remaining_pts,
      weapon_slot = self.weapon_slot,
      shield_slot = self.shield_slot,
      helmet_slot = self.helmet_slot,
      armor_slot = self.armor_slot
    })

    -- vars
    for var in pairs(self.changed_vars) do
      self.server.db:_query(q_set_var, {self.user_id, var, self.vars[var]})
    end
    self.changed_vars = {}

    -- bool vars
    for var in pairs(self.changed_bool_vars) do
      self.server.db:_query(q_set_bool_var, {self.user_id, var, self.bool_vars[var]})
    end
    self.changed_bool_vars = {}

    -- inventories
    self.inventory:save(self.server.db)
    self.chest_inventory:save(self.server.db)

    -- config
    if self.player_config_changed then
      self.server.db:_query(q_set_config, {self.user_id, utils.hex(msgpack.pack(self.player_config))})
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
    state.res_point = self.res_point

    self.server.db:_query(q_set_state, {self.user_id, utils.hex(msgpack.pack(state))})
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
