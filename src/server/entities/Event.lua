local utils = require("lib.utils")
local Entity = require("Entity")
local Mob = require("entities.Mob")
local LivingEntity = require("entities.LivingEntity")
local XPtable = require("XPtable")
local net = require("protocol")
-- deferred
local Client
task(0.01, function()
  Client = require("Client")
end)

local Event = class("Event", LivingEntity)

-- STATICS

Event.TRIGGER_RADIUS = 15 -- visibility/trigger radius in cells

Event.Position = {
  DYNAMIC = 0,
  FRONT = 1,
  BACK = 2
}

Event.Animation = {
  STATIC = 0,
  STATIC_CHARACTER = 1,
  CHARACTER_RANDOM = 2,
  VISUAL_EFFECT = 3,
  CHARACTER_FOLLOW = 4
}

Event.Condition = {
  INTERACT = 0,
  AUTO = 1,
  AUTO_ONCE = 2,
  CONTACT = 3,
  ATTACK = 4,
  VARIABLE = 5,
  EXPRESSION = 6
}

Event.Variable = {
  SERVER = 0,
  CLIENT = 1,
  CLIENT_SPECIAL = 2,
  EVENT_SPECIAL = 3
}

Event.Command = {
  VARIABLE = 0,
  FUNCTION = 1
}

Event.patterns = {
  server_var = "Serveur%[([%w_%-%%éèàçê]+)%]", -- Serveur[string]
  client_var = "Variable%[([%d%.]+)%]", -- Variable[int]
  client_bool_var = "Bool%[([%d%.]+)%]", -- Bool[int]
  event_special_var = "%%([^%.%%]+)%.([^%.%s%%%(%)]+)%%", -- %Nom Ev.Var%
  client_special_var = "%%([^%.%s%%%(%)]+)%%" -- %Var%
}

-- return (Event.Variable type, parameters...) or nil
function Event.parseVariableInstruction(instruction)
  local lhs, op, rhs = string.match(instruction, "^(.-)([<>!=]+)(.*)$")
  if lhs then
    -- detect variable kind
    local id, ids, name

    local pat = Event.patterns

    id = string.match(lhs, "^"..pat.server_var.."$")
    if id then return Event.Variable.SERVER, id, op, rhs end

    -- id range
    id = string.match(lhs, "^"..pat.client_var.."$")
    ids = (id and utils.split(id, "%.%.") or {})
    for i=1,#ids do ids[i] = math.floor(tonumber(ids[i])) end
    if ids[1] then return Event.Variable.CLIENT, "var", ids, op, rhs end

    -- id range
    id = string.match(lhs, "^"..pat.client_bool_var.."$")
    ids = (id and utils.split(id, "%.%.") or {})
    for i=1,#ids do ids[i] = math.floor(tonumber(ids[i])) end
    if ids[1] then return Event.Variable.CLIENT, "bool", ids, op, rhs end

    name, id = string.match(lhs, "^"..pat.event_special_var.."$")
    if name then return Event.Variable.EVENT_SPECIAL, name, id, op, rhs end

    id = string.match(lhs, "^"..pat.client_special_var.."$")
    if id then return Event.Variable.CLIENT_SPECIAL, id, op, rhs end
  end
end

-- return (Event.Condition type, parameters...) or nil
function Event.parseCondition(instruction)
  if instruction == "Appuie sur bouton" then return Event.Condition.INTERACT end
  if instruction == "Automatique" then return Event.Condition.AUTO end
  if instruction == "Auto une seul fois" then return Event.Condition.AUTO_ONCE end
  if instruction == "En contact" then return Event.Condition.CONTACT end
  if instruction == "Attaque" then return Event.Condition.ATTACK end

  -- variable condition
  local r = {Event.parseVariableInstruction(instruction)}
  if r[1] then
    return Event.Condition.VARIABLE, unpack(r)
  end

  -- anonymous condition
  local lhs, op, rhs = string.match(instruction, "^(.-)([<>!=]+)(.*)$")
  if lhs then
    return Event.Condition.EXPRESSION, lhs, op, rhs
  end
end

-- return (Event.Command type, parameters...) or nil
function Event.parseCommand(instruction)
  if string.sub(instruction, 1, 2) == "//" then return end -- ignore comment

  -- variable commands
  local r = {Event.parseVariableInstruction(instruction)}
  if r[1] then
    return Event.Command.VARIABLE, unpack(r)
  end

  -- function
  local id, content = string.match(instruction, "^([%w_]+)%(?(.-)%)?$")
  if id then -- parse arguments
    local args = {}
    if string.sub(content, 1, 1) == "'" then -- textual
      args = utils.split(string.sub(content, 2, string.len(content)-1), "','")
    else -- raw
      for arg in string.gmatch(content, "([^,]+)") do
        table.insert(args, arg)
      end
    end

    return Event.Command.FUNCTION, id, unpack(args)
  end
end

