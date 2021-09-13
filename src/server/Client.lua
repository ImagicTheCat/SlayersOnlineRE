local msgpack = require("MessagePack")
local net = require("protocol")
local Quota = require("Quota")
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
local q_set_data = [[
  UPDATE users SET
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
  WHERE id = {user_id}
]]
local q_prune_skins = [[
  DELETE users_skins FROM users_skins
  INNER JOIN users AS sharer ON users_skins.shared_by = sharer.id
  INNER JOIN users AS self ON users_skins.user_id = self.id
  WHERE users_skins.user_id = {1} AND self.guild != sharer.guild
]]
local q_get_skins = "SELECT name FROM users_skins WHERE user_id = {1}"

-- STATICS

function Client.makePacket(protocol, data)
  return msgpack.pack({protocol, data})
end

-- serialize inventory item data
function Client.serializeItem(server, item, amount)
  local data = {
    amount = amount,
    name = item.name,
    description = item.description,
    req_level = (item.req_level > 0 and item.req_level or nil),
    req_strength = (item.req_strength > 0 and item.req_strength or nil),
    req_dexterity = (item.req_dexterity > 0 and item.req_dexterity or nil),
    req_constitution = (item.req_constitution > 0 and item.req_constitution or nil),
    req_magic = (item.req_magic > 0 and item.req_magic or nil),
    mod_strength = (item.mod_strength ~= 0 and item.mod_strength or nil),
    mod_dexterity = (item.mod_dexterity ~= 0 and item.mod_dexterity or nil),
    mod_constitution = (item.mod_constitution ~= 0 and item.mod_constitution or nil),
    mod_magic = (item.mod_magic ~= 0 and item.mod_magic or nil),
    mod_defense = (item.mod_defense ~= 0 and item.mod_defense or nil),
    mod_hp = (item.mod_hp ~= 0 and item.mod_hp or nil),
    mod_mp = (item.mod_mp ~= 0 and item.mod_mp or nil),
    mod_attack_a = (item.mod_attack_a ~= 0 and item.mod_attack_a or nil),
    mod_attack_b = (item.mod_attack_b ~= 0 and item.mod_attack_b or nil)
  }

  if item.type == 0 then data.usable = true end
  if item.type >= 1 and item.type <= 5 then data.equipable = true end
  local class_data = server.project.classes[item.usable_class]
  if class_data then data.req_class = class_data.name end

  return data
end

-- serialize inventory spell data
function Client.serializeSpell(server, spell, amount)
  return {
    amount = amount,
    name = spell.name,
    description = spell.description
  }
end

-- METHODS

function Client:__construct(server, peer)
  Player.__construct(self)
  self.nettype = "Player"

  self.server = server
  self.peer = peer
  self.valid = false
  do -- quotas
    local quotas = server.cfg.quotas
    self.packets_quota = Quota(quotas.packets[1], quotas.packets[2], function()
      print("client packet quota reached "..tostring(self.peer))
      self:kick("Quota de paquets atteint (anti-spam).")
    end)
    self.packets_quota:start()
    self.data_quota = Quota(quotas.data[1], quotas.data[2], function()
      print("client data quota reached "..tostring(self.peer))
      self:kick("Quota de données entrantes atteint (anti-flood).")
    end)
    self.data_quota:start()
    self.chat_quota = Quota(quotas.chat_all[1], quotas.chat_all[2])
    self.chat_quota:start()
  end

  self.entities = {} -- bound map entities, map of entity
  self.events_by_name = {} -- map of name => event entity
  self.triggered_events = {} -- map of event => trigger condition
  self.to_swipe = false
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

  self.ignores = {
    all = false,
    msg = false,
    msg_players = {}, -- map of pseudo
    trade = false,
    all_chan = false,
    announce_chan = false,
    guild_chan = false,
    group_chan = false
  }

  self:send(Client.makePacket(net.PROTOCOL, net)) -- send protocol
end

