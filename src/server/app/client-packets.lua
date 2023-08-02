-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

-- Client packet handlers (`self` is the Client object).

local digest = require "openssl.digest"
local msgpack = require "MessagePack"
local net = require "app.protocol"
local client_version = require "app.client_version"
local Inventory = require "app.Inventory"
local utils = require "app.utils"
local Client
timer(0.001, function() -- deferred modules
  Client = require "app.Client"
end)

local function error_handler(err)
  io.stderr:write(debug.traceback("client: "..err, 2).."\n")
end

local packet = {}

function packet:VERSION_CHECK(data)
  if self.status ~= "connecting" then return end
  if type(data) == "string" and data == client_version then
    self.status = "logging-in"
    -- send motd (start login)
    self:sendPacket(net.MOTD_LOGIN, {motd = server.motd})
  else
    self:kick("Version du client incompatible avec le serveur, téléchargez la dernière version pour résoudre le problème.")
  end
end

function packet:LOGIN(data)
  if self.status ~= "logging-in" then return end
  -- check inputs
  if type(data) ~= "table" or type(data.pseudo) ~= "string"
    or type(data.password_hash) ~= "string" or #data.pseudo > 50 then return end
  -- login request
  asyncR(function()
    -- get salt
    local salt
    do
      local result = server.db:query("user/getSalt", {data.pseudo})
      if result.rows[1] then salt = result.rows[1].salt end
    end
    -- authenticate
    local password_hash = digest.new("sha512"):final((salt or "")..data.password_hash)
    local rows = server.db:query("user/login", {data.pseudo, {password_hash}}).rows
    if rows[1] then
      local user_row = rows[1]
      local user_id = user_row.id
      -- check connected
      if server.clients_by_id[user_id] then
        self:kick("Déjà connecté.")
        return
      end
      -- check banned
      local ban_timestamp = user_row.ban_timestamp
      if os.time() < ban_timestamp then
        self:kick("Banni jusqu'au "..os.date("!%d/%m/%Y %H:%M", ban_timestamp).." UTC.")
        return
      end
      local ok = xpcall(function()
        -- accepted
        server.clients_by_id[user_id] = self
        self.login_timestamp = os.time()
        self.pseudo = user_row.pseudo
        -- load skin infos
        self.allowed_skins = {}
        --- prune invalid skins
        server.db:query("user/pruneSkins", {user_id})
        --- load
        do
          local rows = server.db:query("user/getSkins", {user_id}).rows
          for _, row in ipairs(rows) do self.allowed_skins[row.name] = true end
        end
        -- load user data
        self.user_rank = user_row.rank
        self.class = user_row.class
        self.level = user_row.level
        self.alignment = user_row.alignment
        self.reputation = user_row.reputation
        self.gold = user_row.gold
        self.chest_gold = user_row.chest_gold
        self.xp = user_row.xp
        self.strength_pts = user_row.strength_pts
        self.dexterity_pts = user_row.dexterity_pts
        self.constitution_pts = user_row.constitution_pts
        self.magic_pts = user_row.magic_pts
        self.remaining_pts = user_row.remaining_pts
        self.weapon_slot = user_row.weapon_slot
        self.shield_slot = user_row.shield_slot
        self.helmet_slot = user_row.helmet_slot
        self.armor_slot = user_row.armor_slot
        self.guild = user_row.guild
        self.guild_rank = user_row.guild_rank
        self.guild_rank_title = user_row.guild_rank_title
        local class_data = server.project.classes[self.class]
        self:setSounds(string.sub(class_data.attack_sound, 7), string.sub(class_data.hurt_sound, 7))
        --- config
        do
          local config = server.cfg.player_config
          if user_row.config then
            config = msgpack.unpack(user_row.config)
          end
          self:applyConfig(config)
        end
        --- play stats
        self.play_stats = {
          creation_timestamp = user_row.creation_timestamp,
          played = user_row.stat_played,
          traveled = user_row.stat_traveled,
          mob_kills = user_row.stat_mob_kills,
          deaths = user_row.stat_deaths
        }
        --- vars
        local rows = server.db:query("user/getVars", {user_id}).rows
        for _, row in ipairs(rows) do self.vars[row.id] = row.value end
        rows = server.db:query("user/getBoolVars", {user_id}).rows
        for _, row in ipairs(rows) do self.bool_vars[row.id] = row.value end
        --- inventories
        self.inventory = Inventory(user_id, 1, server.cfg.inventory_size)
        self.chest_inventory = Inventory(user_id, 2, server.cfg.chest_size)
        self.spell_inventory = Inventory(user_id, 3, server.cfg.spell_inventory_size)
        self.inventory:load(server.db)
        self.chest_inventory:load(server.db)
        self.spell_inventory:load(server.db)
        ---- on item update
        function self.inventory.onItemUpdate(inv, id)
          local data
          local amount = inv.items[id]
          local object = server.project.objects[id]
          if object and amount then
            data = Client.serializeItem(server, object, amount)
          end
          self:sendPacket(net.INVENTORY_UPDATE_ITEMS, {{id,data}})
        end
        ---- send inventory init items
        do
          local objects = server.project.objects
          local items = {}
          for id, amount in pairs(self.inventory.items) do
            local object = objects[id]
            if object then
              table.insert(items, {id, Client.serializeItem(server, object, amount)})
            end
          end
          self:sendPacket(net.INVENTORY_UPDATE_ITEMS, items)
        end
        ---- on chest item update
        function self.chest_inventory.onItemUpdate(inv, id)
          if not self.chest_task then return end -- chest isn't open
          local data
          local amount = inv.items[id]
          local object = server.project.objects[id]
          if object and amount then
            data = Client.serializeItem(server, object, amount)
          end
          self:sendPacket(net.CHEST_UPDATE_ITEMS, {{id,data}})
        end
        ---- on spell item update
        function self.spell_inventory.onItemUpdate(inv, id)
          local data
          local amount = inv.items[id]
          local spell = server.project.spells[id]
          if spell and amount then
            data = Client.serializeSpell(server, spell, amount)
          end
          self:sendPacket(net.SPELL_INVENTORY_UPDATE_ITEMS, {{id,data}})
        end
        ---- send spell inventory init items
        do
          local spells = server.project.spells
          local items = {}
          for id, amount in pairs(self.spell_inventory.items) do
            local spell = spells[id]
            if spell then
              table.insert(items, {id, Client.serializeSpell(server, spell, amount)})
            end
          end
          self:sendPacket(net.SPELL_INVENTORY_UPDATE_ITEMS, items)
        end
        --- state
        local state = {}
        if user_row.state then
          state = msgpack.unpack(user_row.state)
        end
        ---- charaset
        if state.charaset then
          self:setCharaset(state.charaset)
        end
        ---- location
        local map, x, y
        if state.location then
          map = server:getMap(state.location.map)
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
          local spawn_location = server.cfg.spawn_location
          map = server:getMap(spawn_location.map)
          x,y = spawn_location.cx*16, spawn_location.cy*16
        end
        if map then map:addEntity(self) end
        self:teleport(x,y)
        -- compute characteristics, send/init stats
        self:updateCharacteristics()
        self:setHealth(state.health or self.max_health)
        self:setMana(state.mana or self.max_mana)
        self:setXP(self.xp) -- update level/XP
        self:sendPacket(net.STATS_UPDATE, {
          gold = self.gold,
          alignment = self.alignment,
          name = self.pseudo,
          class = class_data.name,
          level = self.level,
          points = self.remaining_pts,
          reputation = self.reputation,
          mana = self.mana,
          inventory_size = self.inventory.max
        })
        -- mark as logged
      end, error_handler)
      if ok then -- login completed
        server.clients_by_pseudo[self.pseudo:lower()] = self
        self.user_id = user_id
        self.status = "logged"
        self:print("Identifié.")
        print("client logged "..tostring(self.peer)..": user#"..user_id.." \""..self.pseudo.."\"")
      else -- login error
        server.clients_by_id[user_id] = nil
        warn("<= login error for user#"..user_id.." \""..user_row.pseudo.."\"")
        self:kick("Erreur du serveur.")
      end
    else -- login failed
      self:print("Identification échouée.")
      -- send motd (start login)
      self:sendPacket(net.MOTD_LOGIN, {motd = server.motd})
    end
  end)