-- process/compute string expression using basic Lua features
-- return computed number (integer) or nil on failure
function Event.computeExpression(str)
  if string.find(str, "[^%.%*/%-%+%(%)%d%s]") then return end -- reject on unallowed characters

  local expr = "return "..str
  local f = utils.loadstring(expr)
  local ok, r = pcall(f)
  if ok then
    local n = tonumber(r)
    if n and n == n and math.abs(n) ~= 1/0 then -- reject NaN/inf values
      return utils.round(n)
    end
  end
end

-- PRIVATE METHODS

-- special var function definitions, map of id => function
-- function(event, args...): should return a number or a string
--- args...: passed string expressions (after substitution)

local client_special_vfunctions = {}

function client_special_vfunctions:rand(max)
  if max then
    return math.random(0, (Event.computeExpression(max) or 1)-1)
  end
end

function client_special_vfunctions:min(a, b)
  if a and b then
    return math.min(Event.computeExpression(a) or 0, Event.computeExpression(b) or 0)
  end
end

function client_special_vfunctions:max(a, b)
  if a and b then
    return math.max(Event.computeExpression(a) or 0, Event.computeExpression(b) or 0)
  end
end

function client_special_vfunctions:upper(str)
  if str then
    return string.upper(str)
  end
end

-- special var accessor definitions, map of id => function
-- function(event, value): should return a number or a string on get mode
--- value: passed string expression (after substitution) on set mode (nil on get mode)

-- form: "%<var>%"
local client_special_vars = {}

function client_special_vars:Name(value)
  if not value then
    return self.client.pseudo
  end
end

function client_special_vars:UpperName(value)
  if not value then
    return string.gsub(string.upper(self.client.pseudo), "%U", "")
  end
end

function client_special_vars:Classe(value)
  if not value then
    local class_data = self.client.server.project.classes[self.client.class]
    return class_data.name
  end
end

function client_special_vars:Skin(value)
  if not value then
    return "Chipset\\"..self.client.charaset.path
  end
end

function client_special_vars:Force(value)
  if value then
    self.client.strength_pts = Event.computeExpression(value) or 0
    self.client:updateCharacteristics()
  else
    return self.client.strength_pts
  end
end

function client_special_vars:Dext(value)
  if value then
    self.client.dexterity_pts = Event.computeExpression(value) or 0
    self.client:updateCharacteristics()
  else
    return self.client.dexterity_pts
  end
end

function client_special_vars:Constit(value)
  if value then
    self.client.constitution_pts = Event.computeExpression(value) or 0
    self.client:updateCharacteristics()
  else
    return self.client.constitution_pts
  end
end

function client_special_vars:Magie(value)
  if value then
    self.client.magic_pts = Event.computeExpression(value) or 0
    self.client:updateCharacteristics()
  else
    return self.client.magic_pts
  end
end

function client_special_vars:Attaque(value)
  if value then
    self.client.ch_attack = Event.computeExpression(value) or 0
    self.client:send(Client.makePacket(net.STATS_UPDATE, {
      attack = self.client.ch_attack,
    }))
  else
    return self.client.ch_attack
  end
end

function client_special_vars:Defense(value)
  if value then
    self.client.ch_defense = Event.computeExpression(value) or 0
    self.client:send(Client.makePacket(net.STATS_UPDATE, {
      defense = self.client.ch_defense,
    }))
  else
    return self.client.ch_defense
  end
end

function client_special_vars:Vie(value)
  if value then
    self.client:setHealth(Event.computeExpression(value) or 0)
  else
    return self.client.health
  end
end

function client_special_vars:VieMax(value)
  if not value then
    return self.client.max_health
  end
end

function client_special_vars:CurrentMag(value)
  if value then
    self.client:setMana(Event.computeExpression(value) or 0)
  else
    return self.client.mana
  end
end

function client_special_vars:MagMax(value)
  if not value then
    return self.client.max_mana
  end
end

function client_special_vars:Alignement(value)
  if value then
    self.client:setAlignment(Event.computeExpression(value) or 0)
  else
    return self.client.alignment
  end
end

function client_special_vars:Reputation(value)
  if value then
    self.client:setReputation(Event.computeExpression(value) or 0)
  else
    return self.client.reputation
  end
end

function client_special_vars:Gold(value)
  if value then
    self.client:setGold(Event.computeExpression(value) or 0)
  else
    return self.client.gold
  end
end

function client_special_vars:Lvl(value)
  if value then
    local xp = XPtable[Event.computeExpression(value) or 0]
    if xp then self.client:setXP(xp) end
  else
    return self.client.level
  end
end

function client_special_vars:LvlPoint(value)
  if value then
    self.client:setRemainingPoints(Event.computeExpression(value) or 0)
  else
    return self.client.remaining_pts
  end
end

function client_special_vars:CurrentXP(value)
  if value then
    self.client:setXP(Event.computeExpression(value) or 0)
  else
    return self.client.xp
  end
end

function client_special_vars:NextXP(value)
  if not value then
    return XPtable[self.client.level+1] or self.client.xp
  end
end

function client_special_vars:Timer(value)
  if value then
    self.client.timers[1] = (Event.computeExpression(value) or 0)
  else
    return self.client.timers[1]
  end
end

function client_special_vars:Timer2(value)
  if value then
    self.client.timers[2] = (Event.computeExpression(value) or 0)
  else
    return self.client.timers[2]
  end
