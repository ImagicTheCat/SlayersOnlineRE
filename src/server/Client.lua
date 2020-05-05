local msgpack = require("MessagePack")
local net = require("protocol")
local Player = require("entities.Player")
local Event = require("entities.Event")
local Mob = require("entities.Mob")
local utils = require("lib.utils")
local sha2 = require("sha2")
local client_version = require("client_version")
local Inventory = require("Inventory")
local XPtable = require("XPtable")
-- deferred require
local Map
task(0.01, function()
  Map = require("Map")
end)

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
  self.event_checks = {} -- map of event to check/update
  self.triggered_events = {} -- map of event => trigger condition
  -- self.running_event

  self.vars = {} -- map of id (number)  => value (number)
  self.var_listeners = {} -- map of id (number) => map of callback
  self.changed_vars = {} -- map of vars id
  self.bool_vars = {} -- map of id (number) => value (number)
  self.bool_var_listeners = {} -- map of id (number) => map of callback
  self.changed_bool_vars = {} -- map of bool vars id
  self.special_var_listeners = {} -- map of id (string) => map of callback
  self.timers = {0,0,0} -- %TimerX% vars (3), incremented every 30ms
  self.kill_player = 0
  self.visible = true
  self.draw_order = 0
  self.view_shift = {0,0}
  self.blocked = false
  self.blocked_skin = false
  self.blocked_attack = false
  self.blocked_defend = false
  self.blocked_cast = false
  self.blocked_chat = false
  self.strings = {"","",""} -- %StringX% vars (3)
  self.move_forward_input = false

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
        self:kick("Version du client incompatible avec le serveur, téléchargez la dernière version pour résoudre le problème.")
      end
    elseif self.valid and protocol == net.LOGIN then -- login
      if not self.user_id and type(data) == "table" and type(data.pseudo) == "string" and type(data.password) == "string" then
        async(function()
          local pass_hash = sha2.sha512("<server_salt>"..data.pseudo..data.password)

          local rows = self.server.db:query(q_login, {data.pseudo, pass_hash})
          if rows and rows[1] and not self.server.clients_by_id[tonumber(rows[1].id)] then
            local user_row = rows[1]

            self.user_id = tonumber(user_row.id) -- mark as logged
            self.server.clients_by_id[self.user_id] = self

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
            local map, x, y
            if state.location then
              map = self.server:getMap(state.location.map)
              x,y = state.location.x, state.location.y
            end

            if state.orientation then
              self:setOrientation(state.orientation)
            end

            ---- misc
            self.respawn_point = state.respawn_point

            -- default spawn
            if not map then
              local spawn_location = self.server.cfg.spawn_location
              map = self.server:getMap(spawn_location.map)
              x,y = spawn_location.cx*16, spawn_location.cy*16
            end

            map:addEntity(self)
            self:teleport(x,y)

            -- compute characteristics, send/init stats
            self:updateCharacteristics()

            self:setHealth(state.health or self.max_health)
            self:setMana(state.mana or self.max_mana)
            self:setXP(self.xp) -- update level/XP

            self:send(Client.makePacket(net.STATS_UPDATE, {
              gold = self.gold,
              alignment = self.alignment,
              name = self.pseudo,
              class = class_data.name,
              level = self.level,
              points = self.remaining_pts,
              reputation = self.reputation,
              mana = self.mana
            }))

            self:sendChatMessage("Identifié.")
          else -- login failed
            self:sendChatMessage("Identification échouée.")
            self:send(Client.makePacket(net.MOTD_LOGIN, self.server.motd)) -- send motd (start login)
          end
        end)
      end
    end
  else -- logged
    if protocol == net.INPUT_ORIENTATION then
      if self:canMove() then self:setOrientation(tonumber(data) or 0) end
    elseif protocol == net.INPUT_MOVE_FORWARD then
      -- update input state (used to stop/resume movements correctly)
      self.move_forward_input = not not data
      if self:canMove() then self:setMoveForward(self.move_forward_input) end
    elseif protocol == net.INPUT_ATTACK then
      if self:canAttack() then self:act("attack", 1) end
    elseif protocol == net.INPUT_DEFEND then
      if self:canDefend() then self:act("defend", 1) end
    elseif protocol == net.INPUT_INTERACT then
      if self:canInteract() then self:interact() end
    elseif protocol == net.INPUT_CHAT then
      if self:canChat() and type(data) == "string" and string.len(data) > 0 and string.len(data) < 1000 then
        if string.sub(data, 1, 1) == "/" then -- parse command
          local args = self.server.parseCommand(string.sub(data, 2))
          if #args > 0 then
            self.server:processCommand(self, args)
          end
        elseif not self.ghost then -- message
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
    elseif protocol == net.ITEM_USE then
      local id = tonumber(data) or 0
      if self:canUseItem() then self:useItem(id) end
    elseif protocol == net.ITEM_TRASH then
      local id = tonumber(data) or 0
      self.inventory:take(id)
    elseif protocol == net.SPEND_CHARACTERISTIC_POINT then
      if self.remaining_pts > 0 then
        local done = true
        if data == "strength" then
          self.strength_pts = self.strength_pts+1
          self:triggerSpecialVariable("Force")
        elseif data == "dexterity" then
          self.dexterity_pts = self.dexterity_pts+1
          self:triggerSpecialVariable("Dext")
        elseif data == "constitution" then
          self.constitution_pts = self.constitution_pts+1
          self:triggerSpecialVariable("Consti")
        else done = false end

        if done then
          self:setRemainingPoints(self.remaining_pts-1)
          self:updateCharacteristics()
        end
      end
    elseif protocol == net.ITEM_EQUIP then
      local id = tonumber(data) or 0
      local item = self.server.project.objects[id]
      if item and self:checkItemRequirements(item) and self.inventory:take(id,true) then
        local done = true
        if item.type == 1 then -- one-handed weapon
          if self.weapon_slot > 0 then self.inventory:put(self.weapon_slot) end
          self.weapon_slot = id
        elseif item.type == 2 then -- two-handed weapon
          if self.weapon_slot > 0 then self.inventory:put(self.weapon_slot) end
          if self.shield_slot > 0 then self.inventory:put(self.shield_slot) end
          self.weapon_slot = id
        elseif item.type == 3 then -- helmet
          if self.helmet_slot > 0 then self.inventory:put(self.helmet_slot) end
          self.helmet_slot = id
        elseif item.type == 4 then -- armor
          if self.armor_slot > 0 then self.inventory:put(self.armor_slot) end
          self.armor_slot = id
        elseif item.type == 5 then -- shield
          if self.shield_slot > 0 then self.inventory:put(self.shield_slot) end
          self.shield_slot = id
          -- check for two-handed weapon
          local weapon = self.server.project.objects[self.weapon_slot]
          if weapon and weapon.type == 2 then
            self.inventory:put(self.weapon_slot)
            self.weapon_slot = 0
          end
        else done = false end

        if done then
          self.inventory:take(id)
          self:updateCharacteristics()
        end
      end
    elseif protocol == net.SLOT_UNEQUIP then
      local done = true
      if data == "helmet" then
        if self.helmet_slot > 0 and self.inventory:put(self.helmet_slot) then
          self.helmet_slot = 0
        end
      elseif data == "armor" then
        if self.armor_slot > 0 and self.inventory:put(self.armor_slot) then
          self.armor_slot = 0
        end
      elseif data == "weapon" then
        if self.weapon_slot > 0 and self.inventory:put(self.weapon_slot) then
          self.weapon_slot = 0
        end
      elseif data == "shield" then
        if self.shield_slot > 0 and self.inventory:put(self.shield_slot) then
          self.shield_slot = 0
        end
      else done = false end

      if done then self:updateCharacteristics() end
    elseif protocol == net.SCROLL_END then
      local r = self.scroll_task
      if r then
        self.scroll_task = nil
        r()
      end
    elseif protocol == net.QUICK_ACTION_BIND then
      if type(data) == "table" and type(data.n) == "number" and data.n >= 1 and data.n <= 3 then
        local id = tonumber(data.id) or 0
        local ok = false
        if data.type == "item" then -- check item bind
          local item = self.server.project.objects[id]
          if item and item.type == 0 then ok = true end
        end
        if ok then
          self:applyConfig({quick_actions = {[data.n] = {type = data.type, id = id}}})
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

