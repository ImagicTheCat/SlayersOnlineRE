local utils = require("lib/utils")
local Entity = require("Entity")

local Event = class("Event", Entity)

-- STATICS

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
  VARIABLE = 5
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
  server_var = "Serveur%[([%w_%-]+)%]", -- Serveur[string]
  client_var = "Variable%[([%d%.]+)%]", -- Variable[int]
  client_bool_var = "Bool%[([%d%.]+)%]", -- Bool[int]
  event_special_var = "%%([^%.%%]+)%.([^%.%s%%]+)%%", -- %Nom Ev.Var%
  client_special_var = "%%([^%.%s%%]+)%%" -- %Var%
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
    ids = (id and utils.split(id, "..") or {})
    for i=1,#ids do ids[i] = math.floor(tonumber(ids[i])) end
    if ids[1] then return Event.Variable.CLIENT, "var", ids, op, rhs end

    -- id range
    id = string.match(lhs, "^"..pat.client_bool_var.."$")
    ids = (id and utils.split(id, "..") or {})
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

  -- variable conditions
  local r = {Event.parseVariableInstruction(instruction)}
  if r[1] then
    return Event.Condition.VARIABLE, unpack(r)
  end
end

-- return (Event.Command type, parameters...) or nil
function Event.parseCommand(instruction)
  if string.sub(instruction, 1, 2) == "//" then return end -- ignore comment

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

  -- variable commands
  local r = {Event.parseVariableInstruction(instruction)}
  if r[1] then
    return Event.Command.VARIABLE, unpack(r)
  end
end

-- process/compute string expression using basic Lua features
-- return computed number (integer) or nil on failure
function Event.computeExpression(str)
  local expr = "return "..string.gsub(str, "[^%.%*/%-%+%(%)%d%s]", " ") -- allowed characters
  local f = loadstring(expr)
  local ok, r = pcall(f)
  if ok then
    local n = tonumber(r)
    if n then
      return utils.round(n)
    end
  end
end

-- PRIVATE METHODS

-- special var accessor definitions, map of id => function
-- function(event, value): should return a number or a string on get mode
--- value: passed string expression (after substitution) on set mode (nil on get mode)

local client_special_vars = {}

function client_special_vars:Name(value)
  if not value then
    return self.client.id
  end
end

local event_special_vars = {}

function event_special_vars:Name(value)
  if not value then
    return self.page.name
  end
end

-- command function definitions, map of id => function
-- function(event, state, args...)
--- args...: function arguments as string expressions (after substitution)
local command_functions = {}

function command_functions:Teleport(state, map_name, cx, cy)
  local cx = Event.computeExpression(cx)
  local cy = Event.computeExpression(cy)

  if map_name and cx and cy then
    local map = self.client.server:getMap(map_name)
    if map then
      self.client:teleport(cx*16, cy*16)
      map:addEntity(self.client)
    end
  end
end

-- METHODS

-- page_index, x, y: specific state or nil
function Event:__construct(client, data, page_index, x, y)
  Entity.__construct(self)

  self:setClient(client)
  self.data = data -- event data
  self.page_index = page_index or self:selectPage()
  self.page = self.data.pages[self.page_index]

  self.special_var_listeners = {} -- map of id (string) => map of callback

  self.trigger_auto = false
  self.trigger_auto_once = false
  self.trigger_attack = false
  self.trigger_contact = false
  self.trigger_interact = false

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

  -- init entity stuff
  self:teleport(x or self.data.x*16, y or self.data.y*16)

  self.set = string.sub(self.page.set, 9) -- remove Chipset/ part
  self.obstacle = self.page.obstacle
  self.orientation = 0

  if self.page.animation_type <= 2 then
    self.orientation = self.page.animation_mod
  end

  if self.page.active and string.len(self.set) > 0 then -- networked event
    self.nettype = "Event"
  end
end

-- process the string to substitute all event language patterns
-- return processed string
function Event:instructionSubstitution(str)
  local pat = Event.patterns

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
  local args = {Event.parseCondition(instruction)}

  if args[1] == Event.Condition.VARIABLE then -- comparison check
    local lhs, op, expr

    if args[2] == Event.Variable.SERVER then
      lhs = self.client.server:getVariable(args[3])
      op, expr = args[4], args[5]
    elseif args[2] == Event.Variable.CLIENT then
      lhs = self.client:getVariable(args[3], args[4][1])
      op, expr = args[5], args[6]
    elseif args[2] == Event.Variable.CLIENT_SPECIAL then
      local f = client_special_vars[args[3]]
      if f then lhs = f(self) end

      op, expr = args[4], args[5]
    elseif args[2] == Event.Variable.EVENT_SPECIAL then
      local event = self.client.events_by_name[args[3]]
      if event then
        local f = event_special_vars[args[4]]
        if f then lhs = f(event) end
      end

      op, expr = args[5], args[6]
    end

    if not lhs then return false end

    expr = self:instructionSubstitution(expr)

    local rhs = Event.computeExpression(expr)
    if not rhs then -- string comparison
      lhs = tostring(lhs)
      rhs = expr
    else -- number comparison
      lhs = tonumber(lhs) or 0
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

    return #self.data.pages
  end
