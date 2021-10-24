local msgpack = require("MessagePack")
local sha2 = require("sha2")
local net = require("app.protocol")
local Quota = require("app.Quota")
local Player = require("app.entities.Player")
local Event = require("app.entities.Event")
local Mob = require("app.entities.Mob")
local utils = require("app.utils")
local client_version = require("app.client_version")
local Inventory = require("app.Inventory")
local XPtable = require("app.XPtable")
-- deferred require
local Map
timer(0.01, function()
  Map = require("app.Map")
end)

-- server-side client
local Client = class("Client", Player)

-- STATICS

local function error_handler(err)
  io.stderr:write(debug.traceback("client: "..err, 2).."\n")
end

function Client.makePacket(protocol, data)
  return msgpack.pack({protocol, data})
end

local EQUIPABLE_ITEM_TYPES = utils.rmap({
  "one-handed-weapon",
  "two-handed-weapon",
  "helmet",
  "armor",
  "shield"
}, true)

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
  data.usable = (item.type == "usable")
  data.equipable = EQUIPABLE_ITEM_TYPES[item.type]
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

-- Packet handlers.
local packet = {}

function packet:VERSION_CHECK(data)
  if self.status ~= "connecting" then return end
  if type(data) == "string" and data == client_version then
    self.status = "logging-in"
    -- send motd (start login)
    self:send(Client.makePacket(net.MOTD_LOGIN, {motd = server.motd}))
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
  async(function()
    -- get salt
    local salt
    do
      local result = server.db:query("user/getSalt", {data.pseudo})
      if result and result.rows[1] then salt = result.rows[1].salt end
    end
    -- authenticate
    local password_hash = sha2.hex2bin(sha2.sha512((salt or "")..data.password_hash))
    local rows = server.db:query("user/login", {data.pseudo, password_hash}).rows
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
        self:applyConfig(user_row.config and msgpack.unpack(user_row.config) or {}, true)
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
          self:send(Client.makePacket(net.INVENTORY_UPDATE_ITEMS, {{id,data}}))
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
          self:send(Client.makePacket(net.INVENTORY_UPDATE_ITEMS, items))
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
          self:send(Client.makePacket(net.CHEST_UPDATE_ITEMS, {{id,data}}))
        end
        ---- on spell item update
        function self.spell_inventory.onItemUpdate(inv, id)
          local data
          local amount = inv.items[id]
          local spell = server.project.spells[id]
          if spell and amount then
            data = Client.serializeSpell(server, spell, amount)
          end
          self:send(Client.makePacket(net.SPELL_INVENTORY_UPDATE_ITEMS, {{id,data}}))
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
        -- mark as logged
      end, error_handler)
      if ok then -- login completed
        server.clients_by_pseudo[self.pseudo:lower()] = self
        self.user_id = user_id
        self.status = "logged"
        self:sendChatMessage("Identifié.")
      else -- login error
        server.clients_by_id[user_id] = nil
        print("<= login error for user#"..user_id.." \""..user_row.pseudo.."\"")
        self:kick("Erreur du serveur.")
      end
    else -- login failed
      self:sendChatMessage("Identification échouée.")
      -- send motd (start login)
      self:send(Client.makePacket(net.MOTD_LOGIN, {motd = server.motd}))
    end
  end)
end
function packet:INPUT_ORIENTATION(data)
  if self.status ~= "logged" then return end
  if self:canMove() then self:setOrientation(tonumber(data) or 0) end
end
function packet:INPUT_MOVE_FORWARD(data)
  if self.status ~= "logged" then return end
  -- update input state (used to stop/resume movements correctly)
  self.move_forward_input = not not data
  if self:canMove() then self:setMoveForward(self.move_forward_input) end
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
  if type(data) == "string" and string.len(data) > 0 and string.len(data) < 1000 then
    if string.sub(data, 1, 1) == "/" then -- parse command
      local args = server.parseCommand(string.sub(data, 2))
      if #args > 0 then
        server:processCommand(self, args)
      end
    elseif self:canChat() then -- message
      self:mapChat(data)
    end
  else
    self:sendChatMessage("Message trop long.")
  end