function Client:timerTick()
  if self.user_id then
    -- increment timers
    for i,time in ipairs(self.timers) do
      self.timers[i] = time+1
    end

    self:triggerSpecialVariable("Timer")
    self:triggerSpecialVariable("Timer2")
    self:triggerSpecialVariable("Timer3")

    -- reset last attacker
    self.last_attacker = nil
  end
end

-- event handling
function Client:eventTick()
  if self.map and not self.running_event then
    -- event checks (update event on page change)
    local event_checks = self.event_checks
    self.event_checks = {}
    for event in pairs(event_checks) do
      local page_index = event:selectPage()
      if page_index ~= event.page_index then -- reload event
        -- remove
        local map = event.map
        if map then
          map:removeEntity(event)
          -- re-create
          local nevent = Event(self, event.data, page_index)
          map:addEntity(nevent)
          nevent:teleport(event.x, event.y)
        end
      end
    end

    -- execute next visible/top-left event
    local events = {}
    local max_delta = Event.TRIGGER_RADIUS*16
    for event, condition in pairs(self.triggered_events) do
      if condition == Event.Condition.AUTO or condition == Event.Condition.AUTO_ONCE then
        local dx = math.abs(event.cx*16-(self.cx*16+self.view_shift[1]))
        local dy = math.abs(event.cy*16-(self.cy*16+self.view_shift[2]))
        if dx <= max_delta and dy <= max_delta then
          table.insert(events, event)
        end
      else
        table.insert(events, event)
      end
    end

    if #events > 0 then
      -- sort ascending top-left
      table.sort(events, function(a,b)
        return a.cx < b.cx or a.cx == b.cx and a.cy < b.cy
      end)

      -- stop movement
      self:setMoveForward(false)

      -- execute event
      local event = events[1]
      local condition = self.triggered_events[event]
      self.triggered_events[event] = nil
      self.running_event = event
      async(function()
        event:execute(condition)
        self.running_event = nil
        self:setMoveForward(self.move_forward_input) -- resume movement
      end)
    end
  end
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