end

function client_special_vars:Timer3(value)
  if value then
    self.client.timers[3] = (Event.computeExpression(value) or 0)
  else
    return self.client.timers[3]
  end
end

function client_special_vars:KillPlayer(value)
  if value then
    self.client.kill_player = (Event.computeExpression(value) or 0)
  else
    return self.client.kill_player
  end
end

function client_special_vars:Visible(value)
  if value then
    self.client.visible = (Event.computeExpression(value) or 0) > 0
    self.client:broadcastPacket("ch_visible", visible)
  else
    return self.client.visible and 1 or 0
  end
end

function client_special_vars:Bloque(value)
  if value then
    self.client.blocked = (Event.computeExpression(value) or 0) > 0
  else
    return self.client.blocked and 1 or 0
  end
end

function client_special_vars:CaseX(value)
  if value then
    self.client:moveToCell(Event.computeExpression(value) or self.client.cx, self.client.cy, true)
  else
    return self.client.cx
  end
end

function client_special_vars:CaseY(value)
  if value then
    self:moveToCell(self.client.cx, Event.computeExpression(value) or self.client.cy, true)
  else
    return self.client.cy
  end
end

function client_special_vars:Position(value)
  if value then
    self.client.draw_order = Event.computeExpression(value) or 0
    self.client:broadcastPacket("ch_draw_order", self.client.draw_order)
  else
    return self.client.draw_order
  end
end

function client_special_vars:CentreX(value)
  if value then
    self.client.view_shift[1] = (Event.computeExpression(value) or 0)*(-16)
    self.client:send(Client.makePacket(net.VIEW_SHIFT_UPDATE, self.client.view_shift))
  else
    return self.client.view_shift[1]/-16
  end
end

function client_special_vars:CentreY(value)
  if value then
    self.client.view_shift[2] = (Event.computeExpression(value) or 0)*(-16)
    self.client:send(Client.makePacket(net.VIEW_SHIFT_UPDATE, self.client.view_shift))
  else
    return self.client.view_shift[2]/-16
  end
end

function client_special_vars:BloqueChangeSkin(value)
  if value then
    self.client.blocked_skin = (Event.computeExpression(value) or 0) > 0
  else
    return self.client.blocked_skin and 1 or 0
  end
end

function client_special_vars:BloqueAttaque(value)
  if value then
    self.client.blocked_attack = (Event.computeExpression(value) or 0) > 0
  else
    return self.client.blocked_attack and 1 or 0
  end
end

function client_special_vars:BloqueDefense(value)
  if value then
    self.client.blocked_defend = (Event.computeExpression(value) or 0) > 0
  else
    return self.client.blocked_defend and 1 or 0
  end
end

function client_special_vars:BloqueMagie(value)
  if value then
    self.client.blocked_cast = (Event.computeExpression(value) or 0) > 0
  else
    return self.client.blocked_cast and 1 or 0
  end
end

function client_special_vars:BloqueDialogue(value)
  if value then
    self.client.blocked_chat = (Event.computeExpression(value) or 0) > 0
  else
    return self.client.blocked_chat and 1 or 0
  end
end

function client_special_vars:NbObjetInventaire(value)
  if not value then
    return self.client.inventory:getAmount()
  end
end

function client_special_vars:Arme(value)
  if not value then
    local item = self.client.server.project.objects[self.client.weapon_slot]
    return item and item.name or ""
  end
end

function client_special_vars:Bouclier(value)
  if not value then
    local item = self.client.server.project.objects[self.client.shield_slot]
    return item and item.name or ""
  end
end

function client_special_vars:Casque(value)
  if not value then
    local item = self.client.server.project.objects[self.client.helmet_slot]
    return item and item.name or ""
  end
end

function client_special_vars:Armure(value)
  if not value then
    local item = self.client.server.project.objects[self.client.armor_slot]
    return item and item.name or ""
  end
end

function client_special_vars:Direction(value)
  if value then
    self.client:setOrientation(Event.computeExpression(value) or 0)
  else
    return self.client.orientation
  end
end

function client_special_vars:Groupe(value)
  -- TODO
  if not value then
    return ""
  end
end

function client_special_vars:Guilde(value)
  -- TODO
  if not value then
    return "Admin"
  end
end

function client_special_vars:Rang(value)
  -- TODO
  if not value then
    return "Default"
  end
end

function client_special_vars:Grade(value)
  -- TODO
  if not value then
    return 0
  end
end

function client_special_vars:String1(value)
  if value then
    self.client.strings[1] = value
  else
    return self.client.strings[1]
  end
end

function client_special_vars:String2(value)
  if value then
    self.client.strings[2] = value
  else
    return self.client.strings[2]
  end
end

function client_special_vars:String3(value)
  if value then
    self.client.strings[3] = value
  else
    return self.client.strings[3]
  end
end

function client_special_vars:EvCaseX(value)
  if not value then
    return self.cx
  end
end

function client_special_vars:EvCaseY(value)
  if not value then
    return self.cy
  end
end

