-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

local msgpack = require "MessagePack"
local net = require "app.protocol"
local Quota = require "app.Quota"
local Player = require "app.entities.Player"
local Event = require "app.entities.Event"
local Mob = require "app.entities.Mob"
local utils = require "app.utils"
local Inventory = require "app.Inventory"
local XPtable = require "app.XPtable"
local packet_handlers = require "app.client-packets"

-- server-side client
local Client = class("Client", Player)

function Client.makePacket(protocol, data)
  return msgpack.pack({protocol, data})
end

local CHAT_ACTION_RADIUS = 15 -- cells

Client.EQUIPABLE_ITEM_TYPES = utils.bimap({
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
  data.usable = item.type == "usable"
  data.equipable = Client.EQUIPABLE_ITEM_TYPES[item.type]
  data.trashable = item.type ~= "quest-item"
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
    self.data_quota = Quota(quotas.data[1], quotas.data[2], function()
      print("client data quota reached "..tostring(self.peer))
      self:kick("Quota de données entrantes atteint (anti-flood).")
    end)
    self.chat_quota = Quota(quotas.chat_all[1], quotas.chat_all[2])
    self.event_errors_quota = Quota(quotas.event_errors[1], quotas.event_errors[2])
  end

  self.entities = {} -- bound map entities, map of entity
  self.events_by_name = {} -- map of name => event entity
  self.triggered_events = {} -- map of event => trigger condition
  -- self.running_event

  self.vars = {} -- map of id (number)  => value (number)
  self.changed_vars = {} -- map of vars id
  self.bool_vars = {} -- map of id (number) => value (number)
  self.changed_bool_vars = {} -- map of bool vars id
  self.timers = {0,0,0} -- %TimerX% vars (3), incremented every 30ms
  self.last_idle_swipe = loop:now()
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
  self.input_move = {false} -- {move_forward, orientation}

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
  local handler = packet_handlers[net[protocol]]
  if handler then handler(self, data) end
end

-- mode: (optional) "reliable" (default), "unsequenced" (unreliable and unsequenced)
function Client:send(packet, mode)
  self.peer:send(packet, 0, mode or "reliable")
end

function Client:sendPacket(protocol, data, mode)
  self:send(Client.makePacket(protocol, data), mode)
end

-- ftext: string or coloredtext (see LÖVE)
function Client:sendChatMessage(ftext)
  self:sendPacket(net.CHAT_MESSAGE, ftext)
end

function Client:print(msg) self:sendChatMessage({{0,1,0.5}, msg}) end

function Client:emitChatAction(ftext)
  if not self.map then return end
  local s_ftext = {self.pseudo.." "}
  for _, v in ipairs(ftext) do table.insert(s_ftext, v) end
  -- send message to all clients in chat radius
  for client in pairs(self.map.clients) do
    local dx = math.abs(self.x-client.x)
    local dy = math.abs(self.y-client.y)
    if dx <= CHAT_ACTION_RADIUS*16 and dy <= CHAT_ACTION_RADIUS*16 then
      client:sendChatMessage(s_ftext)
    end
  end
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
    if xtype.is(entity, Event) then table.insert(events, entity) end
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

function Client:notifyEventError()
  if self.event_errors_quota:check() then
    self:print("Une erreur est survenue dans un événement et peut bloquer la progression du personnage.")
    self.event_errors_quota:add(1)
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
      if condition == "auto" or condition == "auto-once" then
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
      self:setMovement(false)
      -- execute event
      local event = events[1]
      local condition = self.triggered_events[event]
      self.triggered_events[event] = nil
      self.running_event = event
      asyncR(function()
        local ok = xpcall(event.execute, event_error_handler, event, condition)
        if ok then -- events state invalidated, swipe
          self:swipeEvents()
          self.last_idle_swipe = loop:now() -- reset next idle swipe
        else -- rollback on error
          event:rollback()
          self:notifyEventError()
        end
        self.running_event = nil
        self:setMovement(unpack(self.input_move)) -- resume movement
      end)
    else -- swipe events when idle for timer conditions
      -- This may not be enough to handle all editor timing patterns, but
      -- should be good enough while preventing swipe overhead.
      local time = loop:now()
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
  self:sendPacket(net.EVENT_MESSAGE, msg)
  self.message_task:wait()
end

-- (async)
-- return option index (may be invalid)
function Client:requestInputQuery(title, options)
  self.input_query_task = async()
  self:sendPacket(net.EVENT_INPUT_QUERY, {title = title, options = options})
  return self.input_query_task:wait()
end

function Client:requestInputString(title)
  self.input_string_task = async()
  self:sendPacket(net.EVENT_INPUT_STRING, {title = title})
  return self.input_string_task:wait()
end

-- mode: "player-self", "player", "mob-player"
-- radius: cells
-- ghost_allowed: (optional) truthy to allow ghost players
-- return list of entities, sorted by ascending distance
function Client:getSurroundingEntities(mode, radius, ghost_allowed)
  if not self.map then return end
  -- prepare entities
  local entities = {}
  for client in pairs(self.map.clients) do
    if (client ~= self or mode == "player-self") and (not client.ghost or ghost_allowed) then
      table.insert(entities, client)
    end
  end
  if mode == "mob-player" then
    for mob in pairs(self.map.mobs) do table.insert(entities, mob) end
  end
  -- select/sort entries
  local entries = {}
  for _, entity in ipairs(entities) do
    local dx, dy = entity.x-self.x, entity.y-self.y
    local dist = math.sqrt(dx*dx+dy*dy)
    if dist <= radius*16 then table.insert(entries, {entity, dist}) end
  end
  table.sort(entries, function(a,b) return a[2] < b[2] end)
  -- pick
  local list = {}
  for _, entry in ipairs(entries) do table.insert(list, entry[1]) end
  return list
end

-- (async)
-- Request to pick an entity.
-- entities: list of candidates (same map)
-- return picked entity or nil/nothing if invalid
function Client:requestPickEntity(entities)
  self.pick_entity_task = async()
  local ids, check_table = {}, {}
  for _, entity in ipairs(entities) do
    if entity.map == self.map then
      table.insert(ids, entity.id)
      check_table[entity] = true
    end
  end
  self:sendPacket(net.ENTITY_PICK, ids)
  local id = self.pick_entity_task:wait()
  local entity = self.map and self.map.entities_by_id[id]
  return check_table[entity] and entity
end

-- (async) open dialog box
-- text: formatted text
-- options: list of formatted texts
-- no_busy: (optional) if passed/truthy, will show the dialog even if the player is busy
-- return option index or nil/nothing if busy/cancelled
function Client:requestDialog(text, options, no_busy)
  if not self.dialog_task then
    self.dialog_task = async()
    self:sendPacket(net.DIALOG_QUERY, {ftext = text, options = options, no_busy = no_busy})
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
      table.insert(items, {id, Client.serializeItem(server, object, amount)})
    end
  end
  self:sendPacket(net.CHEST_OPEN, {title, items})
  self:sendPacket(net.STATS_UPDATE, {chest_gold = self.chest_gold})
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

  self:sendPacket(net.SHOP_OPEN, {title, buy_items, sell_items})

  self.shop_task:wait()
end

-- open trade with another player
-- return true on success
function Client:openTrade(player)
  if self.trade or player.trade then return end -- already in a trade
  -- Init trade data.
  -- The locked feature is important to prevent timing attacks (change of proposal
  -- just before the other party accepts the trade).
  self.trade = {
    peer = player,
    inventory = Inventory(-1, -1, server.cfg.inventory_size),
    gold = 0,
    step = "initiated"
  }
  player.trade = {
    peer = self,
    inventory = Inventory(-1, -1, server.cfg.inventory_size),
    gold = 0,
    step = "initiated"
  }
  -- bind callbacks: update trade items for each peer
  local function update_item(inv, id, pleft, pright)
    local data
    local amount = inv.items[id]
    local object = server.project.objects[id]
    if object and amount then data = Client.serializeItem(server, object, amount) end
    pleft:sendPacket(net.TRADE_LEFT_UPDATE_ITEMS, {{id,data}})
    pright:sendPacket(net.TRADE_RIGHT_UPDATE_ITEMS, {{id,data}})
  end
  function self.trade.inventory.onItemUpdate(inv, id)
    update_item(inv, id, self, player)
  end
  function player.trade.inventory.onItemUpdate(inv, id)
    update_item(inv, id, player, self)
  end
  self:sendPacket(net.TRADE_OPEN, {title_l = self.pseudo, title_r = player.pseudo})
  player:sendPacket(net.TRADE_OPEN, {title_l = player.pseudo, title_r = self.pseudo})
  return true
end

-- step: "initiated", "submitted", "accepted"
function Client:setTradeStep(step)
  if self.trade.step ~= step then
    local peer = self.trade.peer
    self.trade.step = step
    self:sendPacket(net.TRADE_STEP, step)
    peer:sendPacket(net.TRADE_PEER_STEP, step)
    -- both accepted: complete transaction
    if self.trade.step == "accepted" and peer.trade.step == "accepted" then
      -- check transaction
      if self.gold >= self.trade.gold and peer.gold >= peer.trade.gold and
          self.inventory:getSpace() >= peer.trade.inventory:getAmount() and
          peer.inventory:getSpace() >= self.trade.inventory:getAmount() then
        -- gold
        peer:setGold(peer.gold-peer.trade.gold)
        self:setGold(self.gold+peer.trade.gold)
        self:setGold(self.gold-self.trade.gold)
        peer:setGold(peer.gold+self.trade.gold)
        -- items
        for id, amount in pairs(peer.trade.inventory.items) do
          for i=1,amount do self.inventory:rawput(id) end
        end
        for id, amount in pairs(self.trade.inventory.items) do
          for i=1,amount do peer.inventory:rawput(id) end
        end
        -- close
        local p, msg = Client.makePacket(net.TRADE_CLOSE), "Échange effectué."
        self:send(p); peer:send(p)
        self:print(msg); peer:print(msg)
        self.trade, peer.trade = nil, nil
      else
        self:cancelTrade()
      end
    end
  end
end

function Client:setTradeGold(gold)
  if self.trade.gold ~= gold then
    self.trade.gold = gold
    self.trade.peer:sendPacket(net.TRADE_SET_GOLD, gold)
    self:setTradeStep("initiated")
    self.trade.peer:setTradeStep("initiated")
  end
end

function Client:cancelTrade()
  if self.trade then
    local peer = self.trade.peer
    -- replace items
    for id, amount in pairs(self.trade.inventory.items) do
      for i=1,amount do self.inventory:rawput(id) end
    end
    for id, amount in pairs(peer.trade.inventory.items) do
      for i=1,amount do peer.inventory:rawput(id) end
    end
    -- close
    local p, msg = Client.makePacket(net.TRADE_CLOSE), "Échange annulé."
    self:send(p); peer:send(p)
    self:print(msg); peer:print(msg)
    self.trade, peer.trade = nil, nil
  end
end

-- (async) scroll client view to position
function Client:scrollTo(x,y)
  self.scroll_task = async()
  self:sendPacket(net.SCROLL_TO, {x,y})
  self.scroll_task:wait()
end

function Client:resetScroll()
  self:sendPacket(net.SCROLL_RESET)
end

function Client:kick(reason)
  self:print("[Kicked] "..reason)
  self.peer:disconnect_later()
end

-- (async)
-- Handle disconnection.
function Client:onDisconnect()
  if self.status == "logged" then
    self.status = "disconnecting"
    -- Rollback event effects on disconnection. Effectively handles interruption
    -- by server shutdown too.
    local event = self.running_event
    if event then
      -- Make sure the event coroutine will not continue its execution before the
      -- rollback by disabling async tasks. The server guarantees that no more
      -- packets from the client will be received and we can ignore this kind of task.
      if self.move_timer then self.move_timer:close() end
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
    -- save
    local save_ok
    local ok = server.db:transactionWrap(function() save_ok = self:save() end)
    ok = ok and save_ok
    print("client save "..tostring(self.peer)..": "..(ok and "committed" or "aborted"))
    -- remove player
    if self.map then
      self.map:removeEntity(self)
    end
    -- unreference
    if self.pseudo then server.clients_by_pseudo[self.pseudo:lower()] = nil end
    server.clients_by_id[self.user_id] = nil
    self.user_id = nil
    self.status = "disconnected"
  end
end

-- override
function Client:onMapChange()
  Player.onMapChange(self)
  if self.map then -- join map
    -- send map
    self:sendPacket(net.MAP, {map = self.map:serializeNet(self), id = self.id})
    self:setMapEffect(self.map.data.effect)
    -- build events
    for _, event_data in ipairs(self.map.data.events) do
      local event = Event(self, event_data)
      self.map:addEntity(event)
      event:teleport(event_data.x*16, event_data.y*16)
    end
    self:sendGroupUpdate()
    self:receiveGroupUpdates()
    -- resume movements
    if self:canMove() then
      self:setMovement(unpack(self.input_move))
    end
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
          if xtype.is(entity, Event) and entity:hasConditionFlag("contact") and self:perceivesRealm(entity) then
            entity:trigger("contact")
          end
        end
      end
    end
    self.prevent_next_contact = nil
  end
end

-- override
function Client:onDistTraveled(dist)
  self.play_stats.traveled = self.play_stats.traveled + utils.sanitizeInt(dist)/16
end

-- override
function Client:onAttack(attacker)
  if self.ghost or attacker == self then return end
  if xtype.is(attacker, Mob) then -- mob
    self:damage(attacker:computeAttack(self))
    return true
  elseif xtype.is(attacker, Client) then -- player
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
  data.has_group = self.group ~= nil
  return data
end

function Client:interact()
  -- prevent interact spamming
  if not self.interacting then
    self.interacting = true
    -- event interact check
    local entities = self:raycastEntities(2)
    for _, entity in ipairs(entities) do
      if xtype.is(entity, Event) and
          entity:hasConditionFlag("interact") and self:perceivesRealm(entity) then
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
    self:print("Prérequis insuffisants."); return
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
    self:print("Pas assez de mana."); return
  end
  if self.level < spell.req_level or not
      (spell.usable_class == 0 or self.class == spell.usable_class) then
    self:print("Prérequis insuffisants."); return
  end
  -- acquire target
  local target
  if spell.target_type == "player" then
    local ghosts = spell.type == "resurrect"
    target = self:requestPickEntity(self:getSurroundingEntities("player-self", 7, ghosts))
  elseif spell.target_type == "mob-player" then
    local ghosts = spell.type == "resurrect"
    local pre_entities = self:getSurroundingEntities("mob-player", 7, ghosts)
    local entities = {}
    for _, entity in ipairs(pre_entities) do
      if not xtype.is(entity, Client) or self:canFight(entity) then
        table.insert(entities, entity)
      end
    end
    target = self:requestPickEntity(entities)
  elseif spell.target_type == "self" then
    target = self
  elseif spell.target_type == "around" then
    target = self
  end
  if not target then
    self:print("Cible invalide.")
    return
  end
  -- check line of sight
  if spell.type == "fireball" and not self:hasLOS(target.cx, target.cy) then
    self:print("Pas de ligne de vue.")
    return
  end
  -- cast
  self:setMana(self.mana-spell.mp)
  self:castSpell(target, spell)
  return true
end

function Client:playMusic(path)
  self:sendPacket(net.PLAY_MUSIC, path)
end

function Client:stopMusic()
  self:sendPacket(net.STOP_MUSIC)
end

function Client:playSound(path)
  self:sendPacket(net.PLAY_SOUND, path)
end

-- modify player config
function Client:applyConfig(config)
  utils.mergeInto(config, self.player_config)
  self.player_config_changed = true
  self:sendPacket(net.PLAYER_CONFIG, config)
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

    self:sendPacket(net.STATS_UPDATE, {
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
    })
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

-- (async)
-- The client's status must be "logged" or "disconnecting".
function Client:save()
  -- Data consistency checks.
  -- Event execution and player trades are transactions which modify the state
  -- and may rollback.
  if self.running_event or self.trade then return false end
  -- base data
  server.db:query("user/setData", {
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
    armor_slot = self.armor_slot,
    stat_played = self.play_stats.played + os.time()-self.login_timestamp,
    stat_traveled = self.play_stats.traveled,
    stat_mob_kills = self.play_stats.mob_kills,
    stat_deaths = self.play_stats.deaths
  })
  -- vars
  local changed_vars = self.changed_vars
  self.changed_vars = {}
  for var in pairs(changed_vars) do
    server.db:query("user/setVar", {self.user_id, var, self.vars[var]})
  end
  -- bool vars
  local changed_bool_vars = self.changed_bool_vars
  self.changed_bool_vars = {}
  for var in pairs(changed_bool_vars) do
    server.db:query("user/setBoolVar", {self.user_id, var, self.bool_vars[var]})
  end
  -- inventories
  self.inventory:save(server.db)
  self.chest_inventory:save(server.db)
  self.spell_inventory:save(server.db)
  -- config
  if self.player_config_changed then
    server.db:query("user/setConfig", {self.user_id, {msgpack.pack(self.player_config)}})
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
  server.db:query("user/setState", {self.user_id, {msgpack.pack(state)}})
  return true
end

-- override
function Client:setHealth(health)
  Player.setHealth(self, health)
  self:sendPacket(net.STATS_UPDATE, {health = self.health, max_health = self.max_health})
  self:sendGroupUpdate()
end

-- override
function Client:setMana(mana)
  Player.setMana(self, mana)
  self:sendPacket(net.STATS_UPDATE, {mana = self.mana, max_mana = self.max_mana})
end

-- Note: extra sanitization on important values. If for some reason (e.g. a
-- bug) a player has "inf" golds, every gold transaction can lead to an
-- infection of all players becoming infinitly (or almost) rich.

function Client:setGold(gold)
  self.gold = math.max(0, utils.sanitizeInt(gold))
  self:sendPacket(net.STATS_UPDATE, {gold = self.gold})
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
  self:sendPacket(net.STATS_UPDATE, {
    xp = self.xp,
    current_xp = XPtable[self.level] or 0,
    next_xp = XPtable[self.level+1] or self.xp,
    level = self.level
  })
  self:updateCharacteristics()
  if self.level > old_level then -- level up effects
    self:emitSound("Holy2.wav")
    self:emitAnimation("heal.png", 0, 0, 48, 56, 0.75)
    self:emitHint({{1, 0.78, 0}, utils.fn("LEVEL UP!")})
  end
end

function Client:setAlignment(alignment)
  self.alignment = utils.clamp(utils.sanitizeInt(alignment), 0, 100)
  self:sendPacket(net.STATS_UPDATE, {alignment = self.alignment})
  self:broadcastPacket("update-alignment", self.alignment)
end

function Client:setReputation(reputation)
  self.reputation = utils.sanitizeInt(reputation)
  self:sendPacket(net.STATS_UPDATE, {reputation = self.reputation})
end

function Client:setRemainingPoints(remaining_pts)
  self.remaining_pts = math.max(0, utils.sanitizeInt(remaining_pts))
  self:sendPacket(net.STATS_UPDATE, {points = self.remaining_pts})
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
          act = "group-remove"
        })
        for client in pairs(group) do
          if client.map == self.map then
            -- leave packet to other group member
            if client ~= self then client:send(packet) end
            -- leave packet to self
            self:sendPacket(net.ENTITY_PACKET, {
              id = client.id,
              act = "group-remove"
            })
          end
        end
      end
      -- notify
      for client in pairs(group) do
        if client ~= self then
          client:print("\""..self.pseudo.."\" a quitté le groupe.")
        else
          client:print("Vous avez quitté le groupe \""..self.group.."\".")
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
        client:print("\""..self.pseudo.."\" a rejoint le groupe.")
      else
        client:print("Vous avez rejoint le groupe \""..self.group.."\".")
      end
    end
  end
  -- global group flag update
  self:broadcastPacket("group-flag", self.group ~= nil)