-- (async) scroll client view to position
function Client:scrollTo(x,y)
  self.scroll_task = async()
  self:send(Client.makePacket(net.SCROLL_TO, {x,y}))
  self.scroll_task:wait()
end

function Client:resetScroll()
  self:send(Client.makePacket(net.SCROLL_RESET))
end

function Client:kick(reason)
  self:sendChatMessage("Kicked: "..reason)
  self.peer:disconnect_later()
end

function Client:onDisconnect()
  -- disconnect variable behavior
  local map_data = (self.map and self.map.data)
  if map_data and map_data.si_v >= 0 then
    if self:getVariable("var", map_data.si_v) >= map_data.v_c then
      self.server:setVariable(map_data.svar, map_data.sval)
    end
  end

  self:save()
  if self.map then
    self.map:removeEntity(self)
  end

  if self.user_id then
    self.server.clients_by_id[self.user_id] = nil
    self.user_id = nil
  end
end

-- override
function Client:onMapChange()
  Player.onMapChange(self)

  if self.map then -- join map
    self.prevent_next_contact = true -- prevent cell contact on map join

    -- send map
    self:send(Client.makePacket(net.MAP, {map = self.map:serializeNet(self), id = self.id}))

    -- build events
    for _, event_data in ipairs(self.map.data.events) do
      local event = Event(self, event_data)
      self.map:addEntity(event)
      event:teleport(event_data.x*16, event_data.y*16)
    end
  end
end

-- override
function Client:onCellChange()
  if self.map then
    self:triggerSpecialVariable("CaseX")
    self:triggerSpecialVariable("CaseY")
    self:triggerSpecialVariable("EvCaseX")
    self:triggerSpecialVariable("EvCaseY")

    local cell = self.map:getCell(self.cx, self.cy)
    if cell then
      -- event contact check
      if not self.ghost and not self.prevent_next_contact then
        for entity in pairs(cell) do
          if class.is(entity, Event) and entity.client == self and entity.trigger_contact then
            entity:trigger(Event.Condition.CONTACT)
          end
        end
      end
    end

    self.prevent_next_contact = nil
  end
end

function Client:interact()
  -- event interact check
  local entities = self:raycastEntities(2)

  for _, entity in ipairs(entities) do
    if class.is(entity, Event) and entity.client == self and entity.trigger_interact then
      entity:trigger(Event.Condition.INTERACT)
      break
    end
  end
end

-- consume owned usable item and apply effects
-- return true on success
function Client:useItem(id)
  local item = self.server.project.objects[id]
  if item and item.type == 0 and self.inventory:take(id) then
    self:setHealth(self.health+item.mod_hp)
    self:setMana(self.mana+item.mod_mp)
    self:act("use", 1)
    return true
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