-- aliases
client_special_vars.BloqueAttaqueLocal = client_special_vars.BloqueAttaque
client_special_vars.BloqueDefenseLocal = client_special_vars.BloqueDefense
client_special_vars.BloqueMagieLocal = client_special_vars.BloqueMagie

-- form: "%<Ev>.<var>%"
local event_special_vars = {}

function event_special_vars:Name(value)
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

function event_special_vars:Chipset(value)
  if value then
    self.charaset.path = string.sub(value, 9) -- remove Chipset/ part
    self:setCharaset(self.charaset)
  else
    return (self.charaset.is_skin and "" or "Chipset\\")..self.charaset.path
  end
end

function event_special_vars:Bloquant(value)
  if value then
    self.obstacle = ((Event.computeExpression(value) or 0) > 0)
  else
    return (self.obstacle and 1 or 0)
  end
end

function event_special_vars:Visible(value)
  if value then
    self.active = ((Event.computeExpression(value) or 0) > 0)
    self:broadcastPacket("ch_active", self.active)
  else
    return (self.active and 1 or 0)
  end
end

function event_special_vars:TypeAnim(value)
  if value then
    self.animation_type = (Event.computeExpression(value) or 0)

    -- update
    local data = {
      animation_type = self.animation_type
    }

    if self.animation_type <= 2 then
      self:setOrientation(self.page.animation_mod)
    end

    if self.animation_type ~= Event.Animation.VISUAL_EFFECT then
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

function event_special_vars:Direction(value)
  if value then
    self:setOrientation(Event.computeExpression(value) or 0)
  else
    return self.orientation
  end
end

function event_special_vars:CaseX(value)
  if value then
    self:moveToCell(Event.computeExpression(value) or self.cx, self.cy, true)
  else
    return self.cx
  end
end

function event_special_vars:CaseY(value)
  if value then
    self:moveToCell(self.cx, Event.computeExpression(value) or self.cy, true)
  else
    return self.cy
  end
end

function event_special_vars:CaseNBX(value)
  if value then
    self:moveToCell(Event.computeExpression(value) or self.cx, self.cy)
  end
end

function event_special_vars:CaseNBY(value)
  if value then
    self:moveToCell(self.cx, Event.computeExpression(value) or self.cy)
  end
end

function event_special_vars:X(value)
  if value then
    self.charaset.x = (Event.computeExpression(value) or 0)
    self:setCharaset(self.charaset)
  else
    return self.charaset.x
  end
end

function event_special_vars:Y(value)
  if value then
    self.charaset.y = (Event.computeExpression(value) or 0)
    self:setCharaset(self.charaset)
  else
    return self.charaset.y
  end
end

function event_special_vars:W(value)
  if value then
    self.charaset.w = (Event.computeExpression(value) or 0)
    self:setCharaset(self.charaset)
  else
    return self.charaset.w
  end
end

function event_special_vars:H(value)
  if value then
    self.charaset.h = (Event.computeExpression(value) or 0)
    self:setCharaset(self.charaset)
  else
    return self.charaset.h
  end
end

function event_special_vars:NumAnim(value)
  if value then
    self.animation_number = (Event.computeExpression(value) or 0)
    self:broadcastPacket("ch_animation_number", self.animation_number)
  else
    return self.animation_number
  end
end

function event_special_vars:Vitesse(value)
  if value then
    self.speed = (Event.computeExpression(value) or 0)
  else
    return self.speed
  end
end

function event_special_vars:Transparent(value)
  if value then
    self:setGhost((Event.computeExpression(value) or 0) > 0)
  else
    return self.ghost and 1 or 0
  end
end

function event_special_vars:AnimAttaque(value)
  if value then self:act("attack", 1)
  else return 0 end
end

function event_special_vars:AnimDefense(value)
  if value then self:act("defend", 1)
  else return 0 end
end

function event_special_vars:AnimMagie(value)
  if value then self:act("cast", 1)
  else return 0 end
end

-- command function definitions, map of id => function
-- function(event, state, args...)
--- args...: function arguments as string expressions (after substitution)
local command_functions = {}

function command_functions:AddObject(state, name, amount)
  amount = Event.computeExpression(amount or "") or 1
  local id = self.client.server.project.objects_by_name[name]
  if id and amount > 0 then
    for i=1,amount do self.client.inventory:put(id) end
  end
end

function command_functions:DelObject(state, name, amount)
  amount = Event.computeExpression(amount or "") or 1
  local id = self.client.server.project.objects_by_name[name]
  if id and amount > 0 then
    for i=1,amount do self.client.inventory:take(id) end
  end
end

function command_functions:Teleport(state, map_name, cx, cy)
  local cx = Event.computeExpression(cx)
  local cy = Event.computeExpression(cy)

  if map_name and cx and cy then
    local map = self.client.server:getMap(map_name)
    if map then
      map:addEntity(self.client)
      self.client:teleport(cx*16, cy*16)
    end
  end
end

function command_functions:ChangeResPoint(state, map_name, cx, cy)
  cx = Event.computeExpression(cx)
  cy = Event.computeExpression(cy)

  if map_name and cx and cy then
    self.client.respawn_point = {
      map = map_name,
      cx = cx,
      cy = cy
    }
  end