end

function packet:INPUT_MOVE(data)
  if self.status ~= "logged" then return end
  -- check inputs
  local move_forward, orientation = data[1], data[2]
  if type(move_forward) ~= "boolean" or type(orientation) ~= "number" or
      orientation ~= math.floor(orientation) or orientation < 0 or
      orientation >= 4 then return end
  -- update local inputs
  self.input_move = {move_forward, orientation}
  if self:canMove() then
    self:setMovement(move_forward, orientation)
  end
end

function packet:INPUT_ATTACK(data)
  if self.status ~= "logged" then return end
  if self:canAttack() then self:attack() end
end

function packet:INPUT_DEFEND(data)
  if self.status ~= "logged" then return end
  if self:canDefend() then self:defend() end
end

function packet:INPUT_INTERACT(data)
  if self.status ~= "logged" then return end
  if self:canInteract() then self:interact() end
end

function packet:INPUT_CHAT(data)
  if self.status ~= "logged" then return end
  if type(data) == "string" and #data > 0 and #data < 1000 then
    if string.sub(data, 1, 1) == "/" then -- parse command
      local args = server.parseCommand(string.sub(data, 2))
      if #args > 0 then
        server:processCommand(self, args)
      end
    elseif self:canChat() then -- message
      self:mapChat(data)
    end
  else
    self:print("Message trop long.")
  end