-- update characteristics/gears based on gears/effects/etc
function Client:updateCharacteristics()
  local class_data = self.server.project.classes[self.class]

  self.strength = self.strength_pts+class_data.strength
  self.dexterity = self.dexterity_pts+class_data.dexterity
  self.constitution = self.constitution_pts+class_data.constitution
  self.magic = self.magic_pts+class_data.magic

  self.max_health = 0
  self.ch_defense = 0
  self.ch_attack = 0

  -- gears
  local helmet = self.server.project.objects[self.helmet_slot]
  local armor = self.server.project.objects[self.armor_slot]
  local weapon = self.server.project.objects[self.weapon_slot]
  local shield = self.server.project.objects[self.shield_slot]

  local gears = {weapon, shield, helmet, armor}
  for _, item in pairs(gears) do
    if item then
      self.strength = self.strength+item.mod_strength
      self.dexterity = self.dexterity+item.mod_dexterity
      self.constitution = self.constitution+item.mod_constitution
      self.magic = self.magic+item.mod_magic
      self.max_health = self.max_health+item.mod_hp
      self.max_mana = self.max_mana+item.mod_mp
      self.ch_defense = self.ch_defense+item.mod_defense
    end
  end

  self.ch_attack = math.floor((self.level*10+self.strength*2.48+self.dexterity*5)*class_data.off_index/10)
  self.ch_defense = self.ch_defense+math.floor((self.level*10+self.dexterity*2+self.constitution*5)*class_data.def_index/10)
  self.max_health = self.max_health+math.floor((self.level*20+self.strength*5+self.constitution*30)*class_data.health_index/10)
  self.min_damage = (weapon and weapon.mod_attack_a or 0)
  self.max_damage = (weapon and weapon.mod_attack_b or 0)+math.floor((self.level*20+self.strength*2+self.dexterity*1.5)*class_data.pow_index/10)

  -- update health/mana
  self:setHealth(self.health)
  self:setMana(self.mana)

  -- trigger vars
  self:triggerSpecialVariable("Attaque")
  self:triggerSpecialVariable("Defense")
  self:triggerSpecialVariable("VieMax")
  self:triggerSpecialVariable("MagMax")

  self:send(Client.makePacket(net.STATS_UPDATE, {
    strength = self.strength,
    dexterity = self.dexterity,
    constitution = self.constitution,
    magic = self.magic,
    attack = self.ch_attack,
    defense = self.ch_defense,
    helmet_slot = {name = helmet and helmet.name or ""},
    armor_slot = {name = armor and armor.name or ""},
    weapon_slot = {name = weapon and weapon.name or ""},
    shield_slot = {name = shield and shield.name or ""}
  }))
end

function Client:checkItemRequirements(item)
  return (item.usable_class == 0 or self.class == item.usable_class)
    and item.req_level <= self.level
    and item.req_strength <= self.strength
    and item.req_dexterity <= self.dexterity
    and item.req_constitution <= self.constitution
    and item.req_magic <= self.magic
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
      -- location
      if self.map.data.disconnect_respawn then
        local location = (self.respawn_point or self.server.cfg.spawn_location)
        state.location = {
          map = location.map,
          x = location.cx*16,
          y = location.cy*16
        }
      else
        state.location = {
          map = self.map.id,
          x = self.x,
          y = self.y
        }
      end

      state.orientation = self.orientation
    end

    state.charaset = self.charaset
    state.respawn_point = self.respawn_point
    state.health = self.health
    state.mana = self.mana

    self.server.db:_query(q_set_state, {self.user_id, utils.hex(msgpack.pack(state))})
  end
end

-- override
function Client:setHealth(health)
  Player.setHealth(self, health)
  self:triggerSpecialVariable("Vie")
  self:send(Client.makePacket(net.STATS_UPDATE, {health = self.health, max_health = self.max_health}))
end

-- override
function Client:setMana(mana)
  Player.setMana(self, mana)
  self:triggerSpecialVariable("CurrentMag")
  self:send(Client.makePacket(net.STATS_UPDATE, {mana = self.mana, max_mana = self.max_mana}))
end

function Client:setGold(gold)
  self.gold = math.max(0,gold)
  self:triggerSpecialVariable("Gold")
  self:send(Client.makePacket(net.STATS_UPDATE, {gold = self.gold}))
end