end
function packet:EVENT_MESSAGE_SKIP(data)
  if self.status ~= "logged" then return end
  local r = self.message_task
  if r then
    self.message_task = nil
    r()
  end
end
function packet:EVENT_INPUT_QUERY_ANSWER(data)
  if self.status ~= "logged" then return end
  local r = self.input_query_task
  if r and type(data) == "number" then
    self.input_query_task = nil
    r(data)
  end
end
function packet:EVENT_INPUT_STRING_ANSWER(data)
  if self.status ~= "logged" then return end
  local r = self.input_string_task
  if r and type(data) == "string" then
    self.input_string_task = nil
    r(data)
  end
end
function packet:CHEST_CLOSE(data)
  if self.status ~= "logged" then return end
  local r = self.chest_task
  if r then
    self.chest_task = nil
    r()
  end
end
function packet:SHOP_CLOSE(data)
  if self.status ~= "logged" then return end
  local r = self.shop_task
  if r then
    self.shop_task = nil
    r()
  end
end
function packet:GOLD_STORE(data)
  if self.status ~= "logged" then return end
  local amount = tonumber(data) or 0
  if self.chest_task and amount <= self.gold then
    self.chest_gold = self.chest_gold+amount
    self.gold = self.gold-amount
    self:send(Client.makePacket(net.STATS_UPDATE, {gold = self.gold, chest_gold = self.chest_gold}))
  end
end
function packet:GOLD_WITHDRAW(data)
  if self.status ~= "logged" then return end
  local amount = tonumber(data) or 0
  if self.chest_task and amount <= self.chest_gold then
    self.chest_gold = self.chest_gold-amount
    self.gold = self.gold+amount
    self:send(Client.makePacket(net.STATS_UPDATE, {gold = self.gold, chest_gold = self.chest_gold}))
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
        self:send(Client.makePacket(net.STATS_UPDATE, {gold = self.gold}))
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
      self:send(Client.makePacket(net.STATS_UPDATE, {gold = self.gold}))
    end
  end
end
function packet:ITEM_USE(data)
  if self.status ~= "logged" then return end
  local id = tonumber(data) or 0
  if self:canUseItem() then async(function() self:tryUseItem(id) end) end
end
function packet:ITEM_TRASH(data)
  if self.status ~= "logged" then return end
  local id = tonumber(data) or 0
  self.inventory:take(id)
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
  if item and EQUIPABLE_ITEM_TYPES[item.type] and self:checkItemRequirements(item) then
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
        if item.type == "one-handed-weapon" then
          if self.weapon_slot > 0 then self.inventory:put(self.weapon_slot) end
          self.weapon_slot = id
        elseif item.type == "two-handed-weapon" then
          if self.weapon_slot > 0 then self.inventory:put(self.weapon_slot) end
          if self.shield_slot > 0 then self.inventory:put(self.shield_slot) end
          self.weapon_slot = id
          self.shield_slot = 0
        elseif item.type == "helmet" then
          if self.helmet_slot > 0 then self.inventory:put(self.helmet_slot) end
          self.helmet_slot = id
        elseif item.type == "armor" then
          if self.armor_slot > 0 then self.inventory:put(self.armor_slot) end
          self.armor_slot = id
        elseif item.type == "shield" then
          if self.shield_slot > 0 then self.inventory:put(self.shield_slot) end
          self.shield_slot = id
          -- check for two-handed weapon
          local weapon = server.project.objects[self.weapon_slot]
          if weapon and weapon.type == "two-handed-weapon" then
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
  local r = self.scroll_task
  if r then
    self.scroll_task = nil
    r()
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
function packet:TARGET_PICK(data)
  if self.status ~= "logged" then return end
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
end
function packet:SPELL_CAST(data)
  if self.status ~= "logged" then return end
  local id = tonumber(data) or 0
  local spell = server.project.spells[id]
  if spell and self:canCast(spell) then
    if self.spell_inventory.items[id] > 0 then -- check owned
      async(function() self:tryCastSpell(spell) end)
    end
  end