end

-- send group update packet (join/data)
function Client:sendGroupUpdate()
  -- broadcast update packet to group members on the map and to self (self included)
  local group = self.group and server.groups[self.group]
  if group and self.map then
    local packet = Client.makePacket(net.ENTITY_PACKET, {
      id = self.id,
      act = "group-update",
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
        self:sendPacket(net.ENTITY_PACKET, {
          id = client.id,
          act = "group-update",
          data = {health = client.health, max_health = client.max_health}
        })
      end
    end
  end
end

function Client:onPlayerKill()
  self.kill_player = 1
end

-- override
function Client:onDeath()
  -- stat
  self.play_stats.deaths = self.play_stats.deaths+1
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
      self.respawn_timer:close()
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
      self.respawn_timer:close()
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
  self:sendPacket(net.MAP_EFFECT, effect)
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
  id, value = utils.checkInt(id), utils.checkInt(value)
  local vars = (vtype == "bool" and self.bool_vars or self.vars)
  local changed_vars = (vtype == "bool" and self.changed_bool_vars or self.changed_vars)
  vars[id] = value
  changed_vars[id] = true
end

function Client:getVariable(vtype, id)
  id = utils.checkInt(id)
  local vars = (vtype == "bool" and self.bool_vars or self.vars)
  return vars[id] or 0
end

return Client
