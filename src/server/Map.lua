local IdManager = require("lib/IdManager")
local Client = require("Client")
local net = require("protocol")

local Map = class("Map")

-- STATICS

-- METHODS

function Map:__construct(server, id, map_data)
  self.server = server
  self.id = id
  self.ids = IdManager()

  self.entities = {} -- map of entity => id
  self.clients = {} -- map of clients

  self.living_entity_updates = {} -- map of living entity

  -- load map data
  self.map_data = map_data

  self.w = self.map_data.width
  self.h = self.map_data.height
  self.tileset = string.sub(self.map_data.tileset, 9) -- remove Chipset/ part
  self.tiledata = self.map_data.tiledata
end

function Map:addEntity(entity)
  -- remove the entity from the previous map
  if entity.map then
    entity.map:removeEntity(entity)
  end

  -- reference
  local id = self.ids:gen()
  self.entities[entity] = id
  entity.id = id
  entity.map = self

  -- send entity packet to all map clients
  if entity.nettype then
    self:broadcastPacket(net.ENTITY_ADD, entity:serializeNet())
  end

  if class.is(entity, Client) then
    self.clients[entity] = true
  end

  entity:onMapChange() -- add event
end

function Map:removeEntity(entity)
  local id = self.entities[entity]

  if id then
    -- unreference
    self.ids:free(id)
    entity.id = nil
    entity.map = nil
    self.entities[entity] = nil

    if class.is(entity, Client) then
      self.clients[entity] = nil
    end

    -- send entity packet to all map clients
    if entity.nettype then
      self:broadcastPacket(net.ENTITY_REMOVE, id)
    end

    entity:onMapChange() -- removal event
  end
end

-- broadcast to all map clients
function Map:broadcastPacket(protocol, data, unsequenced)
  local packet = Client.makePacket(protocol, data)
  for client in pairs(self.clients) do
    client:send(packet, unsequenced)
  end
end

function Map:serializeNet()
  local data = {
    w = self.w,
    h = self.h,
    tileset = self.tileset,
    tiledata = self.tiledata
  }

  -- serialize entities
  data.entities = {}
  for entity in pairs(self.entities) do
    if entity.nettype then
      table.insert(data.entities, entity:serializeNet())
    end
  end

  return data
end

function Map:tick(dt)
  -- build continuous movement packet
  local data = {}

  for entity in pairs(self.living_entity_updates) do
    if entity.map == self then
      table.insert(data, {entity.id, entity.x, entity.y})
    end
  end
  
  if next(data) then
    self:broadcastPacket(net.MAP_MOVEMENTS, data, true) -- unsequenced
  end

  self.living_entity_updates = {}
end

return Map
