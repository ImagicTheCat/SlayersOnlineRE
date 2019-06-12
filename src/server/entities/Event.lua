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
  SERVER_VAR = 0,
  CLIENT_VAR = 1,
  CLIENT_SPECIAL_VAR = 2,
  EVENT_VAR = 3
}

Event.Command = {
  VARIABLE = 0,
  FUNCTION = 1
}

Event.patterns = {
  server_var = "Serveur%[([%w_%-]+)%]", -- Serveur[string]
  client_var = "Variable%[(%d+)%]", -- Variable[int]
  client_bool_var = "Bool%[(%d+)%]", -- Bool[int]
  event_var = "%%([^%.%%]+)%.([^%.%s%%]+)%%", -- %Nom Ev.Var%
  client_special_var = "%%([^%.%s%%]+)%%" -- %Var%
}

-- return (Event.Variable type, parameters...) or nil
function Event.parseVariableInstruction(instruction)
  local lhs, op, rhs = string.match(instruction, "^(.-)([<>!=]+)(.*)$")
  if lhs then
    -- detect variable kind
    local id, name

    local pat = Event.patterns

    id = string.match(lhs, "^"..pat.server_var.."$")
    if id then return Event.Variable.SERVER_VAR, id, op, rhs end

    id = string.match(lhs, "^"..pat.client_var.."$")
    if id then return Event.Variable.CLIENT_VAR, "var", tonumber(id), op, rhs end

    id = string.match(lhs, "^"..pat.client_bool_var.."$")
    if id then return Event.Variable.CLIENT_VAR, "bool", tonumber(id), op, rhs end

    name, id = string.match(lhs, "^"..pat.event_var.."$")
    if name then return Event.Variable.EVENT_VAR, name, id, op, rhs end

    id = string.match(lhs, "^"..pat.client_special_var.."$")
    if id then return Event.Variable.CLIENT_SPECIAL_VAR, id, op, rhs end
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
      for arg in string.gmatch(content, "([^,]*)") do
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

-- PRIVATE METHODS

-- vars definitions, map of id => function
-- function(event, value): should return a number or a string on get mode
--- value: passed string (set mode) or nil (get mode)

local client_special_vars = {}

function client_special_vars:Name(value)
  if not value then
    return self.client.id
  end
end

local event_vars = {}

function event_vars:Name(value)
  if not value then
    return self.page.name
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
  str = string.gsub(str, pat.event_var, function(name, id)
    local event = self.client.events_by_name[name]
    if event then
      local f = event_vars[id]
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

-- check if the page conditions are valid
-- return bool
function Event:checkConditions(page)
  -- TODO
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
        if args[1] == Event.Condition.SERVER_VAR then
          self.client.server:listenVariable(args[2], self.vars_callback)
        elseif args[1] == Event.Condition.CLIENT_VAR then
          self.client:listenVariable(args[2], args[3], self.vars_callback)
        end
      end
    end
  else -- removed from map
    -- unreference event by name
    self.client.events_by_name[self.page.name] = nil

    -- unlisten to conditions of all previous and current page
    for i=1,self.page_index do
      local page = self.data.pages[i]
      for _, instruction in ipairs(page.conditions) do
        local args = {Event.parseCondition(instruction)}
        if args[1] == Event.Condition.SERVER_VAR then
          self.client.server:unlistenVariable(args[2], self.vars_callback)
        elseif args[1] == Event.Condition.CLIENT_VAR then
          self.client:unlistenVariable(args[2], args[3], self.vars_callback)
        end
      end
    end
  end
end

return Event