end

-- execute event commands
function Event:trigger()
  -- execution context state
  local state = {
    cursor = 1 -- instruction cursor
  }

  local size = #self.page.commands

  -- process instructions
  while state.cursor <= size do
    local instruction = self.page.commands[state.cursor]
    local args = {Event.parseCommand(instruction)}

    if args[1] == Event.Command.VARIABLE then -- variable assignment
      local op, expr

      if args[2] == Event.Variable.SERVER then
        op, expr = args[4], args[5]
      elseif args[2] == Event.Variable.CLIENT then
        op, expr = args[5], args[6]
      elseif args[2] == Event.Variable.CLIENT_SPECIAL then
        op, expr = args[4], args[5]
      elseif args[2] == Event.Variable.EVENT_SPECIAL then
        op, expr = args[5], args[6]
      end

      if op == "=" then
        expr = self:instructionSubstitution(expr)

        if args[2] == Event.Variable.SERVER then
          self.client.server:setVariable(args[3], Event.computeExpression(expr) or expr)
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
          end
        elseif args[2] == Event.Variable.EVENT_SPECIAL then
          local event = self.client.events_by_name[args[3]]
          if event then
            local f = event_special_vars[args[4]]
            if f then
              f(event, expr)
              event:triggerSpecialVariable(args[4])
            end
          end
        end
      end
    elseif args[1] == Event.Command.FUNCTION then -- function
      local f = command_functions[args[2]]
      if f then
        f(self, state, unpack(args, 3))
      end
    end

    state.cursor = state.cursor+1
  end
end

-- trigger change event
function Event:triggerSpecialVariable(id)
  -- call listeners
  local listeners = self.special_var_listeners[id]
  if listeners then
    for callback in pairs(listeners) do
      callback()
    end
  end
end

function Event:listenSpecialVariable(id, callback)
  local listeners = self.special_var_listeners[id]
  if not listeners then
    listeners = {}
    self.special_var_listeners[id] = listeners
  end

  listeners[callback] = true
end

function Event:unlistenSpecialVariable(vtype, id, callback)
  local listeners = self.special_var_listeners[id]
  if listeners then
    listeners[callback] = nil

    if not next(listeners) then
      self.special_var_listeners[id] = nil
    end
  end
end

-- overload
function Event:serializeNet()
  local data = Entity.serializeNet(self)

  data.animation_type = self.page.animation_type
  data.position_type = self.page.position_type
  data.set = self.set

  if self.page.animation_type ~= Event.Animation.VISUAL_EFFECT then
    data.orientation = self.orientation
  end

  data.w = self.page.w
  data.h = self.page.h
  data.set_x = self.page.set_x
  data.set_y = self.page.set_y

  return data
end

-- overload
function Event:onMapChange()
  if self.map then -- added to map
    -- reference event by name
    self.client.events_by_name[self.page.name] = self

    -- listen to conditions of all previous and current page
    self.vars_callback = function()
      local page_index = self:selectPage()
      if page_index ~= self.page_index then -- reload event
        -- remove
        local map = self.map
        if map then
          local x, y = self.x, self.y
          map:removeEntity(self)

          -- re-create
          map:addEntity(Event(self.client, self.data, self.page_index, self.x, self.y))
        end
      end
    end

    for i=1,self.page_index do
      local page = self.data.pages[i]
      for _, instruction in ipairs(page.conditions) do
        local args = {Event.parseCondition(instruction)}
        if args[1] == Event.Condition.VARIABLE then
          if args[2] == Event.Variable.SERVER then
            self.client.server:listenVariable(args[3], self.vars_callback)
          elseif args[2] == Event.Variable.CLIENT then
            self.client:listenVariable(args[3], args[4], self.vars_callback)
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
      self.trigger_task = itask(0.03, function()
        self:trigger()
      end)
    elseif self.trigger_auto_once then
      task(0.03, function()
        self:trigger()
      end)
    end
  else -- removed from map
    -- unreference event by name
    self.client.events_by_name[self.page.name] = nil

    -- unlisten to conditions of all previous and current page
    for i=1,self.page_index do
      local page = self.data.pages[i]
      for _, instruction in ipairs(page.conditions) do
        local args = {Event.parseCondition(instruction)}
        if args[1] == Event.Condition.VARIABLE then
          if args[2] == Event.Variable.SERVER then
            self.client.server:listenVariable(args[3], self.vars_callback)
          elseif args[2] == Event.Variable.CLIENT then
            self.client:listenVariable(args[3], args[4], self.vars_callback)
          elseif args[2] == Event.Variable.CLIENT_SPECIAL then
            self.client:unlistenSpecialVariable(args[3], self.vars_callback)
          elseif args[2] == Event.Variable.EVENT_SPECIAL then
            local event = self.client.events_by_name[args[3]]
            if event then event:unlistenSpecialVariable(args[4], self.vars_callback) end
          end
        end
      end
    end

    -- auto trigger
    if self.trigger_auto then
      self.trigger_task:remove()
      self.trigger_task = nil
    end
  end
end

return Event