function Client:onPacket(protocol, data)
  -- not logged
  if not self.user_id then
    if not self.valid and protocol == net.VERSION_CHECK then -- check client version
      if type(data) == "string" and data == client_version then
        self.valid = true
        -- send motd (start login)
        self:send(Client.makePacket(net.MOTD_LOGIN, {
          motd = self.server.motd,
          salt = self.server.cfg.client_salt
        }))
      else
        self:kick("Version du client incompatible avec le serveur, téléchargez la dernière version pour résoudre le problème.")
      end
    elseif self.valid and protocol == net.LOGIN then -- login
      -- check inputs
      if type(data) ~= "table" or type(data.pseudo) ~= "string"
        or type(data.password) ~= "string" then return end
      -- login request
      async(function()
        local pass_hash = sha2.sha512(self.server.cfg.server_salt..data.pseudo..data.password)
        local rows = self.server.db:query(q_login, {data.pseudo, pass_hash})
        if rows and rows[1] then
          local user_row = rows[1]
          -- check connected
          if self.server.clients_by_id[tonumber(user_row.id)] then
            self:kick("Déjà connecté.")
            return
          end
          -- check banned
          local ban_timestamp = tonumber(user_row.ban_timestamp)
          if os.time() < ban_timestamp then
            self:kick("Banni jusqu'au "..os.date("!%d/%m/%Y %H:%M", ban_timestamp).." UTC.")
            return
          end
          -- accepted
          self.user_id = tonumber(user_row.id) -- mark as logged
          self.pseudo = user_row.pseudo
          self.server.clients_by_id[self.user_id] = self
          self.server.clients_by_pseudo[self.pseudo] = self
          -- load skin infos
          self.allowed_skins = {}
          --- prune invalid skins
          self.server.db:query(q_prune_skins, {self.user_id})
          --- load
          do
            local rows = self.server.db:query(q_get_skins, {self.user_id})
            if rows then
              for _, row in ipairs(rows) do self.allowed_skins[row.name] = true end
            end
          end
          -- load user data
          self.user_rank = tonumber(user_row.rank)
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
          self.guild = user_row.guild
          self.guild_rank = tonumber(user_row.guild_rank)
          self.guild_rank_title = user_row.guild_rank_title
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
          self.inventory = Inventory(self.user_id, 1, self.server.cfg.inventory_size)
          self.chest_inventory = Inventory(self.user_id, 2, self.server.cfg.chest_size)
          self.spell_inventory = Inventory(self.user_id, 3, self.server.cfg.spell_inventory_size)
          self.inventory:load(self.server.db)
          self.chest_inventory:load(self.server.db)
          self.spell_inventory:load(self.server.db)
          ---- on item update
          function self.inventory.onItemUpdate(inv, id)
            local data
            local amount = inv.items[id]
            local object = self.server.project.objects[id]
            if object and amount then
              data = Client.serializeItem(self.server, object, amount)
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
                table.insert(items, {id, Client.serializeItem(self.server, object, amount)})
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
            if object and amount then
              data = Client.serializeItem(self.server, object, amount)
            end
            self:send(Client.makePacket(net.CHEST_UPDATE_ITEMS, {{id,data}}))
          end
          ---- on spell item update
          function self.spell_inventory.onItemUpdate(inv, id)
            local data
            local amount = inv.items[id]
            local spell = self.server.project.spells[id]
            if spell and amount then
              data = Client.serializeSpell(self.server, spell, amount)
            end
            self:send(Client.makePacket(net.SPELL_INVENTORY_UPDATE_ITEMS, {{id,data}}))
          end
          ---- send spell inventory init items
          do
            local spells = self.server.project.spells
            local items = {}
            for id, amount in pairs(self.spell_inventory.items) do
              local spell = spells[id]
              if spell then
                table.insert(items, {id, Client.serializeSpell(self.server, spell, amount)})
              end
            end
            self:send(Client.makePacket(net.SPELL_INVENTORY_UPDATE_ITEMS, items))
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
          self.blocked = state.blocked
          self.blocked_skin = state.blocked_skin
          self.blocked_attack = state.blocked_attack
          self.blocked_defend = state.blocked_defend
          self.blocked_cast = state.blocked_cast
          self.blocked_chat = state.blocked_chat
          -- default spawn
          if not map then
            local spawn_location = self.server.cfg.spawn_location
            map = self.server:getMap(spawn_location.map)
            x,y = spawn_location.cx*16, spawn_location.cy*16
          end
          if map then map:addEntity(self) end
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
            mana = self.mana,
            inventory_size = self.inventory.max
          }))
          self:sendChatMessage("Identifié.")
        else -- login failed
          self:sendChatMessage("Identification échouée.")
          -- send motd (start login)
          self:send(Client.makePacket(net.MOTD_LOGIN, {
            motd = self.server.motd,
            salt = self.server.cfg.client_salt
          }))
        end
      end)
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
      if type(data) == "string" and string.len(data) > 0 and string.len(data) < 1000 then
        if string.sub(data, 1, 1) == "/" then -- parse command
          local args = self.server.parseCommand(string.sub(data, 2))
          if #args > 0 then
            self.server:processCommand(self, args)
          end
        elseif self:canChat() then -- message
          self:mapChat(data)
        end
      else
        self:sendChatMessage("Message trop long.")
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
        elseif data == "dexterity" then
          self.dexterity_pts = self.dexterity_pts+1
        elseif data == "constitution" then
          self.constitution_pts = self.constitution_pts+1
        else done = false end

        if done then
          self:setRemainingPoints(self.remaining_pts-1)
          self:updateCharacteristics()
        end
      end
    elseif protocol == net.ITEM_EQUIP then
      local id = tonumber(data) or 0
      local item = self.server.project.objects[id]
      -- valid and equipable
      if item and item.type >= 1 and item.type <= 5 and self:checkItemRequirements(item) then
        -- compute preview delta
        local old_ch = {
          strength = self.strength,
          dexterity = self.dexterity,
          constitution = self.constitution,
          magic = self.magic,
          attack = self.ch_attack,
          defense = self.ch_defense,
          min_damage = self.min_damage,
          max_damage = self.max_damage
        }

        local old_weapon = self.weapon_slot
        local old_shield = self.shield_slot
        local old_helmet = self.helmet_slot
        local old_armor = self.armor_slot

        --- update slots
        if item.type == 1 then -- one-handed weapon
          self.weapon_slot = id
        elseif item.type == 2 then -- two-handed weapon
          self.weapon_slot = id
          self.shield_slot = 0
        elseif item.type == 3 then -- helmet
          self.helmet_slot = id
        elseif item.type == 4 then -- armor
          self.armor_slot = id
        elseif item.type == 5 then -- shield
          self.shield_slot = id
          -- check for two-handed weapon
          local weapon = self.server.project.objects[self.weapon_slot]
          if weapon and weapon.type == 2 then
            self.weapon_slot = 0
          end
        end

        --- get new characteristics
        self:updateCharacteristics(true) -- dry
        local new_ch = {
          strength = self.strength,
          dexterity = self.dexterity,
          constitution = self.constitution,
          magic = self.magic,
          attack = self.ch_attack,
          defense = self.ch_defense,
          min_damage = self.min_damage,
          max_damage = self.max_damage
        }

        --- revert slots
        self.weapon_slot = old_weapon
        self.shield_slot = old_shield
        self.helmet_slot = old_helmet
        self.armor_slot = old_armor
        self:updateCharacteristics(true) -- dry revert

        --- compute
        local deltas = {}
        for k,v in pairs(old_ch) do deltas[k] = new_ch[k]-old_ch[k] end

        -- show delta / request
        async(function()
          local fdeltas = {} -- formatted
          local append = function(new_ch, deltas, prop, title) -- format prop
            if deltas[prop] ~= 0 then
              table.insert(fdeltas, "  "..title..": "..utils.fn(deltas[prop], true).." ("..utils.fn(new_ch[prop])..")")
            end
          end
          append(new_ch, deltas, "strength", "Force")
          append(new_ch, deltas, "dexterity", "Dextérité")
          append(new_ch, deltas, "constitution", "Constitution")
          append(new_ch, deltas, "magic", "Magie")
          append(new_ch, deltas, "attack", "Attaque")
          append(new_ch, deltas, "defense", "Défense")
          append(new_ch, deltas, "min_damage", "Dégâts min")
          append(new_ch, deltas, "max_damage", "Dégâts max")

          local dialog_r = self:requestDialog({"Équiper ", {0,1,0.5} , item.name, {1,1,1}, " ?\n"..table.concat(fdeltas, "\n")}, {"Équiper"}, true)
          -- equip item
          if dialog_r == 1 and self:checkItemRequirements(item) and self.inventory:take(id,true) then
            local done = true
            if item.type == 1 then -- one-handed weapon
              if self.weapon_slot > 0 then self.inventory:put(self.weapon_slot) end
              self.weapon_slot = id
            elseif item.type == 2 then -- two-handed weapon
              if self.weapon_slot > 0 then self.inventory:put(self.weapon_slot) end
              if self.shield_slot > 0 then self.inventory:put(self.shield_slot) end
              self.weapon_slot = id
              self.shield_slot = 0
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
        end)
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
      if type(data) == "table" and type(data.type) == "string" --
          and type(data.n) == "number" and data.n >= 1 and data.n <= 3 then
        local id = tonumber(data.id)
        if id then -- bind
          local ok = false
          if data.type == "item" then -- check item bind
            local item = self.server.project.objects[id]
            if item and item.type == 0 then ok = true end
          elseif data.type == "spell" then -- check spell bind
            local spell = self.server.project.spells[id]
            if spell then ok = true end
          end
          if ok then
            self:applyConfig({quick_actions = {[data.n] = {type = data.type, id = id}}})
          end
        else -- unbind
          self:applyConfig({quick_actions = {[data.n] = {type = "item", id = 0}}})
        end
      end
    elseif protocol == net.TARGET_PICK then
      local r = self.pick_target_task
      if r then
        self.pick_target_task = nil
        local id = tonumber(data)
        if id and self.map then
          r(self.map.entities_by_id[id])
        else
          r()
        end
      end
    elseif protocol == net.SPELL_CAST then
      local id = tonumber(data) or 0
      if self:canCast(id) then self:castSpell(id) end
    elseif protocol == net.TRADE_SEEK then
      async(function()
        -- pick target
        local entity = self:requestPickTarget("player", 7)
        if entity then
          if not entity.ignores.trade then
            self:sendChatMessage("Requête envoyée.")
            -- open dialog
            local dialog_r = entity:requestDialog({{0,1,0.5}, self.pseudo, {1,1,1}, " souhaite lancer un échange avec vous."}, {"Accepter"})
            if dialog_r == 1 then
              if not (self.map == entity.map and self:openTrade(entity)) then
                self:sendChatMessage("Échange impossible.")
                entity:sendChatMessage("Échange impossible.")
              end
            else
              self:sendChatMessage("Joueur occupé / échange refusé.")
            end
          else self:sendChatMessage("Joueur occupé.") end
        else
          self:sendChatMessage("Cible invalide.")
        end
      end)
    elseif protocol == net.TRADE_SET_GOLD then
      if self.trade and not self.trade.locked then
        self:setTradeGold(tonumber(data) or 0)
      end
    elseif protocol == net.TRADE_PUT_ITEM then
      local id = tonumber(data) or 0
      if self.trade and not self.trade.locked and self.inventory:take(id) then
        self.trade.inventory:put(id)
        self.trade.peer:setTradeLock(false)
      end
    elseif protocol == net.TRADE_TAKE_ITEM then
      local id = tonumber(data) or 0
      if self.trade and not self.trade.locked and self.trade.inventory:take(id) then
        self.inventory:put(id)
        self.trade.peer:setTradeLock(false)
      end
    elseif protocol == net.TRADE_LOCK then
      self:setTradeLock(true)
    elseif protocol == net.TRADE_CLOSE then
      self:cancelTrade()
    elseif protocol == net.DIALOG_RESULT then
      if self.dialog_task then self.dialog_task(tonumber(data)) end
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
    -- reset last attacker
    self.last_attacker = nil
  end
