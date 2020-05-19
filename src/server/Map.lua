local IdManager = require("lib.IdManager")
local Client = require("Client")
local net = require("protocol")
local Mob = require("entities.Mob")
local utils = require("lib.utils")

local Map = class("Map")

-- STATICS

Map.Type = {
  SAFE = 0,
  PVE = 1,
  PVP = 2,
  PVE_PVP = 3,
  PVP_NOREPUT = 4,
  PVP_NOREPUT_POT = 5
}

-- METHODS

function Map:__construct(server, id, data)
  self.server = server
  self.id = id
  self.ids = IdManager()

  self.data = data -- map data

  self.entities = {} -- map of entity => id
  self.entities_by_id = {} -- map of id => entity
  self.clients = {} -- map of client
  self.cells = {} -- map space partitioning (16x16 cells), map of cell index => map of entity

  self.living_entity_updates = {} -- map of living entity
  self.movement_packet_count = 0

  self.w = self.data.width
  self.h = self.data.height
  self.tileset = string.sub(self.data.tileset, 9) -- remove Chipset/ part
  self.background = string.sub(self.data.background, 9) -- remove Chipset/ part

  local music_name = string.match(data.music, "^Sound\\(.+)%.mid$")
  self.music = music_name and music_name..".ogg"

  self.tiledata = self.data.tiledata
  self.tileset_data = self.data.tileset_data

  -- init mob areas
  self.mob_areas = {} -- list of mob area states
  for i, area in ipairs(data.mob_areas) do
    self.mob_areas[i] = { mob_count = 0 }
    if area.type >= 0 then
      self:mobAreaSpawnTask(i)
    end
  end
end

-- return cell (map of entity) or nil if invalid or empty
function Map:getCell(x, y)
  if x >= 0 and x < self.w and y >= 0 and y < self.h then
    return self.cells[y*self.w+x]
  end
end

-- called by Map and Entity
function Map:addToCell(entity, x, y)
  if x >= 0 and x < self.w and y >= 0 and y < self.h then
    local index = y*self.w+x
    local cell = self.cells[index]
    if not cell then -- create cell
      cell = {}
      self.cells[index] = cell
    end

    cell[entity] = true
  end
end

-- called by Map and Entity
function Map:removeFromCell(entity, x, y)
  if x >= 0 and x < self.w and y >= 0 and y < self.h then
    local index = y*self.w+x
    local cell = self.cells[index]
    if cell then
      cell[entity] = nil

      if not next(cell) then -- free cell if empty
        self.cells[index] = nil
      end
    end
  end
end

-- will remove the entity from its previous map
-- adding an entity set its position to (-1,-1) cell, it must be teleported afterwards
function Map:addEntity(entity)
  -- remove the entity from the previous map
  if entity.map then
    entity.map:removeEntity(entity)
  end

  if not entity.client or self.clients[entity.client] then -- unbound or bound to existing client
    -- reference
    local id = self.ids:gen()
    self.entities[entity] = id
    self.entities_by_id[id] = entity
    entity.id = id
    entity.map = self
    entity.x, entity.y = -16, -16
    entity.cx, entity.cy = -1, -1

    -- reference client bound entity
    if entity.client then
      entity.client.entities[entity] = true
    end

    -- send entity packet to bound or all map clients
    if entity.nettype then
      if entity.client and self.clients[entity.client] then
        entity.client:send(Client.makePacket(net.ENTITY_ADD, entity:serializeNet()))
      else
        self:broadcastPacket(net.ENTITY_ADD, entity:serializeNet())
      end
    end

    if class.is(entity, Client) then
      self.clients[entity] = true
    end

    entity:onMapChange() -- add event
  end
end

function Map:removeEntity(entity)
  local ok = self.entities[entity]

  if ok then
    local id = entity.id

    -- unreference
    self.ids:free(id)
    entity.id = nil
    entity.map = nil
    self.entities[entity] = nil
    self.entities_by_id[id] = nil
    self:removeFromCell(entity, entity.cx, entity.cy)

    -- unreference client bound entity
    if entity.client then
      entity.client.entities[entity] = nil
    end

    if class.is(entity, Client) then -- handle client removal
      self.clients[entity] = nil

      -- remove client bound entities
      for c_entity in pairs(entity.entities) do
        self:removeEntity(c_entity)
      end
    end

    -- send entity packet to bound or all map clients
    if entity.nettype then
      if entity.client and self.clients[entity.client] then
        entity.client:send(Client.makePacket(net.ENTITY_REMOVE, id))
      else
        self:broadcastPacket(net.ENTITY_REMOVE, id)
      end
    end

    entity:onMapChange() -- removal event
  end
