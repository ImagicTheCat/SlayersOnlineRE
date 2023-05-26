-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

local utils = require("app.utils")
local Entity = require("app.Entity")
local Mob = require("app.entities.Mob")
local LivingEntity = require("app.entities.LivingEntity")
local XPtable = require("app.XPtable")
local net = require("app.protocol")
local Deserializer = require("app.Deserializer")
-- deferred
local Client
timer(0.01, function()
  Client = require("app.Client")
end)

local Event = class("Event", LivingEntity)

Event.TRIGGER_RADIUS = 15 -- visibility/trigger radius in cells
Event.FLEE_RADIUS = 6 -- cells

local ORIENTED_ANIMATION_TYPES = utils.bimap({
  "static",
  "static-character",
  "character-random"
}, true)

local checkInt = utils.checkInt

-- function vars definitions, map of id => function
-- form: %var(...)%
-- function(event, args...)

local function_vars = {}

function function_vars:rand(max)
  return math.random(0, checkInt(max)-1)
end

function function_vars:min(a, b)
  return math.min(checkInt(a), checkInt(b))
end

function function_vars:max(a, b)
  return math.max(checkInt(a), checkInt(b))
end

function function_vars:upper(str)
  return string.upper(str)
end

-- special var accessor definitions, map of id => function
-- form: "%var%"
-- function(event, value): should return on get mode
--- value: nil on get mode
local special_vars = {}

function special_vars:Name(value)
  if not value then
    return self.client.pseudo
  else
    error "can't set Name"
  end
end

function special_vars:UpperName(value)
  if not value then
    return (string.gsub(string.upper(self.client.pseudo), "%U", ""))
  else
    error "can't set UpperName"
  end
end

function special_vars:Classe(value)
  if not value then
    local class_data = server.project.classes[self.client.class]
    return class_data.name
  else
    error "can't set Classe"
  end
end

function special_vars:Skin(value)
  if not value then
    return "Chipset\\"..self.client.charaset.path
  else
    error "can't set Skin"
  end
end

function special_vars:Force(value)
  if value then
    self.client.strength_pts = checkInt(value)
    self.client:updateCharacteristics()
  else
    return self.client.strength_pts
  end
end

function special_vars:Dext(value)
  if value then
    self.client.dexterity_pts = checkInt(value)
    self.client:updateCharacteristics()
  else
    return self.client.dexterity_pts
  end
end

function special_vars:Constit(value)
  if value then
    self.client.constitution_pts = checkInt(value)
    self.client:updateCharacteristics()
  else
    return self.client.constitution_pts
  end
end

function special_vars:Magie(value)
  if value then
    self.client.magic_pts = checkInt(value)
    self.client:updateCharacteristics()
  else
    return self.client.magic_pts
  end
end

function special_vars:Attaque(value)
  if value then
    self.client.ch_attack = checkInt(value)
    self.client:sendPacket(net.STATS_UPDATE, {attack = self.client.ch_attack})
  else
    return self.client.ch_attack
  end
end

function special_vars:Defense(value)
  if value then
    self.client.ch_defense = checkInt(value)
    self.client:sendPacket(net.STATS_UPDATE, {defense = self.client.ch_defense})
  else
    return self.client.ch_defense
  end
end

function special_vars:Vie(value)
  if value then
    value = checkInt(value)
    local delta = value-self.client.health
    if delta > 0 then self.client:emitHint({{0,1,0}, utils.fn(delta)})
    elseif delta < 0 then self.client:broadcastPacket("damage", -delta) end
    self.client:setHealth(value)
  else
    return self.client.health
  end
end

function special_vars:VieMax(value)
  if not value then
    return self.client.max_health
  else
    error "can't set VieMax"
  end
end

function special_vars:CurrentMag(value)
  if value then
    self.client:setMana(checkInt(value))
  else
    return self.client.mana
  end
end

function special_vars:MagMax(value)
  if not value then
    return self.client.max_mana
  else
    error "can't set MagMax"
  end
end