end

function Client:minuteTick()
  if self.user_id then
    self:setAlignment(self.alignment+1)
  end
end

-- Produce an event swipe at the next event tick.
-- Should be called when variables change.
function Client:markSwipe() self.to_swipe = true end

local function event_error_handler(err)
  io.stderr:write(debug.traceback("event: "..err, 2).."\n")
end

-- event handling
function Client:eventTick()
  if self.map and not self.running_event then
    local radius = Event.TRIGGER_RADIUS
    -- swipe events for page changes
    if self.to_swipe then
      self.to_swipe = false
      local cx = self.cx+utils.round(self.view_shift[1]/16)
      local cy = self.cy+utils.round(self.view_shift[2]/16)
      for x=cx-radius, cx+radius do
        for y=cy-radius, cy+radius do
          local cell = self.map:getCell(x,y)
          if cell then
            for entity in pairs(cell) do
              if class.is(entity, Event) then
                local event = entity
                local page_index = event:selectPage()
                if page_index ~= event.page_index then -- reload event
                  -- remove
                  self.map:removeEntity(event)
                  -- re-create
                  local nevent = Event(self, event.data, page_index)
                  self.map:addEntity(nevent)
                  nevent:teleport(event.x, event.y)
                end
              end
            end
          end
        end
      end
    end
    -- execute next visible/top-left event
    local events = {}
    local max_delta = radius*16
    for event, condition in pairs(self.triggered_events) do
      if condition == "auto" or condition == "auto_once" then
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
        local ok = xpcall(event.execute, event_error_handler, event, condition)
        if not ok then event:rollback() end -- rollback on error
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

