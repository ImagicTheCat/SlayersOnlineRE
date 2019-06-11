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
  NONE = 0,
  INTERACT = 1,
  AUTO = 2,
  AUTO_ONCE = 3,
  CONTACT = 4,
  SERVER_VAR = 5,
  CLIENT_VAR = 6,
  CLIENT_SPECIAL_VAR = 7,
  EVENT_VAR = 8,
  ATTACK = 9
}

-- return Event.Condition type, parameters...
function Event.parseCondition(instruction)
  if instruction == "Appuie sur bouton" then return Event.Condition.INTERACT end
  if instruction == "Automatique" then return Event.Condition.AUTO end
  if instruction == "Auto une seul fois" then return Event.Condition.AUTO_ONCE end
  if instruction == "En contact" then return Event.Condition.CONTACT end
  if instruction == "Attaque" then return Event.Condition.ATTACK end

  -- variable conditions
  local lhs, op, rhs = string.match(instruction, "^(.-)([<>!=]+)(.*)$")
  if lhs then
    -- detect variable kind
    local id, name

    id = string.match(lhs, "^Serveur%[([%w_%-]+)%]$")
    if id then return Event.Condition.SERVER_VAR, id, op, rhs end

    id = string.match(lhs, "^Variable%[(%d+)%]$")
    if id then return Event.Condition.CLIENT_VAR, "var", tonumber(id), op, rhs end

    id = string.match(lhs, "^Bool%[(%d+)%]$")
    if id then return Event.Condition.CLIENT_VAR, "bool", tonumber(id), op, rhs end

    name, id = string.match(lhs, "^%%([^%.]+)%.([^%.]+)%%$")
    if name then return Event.Condition.EVENT_VAR, name, id, op, rhs end

    id = string.match(lhs, "^%%([^%.]+)%%$")
    if id then return Event.Condition.CLIENT_SPECIAL_VAR, id, op, rhs end
  end

  return Event.Condition.NONE
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
