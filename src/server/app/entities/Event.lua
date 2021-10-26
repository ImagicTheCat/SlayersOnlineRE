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

-- STATICS

Event.TRIGGER_RADIUS = 15 -- visibility/trigger radius in cells

local ORIENTED_ANIMATION_TYPES = utils.rmap({
  "static",
  "static-character",
  "character-random"
}, true)

-- PRIVATE METHODS

-- function vars definitions, map of id => function
-- form: %var(...)%
-- function(event, args...)

local function_vars = {}

function function_vars:rand(max)
  if max then
    return math.random(0, (tonumber(max) or 1)-1)
  end
end

function function_vars:min(a, b)
  if a and b then
    return math.min(tonumber(a) or 0, tonumber(b) or 0)
  end
end

function function_vars:max(a, b)
  if a and b then
    return math.max(tonumber(a) or 0, tonumber(b) or 0)
  end
end

function function_vars:upper(str)
  if str then
    return string.upper(str)
  end
end

-- special var accessor definitions, map of id => function
-- form: "%var%"
-- function(event, value): should return on get mode
--- value: nil on get mode
local special_vars = {}

function special_vars:Name(value)
  if not value then
    return self.client.pseudo
  end
end

function special_vars:UpperName(value)
  if not value then
    return (string.gsub(string.upper(self.client.pseudo), "%U", ""))
  end
end

function special_vars:Classe(value)
  if not value then
    local class_data = server.project.classes[self.client.class]
    return class_data.name
  end
end

function special_vars:Skin(value)
  if not value then
    return "Chipset\\"..self.client.charaset.path
  end
end

function special_vars:Force(value)
  if value then
    self.client.strength_pts = tonumber(value) or 0
    self.client:updateCharacteristics()
  else
    return self.client.strength_pts
  end
end

function special_vars:Dext(value)
  if value then
    self.client.dexterity_pts = tonumber(value) or 0
    self.client:updateCharacteristics()
  else
    return self.client.dexterity_pts
  end
end

function special_vars:Constit(value)
  if value then
    self.client.constitution_pts = tonumber(value) or 0
    self.client:updateCharacteristics()
  else
    return self.client.constitution_pts
  end
end

function special_vars:Magie(value)
  if value then
    self.client.magic_pts = tonumber(value) or 0
    self.client:updateCharacteristics()
  else
    return self.client.magic_pts
  end
end

function special_vars:Attaque(value)
  if value then
    self.client.ch_attack = tonumber(value) or 0
    self.client:sendPacket(net.STATS_UPDATE, {attack = self.client.ch_attack})
  else
    return self.client.ch_attack
  end
end

function special_vars:Defense(value)
  if value then
    self.client.ch_defense = tonumber(value) or 0
    self.client:sendPacket(net.STATS_UPDATE, {defense = self.client.ch_defense})
  else
    return self.client.ch_defense
  end
end

function special_vars:Vie(value)
  if value then
    value = tonumber(value) or 0
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
  end
end

function special_vars:CurrentMag(value)
  if value then
    self.client:setMana(tonumber(value) or 0)
  else
    return self.client.mana
  end
end

function special_vars:MagMax(value)
  if not value then
    return self.client.max_mana
  end
end

function special_vars:Alignement(value)
  if value then
    value = tonumber(value) or 0
    local delta = value-self.client.alignment
    self.client:emitHint(utils.fn(delta, true).." alignement")
    self.client:setAlignment(value)
  else
    return self.client.alignment
  end
end

function special_vars:Reputation(value)
  if value then
    value = tonumber(value) or 0
    local delta = value-self.client.alignment
    self.client:emitHint(utils.fn(delta, true).." réputation")
    self.client:setReputation(value)
  else
    return self.client.reputation
  end
end

function special_vars:Gold(value)
  if value then
    value = tonumber(value) or 0
    local delta = value-self.client.gold
    self.client:emitHint({{1,0.78,0}, utils.fn(delta, true)})
    self.client:setGold(value)
  else
    return self.client.gold
  end
end

function special_vars:Lvl(value)
  if value then
    local xp = XPtable[tonumber(value) or 0]
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
    self.client:setRemainingPoints(tonumber(value) or 0)
  else
    return self.client.remaining_pts
  end
end

function special_vars:CurrentXP(value)
  if value then
    value = tonumber(value) or 0
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
  end
end

function special_vars:Timer(value)
  if value then
    self.client.timers[1] = tonumber(value) or 0
  else
    return self.client.timers[1]
  end
end

function special_vars:Timer2(value)
  if value then
    self.client.timers[2] = tonumber(value) or 0
  else
    return self.client.timers[2]
  end
end

function special_vars:Timer3(value)
  if value then
    self.client.timers[3] = tonumber(value) or 0
  else
    return self.client.timers[3]
  end