-- (async)
-- type: target type (string)
--- "player" (only player)
--- "mob" (mob/player)
-- radius: square radius in cells
-- return picked entity or nothing if invalid
function Client:requestPickTarget(type, radius)
  self.pick_target_task = async()
  self:send(Client.makePacket(net.TARGET_PICK, {type = type, radius = radius*16}))
  local entity = self.pick_target_task:wait()
  if entity and entity ~= self then
    local dx = math.abs(self.x-entity.x)
    local dy = math.abs(self.y-entity.y)
    if dx <= radius*16 and dy <= radius*16 --
      and (type == "player" and class.is(entity, Player) --
      or type == "mob" and (class.is(entity, Mob) or class.is(entity, Player))) then
      return entity
    end
  end
end

-- (async) open dialog box
-- text: formatted text
-- options: list of formatted texts
-- no_busy: (optional) if passed/truthy, will show the dialog even if the player is busy
-- return option index or nil/nothing if busy/cancelled
function Client:requestDialog(text, options, no_busy)
  if not self.dialog_task then
    self.dialog_task = async()
    self:send(Client.makePacket(net.DIALOG_QUERY, {ftext = text, options = options, no_busy = no_busy}))
    local r = tonumber(self.dialog_task:wait())
    self.dialog_task = nil
    if r == nil or options[r] then return r end
  end
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
      local data = Client.serializeItem(self.server, object, 0)
      data.price = object.price
      data.id = id
      table.insert(buy_items, data)
    end
  end

  local sell_items = {}
  for id, amount in pairs(self.inventory.items) do
    local object = objects[id]
    if object then
      local data = Client.serializeItem(self.server, object, amount)
      data.id = id
      data.price = object.price
      table.insert(sell_items, data)
    end
  end

  self:send(Client.makePacket(net.SHOP_OPEN, {title, buy_items, sell_items}))

  self.shop_task:wait()