end

function command_functions:SScroll(state, cx, cy)
  cx = Event.computeExpression(cx)
  cy = Event.computeExpression(cy)

  if cx and cy then
    self.client:scrollTo(cx*16, cy*16)
  end
end

function command_functions:ChangeSkin(state, path)
  self.client:setCharaset({
    path = string.sub(path, 9), -- remove "Chipset/" part
    x = 0, y = 0,
    w = 24, h = 32,
    is_skin = false
  })
end

function command_functions:Message(state, msg)
  if msg then
    self.client:requestMessage(msg)
  end
end

function command_functions:Condition(state, condition)
  if condition then
    local ok

    local ctype = Event.parseCondition(condition)

    if ctype == Event.Condition.VARIABLE or ctype == Event.Condition.EXPRESSION then -- condition check
      ok = self:checkCondition(condition)
    else -- condition trigger check
      ok = (ctype == state.condition)
    end

    if not ok then -- skip condition block
      local i = state.cursor+1
      local size = #self.page.commands
      local i_found

      while not i_found and i <= size do -- find next Condition instruction
        local args = {Event.parseCommand(self.page.commands[i])}
        if args[1] == Event.Command.FUNCTION and args[2] == "Condition" then
          i_found = i
        end

        i = i+1
      end

      if i_found then
        state.cursor = i_found-1
      else -- skip all
        state.cursor = i-1
      end
    end
  end
end

function command_functions:InputQuery(state, title, ...)
  local options = {...}

  local answer = options[self.client:requestInputQuery(title, options)] or ""
  answer = self:instructionSubstitution(answer)

  local i = state.cursor+1
  local size = #self.page.commands
  local i_found
  while not i_found and i <= size do -- skip after valid OnResultQuery or QueryEnd
    local args = {Event.parseCommand(self.page.commands[i])}
    if args[1] == Event.Command.FUNCTION then
      if (args[2] == "OnResultQuery" and self:instructionSubstitution(args[3]) == answer)
        or args[2] == "QueryEnd" then
        i_found = i
      end
    end

    i = i+1
  end

  if i_found then
    state.cursor = i_found
  else -- skip all
    state.cursor = i-1
  end
end

function command_functions:OnResultQuery(state)
  local i = state.cursor+1
  local size = #self.page.commands
  local i_found
  while not i_found and i <= size do -- skip after QueryEnd
    local args = {Event.parseCommand(self.page.commands[i])}
    if args[1] == Event.Command.FUNCTION and args[2] == "QueryEnd" then
      i_found = i
    end

    i = i+1
  end

  if i_found then
    state.cursor = i_found
  else -- skip all
    state.cursor = i-1
  end
end

function command_functions:QueryEnd(state)
  -- void, prevent not implemented warning
end

function command_functions:Magasin(state, title, ...)
  local items, items_id = {...}, {}
  local objects_by_name = self.client.server.project.objects_by_name
  for _, item in ipairs(items) do
    local id = objects_by_name[item]
    if id then table.insert(items_id, id) end
  end

  self.client:openShop(title, items_id)
end

function command_functions:Coffre(state, title)
  self.client:openChest(title)
end

function command_functions:GenereMonstre(state, name, x, y, amount)
  x,y,amount = Event.computeExpression(x), Event.computeExpression(y), Event.computeExpression(amount) or 0
  if name and x and y and amount > 0 then
    local mob_data = self.client.server.project.mobs[self.client.server.project.mobs_by_name[name]]
    if mob_data then
      for i=1,amount do
        local mob = Mob(mob_data)
        self.map:addEntity(mob)
        mob:teleport(x*16, y*16)
      end
    end
  end
end

function command_functions:TueMonstre(state)
  -- TODO
end

function command_functions:AddMagie(state, name)
  -- TODO
end

function command_functions:DelMagie(state, name)
  -- TODO
end

function command_functions:ChAttaqueSound(state, path)
  -- remove Sound/ part
  self.client:setSounds(string.sub(path, 7), self.client.hurt_sound)
end

function command_functions:ChBlesseSound(state, path)
  -- remove Sound/ part
  self.client:setSounds(self.client.attack_sound, string.sub(path, 7))
end

function command_functions:Attente(state, amount)
  amount = Event.computeExpression(amount) or 0
  if amount > 0 then
    local r = async()
    task(amount*0.03, function() r() end)
    r:wait()
  end
end

function command_functions:PlayMusic(state, path)
  local sub_path = string.match(path, "^Sound\\(.+)%.mid$")
  path = sub_path and sub_path..".ogg"

  if path then self.client:playMusic(path) end
end

function command_functions:StopMusic(state)
  self.client:stopMusic()
end

function command_functions:PlaySound(state, path)
  self.client:playSound(string.sub(path, 7)) -- remove Sound\ part
end

-- METHODS