end

function special_vars:KillPlayer(value)
  if value then
    self.client.kill_player = tonumber(value) or 0
  else
    return self.client.kill_player
  end
end

function special_vars:Visible(value)
  if value then
    self.client.visible = (tonumber(value) or 0) > 0
    self.client:broadcastPacket("ch_visible", visible)
  else
    return self.client.visible and 1 or 0
  end
end

function special_vars:Bloque(value)
  if value then
    self.client.blocked = (tonumber(value) or 0) > 0
  else
    return self.client.blocked and 1 or 0
  end
end

-- async
function special_vars:CaseX(value)
  if value then
    self.client:moveToCell(tonumber(value) or self.client.cx, self.client.cy, true)
  else
    return self.client.cx
  end
end

-- async
function special_vars:CaseY(value)
  if value then
    self.client:moveToCell(self.client.cx, tonumber(value) or self.client.cy, true)
  else
    return self.client.cy
  end
end

function special_vars:Position(value)
  if value then
    self.client.draw_order = tonumber(value) or 0
    self.client:broadcastPacket("ch_draw_order", self.client.draw_order)
  else
    return self.client.draw_order
  end
end

function special_vars:CentreX(value)
  if value then
    self.client.view_shift[1] = (tonumber(value) or 0)*(-16)
    self.client:sendPacket(net.VIEW_SHIFT_UPDATE, self.client.view_shift)
  else
    return self.client.view_shift[1]/-16
  end
end

function special_vars:CentreY(value)
  if value then
    self.client.view_shift[2] = (tonumber(value) or 0)*(-16)
    self.client:sendPacket(net.VIEW_SHIFT_UPDATE, self.client.view_shift)
  else
    return self.client.view_shift[2]/-16
  end
end

function special_vars:BloqueChangeSkin(value)
  if value then
    self.client.blocked_skin = (tonumber(value) or 0) > 0
  else
    return self.client.blocked_skin and 1 or 0
  end
end

function special_vars:BloqueAttaque(value)
  if value then
    self.client.blocked_attack = (tonumber(value) or 0) > 0
  else
    return self.client.blocked_attack and 1 or 0
  end
end

function special_vars:BloqueDefense(value)
  if value then
    self.client.blocked_defend = (tonumber(value) or 0) > 0
  else
    return self.client.blocked_defend and 1 or 0
  end
end

function special_vars:BloqueMagie(value)
  if value then
    self.client.blocked_cast = (tonumber(value) or 0) > 0
  else
    return self.client.blocked_cast and 1 or 0
  end
end

function special_vars:BloqueDialogue(value)
  if value then
    self.client.blocked_chat = (tonumber(value) or 0) > 0
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
  end
end

function special_vars:Arme(value)
  if not value then
    local item = server.project.objects[self.client.weapon_slot]
    return item and item.name or ""
  end
end

function special_vars:Bouclier(value)
  if not value then
    local item = server.project.objects[self.client.shield_slot]
    return item and item.name or ""
  end
end

function special_vars:Casque(value)
  if not value then
    local item = server.project.objects[self.client.helmet_slot]
    return item and item.name or ""
  end
end

function special_vars:Armure(value)
  if not value then
    local item = server.project.objects[self.client.armor_slot]
    return item and item.name or ""
  end
end

function special_vars:Direction(value)
  if value then
    self.client:setOrientation(tonumber(value) or 0)
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
  end
end

function special_vars:Rang(value)
  if not value then
    return self.client.guild_rank_title
  end
end

function special_vars:Grade(value)
  if not value then
    return self.client.guild_rank
  end
end

function special_vars:String1(value)
  if value then
    self.client.strings[1] = value
  else
    return self.client.strings[1]
  end
end

function special_vars:String2(value)
  if value then
    self.client.strings[2] = value
  else
    return self.client.strings[2]
  end
end

function special_vars:String3(value)
  if value then
    self.client.strings[3] = value
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
  end
end

function special_vars:Effect(value)
  if not value then
    return self.client.map_effect
  else self.client:setMapEffect(tonumber(value) or 0) end
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

    self.name = value

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
    self.obstacle = ((tonumber(value) or 0) > 0)
  else
    return (self.obstacle and 1 or 0)
  end
end

function event_vars:Visible(value)
  if value then
    self.active = ((tonumber(value) or 0) > 0)
    self:broadcastPacket("ch_active", self.active)
  else
    return (self.active and 1 or 0)
  end
end

function event_vars:TypeAnim(value)
  if value then
    value = tonumber(value) or 0
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
    self:moveAI() -- re-launch move random behavior
    self:broadcastPacket("ch_animation_type", data)
  else
    return self.animation_type
  end
end

function event_vars:Direction(value)
  if value then
    self:setOrientation(tonumber(value) or 0)
  else
    return self.orientation
  end