end

-- open trade with another player
-- return true on success
function Client:openTrade(player)
  if self.trade or player.trade then return end -- already trading check

  -- init trading data
  self.trade = {
    peer = player,
    inventory = Inventory(-1, -1, self.server.cfg.inventory_size),
    gold = 0,
    locked = false
  }
  player.trade = {
    peer = self,
    inventory = Inventory(-1, -1, self.server.cfg.inventory_size),
    gold = 0,
    locked = false
  }

  -- bind callbacks: update trade items for each peer
  local function update_item(inv, id, pleft, pright)
    local data
    local amount = inv.items[id]
    local object = self.server.project.objects[id]
    if object and amount then data = Client.serializeItem(self.server, object, amount) end
    pleft:send(Client.makePacket(net.TRADE_LEFT_UPDATE_ITEMS, {{id,data}}))
    pright:send(Client.makePacket(net.TRADE_RIGHT_UPDATE_ITEMS, {{id,data}}))
  end

  function self.trade.inventory.onItemUpdate(inv, id)
    update_item(inv, id, self, player)
  end
  function player.trade.inventory.onItemUpdate(inv, id)
    update_item(inv, id, player, self)
  end

  self:send(Client.makePacket(net.TRADE_OPEN, {title_l = self.pseudo, title_r = player.pseudo}))
  player:send(Client.makePacket(net.TRADE_OPEN, {title_l = player.pseudo, title_r = self.pseudo}))

  return true
end

function Client:setTradeLock(locked)
  if self.trade.locked ~= locked then
    local peer = self.trade.peer
    self.trade.locked = locked
    self:send(Client.makePacket(net.TRADE_LOCK, locked))
    peer:send(Client.makePacket(net.TRADE_PEER_LOCK, locked))

    -- check both locked: complete transaction
    if locked and peer.trade.locked then
      -- gold
      peer:setGold(peer.gold-peer.trade.gold)
      self:setGold(self.gold+peer.trade.gold)
      self:setGold(self.gold-self.trade.gold)
      peer:setGold(peer.gold+self.trade.gold)
      -- items
      for id, amount in pairs(peer.trade.inventory.items) do
        for i=1,amount do self.inventory:put(id) end
      end
      for id, amount in pairs(self.trade.inventory.items) do
        for i=1,amount do peer.inventory:put(id) end
      end
      -- close
      local p, msg = Client.makePacket(net.TRADE_CLOSE), "Échange effectué."
      self:send(p); peer:send(p)
      self:sendChatMessage(msg)
      peer:sendChatMessage(msg)
      self.trade, peer.trade = nil, nil
    end
  end
end

function Client:setTradeGold(gold)
  if self.trade.gold ~= gold then
    self.trade.gold = gold
    self.trade.peer:send(Client.makePacket(net.TRADE_SET_GOLD, gold))
    self.trade.peer:setTradeLock(false)
  end
end