function special_vars:Alignement(value)
  if value then
    value = checkInt(value)
    local delta = value-self.client.alignment
    self.client:emitHint(utils.fn(delta, true).." alignement")
    self.client:setAlignment(value)
  else
    return self.client.alignment
  end
end

function special_vars:Reputation(value)
  if value then
    value = checkInt(value)
    local delta = value-self.client.alignment
    self.client:emitHint(utils.fn(delta, true).." réputation")
    self.client:setReputation(value)
  else
    return self.client.reputation
  end
end

function special_vars:Gold(value)
  if value then
    value = checkInt(value)
    local delta = value-self.client.gold
    self.client:emitHint({{1,0.78,0}, utils.fn(delta, true)})
    self.client:setGold(value)
  else
    return self.client.gold
  end
end

function special_vars:Lvl(value)
  if value then
    local xp = XPtable[checkInt(value)]
    if xp then
      local delta = xp-self.client.xp
      self.client:emitHint({{0,0.9,1}, utils.fn(delta, true)})
      self.client:setXP(xp)
    end
  else
    return self.client.level
  end
end

function special_vars:LvlPoint(value)
  if value then
    self.client:setRemainingPoints(checkInt(value))
  else
    return self.client.remaining_pts
  end
end

function special_vars:CurrentXP(value)
  if value then
    value = checkInt(value)
    local delta = value-self.client.xp
    self.client:emitHint({{0,0.9,1}, utils.fn(delta, true)})
    self.client:setXP(tonumber(value) or 0)
  else
    return self.client.xp
  end
end

function special_vars:NextXP(value)
  if not value then
    return XPtable[self.client.level+1] or self.client.xp
  else
    error "can't set NextXP"
  end
end

function special_vars:Timer(value)
  if value then
    self.client.timers[1] = checkInt(value)
  else
    return self.client.timers[1]
  end
end

function special_vars:Timer2(value)
  if value then
    self.client.timers[2] = checkInt(value)
  else
    return self.client.timers[2]
  end
end

function special_vars:Timer3(value)
  if value then
    self.client.timers[3] = checkInt(value)
  else
    return self.client.timers[3]
  end
end

function special_vars:KillPlayer(value)
  if value then
    self.client.kill_player = checkInt(value)
  else
    return self.client.kill_player
  end
end

function special_vars:Visible(value)
  if value then
    self.client.visible = checkInt(value) > 0
    self.client:broadcastPacket("ch-visible", self.client.visible)
  else
    return self.client.visible and 1 or 0
  end
end

function special_vars:Bloque(value)
  if value then
    self.client.blocked = checkInt(value) > 0
  else
    return self.client.blocked and 1 or 0
  end
end

-- async
function special_vars:CaseX(value)
  if value then
    self.client:moveToCell(checkInt(value), self.client.cy, true)
  else
    return self.client.cx
  end
end

-- async
function special_vars:CaseY(value)
  if value then
    self.client:moveToCell(self.client.cx, checkInt(value), true)
  else
    return self.client.cy
  end
end

function special_vars:Position(value)
  if value then
    self.client.draw_order = checkInt(value)
    self.client:broadcastPacket("ch-draw-order", self.client.draw_order)
  else
    return self.client.draw_order
  end
end

function special_vars:CentreX(value)
  if value then
    self.client.view_shift[1] = checkInt(value) * -16
    self.client:sendPacket(net.VIEW_SHIFT_UPDATE, self.client.view_shift)
  else
    return self.client.view_shift[1] / -16
  end
end

function special_vars:CentreY(value)
  if value then
    self.client.view_shift[2] = checkInt(value) * -16
    self.client:sendPacket(net.VIEW_SHIFT_UPDATE, self.client.view_shift)
  else
    return self.client.view_shift[2] / -16
  end
end

function special_vars:BloqueChangeSkin(value)
  if value then
    self.client.blocked_skin = checkInt(value) > 0
  else
    return self.client.blocked_skin and 1 or 0
  end
end

function special_vars:BloqueAttaque(value)
  if value then
    self.client.blocked_attack = checkInt(value) > 0
  else
    return self.client.blocked_attack and 1 or 0
  end
end

