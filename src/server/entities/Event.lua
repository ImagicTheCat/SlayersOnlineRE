local utils = require("lib/utils")
local Entity = require("Entity")
local LivingEntity = require("entities/LivingEntity")

local Event = class("Event", LivingEntity)

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
    if n then
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

local client_special_vars = {}

function client_special_vars:Name(value)
  if not value then
    return self.client.id
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

function event_special_vars:Speed(value)
  if value then
    self.speed = (Event.computeExpression(value) or 0)
  else
    return self.speed
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

function command_functions:Message(state, msg)
  if msg then
    self.client:requestMessage(msg)
  end
end

function command_functions:Condition(state, condition)
  if condition then
    local ok

    local ctype = Event.parseCondition(condition)

    if ctype == Event.Condition.VARIABLE then -- condition check
      ok = self:checkCondition(condition)
    else -- trigger check
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

  local answer = self.client:requestInputQuery(title, options)

  local i = state.cursor+1
  local size = #self.page.commands
  local i_found
  while not i_found and i <= size do -- skip after valid OnResultQuery or QueryEnd
    local args = {Event.parseCommand(self.page.commands[i])}
    if args[1] == Event.Command.FUNCTION then
      if (args[2] == "OnResultQuery" and args[3] == answer)
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

-- METHODS

-- page_index, x, y: specific state or nil
function Event:__construct(client, data, page_index, x, y)
  LivingEntity.__construct(self)

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

  -- init entity stuff
  self:teleport(x or self.data.x*16, y or self.data.y*16)

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

      if f then
        f(self, unpack(args))
      end

      return f(self)
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
  elseif args[1] == Event.Condition.EXPRESSION then -- expression comparison
    local lhs_expr, op, rhs_expr = args[2], args[3], args[4]

    lhs_expr = self:instructionSubstitution(lhs_expr)
    rhs_expr = self:instructionSubstitution(rhs_expr)

    local rhs = Event.computeExpression(rhs_expr)
    if not rhs then -- string comparison
      lhs = rhs_expr
      rhs = rhs_expr
    else -- number comparison
      lhs = Event.computeExpression(lhs_expr) or 0
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

-- (async) execute event script commands (will wait on instructions and for previous events to complete)
-- condition: Event.Condition type triggered
function Event:trigger(condition)
  local r = async()

  table.insert(self.client.event_queue, r)
  if #self.client.event_queue > 1 then -- wait for previous event next call
    r:wait()
  end

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
      elseif args[2] == Event.Variable.EVENT_SPECIAL then
        op, expr = args[5], args[6]
      end

      if op == "=" then
        expr = self:instructionSubstitution(expr, true)

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

      -- process function arguments
      local fargs = {}
      for i=3,#args do
        table.insert(fargs, self:instructionSubstitution(args[i], true))
      end

      if f then
        f(self, state, unpack(fargs))
      end
    end

    state.cursor = state.cursor+1
  end

  -- end
  table.remove(self.client.event_queue, 1)

  -- next event call
  local next_r = self.client.event_queue[1]
  if next_r then
    next_r()
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
    self.move_ai_task = task(utils.randf(0.75, 7), function()
      local ok
      local ncx, ncy

      if not self.client.event_queue[1] then -- prevent movement when an event is in execution
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

-- overload
function Event:onMapChange()
  if self.map then -- added to map
    self:moveAI()

    -- reference event by name
    self.client.events_by_name[self.name] = self

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
      self.trigger_task = true

      -- task iteration
      local function iteration()
        if self.trigger_task then
          task(0.03, function()
            async(function()
              self:trigger(Event.Condition.AUTO)
              iteration()
            end)
          end)
        end
      end

      iteration()
    elseif self.trigger_auto_once then
      task(0.03, function()
        async(function()
          self:trigger(Event.Condition.AUTO_ONCE)
        end)
      end)
    end
  else -- removed from map
    -- unreference event by name
    self.client.events_by_name[self.name] = nil

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
      self.trigger_task = nil
    end
  end
end

return Event