-- page_index: specific state or nil
function Event:__construct(client, data, page_index)
  LivingEntity.__construct(self)

  self:setClient(client)
  self.data = data -- event data
  self.page_index = page_index or self:selectPage()
  self.page = self.data.pages[self.page_index]

  self.special_var_listeners = {} -- map of id (string) => map of callback
  self.server_vars_listened = {} -- map of id (string)

  self.trigger_auto = false
  self.trigger_auto_once = false
  self.trigger_attack = false
  self.trigger_contact = false
  self.trigger_interact = false

  self.name = self.page.name

  for _, instruction in ipairs(self.page.conditions) do
    local ctype = Event.parseCondition(instruction)
    if ctype == Event.Condition.AUTO then
      self.trigger_auto = true
    elseif ctype == Event.Condition.AUTO_ONCE then
      self.trigger_auto_once = true
    elseif ctype == Event.Condition.ATTACK then
      self.trigger_attack = true
    elseif ctype == Event.Condition.CONTACT then
      self.trigger_contact = true
    elseif ctype == Event.Condition.INTERACT then
      self.trigger_interact = true
    end
  end

  self:setCharaset({
    path = string.sub(self.page.set, 9), -- remove Chipset/ part
    x = self.page.set_x, y = self.page.set_y,
    w = self.page.w, h = self.page.h,
    is_skin = false
  })

  self.obstacle = self.page.obstacle
  self.active = self.page.active -- (active/visible)
  self.animation_type = self.page.animation_type
  self.animation_number = self.page.animation_number
  self.speed = self.page.speed
  self:setGhost(self.page.transparent)

  if self.animation_type <= 2 then
    self.orientation = self.page.animation_mod
  end

  if self.page.active and string.len(self.page.set) > 0 then -- networked event
    self.nettype = "Event"
  end
end

-- (async) process the string to substitute all event language patterns
-- f_input: if passed/true, will substitute InputString functions (async)
-- return processed string
function Event:instructionSubstitution(str, f_input)
  local pat = Event.patterns

  if f_input then -- special: "InputString('')"
    str = utils.gsub(str, "InputString%('(.*)'%)", function(title)
      title = self:instructionSubstitution(title, f_input)

      return self.client:requestInputString(title)
    end)
  end

  -- special: variable functions "%func(...)%"
  str = utils.gsub(str, "%%([%w_]+)%((.-)%)%%", function(id, content)
    local f = client_special_vfunctions[id]
    if f then
      -- process function arguments
      local args = utils.split(content, ",")
      for i=1,#args do
        args[i] = self:instructionSubstitution(args[i], f_input)
      end
      return f(self, unpack(args))
    end
  end)

  -- server var
  str = string.gsub(str, pat.server_var, function(id)
    return self.client.server:getVariable(id)
  end)

  -- client var
  str = string.gsub(str, pat.client_var, function(id)
    id = tonumber(id)
    if id then return self.client:getVariable("var", id) end
  end)

  -- client bool var
  str = string.gsub(str, pat.client_bool_var, function(id)
    id = tonumber(id)
    if id then return self.client:getVariable("bool", id) end
  end)

  -- event var
  str = string.gsub(str, pat.event_special_var, function(name, id)
    local event = self.client.events_by_name[name]
    if event then
      local f = event_special_vars[id]
      if f then return f(event) end
    end
  end)

  -- client special var
  str = string.gsub(str, pat.client_special_var, function(id)
    local f = client_special_vars[id]
    if f then return f(self) end
  end)

  return str
end

-- check condition instruction
-- return bool
function Event:checkCondition(instruction)
  --print("CD", self.data.x, self.data.y, instruction)
  local args = {Event.parseCondition(instruction)}

  local lhs, op, expr
  if args[1] == Event.Condition.VARIABLE then -- comparison check
    if args[2] == Event.Variable.SERVER then
      local key = self:instructionSubstitution(args[3])
      lhs = self.client.server:getVariable(key)
      op, expr = args[4], args[5]
    elseif args[2] == Event.Variable.CLIENT then
      lhs = self.client:getVariable(args[3], args[4][1])
      op, expr = args[5], args[6]
    elseif args[2] == Event.Variable.CLIENT_SPECIAL then
      if args[3] == "Inventaire" then -- inventory check, set lhs as rhs or "" if not owned
        local rhs = self:instructionSubstitution(args[5])
        local id = self.client.server.project.objects_by_name[rhs]
        lhs = (id and (self.client.inventory.items[id] or 0) > 0 and rhs or "")
      else -- regular
        local f = client_special_vars[args[3]]
        if f then lhs = f(self)
        else print("event: client special variable \""..args[3].."\" not implemented") end
      end
      op, expr = args[4], args[5]
    elseif args[2] == Event.Variable.EVENT_SPECIAL then
      local event = self.client.events_by_name[args[3]]
      if event then
        local f = event_special_vars[args[4]]
        if f then lhs = f(event)
        else print("event: event special variable \""..args[4].."\" not implemented") end
      end

      op, expr = args[5], args[6]
    end
  elseif args[1] == Event.Condition.EXPRESSION then -- expression comparison
    lhs, op, expr = self:instructionSubstitution(args[2]), args[3], args[4]
  end

  if op then -- comparison
    if not lhs then return false end
    lhs = tostring(lhs)
    local rhs = self:instructionSubstitution(expr)

    local rhs_n = Event.computeExpression(rhs)
    local lhs_n = Event.computeExpression(lhs)
    if rhs_n and lhs_n then -- number comparison
      lhs = lhs_n
      rhs = rhs_n
    else -- string comparison
      lhs = lhs_n and tostring(lhs_n) or lhs
      rhs = rhs_n and tostring(rhs_n) or rhs
    end

    if op == "=" then return (lhs == rhs)
    elseif op == "<" then return (lhs < rhs)
    elseif op == ">" then return (lhs > rhs)
    elseif op == "<=" then return (lhs <= rhs)
    elseif op == ">=" then return (lhs >= rhs)
    elseif op == "!=" then return (lhs ~= rhs)
    else return false end
  end

  return true