end

function packet:EVENT_MESSAGE_SKIP(data)
  if self.status ~= "logged" then return end
  local task = self.message_task
  if task then
    self.message_task = nil
    task:complete()
  end
end

function packet:EVENT_INPUT_QUERY_ANSWER(data)
  if self.status ~= "logged" then return end
  local task = self.input_query_task
  if task and type(data) == "number" then
    self.input_query_task = nil
    task:complete(data)
  end
end

function packet:EVENT_INPUT_STRING_ANSWER(data)
  if self.status ~= "logged" then return end
  local task = self.input_string_task
  if task and type(data) == "string" then
    self.input_string_task = nil
    task:complete(data)
  end
end

function packet:CHEST_CLOSE(data)
  if self.status ~= "logged" then return end
  local task = self.chest_task
  if task then
    self.chest_task = nil
    task:complete()
  end
end

function packet:SHOP_CLOSE(data)
  if self.status ~= "logged" then return end
  local task = self.shop_task
  if task then
    self.shop_task = nil
    task:complete()
  end
end

function packet:GOLD_STORE(data)
  if self.status ~= "logged" then return end
  local amount = tonumber(data) or 0
  if self.chest_task and amount <= self.gold then
    self.chest_gold = self.chest_gold+amount
    self.gold = self.gold-amount
    self:sendPacket(net.STATS_UPDATE, {gold = self.gold, chest_gold = self.chest_gold})
  end
end

function packet:GOLD_WITHDRAW(data)
  if self.status ~= "logged" then return end
  local amount = tonumber(data) or 0
  if self.chest_task and amount <= self.chest_gold then
    self.chest_gold = self.chest_gold-amount
    self.gold = self.gold+amount
    self:sendPacket(net.STATS_UPDATE, {gold = self.gold, chest_gold = self.chest_gold})
  end
end

function packet:ITEM_STORE(data)
  if self.status ~= "logged" then return end
  local id = tonumber(data) or 0
  if self.chest_task and self.inventory:take(id, true) and self.chest_inventory:put(id) then
    self.inventory:take(id)
  end
end