function Client:cancelTrade()
  if self.trade then
    local peer = self.trade.peer
    -- replace items
    for id, amount in pairs(self.trade.inventory.items) do
      for i=1,amount do self.inventory:put(id) end
    end
    for id, amount in pairs(peer.trade.inventory.items) do
      for i=1,amount do peer.inventory:put(id) end
    end

    local p, msg = Client.makePacket(net.TRADE_CLOSE), "Échange annulé."
    self:send(p); peer:send(p)
    self:sendChatMessage(msg)
    peer:sendChatMessage(msg)
    self.trade, peer.trade = nil, nil
  end
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
  self:sendChatMessage("[Kicked] "..reason)
  self.peer:disconnect_later()
end

function Client:onDisconnect()
  -- Rollback event effects on disconnection. Effectively handles interruption
  -- by server shutdown too.
  local event = self.running_event
  if event then
    -- Make sure the event coroutine will not continue its execution before the
    -- rollback by disabling async tasks. The server guarantees that no more
    -- packets from the client will be received and we can ignore this kind of task.
    if self.move_task then self.move_task:remove() end
    if event.wait_task then event.wait_task:remove() end
    -- rollback
    event:rollback()
  end
  -- disconnect variable behavior
  local map_data = (self.map and self.map.data)
  if map_data and map_data.si_v >= 0 then
    if self:getVariable("var", map_data.si_v) >= map_data.v_c then
      self.server:setVariable(map_data.svar, map_data.sval)
    end
  end
  self:setGroup(nil)
  self:cancelTrade()
  -- save
  self:save()
  if self.map then
    self.map:removeEntity(self)
  end
  -- unreference
  if self.user_id then
    self.server.clients_by_id[self.user_id] = nil
    self.server.clients_by_pseudo[self.pseudo] = nil
    self.user_id = nil
  end
  -- quotas
  self.packets_quota:stop()
  self.data_quota:stop()
  self.chat_quota:stop()
end

-- override
function Client:onMapChange()
  Player.onMapChange(self)
  if self.map then -- join map
    self.prevent_next_contact = true -- prevent cell contact on map join
    -- send map
    self:send(Client.makePacket(net.MAP, {map = self.map:serializeNet(self), id = self.id}))
    self:setMapEffect(self.map.data.effect)
    -- build events
    for _, event_data in ipairs(self.map.data.events) do
      local event = Event(self, event_data)
      self.map:addEntity(event)
      event:teleport(event_data.x*16, event_data.y*16)
    end
    self:sendGroupUpdate()
    self:receiveGroupUpdates()
  end
end

-- override
function Client:onCellChange()
  if self.map then
    self:markSwipe()
    local cell = self.map:getCell(self.cx, self.cy)
    if cell then
      -- event contact check
      if not self.ghost and not self.prevent_next_contact then
        for entity in pairs(cell) do
          if class.is(entity, Event) and entity.client == self and entity.trigger_contact then
            entity:trigger("contact")
          end
        end
      end
    end
    self.prevent_next_contact = nil
  end
end

-- override
function Client:onAttack(attacker)
  if self.ghost or attacker == self then return end

  if class.is(attacker, Mob) then -- mob
    self:damage(attacker:computeAttack(self))
    return true
  elseif class.is(attacker, Player) then -- player
    if self.map.data.type == Map.Type.PVE then return false end -- PVE only check
    if self.group and self.group == attacker.group then return false end -- group check
    if self.map.data.type == Map.Type.PVE_PVP -- PVE/PVP guild/group check
      and self.guild and self.guild == attacker.guild -- same guild
      and self.group == attacker.group then return false end -- same group or none
    if math.abs(self.level-attacker.level) >= 10 then return false end -- level check

    self.last_attacker = attacker
    -- alignment loss
    local amount = attacker:computeAttack(self)
    if amount and self.map.data.type == Map.Type.PVE_PVP then
      attacker:setAlignment(attacker.alignment-5)
      attacker:emitHint("-5 alignement")
    end
    self:damage(amount)
    return true
  end
end

-- override
function Client:serializeNet()
  local data = Player.serializeNet(self)
  data.pseudo = self.pseudo
  data.guild = self.guild
  data.alignment = self.alignment
  return data
end

function Client:interact()
  -- event interact check
  local entities = self:raycastEntities(2)
  for _, entity in ipairs(entities) do
    if class.is(entity, Event) and entity.client == self and entity.trigger_interact then
      entity:trigger("interact")
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
    -- heal effect
    if item.mod_hp > 0 then
      self:emitSound("Holy2.wav")
      self:emitAnimation("heal.png", 0, 0, 48, 56, 0.75)
      self:emitHint({{0,1,0}, utils.fn(item.mod_hp)})
    elseif item.mod_hp < 0 then -- damage
      self:broadcastPacket("damage", -item.mod_hp)
    end
    -- mana effect
    if item.mod_mp > 0 then
      self:emitSound("Holy2.wav")
      self:emitAnimation("mana.png", 0, 0, 48, 56, 0.75)
      self:emitHint({{0.04,0.42,1}, utils.fn(item.mod_mp)})
    end
    return true
  end