end

-- check if the page conditions are valid
-- return bool
function Event:checkConditions(page)
  for _, instruction in ipairs(page.conditions) do
    if not self:checkCondition(instruction) then return false end
  end

  return true
end

-- search for a valid page
-- return page index
function Event:selectPage()
  for i, page in ipairs(self.data.pages) do
    if self:checkConditions(page) then
      return i
    end
  end

  return #self.data.pages
end

-- trigger the event (marked for execution, doesn't execute the event)
-- condition: Event.Condition type triggered
function Event:trigger(condition)
--  print("TRIGGER", condition, self.cx, self.cy, self.page_index)
  self.client.triggered_events[self] = condition
end

-- (async) execute event script commands
-- condition: Event.Condition type triggered
function Event:execute(condition)
  --print("EXECUTE", condition, self.map.id, self.cx, self.cy, self.page_index)

  if condition == Event.Condition.INTERACT then
    local atype = self.animation_type
    if atype == Event.Animation.CHARACTER_RANDOM or atype == Event.Animation.STATIC_CHARACTER then
      -- look at player
      local orientation = LivingEntity.vectorOrientation(self.client.x-self.x, self.client.y-self.y)
      self:setOrientation(orientation)
    end
  end

  -- execution context state
  local state = {
    cursor = 1, -- instruction cursor
    condition = condition
  }

  -- process instructions
  local size = #self.page.commands

  while state.cursor <= size do
    local instruction = self.page.commands[state.cursor]
    --print("INS", instruction)
    local args = {Event.parseCommand(instruction)}

    if args[1] == Event.Command.VARIABLE then -- variable assignment
      local op, expr

      if args[2] == Event.Variable.SERVER then
        op, expr = args[4], args[5]

        -- concat compatibility support
        expr = string.gsub(expr, "Concat%('(.*)'%)", "Serveur["..args[3].."]%1")
      elseif args[2] == Event.Variable.CLIENT then
        op, expr = args[5], args[6]
      elseif args[2] == Event.Variable.CLIENT_SPECIAL then
        op, expr = args[4], args[5]

        -- concat compatibility support
        expr = string.gsub(expr, "Concat%('(.*)'%)", "%%"..args[3].."%%%1")
      elseif args[2] == Event.Variable.EVENT_SPECIAL then
        op, expr = args[5], args[6]
      end

      if op == "=" then
        expr = self:instructionSubstitution(expr, true)

        if args[2] == Event.Variable.SERVER then
          local key = self:instructionSubstitution(args[3])
          self.client.server:setVariable(key, Event.computeExpression(expr) or expr)
        elseif args[2] == Event.Variable.CLIENT then
          local value = (Event.computeExpression(expr) or 0)
          for id=args[4][1], (args[4][2] or args[4][1]) do -- range set
            self.client:setVariable(args[3], id, value)
          end
        elseif args[2] == Event.Variable.CLIENT_SPECIAL then
          local f = client_special_vars[args[3]]
          if f then
            f(self, expr)
            self.client:triggerSpecialVariable(args[3])
          else print("event: client special variable \""..args[3].."\" not implemented") end
        elseif args[2] == Event.Variable.EVENT_SPECIAL then
          local event = self.client.events_by_name[args[3]]
          if event then
            local f = event_special_vars[args[4]]
            if f then
              f(event, expr)
              event:triggerSpecialVariable(args[4])
            else print("event: event special variable \""..args[4].."\" not implemented") end
          end
        end
      end
    elseif args[1] == Event.Command.FUNCTION then -- function
      local f = command_functions[args[2]]

      -- process function arguments
      local fargs = {}
      for i=3,#args do
        table.insert(fargs, self:instructionSubstitution(args[i], true))
      end

      if f then
        f(self, state, unpack(fargs))
      else print("event: command function \""..args[2].."\" not implemented") end
    end

    state.cursor = state.cursor+1
  end

  -- end
  self.client:resetScroll()
end

-- trigger special variable (client/event) change event
function Event:triggerSpecialVariable(id)
  -- call listeners
  local listeners = self.special_var_listeners[id]
  if listeners then
    for callback in pairs(listeners) do
      callback()
    end
  end
end

-- listen special variable (client/event)
-- client/event name collisions are not really a problem (trigger a full page check anyway)
function Event:listenSpecialVariable(id, callback)
  local listeners = self.special_var_listeners[id]
  if not listeners then
    listeners = {}
    self.special_var_listeners[id] = listeners
  end

  listeners[callback] = true
end

function Event:unlistenSpecialVariable(id, callback)
  local listeners = self.special_var_listeners[id]
  if listeners then
    listeners[callback] = nil

    if not next(listeners) then
      self.special_var_listeners[id] = nil
    end
  end
end

-- override
function Event:serializeNet()
  local data = LivingEntity.serializeNet(self)

  data.animation_type = self.animation_type
  data.position_type = self.page.position_type

  if self.animation_type ~= Event.Animation.VISUAL_EFFECT then
    data.orientation = self.orientation
    data.animation_number = self.animation_number
  else
    data.animation_wc = math.max(self.page.animation_number, 1)
    data.animation_hc = math.max(self.page.animation_mod, 1)
  end

  data.active = self.active

  return data
end

-- randomly move the event if type is Animation.CHARACTER_RANDOM
-- (starts a unique loop, will call itself again)
function Event:moveAI()
  if self.map and not self.move_ai_task
    and (self.animation_type == Event.Animation.CHARACTER_RANDOM or self.animation_type == Event.Animation.CHARACTER_FOLLOW) then
    self.move_ai_task = task(utils.randf(1, 5)/self.speed*2, function()
      local ok
      local ncx, ncy

      if not self.client.running_event then -- prevent movement when an event is in execution
        -- search for a passable cell
        local i = 1
        while not ok and i <= 10 do
          -- random/follow orientation
          local orientation
          if self.animation_type == Event.Animation.CHARACTER_FOLLOW then
            orientation = LivingEntity.vectorOrientation(self.client.x-self.x, self.client.y-self.y)
          else
            orientation = math.random(0,3)
          end

          local dx, dy = LivingEntity.orientationVector(orientation)
          ncx, ncy = self.cx+dx, self.cy+dy

          ok = (self.map and self.map:isCellPassable(self, ncx, ncy))

          i = i+1
        end
      end

      if ok then
        self:moveToCell(ncx, ncy)
      end

      self.move_ai_task = nil

      self:moveAI()
    end)
  end
end

-- override
function Event:onAttack(attacker)
  if class.is(attacker, Client) and self.trigger_attack then -- event
    self:trigger(Event.Condition.ATTACK)
    return true
  end
end

-- override
function Event:onMapChange()
  if self.map then -- added to map
    self:moveAI()

    -- reference event by name
    self.client.events_by_name[self.name] = self

    -- listen to conditions of all previous and current page
    --- callback on conditions change (select a new page)
    self.vars_callback = function() self.client.event_checks[self] = true end

    for i=1,self.page_index do
      local page = self.data.pages[i]
      for _, instruction in ipairs(page.conditions) do
        local args = {Event.parseCondition(instruction)}
        if args[1] == Event.Condition.VARIABLE then
          if args[2] == Event.Variable.SERVER then
            local key = self:instructionSubstitution(args[3])
            self.server_vars_listened[key] = true
            self.client.server:listenVariable(key, self.vars_callback)
          elseif args[2] == Event.Variable.CLIENT then
            self.client:listenVariable(args[3], args[4][1], self.vars_callback)
          elseif args[2] == Event.Variable.CLIENT_SPECIAL then
            self.client:listenSpecialVariable(args[3], self.vars_callback)
          elseif args[2] == Event.Variable.EVENT_SPECIAL then
            local event = self.client.events_by_name[args[3]]
            if event then event:listenSpecialVariable(args[4], self.vars_callback) end
          end
        end
      end
    end

    -- auto trigger
    if self.trigger_auto then
      self.trigger_task = true

      -- task iteration
      local function iteration()
        task(0.03, function()
            if self.trigger_task then
              self:trigger(Event.Condition.AUTO)
              iteration()
            end
        end)
      end

      iteration()
    elseif self.trigger_auto_once then
      self:trigger(Event.Condition.AUTO_ONCE)
    end
  else -- removed from map
    -- unreference event by name
    self.client.events_by_name[self.name] = nil

    -- unreference trigger/check
    self.client.event_checks[self] = nil
    self.client.triggered_events[self] = nil

    -- unlisten to conditions of all previous and current page
    for i=1,self.page_index do
      local page = self.data.pages[i]
      for _, instruction in ipairs(page.conditions) do
        local args = {Event.parseCondition(instruction)}
        if args[1] == Event.Condition.VARIABLE then
          if args[2] == Event.Variable.CLIENT then
            self.client:unlistenVariable(args[3], args[4], self.vars_callback)
          elseif args[2] == Event.Variable.CLIENT_SPECIAL then
            self.client:unlistenSpecialVariable(args[3], self.vars_callback)
          elseif args[2] == Event.Variable.EVENT_SPECIAL then
            local event = self.client.events_by_name[args[3]]
            if event then event:unlistenSpecialVariable(args[4], self.vars_callback) end
          end
        end
      end
    end

    for id in pairs(self.server_vars_listened) do
      self.client.server:unlistenVariable(id, self.vars_callback)
    end
    self.server_vars_listened = {}

    -- auto trigger
    if self.trigger_auto then
      self.trigger_task = nil
    end
  end
end

return Event