end

function event_vars:CaseX(value)
  if value then
    self:moveToCell(tonumber(value) or self.cx, self.cy, true)
  else
    return self.cx
  end
end

function event_vars:CaseY(value)
  if value then
    self:moveToCell(self.cx, tonumber(value) or self.cy, true)
  else
    return self.cy
  end
end

function event_vars:CaseNBX(value)
  if value then
    self:moveToCell(tonumber(value) or self.cx, self.cy)
  end
end

function event_vars:CaseNBY(value)
  if value then
    self:moveToCell(self.cx, tonumber(value) or self.cy)
  end
end

function event_vars:X(value)
  if value then
    self.charaset.x = (tonumber(value) or 0)
    self:setCharaset(self.charaset)
  else
    return self.charaset.x
  end
end

function event_vars:Y(value)
  if value then
    self.charaset.y = (tonumber(value) or 0)
    self:setCharaset(self.charaset)
  else
    return self.charaset.y
  end
end

function event_vars:W(value)
  if value then
    self.charaset.w = (tonumber(value) or 0)
    self:setCharaset(self.charaset)
  else
    return self.charaset.w
  end
end

function event_vars:H(value)
  if value then
    self.charaset.h = (tonumber(value) or 0)
    self:setCharaset(self.charaset)
  else
    return self.charaset.h
  end
end

function event_vars:NumAnim(value)
  if value then
    self.animation_number = (tonumber(value) or 0)
    self:broadcastPacket("ch_animation_number", self.animation_number)
  else
    return self.animation_number
  end
end

function event_vars:Vitesse(value)
  if value then
    self.speed = (tonumber(value) or 0)
  else
    return self.speed
  end
end

function event_vars:Transparent(value)
  if value then
    self:setGhost((tonumber(value) or 0) > 0)
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
  amount = tonumber(amount) or 1
  local id = server.project.objects_by_name[name]
  if id and amount > 0 then
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
end

function command_functions:DelObject(name, amount)
  amount = tonumber(amount) or 1
  local id = server.project.objects_by_name[name]
  if id and amount > 0 then
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
end

function command_functions:Teleport(map_name, cx, cy)
  local cx = tonumber(cx)
  local cy = tonumber(cy)

  if map_name and cx and cy then
    local map = server:getMap(map_name)
    if map then
      map:addEntity(self.client)
      self.client:teleport(cx*16, cy*16)
    end
  end
end

function command_functions:ChangeResPoint(map_name, cx, cy)
  cx = tonumber(cx)
  cy = tonumber(cy)

  if map_name and cx and cy then
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
end

function command_functions:SScroll(cx, cy)
  cx = tonumber(cx)
  cy = tonumber(cy)

  if cx and cy then
    self.client:scrollTo(cx*16, cy*16)
  end
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
  if msg then
    self.client:requestMessage(msg)
  end
end

function command_functions:InputString(title)
  return self.client:requestInputString(title)
end

function command_functions:InputQuery(title, ...)
  local options = {...}
  return options[self.client:requestInputQuery(title, options)] or ""
end

function command_functions:Magasin(title, ...)
  local items, items_id = {...}, {}
  local objects_by_name = server.project.objects_by_name
  for _, item in ipairs(items) do
    local id = objects_by_name[item]
    if id then table.insert(items_id, id) end
  end

  self.client:openShop(title, items_id)
end

function command_functions:Coffre(title)
  self.client:openChest(title)
end

function command_functions:GenereMonstre(name, x, y, amount)
  x,y,amount = tonumber(x), tonumber(y), tonumber(amount) or 0
  if name and x and y and amount > 0 then
    local mob_data = server.project.mobs[server.project.mobs_by_name[name]]
    if mob_data then
      for i=1,amount do
        local mob = Mob(mob_data)
        self.map:addEntity(mob)
        mob:teleport(x*16, y*16)
        self.map:bindGeneratedMob(mob)
      end
    end
  end
end

function command_functions:TueMonstre()
  self.map:killGeneratedMobs()
end

function command_functions:AddMagie(name, amount)
  amount = tonumber(amount) or 1
  local id = server.project.spells_by_name[name]
  if id and amount > 0 then
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
end

function command_functions:DelMagie(name, amount)
  amount = tonumber(amount) or 1
  local id = server.project.spells_by_name[name]
  if id and amount > 0 then
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
  amount = tonumber(amount) or 0
  if amount > 0 then
    self.wait_task = async()
    timer(amount*0.03, function()
      local r = self.wait_task
      if r then
        self.wait_task = nil
        r()
      end
    end)
    self.wait_task:wait()
  end
end

function command_functions:PlayMusic(path)
  local sub_path = string.match(path, "^Sound\\(.+)%.mid$")
  path = sub_path and sub_path..".ogg"

  if path then self.client:playMusic(path) end