function special_vars:BloqueDefense(value)
  if value then
    self.client.blocked_defend = checkInt(value) > 0
  else
    return self.client.blocked_defend and 1 or 0
  end
end

function special_vars:BloqueMagie(value)
  if value then
    self.client.blocked_cast = checkInt(value) > 0
  else
    return self.client.blocked_cast and 1 or 0
  end
end

function special_vars:BloqueDialogue(value)
  if value then
    self.client.blocked_chat = checkInt(value) > 0
  else
    return self.client.blocked_chat and 1 or 0
  end
end

function special_vars:BloqueChevauchement(value)
  -- disabled
  if not value then return 0 end
end

function special_vars:NbObjetInventaire(value)
  if not value then
    return self.client.inventory:getAmount()
  else
    error "can't set NbObjetInventaire"
  end
end

function special_vars:Arme(value)
  if not value then
    local item = server.project.objects[self.client.weapon_slot]
    return item and item.name or ""
  else
    error "can't set Arme"
  end
end

function special_vars:Bouclier(value)
  if not value then
    local item = server.project.objects[self.client.shield_slot]
    return item and item.name or ""
  else
    error "can't set Bouclier"
  end
end

function special_vars:Casque(value)
  if not value then
    local item = server.project.objects[self.client.helmet_slot]
    return item and item.name or ""
  else
    error "can't set Casque"
  end
end

function special_vars:Armure(value)
  if not value then
    local item = server.project.objects[self.client.armor_slot]
    return item and item.name or ""
  else
    error "can't set Armure"
  end
end

function special_vars:Direction(value)
  if value then
    self.client:setOrientation(checkInt(value))
  else
    return self.client.orientation
  end
end