function packet:ITEM_WITHDRAW(data)
  if self.status ~= "logged" then return end
  local id = tonumber(data) or 0
  if self.chest_task and self.chest_inventory:take(id, true) and self.inventory:put(id) then
    self.chest_inventory:take(id)
  end
end

function packet:ITEM_BUY(data)
  if self.status ~= "logged" then return end
  if self.shop_task and type(data) == "table" then
    local id, amount = tonumber(data[1]) or 0, tonumber(data[2]) or 0
    local item = server.project.objects[id]
    if item and amount > 0 then
      if item.price*amount <= self.gold then
        for i=1,amount do -- buy one by one
          if self.inventory:put(id) then
            self.gold = self.gold-item.price
          else break end
        end
        self:sendPacket(net.STATS_UPDATE, {gold = self.gold})
      end
    end
  end
end

function packet:ITEM_SELL(data)
  if self.status ~= "logged" then return end
  local id = tonumber(data) or 0
  local item = server.project.objects[id]
  if self.shop_task and item then
    if self.inventory:take(id) then
      self.gold = self.gold+math.ceil(item.price*0.1)
      self:sendPacket(net.STATS_UPDATE, {gold = self.gold})
    end
  end
end

function packet:ITEM_USE(data)
  if self.status ~= "logged" then return end
  local id = tonumber(data) or 0
  if self:canUseItem() then asyncR(function() self:tryUseItem(id) end) end
end

function packet:ITEM_TRASH(data)
  if self.status ~= "logged" then return end
  local id = tonumber(data) or 0
  local item = server.project.objects[id]
  if item and item.type ~= "quest-item" then self.inventory:take(id) end
end

function packet:SPEND_CHARACTERISTIC_POINT(data)
  if self.status ~= "logged" then return end
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
end