end

-- check if the cell is passable for a specific entity
-- return bool
function Map:isCellPassable(entity, x, y)
  if x >= 0 and x < self.w and y >= 0 and y < self.h then -- valid cell
    -- tileset check
    --- get tile from tileset
    local tdata = self.tileset_data
    local index = (x*self.h+y)*4+1
    local xl, xh, yl, yh = self.tiledata[index] or 0, self.tiledata[index+1] or 0, self.tiledata[index+2] or 0, self.tiledata[index+3] or 0

    --- check passable
    local l_passage, h_passable = true, true
    if xl > 0 and yl > 0 then
      l_passable = tdata.passable[(xl-1)*tdata.hc+yl]
    end

    if xh > 0 and yh > 0 then
      h_passable = tdata.passable[tdata.wc*tdata.hc+(xh-1)*tdata.hc+yh]
    end

    if not l_passable or not h_passable then
      return false
    end

    -- entities check
    local cell = self:getCell(x,y)
    if cell then
      if class.is(entity, Client) then -- Client check
        for c_entity in pairs(cell) do
          if c_entity.obstacle and (not c_entity.client or c_entity.client == entity) then
            return false
          end
        end
      else -- regular entity
        for c_entity in pairs(cell) do
          if c_entity.obstacle and (not c_entity.client or c_entity.client == entity.client) then
            return false
          end
        end
      end
    end

    return true
  end

  return false
end

-- broadcast to all map clients
function Map:broadcastPacket(protocol, data, unsequenced)
  local packet = Client.makePacket(protocol, data)
  for client in pairs(self.clients) do
    client:send(packet, unsequenced)
  end
end

-- serialize map data for a specific client
function Map:serializeNet(client)
  local data = {
    map_index = self.data.index,
    packet_index = self.movement_packet_count,
    w = self.w,
    h = self.h,
    tileset = self.tileset,
    background = self.background,
    tiledata = self.tiledata,
    music = self.music
  }

  -- serialize entities
  data.entities = {}
  for entity in pairs(self.entities) do
    if entity.nettype and (not entity.client or entity.client == client) then
      table.insert(data.entities, entity:serializeNet())
    end
  end

  return data
end

function Map:tick(dt)
  -- build continuous movement packet
  local data = {entities = {}}

  for entity in pairs(self.living_entity_updates) do
    if entity.map == self then
      table.insert(data.entities, {entity.id, entity.x, entity.y})
    end
  end
  
  -- send packet update with map and packet indexes to prevent invalid updates
  if next(data.entities) then
    self.movement_packet_count = self.movement_packet_count+1
    data.mi = self.data.index
    data.pi = self.movement_packet_count
    self:broadcastPacket(net.MAP_MOVEMENTS, data, true) -- unsequenced
  end

  self.living_entity_updates = {}
end

-- check if a mob can be spawned at the cell coordinates
function Map:canSpawnMob(mob, cx, cy)
  -- check passable
  if not self:isCellPassable(mob, cx, cy) then return false end

  -- check for no spawn areas
  for _, area in ipairs(self.data.mob_areas) do
    if area.type < 0 and cx >= area.x1 and cx <= area.x2 and cy >= area.y1 and cy <= area.y2 then
      return false
    end
  end

  return true
end

function Map:mobAreaSpawnTask(index)
  local def = self.data.mob_areas[index]
  local area = self.mob_areas[index]

  if def then
    if area.mob_count < def.max_mobs then -- try to spawn
      local mob_data = self.server.project.mobs[def.type+1]
      if mob_data then
        local mob = Mob(mob_data, area)

        -- find position
        local i = 0
        local done = false
        while not done and i < 10 do
          local cx, cy = math.random(def.x1, def.x2), math.random(def.y1, def.y2)
          if self:canSpawnMob(mob, cx, cy) then
            self:addEntity(mob)
            mob:teleport(cx*16, cy*16)
            area.mob_count = area.mob_count+1
            done = true
          end
        end
      end
    end

    -- next call
    local duration = 1/(def.spawn_speed == 0 and 60 or def.spawn_speed)*60*utils.randf(0.80, 1)
    task(duration, function()
      self:mobAreaSpawnTask(index)
    end)
  end
end

return Map