end

-- try to cast a spell
function Client:castSpell(id)
  local spell = self.server.project.spells[id]
  if spell and self.spell_inventory.items[id] > 0 then -- check owned
    if spell.mp > self.mana then -- mana check
      self:sendChatMessage("Pas assez de mana.")
      return
    end
    if self.level < spell.req_level then -- level check
      self:sendChatMessage("Niveau trop bas.")
      return
    end

    async(function()
      -- acquire target
      local target
      if spell.target_type == 0 then -- player
        target = self:requestPickTarget("player", 7)
      elseif spell.target_type == 1 then -- mob
        target = self:requestPickTarget("mob", 7)
      elseif spell.target_type == 2 then -- self
        target = self
      elseif spell.target_type == 3 then -- area
        target = self
        -- TODO
      end

      if not target then -- target check
        self:sendChatMessage("Cible invalide.")
        return
      end

      local cast_duration = spell.cast_duration*0.03

      -- cast spell
      self:act("cast", cast_duration)
      task(cast_duration, function()
        self:emitHint({{0.77,0.18,1}, spell.name})
        target:applySpell(self, spell)
      end)
    end)
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
-- dry: (optional) if passed/truthy, will not trigger any update (but affects properties)
--- used for temporary characteristics modulation
function Client:updateCharacteristics(dry)
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

  if not dry then
    -- update health/mana
    self:setHealth(self.health)
    self:setMana(self.mana)

    -- trigger vars
    self:markSwipe()

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
    self.spell_inventory:save(self.server.db)

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
    state.blocked = self.blocked
    state.blocked_skin = self.blocked_skin
    state.blocked_attack = self.blocked_attack
    state.blocked_defend = self.blocked_defend
    state.blocked_cast = self.blocked_cast
    state.blocked_chat = self.blocked_chat

    self.server.db:_query(q_set_state, {self.user_id, utils.hex(msgpack.pack(state))})
  end
end

-- override
function Client:setOrientation(orientation)
  Player.setOrientation(self, orientation)
  self:markSwipe()
end

-- override
function Client:setHealth(health)
  Player.setHealth(self, health)
  self:markSwipe()
  self:send(Client.makePacket(net.STATS_UPDATE, {health = self.health, max_health = self.max_health}))
  self:sendGroupUpdate()
end

-- override
function Client:setMana(mana)
  Player.setMana(self, mana)
  self:markSwipe()
  self:send(Client.makePacket(net.STATS_UPDATE, {mana = self.mana, max_mana = self.max_mana}))
end

function Client:setGold(gold)
  self.gold = math.max(0,gold)
  self:markSwipe()
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

  self:markSwipe()

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
  self:markSwipe()
  self:send(Client.makePacket(net.STATS_UPDATE, {alignment = self.alignment}))
  self:broadcastPacket("update_alignment", self.alignment)
end

function Client:setReputation(reputation)
  self.reputation = reputation
  self:markSwipe()
  self:send(Client.makePacket(net.STATS_UPDATE, {reputation = self.reputation}))
end

function Client:setRemainingPoints(remaining_pts)
  self.remaining_pts = math.max(0, remaining_pts)
  self:markSwipe()
  self:send(Client.makePacket(net.STATS_UPDATE, {points = self.remaining_pts}))
end

-- leave current group and join new group
-- id: key (string) or falsy to just leave
function Client:setGroup(id)
  if self.group then -- leave old group
    local group = self.server.groups[self.group]
    if group then
      -- broadcast leave packet to group member on the map and to self (self included)
      if self.map then
        local packet = Client.makePacket(net.ENTITY_PACKET, {
          id = self.id,
          act = "group_remove"
        })

        for client in pairs(group) do
          if client.map == self.map then
            -- leave packet to other group member
            if client ~= self then client:send(packet) end

            -- leave packet to self
            self:send(Client.makePacket(net.ENTITY_PACKET, {
              id = client.id,
              act = "group_remove"
            }))
          end
        end
      end

      -- notify
      for client in pairs(group) do
        if client ~= self then
          client:sendChatMessage("\""..self.pseudo.."\" a quitté le groupe.")
        else
          client:sendChatMessage("Vous avez quitté le groupe \""..self.group.."\".")
        end
      end

      group[self] = nil
      -- remove if empty
      if not next(group) then self.server.groups[self.group] = nil end
      self.group = nil
    end
  end

  if id then -- join
    local group = self.server.groups[id]
    if not group then -- create group
      group = {}
      self.server.groups[id] = group
    end

    group[self] = true
    self.group = id
    self:sendGroupUpdate()
    self:receiveGroupUpdates()
    -- notify
    for client in pairs(group) do
      if client ~= self then
        client:sendChatMessage("\""..self.pseudo.."\" a rejoint le groupe.")
      else
        client:sendChatMessage("Vous avez rejoint le groupe \""..self.group.."\".")
      end
    end
  end