function Client:setXP(xp)
  self.xp = xp
  local current = XPtable[self.level]
  if self.xp < current then self.xp = current -- reset to current level XP
  else -- level ups
    local new_points = 0
    local next_xp = XPtable[self.level+1]
    while next_xp and self.xp >= next_xp do
      self.level = self.level+1 -- level up
      new_points = new_points+5
      next_xp = XPtable[self.level+1]
    end
    self:setRemainingPoints(self.remaining_pts+new_points)
  end

  self:triggerSpecialVariable("CurrentXP")
  self:triggerSpecialVariable("NextXP")

  self:send(Client.makePacket(net.STATS_UPDATE, {
    xp = self.xp,
    current_xp = XPtable[self.level] or 0,
    next_xp = XPtable[self.level+1] or self.xp,
    level = self.level
  }))

  self:updateCharacteristics()
end

function Client:setAlignment(alignment)
  self.alignment = utils.clamp(alignment, 0, 100)
  self:triggerSpecialVariable("Alignement")
  self:send(Client.makePacket(net.STATS_UPDATE, {alignment = self.alignment}))
end

function Client:setReputation(reputation)
  self.reputation = reputation
  self:triggerSpecialVariable("Reputation")
  self:send(Client.makePacket(net.STATS_UPDATE, {reputation = self.reputation}))
end

function Client:setRemainingPoints(remaining_pts)
  self.remaining_pts = math.max(0, remaining_pts)
  self:triggerSpecialVariable("LvlPoint")
  self:send(Client.makePacket(net.STATS_UPDATE, {points = self.remaining_pts}))
end

function Client:onPlayerKill()
  self.kill_player = 1
  self:triggerSpecialVariable("KillPlayer")
end

-- override
function Client:onDeath()
  -- XP loss (1%)
  if self.map and self.map.data.type == Map.Type.PVE or self.map.data.type == Map.Type.PVE_PVP then
    self:setXP(math.floor(self.xp*0.99))
  end

  if self.last_attacker then -- killed by player
    -- gold stealing (1%)
    local gold_amount = math.floor(self.gold*0.01)
    self.last_attacker:setGold(self.last_attacker.gold+gold_amount)
    self:setGold(self.gold-gold_amount)

    self.last_attacker:onPlayerKill()
  end

  -- set ghost
  self:setGhost(true)

  -- respawn after a while
  task(5, function() self:respawn() end)
end

function Client:respawn()
  if self.map then -- check if still on the world
    self:setGhost(false)
    self:setHealth(self.max_health) -- reset health

    -- respawn
    local respawned = false
    if self.respawn_point then -- res point respawn
      local map = self.server:getMap(self.respawn_point.map)
      if map then
        map:addEntity(self)
        self:teleport(self.respawn_point.cx*16, self.respawn_point.cy*16)
        respawned = true
      end
    end

    if not respawned then -- default respawn
      local spawn_location = self.server.cfg.spawn_location
      local map = self.server:getMap(spawn_location.map)
      if map then
        map:addEntity(self)
        self:teleport(spawn_location.cx*16, spawn_location.cy*16)
      end
    end
  end
end

-- restriction checks

function Client:canAttack()
  if self.map and self.map.data.type == Map.Type.SAFE then return false end
  return not self.running_event and not self.acting and not self.ghost
end

function Client:canDefend()
  if self.map and self.map.data.type == Map.Type.SAFE then return false end
  return not self.running_event and not self.acting and not self.ghost
end

function Client:canCast()
  if self.map and self.map.data.type == Map.Type.SAFE then return false end
  return not self.running_event and not self.ghost
end

function Client:canChat()
  return not self.running_event and not self.ghost
end

function Client:canMove()
  return not self.running_event
end

function Client:canInteract()
  return not self.running_event and not self.ghost
end

function Client:canUseItem()
  if self.map and self.map.data.type == Map.Type.PVP or self.map.data.type == Map.Type.PVP_NOREPUT then
    return false
  end
  return not self.running_event and not self.acting and not self.ghost and self.alignment > 20
end

-- variables

-- vtype: string, "bool" (boolean) or "var" (integer)
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

function Client:unlistenSpecialVariable(id, callback)
  local listeners = self.special_var_listeners[id]
  if listeners then
    listeners[callback] = nil

    if not next(listeners) then
      self.special_var_listeners[id] = nil
    end
  end
end

return Client