end
function packet:TRADE_SEEK(data)
  if self.status ~= "logged" then return end
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
end
function packet:TRADE_SET_GOLD(data)
  if self.status ~= "logged" then return end
  if self.trade and not self.trade.locked then
    self:setTradeGold(tonumber(data) or 0)
  end
end
function packet:TRADE_PUT_ITEM(data)
  if self.status ~= "logged" then return end
  local id = tonumber(data) or 0
  if self.trade and not self.trade.locked and self.inventory:take(id) then
    self.trade.inventory:put(id)
    self.trade.peer:setTradeLock(false)
  end
end
function packet:TRADE_TAKE_ITEM(data)
  if self.status ~= "logged" then return end
  local id = tonumber(data) or 0
  if self.trade and not self.trade.locked and self.trade.inventory:take(id) then
    self.inventory:put(id)
    self.trade.peer:setTradeLock(false)
  end
end
function packet:TRADE_LOCK(data)
  if self.status ~= "logged" then return end
  self:setTradeLock(true)
end
function packet:TRADE_CLOSE(data)
  if self.status ~= "logged" then return end
  self:cancelTrade()
end
function packet:DIALOG_RESULT(data)
  if self.status ~= "logged" then return end
  if self.dialog_task then self.dialog_task(tonumber(data)) end
end

-- METHODS

function Client:__construct(peer)
  Player.__construct(self)
  self.nettype = "Player"

  self.peer = peer
  self.status = "connecting"
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
  -- self.running_event

  self.vars = {} -- map of id (number)  => value (number)
  self.var_listeners = {} -- map of id (number) => map of callback
  self.changed_vars = {} -- map of vars id
  self.bool_vars = {} -- map of id (number) => value (number)
  self.bool_var_listeners = {} -- map of id (number) => map of callback
  self.changed_bool_vars = {} -- map of bool vars id
  self.special_var_listeners = {} -- map of id (string) => map of callback
  self.timers = {0,0,0} -- %TimerX% vars (3), incremented every 30ms
  self.last_idle_swipe = clock()
  self.kill_player = 0
  self.visible = true
  self.draw_order = 0
  self.view_shift = {0,0}
  self.blocked = false
  self.spell_blocked = false -- blocked by a spell effect
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
end

function Client:onPacket(protocol, data)
  local handler = packet[net[protocol]]
  if handler then handler(self, data) end
end

-- unsequenced: unsequenced and unreliable if true/passed, reliable otherwise
function Client:send(packet, unsequenced)
  self.peer:send(packet, 0, (unsequenced and "unsequenced" or "reliable"))
end

function Client:sendChatMessage(msg)
  self:send(Client.makePacket(net.CHAT_MESSAGE_SERVER, msg))
end

function Client:timerTick()
end

function Client:minuteTick()
  if self.status == "logged" then self:setAlignment(self.alignment+1) end
end

local function event_error_handler(err)
  io.stderr:write(debug.traceback("event: "..err, 2).."\n")
end

-- Update events (page selection).
function Client:swipeEvents()
  local events = {}
  for entity in pairs(self.entities) do
    if class.is(entity, Event) then table.insert(events, entity) end
  end
  -- swipe events for page changes
  for _, event in ipairs(events) do
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

-- event handling
function Client:eventTick(timer_ticks)
  if self.status == "logged" and self.map and not self.running_event then
    -- Timer increments.
    for i, time in ipairs(self.timers) do
      self.timers[i] = time+timer_ticks
    end
    -- Misc.
    -- reset last attacker
    self.last_attacker = nil
    -- Execute next visible/top-left event.
    local events = {}
    local max_delta = Event.TRIGGER_RADIUS*16
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
      -- sort ascending top-left (line by line)
      table.sort(events, function(a,b)
        return a.cy < b.cy or a.cy == b.cy and a.cx < b.cx
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
        if ok then -- events state invalidated, swipe
          self:swipeEvents()
          self.last_idle_swipe = clock() -- reset next idle swipe
        else -- rollback on error
          event:rollback()
        end
        self.running_event = nil
        self:setMoveForward(self.move_forward_input) -- resume movement
      end)
    else -- swipe events when idle for timer conditions
      -- This may not be enough to handle all editor timing patterns, but
      -- should be good enough while preventing swipe overhead.
      local time = clock()
      if time-self.last_idle_swipe >= 0.25 then
        self.last_idle_swipe = time
        self:swipeEvents()
      end
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
-- Request to pick a target (self excluded).
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
    if dx <= radius*16 and dy <= radius*16 and
        (type == "player" and class.is(entity, Player) or
        type == "mob" and (class.is(entity, Mob) or class.is(entity, Player))) then
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
    local r = self.dialog_task:wait()
    self.dialog_task = nil
    if not r or options[r] then return r end
  end