end

function command_functions:StopMusic()
  self.client:stopMusic()
end

function command_functions:PlaySound(path)
  self.client:playSound(string.sub(path, 7)) -- remove Sound\ part
end

-- METHODS

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
    else return self.client:getVariable("var", id) end
  end
  local function bool_var(id, value)
    if value then
      -- save
      if not self.transaction.bool_vars[id] then
        self.transaction.bool_vars[id] = self.client:getVariable("bool", id)
      end
      -- set
      self.client:setVariable("bool", id, value)
    else return self.client:getVariable("bool", id) end
  end
  local function server_var(id, value)
    if value then
      -- save
      if not self.transaction.server_vars[id] then
        self.transaction.server_vars[id] = server:getVariable(id)
      end
      -- set
      server:setVariable(id, value)
    else return server:getVariable(id) end
  end
  local function special_var(id, value)
    local f = special_vars[id]
    if f then
      if value then
        -- save
        if not self.transaction.special_vars[id] and id ~= "CaseX" and id ~= "CaseY" then
          self.transaction.special_vars[id] = f(self)
        end
        -- set
        f(self, value)
      else return f(self) end
    end
  end
  local function func_var(id, ...)
    local f = function_vars[id]
    if f then return f(self, ...) end
  end
  local function event_var(event_id, id, value)
    local event = self.client.events_by_name[event_id]
    if event then
      local f = event_vars[id]
      if f then
        return f(event, value)
      end
    end
  end
  local function func(id, ...)
    local f = command_functions[id]
    if f then return f(self, ...) end
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
  if self.page.conditions_flags then
    self.trigger_auto = self.page.conditions_flags.auto
    self.trigger_auto_once = self.page.conditions_flags.auto_once
    self.trigger_attack = self.page.conditions_flags.attack
    self.trigger_contact = self.page.conditions_flags.contact
    self.trigger_interact = self.page.conditions_flags.interact
  end
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
    return ok and r
  end
  return false
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
  --print("EXECUTE", condition, self.map.id, self.cx, self.cy, self.page_index)
  if condition == "interact" then
    local atype = self.animation_type
    if atype == "character-random" or atype == "static-character" then
      -- look at player
      local orientation = LivingEntity.vectorOrientation(self.client.x-self.x, self.client.y-self.y)
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

-- randomly move the event if type is "character_random"
-- (starts a unique loop, will call itself again)
function Event:moveAI()
  local atype = self.animation_type
  if self.map and not self.move_ai_timer and
      (atype == "character-random" or atype == "character-follow") then
    self.move_ai_timer = timer(utils.randf(1, 5)/self.speed*(atype == "character-follow" and 0.25 or 1.5), function()
      if not self.client.running_event and self.map then -- prevent movement when an event is in execution
        if self.animation_type == "character-follow" then -- follow mode
          local dcx, dcy = self.client.cx-self.cx, self.client.cy-self.cy
          if math.abs(dcx)+math.abs(dcy) > 1 then -- too far, move to target
            local dx, dy = utils.sign(dcx), utils.sign(dcy)
            if dx ~= 0 and math.abs(dcx) > math.abs(dy) and self.map:isCellPassable(self, self.cx+dx, self.cy) then
              self:moveToCell(self.cx+dx, self.cy)
            elseif dy ~= 0 and self.map:isCellPassable(self, self.cx, self.cy+dy) then
              self:moveToCell(self.cx, self.cy+dy)
            end
          end
        else -- idle mode
          -- random movement
          local ok
          local ncx, ncy
          -- search for a passable cell
          local i = 1
          while not ok and i <= 10 do
            local orientation = math.random(0,3)
            local dx, dy = LivingEntity.orientationVector(orientation)
            ncx, ncy = self.cx+dx, self.cy+dy
            ok = self.map:isCellPassable(self, ncx, ncy)
            i = i+1
          end
          if ok then
            self:moveToCell(ncx, ncy)
          end
        end
      end
      -- next AI tick
      self.move_ai_timer = nil
      self:moveAI()
    end)
  end
end

-- override
function Event:onAttack(attacker)
  if class.is(attacker, Client) and self.trigger_attack then -- event
    self:trigger("attack")
    return true
  end
end

-- override
function Event:onMapChange()
  if self.map then -- added to map
    self:moveAI()
    -- reference event by name
    self.client.events_by_name[self.name] = self
    -- auto trigger
    if self.trigger_auto then
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
    elseif self.trigger_auto_once then
      self:trigger("auto_once")
    end
  else -- removed from map
    -- unreference event by name
    self.client.events_by_name[self.name] = nil
    -- unreference trigger
    self.client.triggered_events[self] = nil
    -- auto trigger
    if self.trigger_auto then
      self.trigger_task = nil
    end
  end
end

return Event