end

-- send group update packet (join/data)
function Client:sendGroupUpdate()
  -- broadcast update packet to group members on the map and to self (self included)
  local group = self.group and self.server.groups[self.group]
  if group and self.map then
    local packet = Client.makePacket(net.ENTITY_PACKET, {
      id = self.id,
      act = "group_update",
      data = {health = self.health, max_health = self.max_health}
    })

    for client in pairs(group) do
      if client.map == self.map then client:send(packet) end
    end
  end
end

-- send group update packet for other group members
function Client:receiveGroupUpdates()
  -- update packet for each group member on the map to self
  local group = self.group and self.server.groups[self.group]
  if group and self.map then
    for client in pairs(group) do
      if client ~= self and client.map == self.map then
        self:send(Client.makePacket(net.ENTITY_PACKET, {
          id = client.id,
          act = "group_update",
          data = {health = client.health, max_health = client.max_health}
        }))
      end
    end
  end
end

function Client:onPlayerKill()
  self.kill_player = 1
  self:markSwipe()
end

-- override
function Client:onDeath()
  -- XP loss (1%)
  if self.map and self.map.data.type == Map.Type.PVE or self.map.data.type == Map.Type.PVE_PVP then
    local new_xp = math.floor(self.xp*0.99)
    local delta = new_xp-self.xp
    if delta < 0 then self:emitHint({{0,0.9,1}, utils.fn(delta, true)}) end
    self:setXP(new_xp)
  end

  if self.last_attacker then -- killed by player
    print(self.last_attacker)
    -- gold stealing (1%)
    local gold_amount = math.floor(self.gold*0.01)
    if gold_amount > 0 then
      self.last_attacker:setGold(self.last_attacker.gold+gold_amount)
      self:setGold(self.gold-gold_amount)
      self.last_attacker:emitHint({{1,0.78,0}, utils.fn(gold_amount, true)})
      self:emitHint({{1,0.78,0}, utils.fn(-gold_amount, true)})
    end

    -- reputation
    if self.map and self.map.data.type == Map.Type.PVP then
      local reputation_amount = math.floor(self.level*0.1)
      if reputation_amount > 0 then
        self.last_attacker:setReputation(self.last_attacker.reputation+reputation_amount)
        self.last_attacker:emitHint(utils.fn(reputation_amount, true).." réputation")
      end
    end

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

-- effect: int
--- 0: none
--- 1: dark cave
--- 2: night
--- 3: heat
--- 4: rain
--- 5: snow
--- 6: fog
function Client:setMapEffect(effect)
  self.map_effect = effect
  self:send(Client.makePacket(net.MAP_EFFECT, effect))
end

-- restriction checks

function Client:canAttack()
  if self.map and self.map.data.type == Map.Type.SAFE then return false end
  return not self.running_event and not self.acting and not self.ghost and not self.blocked_attack
end

function Client:canDefend()
  if self.map and self.map.data.type == Map.Type.SAFE then return false end
  return not self.running_event and not self.acting and not self.ghost and not self.blocked_defend
end

-- id: spell id
function Client:canCast(id)
  local spell = self.server.project.spells[id]
  if not spell then return false end
  if self.map and self.map.data.type == Map.Type.SAFE and spell.target_type ~= 2 then return false end
  return not self.running_event and not self.acting and not self.ghost and not self.blocked_cast
end

function Client:canChat()
  return not self.running_event and not self.ghost and not self.blocked_chat
end

function Client:canMove()
  return not self.running_event and not self.blocked
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

function Client:canChangeSkin()
  return not self.blocked_skin
end

function Client:canChangeGroup()
  return not (self.map.data.type == Map.Type.PVP --
    or self.map.data.type == Map.Type.PVP_NOREPUT --
    or self.map.data.type == Map.Type.PVP_NOREPUT_POT)
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
    self:markSwipe()

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