end

-- (async) open chest GUI
function Client:openChest(title)
  self.chest_task = async()
  -- send init items
  local objects = server.project.objects
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

  local objects = server.project.objects

  local buy_items = {}
  for _, id in ipairs(items) do
    local object = objects[id]
    if object then
      local data = Client.serializeItem(server, object, 0)
      data.price = object.price
      data.id = id
      table.insert(buy_items, data)
    end
  end

  local sell_items = {}
  for id, amount in pairs(self.inventory.items) do
    local object = objects[id]
    if object then
      local data = Client.serializeItem(server, object, amount)
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
    inventory = Inventory(-1, -1, server.cfg.inventory_size),
    gold = 0,
    locked = false
  }
  player.trade = {
    peer = self,
    inventory = Inventory(-1, -1, server.cfg.inventory_size),
    gold = 0,
    locked = false
  }

  -- bind callbacks: update trade items for each peer
  local function update_item(inv, id, pleft, pright)
    local data
    local amount = inv.items[id]
    local object = server.project.objects[id]
    if object and amount then data = Client.serializeItem(server, object, amount) end
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
  self.status = "disconnecting"
  -- Rollback event effects on disconnection. Effectively handles interruption
  -- by server shutdown too.
  local event = self.running_event
  if event then
    -- Make sure the event coroutine will not continue its execution before the
    -- rollback by disabling async tasks. The server guarantees that no more
    -- packets from the client will be received and we can ignore this kind of task.
    if self.move_timer then self.move_timer:remove() end
    event.wait_task = nil
    -- rollback
    event:rollback()
    self.running_event = nil
  end
  -- disconnect variable behavior
  local map_data = (self.map and self.map.data)
  if map_data and map_data.si_v >= 0 then
    if self:getVariable("var", map_data.si_v) >= map_data.v_c then
      server:setVariable(map_data.svar, map_data.sval)
    end
  end
  self:setGroup(nil)
  self:cancelTrade()
  async(function()
    -- save
    server.db:transactionWrap(function() self:save() end)
    -- remove player
    if self.map then
      self.map:removeEntity(self)
    end
    -- quotas
    self.packets_quota:stop()
    self.data_quota:stop()
    self.chat_quota:stop()
    -- unreference
    if self.pseudo then server.clients_by_pseudo[self.pseudo:lower()] = nil end
    if self.user_id then
      server.clients_by_id[self.user_id] = nil
      self.user_id = nil
    end
    self.status = "disconnected"
  end)
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
  elseif class.is(attacker, Client) then -- player
    if not attacker:canFight(self) then return false end
    -- alignment loss
    local amount = attacker:computeAttack(self)
    if amount and self.map.data.type == "PvE-PvP" then
      attacker:setAlignment(attacker.alignment-5)
      attacker:emitHint("-5 alignement")
    end
    if amount then self.last_attacker = attacker end
    self:damage(amount)
    attacker:triggerGearSpells(self)
    return true
  end
end