function packet:ITEM_EQUIP(data)
  if self.status ~= "logged" then return end
  local id = tonumber(data) or 0
  local item = server.project.objects[id]
  -- valid and equipable
  if item and Client.EQUIPABLE_ITEM_TYPES[item.type] and self:checkItemRequirements(item) then
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
    if item.type == "one-handed-weapon" then
      self.weapon_slot = id
    elseif item.type == "two-handed-weapon" then
      self.weapon_slot = id
      self.shield_slot = 0
    elseif item.type == "helmet" then
      self.helmet_slot = id
    elseif item.type == "armor" then
      self.armor_slot = id
    elseif item.type == "shield" then
      self.shield_slot = id
      -- check for two-handed weapon
      local weapon = server.project.objects[self.weapon_slot]
      if weapon and weapon.type == "two-handed-weapon" then
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
    asyncR(function()
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
      -- Equip item.
      -- This lets the inventory increase beyond limits to avoid complexity/bugs.
      if dialog_r == 1 and self:checkItemRequirements(item) and
          self.inventory:take(id, true) then
        --
        local done = true
        if item.type == "one-handed-weapon" then
          if self.weapon_slot > 0 then self.inventory:rawput(self.weapon_slot) end
          self.weapon_slot = id
        elseif item.type == "two-handed-weapon" then
          if self.weapon_slot > 0 then self.inventory:rawput(self.weapon_slot) end
          if self.shield_slot > 0 then self.inventory:rawput(self.shield_slot) end
          self.weapon_slot = id
          self.shield_slot = 0
        elseif item.type == "helmet" then
          if self.helmet_slot > 0 then self.inventory:rawput(self.helmet_slot) end
          self.helmet_slot = id
        elseif item.type == "armor" then
          if self.armor_slot > 0 then self.inventory:rawput(self.armor_slot) end
          self.armor_slot = id
        elseif item.type == "shield" then
          if self.shield_slot > 0 then self.inventory:rawput(self.shield_slot) end
          self.shield_slot = id
          -- check for two-handed weapon
          local weapon = server.project.objects[self.weapon_slot]
          if weapon and weapon.type == "two-handed-weapon" then
            self.inventory:rawput(self.weapon_slot)
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
end

function packet:SLOT_UNEQUIP(data)
  if self.status ~= "logged" then return end
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
end

function packet:SCROLL_END(data)
  if self.status ~= "logged" then return end
  local task = self.scroll_task
  if task then
    self.scroll_task = nil
    task:complete()
  end
end

function packet:QUICK_ACTION_BIND(data)
  if self.status ~= "logged" then return end
  if type(data) == "table" and type(data.type) == "string" --
      and type(data.n) == "number" and data.n >= 1 and data.n <= 3 then
    local id = tonumber(data.id)
    if id then -- bind
      local ok = false
      if data.type == "item" then -- check item bind
        local item = server.project.objects[id]
        if item and item.type == "usable" then ok = true end
      elseif data.type == "spell" then -- check spell bind
        local spell = server.project.spells[id]
        if spell then ok = true end
      end
      if ok then
        self:applyConfig({quick_actions = {[data.n] = {type = data.type, id = id}}})
      end
    else -- unbind
      self:applyConfig({quick_actions = {[data.n] = {type = "item", id = 0}}})
    end
  end
end

function packet:ENTITY_PICK(data)
  if self.status ~= "logged" then return end
  local task = self.pick_entity_task
  if task then
    self.pick_entity_task = nil
    task:complete(type(data) == "number" and data)
  end
end

function packet:SPELL_CAST(data)
  if self.status ~= "logged" then return end
  local id = tonumber(data) or 0
  local spell = server.project.spells[id]
  if spell and self:canCast(spell) then
    if self.spell_inventory.items[id] > 0 then -- check owned
      asyncR(function() self:tryCastSpell(spell) end)
    end
  end
end

function packet:TRADE_SEEK(data)
  if self.status ~= "logged" then return end
  asyncR(function()
    -- pick target
    local entity = self:requestPickEntity(self:getSurroundingEntities("player", 7))
    if entity then
      if not entity.ignores.trade then
        self:print("Requête envoyée.")
        -- open dialog
        local dialog_r = entity:requestDialog({{0,1,0.5}, self.pseudo, {1,1,1}, " souhaite lancer un échange avec vous."}, {"Accepter"})
        if dialog_r == 1 then
          if not (self.map == entity.map and self:openTrade(entity)) then
            self:print("Échange impossible.")
            entity:print("Échange impossible.")
          end
        else
          self:print("Joueur occupé / échange refusé.")
        end
      else self:print("Joueur occupé.") end
    else
      self:print("Cible invalide.")
    end
  end)
end

function packet:TRADE_SET_GOLD(data)
  if self.status ~= "logged" then return end
  if self.trade then self:setTradeGold(tonumber(data) or 0) end
end

function packet:TRADE_PUT_ITEM(data)
  if self.status ~= "logged" then return end
  local id = tonumber(data) or 0
  if self.trade and self.inventory:take(id) then
    self.trade.inventory:rawput(id)
    self:setTradeStep("initiated")
    self.trade.peer:setTradeStep("initiated")
  end
end

function packet:TRADE_TAKE_ITEM(data)
  if self.status ~= "logged" then return end
  local id = tonumber(data) or 0
  if self.trade and self.trade.inventory:take(id) then
    self.inventory:rawput(id)
    self:setTradeStep("initiated")
    self.trade.peer:setTradeStep("initiated")
  end
end

function packet:TRADE_STEP()
  if self.status ~= "logged" then return end
  if self.trade then
    local peer = self.trade.peer
    if self.trade.step == "initiated" then
      self:setTradeStep("submitted")
    elseif self.trade.step == "submitted" and
        (peer.trade.step == "submitted" or peer.trade.step == "accepted") then
      self:setTradeStep("accepted")
    end
  end
end

function packet:TRADE_CLOSE(data)
  if self.status ~= "logged" then return end
  self:cancelTrade()
end

function packet:DIALOG_RESULT(data)
  if self.status ~= "logged" then return end
  if self.dialog_task then self.dialog_task:complete(tonumber(data)) end
end

return packet