function special_vars:Groupe(value)
  if not value then
    return self.client.group or ""
  else
    self.client:setGroup(#value > 0 and value or nil)
  end
end

function special_vars:Guilde(value)
  if not value then
    return self.client.guild
  else
    error "can't set Guilde"
  end
end

function special_vars:Rang(value)
  if not value then
    return self.client.guild_rank_title
  else
    error "can't set Rang"
  end
end

function special_vars:Grade(value)
  if not value then
    return self.client.guild_rank
  else
    error "can't set Grade"
  end
end

function special_vars:String1(value)
  if value then
    self.client.strings[1] = tostring(value)
  else
    return self.client.strings[1]
  end
end

function special_vars:String2(value)
  if value then
    self.client.strings[2] = tostring(value)
  else
    return self.client.strings[2]
  end
end

function special_vars:String3(value)
  if value then
    self.client.strings[3] = tostring(value)
  else
    return self.client.strings[3]
  end
end

function special_vars:EvCaseX(value)
  if not value then
    return self.cx
  end
end

function special_vars:EvCaseY(value)
  if not value then
    return self.cy
  else
    error "can't set EvCaseY"
  end
end

function special_vars:Effect(value)
  if not value then
    return self.client.map_effect
  else
    self.client:setMapEffect(checkInt(value))
  end
end

-- aliases
special_vars.BloqueAttaqueLocal = special_vars.BloqueAttaque
special_vars.BloqueDefenseLocal = special_vars.BloqueDefense
special_vars.BloqueMagieLocal = special_vars.BloqueMagie

-- event vars, map of id => function
-- form: "%Ev.var%"
-- function(event, value): should return on get mode
--- value: nil on get mode
local event_vars = {}

function event_vars:Name(value)
  if value then
    -- unreference
    local entity = self.client.events_by_name[self.name]
    if entity == self then
      self.client.events_by_name[self.name] = nil
    end
    self.name = tostring(value)
    -- reference
    self.client.events_by_name[self.name] = self
  else
    return self.page.name
  end
end

function event_vars:Chipset(value)
  if value then
    self.charaset.path = string.sub(value, 9) -- remove Chipset/ part
    self:setCharaset(self.charaset)
  else
    return "Chipset\\"..self.charaset.path
  end
end

function event_vars:Bloquant(value)
  if value then
    self.obstacle = checkInt(value) > 0
  else
    return (self.obstacle and 1 or 0)
  end
end

function event_vars:Visible(value)
  if value then
    self.active = checkInt(value) > 0
    self:broadcastPacket("ch-active", self.active)
  else
    return (self.active and 1 or 0)
  end
end

function event_vars:TypeAnim(value)
  if value then
    value = checkInt(value)
    self.animation_type = Deserializer.EVENT_ANIMATION_TYPES[value] or "static"
    -- update
    local data = {animation_type = self.animation_type}
    if ORIENTED_ANIMATION_TYPES[self.animation_type] then
      self:setOrientation(self.page.animation_mod)
    end
    if self.animation_type ~= "visual-effect" then
      data.animation_number = self.animation_number
    else
      data.animation_wc = math.max(self.page.animation_number, 1)
      data.animation_hc = math.max(self.page.animation_mod, 1)
    end
    self:startAI()
    self:broadcastPacket("ch-animation-type", data)
  else
    return self.animation_type
  end
end

function event_vars:Direction(value)
  if value then
    self:setOrientation(checkInt(value))
  else
    return self.orientation
  end
end

function event_vars:CaseX(value)
  if value then
    self:moveToCell(checkInt(value), self.cy, true)
  else
    return self.cx
  end
end

function event_vars:CaseY(value)
  if value then
    self:moveToCell(self.cx, checkInt(value), true)
  else
    return self.cy
  end
end

function event_vars:CaseNBX(value)
  if value then
    self:moveToCell(checkInt(value), self.cy)
  else
    error "can't set Ev.CaseNBX"
  end
end

function event_vars:CaseNBY(value)
  if value then
    self:moveToCell(self.cx, checkInt(value))
  else
    error "can't set Ev.CaseNBY"
  end
end

function event_vars:X(value)
  if value then
    self.charaset.x = checkInt(value)
    self:setCharaset(self.charaset)
  else
    return self.charaset.x
  end
end

function event_vars:Y(value)
  if value then
    self.charaset.y = checkInt(value)
    self:setCharaset(self.charaset)
  else
    return self.charaset.y
  end
end

function event_vars:W(value)
  if value then
    self.charaset.w = checkInt(value)
    self:setCharaset(self.charaset)
  else
    return self.charaset.w
  end
end

function event_vars:H(value)
  if value then
    self.charaset.h = checkInt(value)
    self:setCharaset(self.charaset)
  else
    return self.charaset.h
  end
end

function event_vars:NumAnim(value)
  if value then
    self.animation_number = checkInt(value)
    self:broadcastPacket("ch-animation-number", self.animation_number)
  else
    return self.animation_number
  end
end

function event_vars:Vitesse(value)
  if value then
    self.speed = checkInt(value)
  else
    return self.speed
  end
end

function event_vars:Transparent(value)
  if value then
    self:setGhost(checkInt(value) > 0)
  else
    return self.ghost and 1 or 0
  end
end

function event_vars:AnimAttaque(value)
  if value then self:act("attack", 1)
  else return 0 end
end

function event_vars:AnimDefense(value)
  if value then self:act("defend", 1)
  else return 0 end
end

function event_vars:AnimMagie(value)
  if value then self:act("cast", 1)
  else return 0 end
end

-- command function definitions, map of id => function
-- form: Command(...)
-- function(event, args...)
local command_functions = {}

function command_functions:AddObject(name, amount)
  amount = amount and checkInt(amount) or 1
  local id = server.project.objects_by_name[name]
  assert(id, "couldn't find item")
  assert(amount > 0, "invalid amount")
  -- save
  if not self.transaction.items[id] then
    self.transaction.items[id] = self.client.inventory:get(id)
  end
  -- set
  local count = 0
  for i=1,amount do
    if self.client.inventory:put(id) then count = count+1 end
  end
  if count > 0 then self.client:emitHint("+ "..name..(count > 1 and " x"..count or "")) end
end

function command_functions:DelObject(name, amount)
  amount = amount and checkInt(amount) or 1
  local id = server.project.objects_by_name[name]
  assert(id, "couldn't find item")
  assert(amount > 0, "invalid amount")
  -- save
  if not self.transaction.items[id] then
    self.transaction.items[id] = self.client.inventory:get(id)
  end
  -- set
  local count = 0
  for i=1,amount do
    if self.client.inventory:take(id) then count = count+1 end
  end
  if count > 0 then self.client:emitHint("- "..name..(count > 1 and " x"..count or "")) end
end

function command_functions:Teleport(map_name, cx, cy)
  local cx, cy = checkInt(cx), checkInt(cy)
  assert(type(map_name) == "string", "invalid map name")
  local map = server:getMap(map_name)
  assert(map, "couldn't find map")
  self.client.prevent_next_contact = true -- prevent teleport loop
  map:addEntity(self.client)
  self.client:teleport(cx*16, cy*16)
end

function command_functions:ChangeResPoint(map_name, cx, cy)
  cx, cy = checkInt(cx), checkInt(cy)
  assert(type(map_name) == "string", "invalid map name")
  -- save
  if not self.transaction.respawn_point then
    self.transaction.respawn_point = self.client.respawn_point
  end
  -- set
  self.client.respawn_point = {
    map = map_name,
    cx = cx,
    cy = cy
  }
end

function command_functions:SScroll(cx, cy)
  cx, cy = checkInt(cx), checkInt(cy)
  self.client:scrollTo(cx*16, cy*16)
end

function command_functions:ChangeSkin(path)
  -- save
  if not self.transaction.charaset then
    self.transaction.charaset = self.client.charaset
  end
  -- set
  self.client:setCharaset({
    path = string.sub(path, 9), -- remove "Chipset/" part
    x = 0, y = 0,
    w = 24, h = 32
  })
end

function command_functions:Message(msg)
  assert(msg, "missing message")
  self.client:requestMessage(msg)
end

function command_functions:InputString(title)
  assert(title, "missing title")
  return self.client:requestInputString(title)
end

function command_functions:InputQuery(title, ...)
  assert(title, "missing title")
  local options = {...}
  return options[self.client:requestInputQuery(title, options)] or ""
end

function command_functions:Magasin(title, ...)
  assert(title, "missing title")
  local items, items_id = {...}, {}
  local objects_by_name = server.project.objects_by_name
  for _, item in ipairs(items) do
    local id = objects_by_name[item]
    if id then table.insert(items_id, id) end
  end
  self.client:openShop(title, items_id)
end

function command_functions:Coffre(title)
  assert(title, "missing title")
  self.client:openChest(title)
end

function command_functions:GenereMonstre(name, x, y, amount)
  x, y, amount = checkInt(x), checkInt(y), checkInt(amount)
  assert(amount > 0, "invalid amount")
  local mob_data = server.project.mobs[server.project.mobs_by_name[name]]
  assert(mob_data, "couldn't find mob data")
  for i=1,amount do
    local mob = Mob(mob_data)
    self.map:addEntity(mob)
    mob:teleport(x*16, y*16)
    self.map:bindGeneratedMob(mob)
  end
end

function command_functions:TueMonstre()
  self.map:killGeneratedMobs()
end

function command_functions:AddMagie(name, amount)
  amount = amount and checkInt(amount) or 1
  local id = server.project.spells_by_name[name]
  assert(id, "couldn't find spell")
  assert(amount > 0, "invalid amount")
  -- save
  if not self.transaction.spells[id] then
    self.transaction.spells[id] = self.client.spell_inventory:get(id)
  end
  -- set
  local count = 0
  for i=1,amount do
    if self.client.spell_inventory:put(id) then count = count+1 end
  end
  if count > 0 then self.client:emitHint("+ "..name..(count > 1 and " x"..count or "")) end
end

function command_functions:DelMagie(name, amount)
  amount = amount and checkInt(amount) or 1
  local id = server.project.spells_by_name[name]
  assert(id, "couldn't find spell")
  assert(amount > 0, "invalid amount")
  -- save
  if not self.transaction.spells[id] then
    self.transaction.spells[id] = self.client.spell_inventory:get(id)
  end
  -- set
  local count = 0
  for i=1,amount do
    if self.client.spell_inventory:take(id) then count = count+1 end
  end
  if count > 0 then self.client:emitHint("- "..name..(count > 1 and " x"..count or "")) end
end

function command_functions:ChAttaqueSound(path)
  -- save
  if not self.transaction.attack_sound then
    self.transaction.attack_sound = self.client.attack_sound
  end
  -- set
  -- remove Sound/ part
  self.client:setSounds(string.sub(path, 7), self.client.hurt_sound)
end

function command_functions:ChBlesseSound(path)
  -- save
  if not self.transaction.hurt_sound then
    self.transaction.hurt_sound = self.client.hurt_sound
  end
  -- set
  -- remove Sound/ part
  self.client:setSounds(self.client.attack_sound, string.sub(path, 7))
end

function command_functions:Attente(amount)
  amount = checkInt(amount)
  assert(amount > 0, "invalid amount")
  self.wait_task = async()
  timer(amount*0.03, function()
    local task = self.wait_task
    if task then
      self.wait_task = nil
      task:complete()
    end
  end)
  self.wait_task:wait()
end

function command_functions:PlayMusic(path)
  local sub_path = string.match(path, "^Sound\\(.+)%.mid$")
  assert(sub_path, "wrong path")
  path = sub_path..".ogg"
  self.client:playMusic(path)
end

function command_functions:StopMusic()
  self.client:stopMusic()
end

function command_functions:PlaySound(path)
  self.client:playSound(string.sub(path, 7)) -- remove Sound\ part
end

-- expose definitions
Event.special_vars = special_vars
Event.function_vars = function_vars
Event.event_vars = event_vars
Event.command_functions = command_functions

-- Event class

-- page_index: specific state or nil
function Event:__construct(client, data, page_index)
  LivingEntity.__construct(self)
  self.nettype = "Event"
  self:setClient(client)
  -- prepare event's execution environment
  local function var(id, value)
    if value then
      -- save
      if not self.transaction.vars[id] then
        self.transaction.vars[id] = self.client:getVariable("var", id)
      end
      -- set
      self.client:setVariable("var", id, value)
    else
      return self.client:getVariable("var", id)
    end
  end
  local function bool_var(id, value)
    if value then
      -- save
      if not self.transaction.bool_vars[id] then
        self.transaction.bool_vars[id] = self.client:getVariable("bool", id)
      end
      -- set
      self.client:setVariable("bool", id, value)
    else
      return self.client:getVariable("bool", id)
    end
  end
  local function server_var(id, value)
    if value then
      -- save
      if not self.transaction.server_vars[id] then
        self.transaction.server_vars[id] = server:getVariable(id)
      end
      -- set
      server:setVariable(id, value)
    else
      return server:getVariable(id)
    end
  end
  local function special_var(id, value)
    local f = special_vars[id]
    if not f then error("unknown special var "..string.format("%q", id)) end
    if value then
      -- save
      if not self.transaction.special_vars[id] and id ~= "CaseX" and id ~= "CaseY" then
        self.transaction.special_vars[id] = f(self)
      end
      -- set
      f(self, value)
    else
      return f(self)
    end
  end
  local function func_var(id, ...)
    local f = function_vars[id]
    if not f then error("unknown function var "..string.format("%q", id)) end
    return f(self, ...)
  end
  local function event_var(event_id, id, value)
    local event = self.client.events_by_name[event_id]
    if not event then error("couldn't find event "..string.format("%q", event_id)) end
    local f = event_vars[id]
    if not f then error("unknown event var "..string.format("%q", id)) end
    return f(event, value)
  end
  local function func(id, ...)
    local f = command_functions[id]
    if not f then error("unknown command "..string.format("%q", id)) end
    return f(self, ...)
  end
  local function inventory(item)
    -- return item quantity in inventory
    local id = server.project.objects_by_name[item]
    return id and self.client.inventory.items[id] or 0
  end
  self.env = {var, bool_var, server_var, special_var, func_var, event_var, func, inventory}
  -- setup data
  self.data = data -- event data
  self.page_index = page_index or self:selectPage()
  self.page = self.data.pages[self.page_index]
  self.name = self.page.name
  self:setCharaset({
    path = string.sub(self.page.set, 9), -- remove Chipset/ part
    x = self.page.set_x, y = self.page.set_y,
    w = self.page.w, h = self.page.h
  })
  self.obstacle = self.page.obstacle
  self.active = self.page.active and #self.page.set > 0 -- (active/visible)
  self.animation_type = self.page.animation_type
  self.animation_number = self.page.animation_number
  self.speed = self.page.speed
  self:setGhost(self.page.transparent)
  if ORIENTED_ANIMATION_TYPES[self.animation_type] then
    self.orientation = self.page.animation_mod
  end
end

-- override
function Event:setOrientation(orientation)
  LivingEntity.setOrientation(self, orientation)
end

local function error_handler(err)
  io.stderr:write(debug.traceback("event: "..err, 2).."\n")
end

-- check if the page conditions are valid
-- return bool
function Event:checkConditions(page)
  if page.conditions_func then
    local ok, r = xpcall(page.conditions_func, error_handler, nil, unpack(self.env))
    if not ok then self.client:notifyEventError() end
    return ok and r
  end
  return false
end

function Event:hasConditionFlag(flag)
  return self.page.conditions_flags and self.page.conditions_flags[flag]
end

-- search for a valid page
-- return page index
function Event:selectPage()
  for i, page in ipairs(self.data.pages) do
    if self:checkConditions(page) then return i end
  end
  return #self.data.pages
end

-- trigger the event (marked for execution, doesn't execute the event)
-- condition: type triggered
function Event:trigger(condition)
--  print("TRIGGER", condition, self.cx, self.cy, self.page_index)
  self.client.triggered_events[self] = condition
end

-- (async) execute event script commands
-- condition: type triggered
function Event:execute(condition)
--  print("EXECUTE", condition, self.map.id, self.cx, self.cy, self.page_index)
  if condition == "interact" then
    local atype = self.animation_type
    if atype == "character-random" or atype == "static-character" then
      -- look at player
      local orientation = utils.vectorOrientation(self.client.x-self.x, self.client.y-self.y)
      self:setOrientation(orientation)
    end
  end
  -- init transaction and state
  self:startTransaction()
  local state = {
    condition = condition
  }
  self.page.commands_func(state, unpack(self.env))
  -- end
  self.client:resetScroll()
end

-- The transaction is used to handle the "soft" event interruptions like an
-- event error, client disconnection or server shutdown by doing a rollback.
function Event:startTransaction()
  self.transaction = {
    -- values to be restored
    server_vars = {},
    vars = {},
    bool_vars = {},
    special_vars = {},
    items = {},
    spells = {}
  }
end

-- Rollback event execution effects.
function Event:rollback()
  local tr = self.transaction
  -- restore values
  for k,v in pairs(tr.vars) do self.client:setVariable("var", k, v) end
  for k,v in pairs(tr.bool_vars) do self.client:setVariable("bool", k, v) end
  for k,v in pairs(tr.server_vars) do server:setVariable(k, v) end
  for k,v in pairs(tr.special_vars) do special_vars[k](self, v) end
  for id, amount in pairs(tr.items) do self.client.inventory:set(id, amount) end
  for id, amount in pairs(tr.spells) do self.client.spell_inventory:set(id, amount) end
  if tr.respawn_point then self.client.respawn_point = tr.respawn_point end
  if tr.charaset then self.client.charaset = tr.charaset end
  if tr.hurt_sound or tr.attack_sound then
    self.client:setSounds(tr.attack_sound or self.client.attack_sound,
      tr.hurt_sound or self.client.hurt_sound)
  end
end

-- override
function Event:serializeNet()
  local data = LivingEntity.serializeNet(self)

  data.animation_type = self.animation_type
  data.position_type = self.page.position_type

  if self.animation_type ~= "visual-effect" then
    data.orientation = self.orientation
    data.animation_number = self.animation_number
  else
    data.animation_wc = math.max(self.page.animation_number, 1)
    data.animation_hc = math.max(self.page.animation_mod, 1)
  end

  data.active = self.active

  return data
end

-- Find a random cell for idle movements.
-- return (cx, cy) or nothing
local function findRandomCell(self)
  local ncx, ncy
  local dirs = {0,1,2,3}
  while #dirs > 0 do
    local i = math.random(1, #dirs)
    local orientation = dirs[i]
    table.remove(dirs, i)
    local dx, dy = utils.orientationVector(orientation)
    ncx, ncy = self.cx+dx, self.cy+dy
    if self.map:isCellPassable(self, ncx, ncy) then return ncx, ncy end
  end
end

-- async
local function AI_thread(self)
  while self.map and (self.animation_type == "character-random" or
      self.animation_type == "character-follow") do
    if not self.client.running_event then -- prevent movement during event execution
      if self.animation_type == "character-follow" then -- follow mode
        local dx, dy = self.client.x-self.x, self.client.y-self.y
        if math.sqrt(dx*dx+dy*dy) > 16 then -- too far, move to target
          local sdx, sdy = utils.sign(dx), utils.sign(dy)
          if math.abs(dx) > math.abs(dy) then
            if self.map:isCellPassable(self, self.cx+sdx, self.cy) then
              self:moveToCell(self.cx+sdx, self.cy)
            elseif self.map:isCellPassable(self, self.cx, self.cy+sdy) then
              self:moveToCell(self.cx, self.cy+sdy)
            end
          else
            if self.map:isCellPassable(self, self.cx, self.cy+sdy) then
              self:moveToCell(self.cx, self.cy+sdy)
            elseif self.map:isCellPassable(self, self.cx+sdx, self.cy) then
              self:moveToCell(self.cx+sdx, self.cy)
            end
          end
        end
      else -- idle mode
        local ncx, ncy
        if self.speed < 0 then -- flee mode
          -- compute flee probability based on distance to player
          local dx, dy = self.client.x-self.x, self.client.y-self.y
          local dist = math.sqrt(dx*dx+dy*dy)
          local flee_probability = 1-dist/(Event.FLEE_RADIUS*16)
          if math.random() < flee_probability then
            local dcx, dcy = utils.dvec(-dx, -dy)
            if self.map:isCellPassable(self, self.cx+dcx, self.cy+dcy) then
              ncx, ncy = self.cx+dcx, self.cy+dcy
            end
          end
        end
        -- fallback to random movements
        if not ncx then ncx, ncy = findRandomCell(self) end
        -- move
        if ncx then self:moveToCell(ncx, ncy) end
      end
    end
    wait(utils.randf(1,5)/math.abs(self.speed) *
      (self.animation_type == "character-follow" and 0.25 or 1.5) *
      (self.speed < 0 and 0.5 or 1))
  end
end

function Event:startAI()
  if (not self.ai_task or self.ai_task:done()) and
     (self.animation_type == "character-random" or
      self.animation_type == "character-follow") then
    self.ai_task = async(AI_thread, self)
    -- propagate errors
    self.ai_task:wait(function(task) task:wait() end)
  end
end

-- override
function Event:onAttack(attacker)
  if xtype.is(attacker, Client) and self:hasConditionFlag("attack") then -- event
    self:trigger("attack")
    return true
  end
end

-- override
function Event:onMapChange()
  if self.map then -- added to map
    self:startAI()
    -- reference event by name
    self.client.events_by_name[self.name] = self
    -- auto trigger
    if self:hasConditionFlag("auto") then
      self.trigger_task = true
      -- task iteration
      local function iteration()
        timer(0.5, function()
            if self.trigger_task then
              self:trigger("auto")
              iteration()
            end
        end)
      end
      self:trigger("auto")
      iteration()
    elseif self:hasConditionFlag("auto-once") then
      self:trigger("auto-once")
    end
  else -- removed from map
    -- unreference event by name
    self.client.events_by_name[self.name] = nil
    -- unreference trigger
    self.client.triggered_events[self] = nil
    -- auto trigger
    if self:hasConditionFlag("auto") then
      self.trigger_task = nil
    end
  end
end

return Event