-- target: LivingEntity
function Client:triggerGearSpells(target)
  local objs = server.project.objects
  local gears = {
    objs[self.helmet_slot], objs[self.armor_slot],
    objs[self.weapon_slot], objs[self.shield_slot]
  }
  for _, item in pairs(gears) do
    local spell = server.project.spells[item.spell]
    if spell then self:castSpell(target, spell, "nocast") end
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
  -- prevent interact spamming
  if not self.interacting then
    self.interacting = true
    -- event interact check
    local entities = self:raycastEntities(2)
    for _, entity in ipairs(entities) do
      if class.is(entity, Event) and entity.client == self and entity.trigger_interact then
        entity:trigger("interact")
        break
      end
    end
    timer(0.25, function() self.interacting = false end)
  end
end

-- (async) Consume owned usable item and apply effects.
-- return true on success
function Client:tryUseItem(id)
  local item = server.project.objects[id]
  local spell = server.project.spells[item.spell]
  -- checks
  if not item or item.type ~= "usable" then return end
  if not self:checkItemRequirements(item) then
    self:sendChatMessage("Prérequis insuffisants."); return
  end
  if spell and (not self:canCast(spell) or not self:tryCastSpell(spell)) then return end
  -- consume
  if not self.inventory:take(id) then return end
  if not spell then self:act("use", 1) end
  -- heal effect
  self:setHealth(self.health+item.mod_hp)
  if item.mod_hp > 0 then
    self:emitSound("Holy2.wav")
    self:emitAnimation("heal.png", 0, 0, 48, 56, 0.75)
    self:emitHint({{0,1,0}, utils.fn(item.mod_hp)})
  elseif item.mod_hp < 0 then -- damage
    self:broadcastPacket("damage", -item.mod_hp)
  end
  -- mana effect
  self:setMana(self.mana+item.mod_mp)
  if item.mod_mp > 0 then
    self:emitSound("Holy2.wav")
    self:emitAnimation("mana.png", 0, 0, 48, 56, 0.75)
    self:emitHint({{0.04,0.42,1}, utils.fn(item.mod_mp)})
  end
  return true
end

-- (async) Try to cast a spell.
-- spell: spell data
-- return true on success
function Client:tryCastSpell(spell)
  if spell.mp > self.mana then -- check mana
    self:sendChatMessage("Pas assez de mana."); return
  end
  if self.level < spell.req_level or not
      (spell.usable_class == 0 or self.class == spell.usable_class) then
    self:sendChatMessage("Prérequis insuffisants."); return
  end
  -- acquire target
  local target
  if spell.target_type == "player" then
    target = self:requestPickTarget("player", 7)
  elseif spell.target_type == "mob-player" then
    target = self:requestPickTarget("mob", 7)
    -- check for invalid player target
    if class.is(target, Client) and not self:canFight(target) then target = nil end
  elseif spell.target_type == "self" then
    target = self
  elseif spell.target_type == "around" then
    target = self
  end
  if not target then
    self:sendChatMessage("Cible invalide.")
    return
  end
  -- check line of sight
  if spell.type == "fireball" and not self:hasLOS(target.cx, target.cy) then
    self:sendChatMessage("Pas de ligne de vue.")
    return
  end
  -- cast
  self:setMana(self.mana-spell.mp)
  self:castSpell(target, spell)
  return true
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
  local class_data = server.project.classes[self.class]

  self.strength = self.strength_pts+class_data.strength
  self.dexterity = self.dexterity_pts+class_data.dexterity
  self.constitution = self.constitution_pts+class_data.constitution
  self.magic = self.magic_pts+class_data.magic

  self.max_health = 0
  self.ch_defense = 0
  self.ch_attack = 0

  -- gears
  local helmet = server.project.objects[self.helmet_slot]
  local armor = server.project.objects[self.armor_slot]
  local weapon = server.project.objects[self.weapon_slot]
  local shield = server.project.objects[self.shield_slot]

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
  if not self.user_id or self.running_event then return false end
  -- base data
  server.db:_query("user/setData", {
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
    server.db:_query("user/setVar", {self.user_id, var, self.vars[var]})
  end
  self.changed_vars = {}
  -- bool vars
  for var in pairs(self.changed_bool_vars) do
    server.db:_query("user/setBoolVar", {self.user_id, var, self.bool_vars[var]})
  end
  self.changed_bool_vars = {}
  -- inventories
  self.inventory:save(server.db)
  self.chest_inventory:save(server.db)
  self.spell_inventory:save(server.db)
  -- config
  if self.player_config_changed then
    server.db:_query("user/setConfig", {self.user_id, msgpack.pack(self.player_config)})
    self.player_config_changed = false
  end
  -- state
  local state = {}
  if self.map then
    -- location
    if self.map.data.disconnect_respawn then
      local location = (self.respawn_point or server.cfg.spawn_location)
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
  server.db:_query("user/setState", {self.user_id, msgpack.pack(state)})
  return true
end

-- override
function Client:setOrientation(orientation)
  Player.setOrientation(self, orientation)
end

-- override
function Client:setHealth(health)
  Player.setHealth(self, health)
  self:send(Client.makePacket(net.STATS_UPDATE, {health = self.health, max_health = self.max_health}))
  self:sendGroupUpdate()
end

-- override
function Client:setMana(mana)
  Player.setMana(self, mana)
  self:send(Client.makePacket(net.STATS_UPDATE, {mana = self.mana, max_mana = self.max_mana}))
end

-- Note: extra sanitization on important values. If for some reason (e.g. a
-- bug) a player has "inf" golds, every gold transaction can lead to an
-- infection of all players becoming infinitly (or almost) rich.

function Client:setGold(gold)
  self.gold = math.max(0, utils.sanitizeInt(gold))
  self:send(Client.makePacket(net.STATS_UPDATE, {gold = self.gold}))
end

function Client:setXP(xp)
  local old_level = self.level
  self.xp = utils.sanitizeInt(xp)
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
  self:send(Client.makePacket(net.STATS_UPDATE, {
    xp = self.xp,
    current_xp = XPtable[self.level] or 0,
    next_xp = XPtable[self.level+1] or self.xp,
    level = self.level
  }))
  self:updateCharacteristics()
  if self.level > old_level then -- level up effects
    self:emitSound("Holy2.wav")
    self:emitAnimation("heal.png", 0, 0, 48, 56, 0.75)
    self:emitHint({{1, 0.78, 0}, utils.fn("LEVEL UP!")})
  end
end

function Client:setAlignment(alignment)
  self.alignment = utils.clamp(utils.sanitizeInt(alignment), 0, 100)
  self:send(Client.makePacket(net.STATS_UPDATE, {alignment = self.alignment}))
  self:broadcastPacket("update_alignment", self.alignment)
end

function Client:setReputation(reputation)
  self.reputation = utils.sanitizeInt(reputation)
  self:send(Client.makePacket(net.STATS_UPDATE, {reputation = self.reputation}))
end

function Client:setRemainingPoints(remaining_pts)
  self.remaining_pts = math.max(0, utils.sanitizeInt(remaining_pts))
  self:send(Client.makePacket(net.STATS_UPDATE, {points = self.remaining_pts}))
end

-- leave current group and join new group
-- id: case insensitive key or falsy to just leave
function Client:setGroup(id)
  if self.group then -- leave old group
    local group = server.groups[self.group]
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
      if not next(group) then server.groups[self.group] = nil end
      self.group = nil
    end
  end
  -- join
  if id then
    id = id:lower()
    local group = server.groups[id]
    if not group then -- create group
      group = {}
      server.groups[id] = group
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
  local group = self.group and server.groups[self.group]
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
  local group = self.group and server.groups[self.group]
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
end

-- override
function Client:onDeath()
  -- XP loss (1%)
  if self.map and self.map.data.type == "PvE" or self.map.data.type == "PvE-PvP" then
    local new_xp = math.floor(self.xp*0.99)
    local delta = new_xp-self.xp
    if delta < 0 then self:emitHint({{0,0.9,1}, utils.fn(delta, true)}) end
    self:setXP(new_xp)
  end
  if self.last_attacker then -- killed by player
    -- gold stealing (1%)
    local gold_amount = math.floor(self.gold*0.01)
    if gold_amount > 0 then
      self.last_attacker:setGold(self.last_attacker.gold+gold_amount)
      self:setGold(self.gold-gold_amount)
      self.last_attacker:emitHint({{1,0.78,0}, utils.fn(gold_amount, true)})
      self:emitHint({{1,0.78,0}, utils.fn(-gold_amount, true)})
    end
    -- reputation
    if self.map and self.map.data.type == "PvP" then
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
  self.respawn_timer = timer(server.cfg.respawn_delay, function() self:respawn() end)
end

-- Resurrect player before respawn.
function Client:resurrect()
  if self.map then
    if self.respawn_timer then
      self.respawn_timer:remove()
      self.respawn_timer = nil
    end
    if self.ghost then
      self:setGhost(false)
      self:setHealth(1)
    end
  end
end

function Client:respawn()
  if self.map then -- check if still on the world
    if self.respawn_timer then
      self.respawn_timer:remove()
      self.respawn_timer = nil
    end
    self:setGhost(false)
    self:setHealth(self.max_health) -- reset health
    -- respawn
    local respawned = false
    if self.respawn_point then -- res point respawn
      local map = server:getMap(self.respawn_point.map)
      if map then
        map:addEntity(self)
        self:teleport(self.respawn_point.cx*16, self.respawn_point.cy*16)
        respawned = true
      end
    end
    if not respawned then -- default respawn
      local spawn_location = server.cfg.spawn_location
      local map = server:getMap(spawn_location.map)
      if map then
        map:addEntity(self)
        self:teleport(spawn_location.cx*16, spawn_location.cy*16)
      end
    end
  end
end

function Client:setMapEffect(effect)
  self.map_effect = effect
  self:send(Client.makePacket(net.MAP_EFFECT, effect))
end

-- restriction checks

-- Check if the player can fight another one (self is handled).
-- target: Client
function Client:canFight(target)
  if self == target or not self.map or self.map ~= target.map then return false end
  if self.map.data.type == "PvE" then return false end -- PVE only check
  if self.group and self.group == target.group then return false end -- group check
  if self.map.data.type == "PvE-PvP" -- PVE/PVP guild/group check
    and #self.guild > 0 and self.guild == target.guild -- same guild
    and self.group == target.group then return false end -- same group or none
  if math.abs(self.level-target.level) >= 10 then return false end -- level check
  return true
end

function Client:canAttack()
  if self.map and self.map.data.type == "safe" then return false end
  return not self.running_event and not self.acting and not self.ghost and not self.blocked_attack
end

function Client:canDefend()
  if self.map and self.map.data.type == "safe" then return false end
  return not self.running_event and not self.acting and not self.ghost and not self.blocked_defend
end

-- Check basic cast ability.
-- spell: spell data
function Client:canCast(spell)
  if self.map and self.map.data.type == "safe" then
    -- check target
    if not (spell.target_type == "self" or spell.target_type == "player") then
      return false
    end
    -- check type
    if spell.target_type == "player" and not (spell.type == "unique" or spell.type == "AoE") then
      return false
    end
  end
  return not self.running_event and not self.acting and
      not self.ghost and not self.blocked_cast
end

function Client:canChat()
  return not self.running_event and not self.ghost and not self.blocked_chat
end

function Client:canMove()
  return not self.running_event and not self.move_task and not self.blocked and not self.spell_blocked
end

function Client:canInteract()
  return not self.running_event and not self.ghost
end

function Client:canUseItem()
  if self.map and self.map.data.type == "PvP" or self.map.data.type == "PvP-noreput" then
    return false
  end
  return not self.running_event and not self.acting and not self.ghost and self.alignment > 20
end

function Client:canChangeSkin()
  return not self.blocked_skin
end

function Client:canChangeGroup()
  return not (self.map.data.type == "PvP" --
    or self.map.data.type == "PvP-noreput" --
    or self.map.data.type == "PvP-noreput-pot")
end

-- variables

-- vtype: string, "bool" (boolean) or "var" (integer)
function Client:setVariable(vtype, id, value)
  id, value = tonumber(id) or 0, tonumber(value) or 0
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

function Client:getVariable(vtype, id)
  id = tonumber(id) or 0
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
