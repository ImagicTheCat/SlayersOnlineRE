local IdManager = require("lib/IdManager")
local Client = require("Client")
local net = require("protocol")

local Map = class("Map")

-- STATICS

-- METHODS

function Map:__construct(server, id, data)
  self.server = server
  self.id = id
  self.ids = IdManager()

  self.entities = {} -- map of entity
  self.clients = {} -- map of clients

  self.living_entity_updates = {} -- map of living entity

  self.data = data -- map data

  self.w = self.data.width
  self.h = self.data.height
  self.tileset = string.sub(self.data.tileset, 9) -- remove Chipset/ part
  self.tiledata = self.data.tiledata
end

function Map:addEntity(entity)
  -- remove the entity from the previous map
  if entity.map then
    entity.map:removeEntity(entity)
  end

  if not entity.client or self.clients[entity.client] then -- unbound or bound to existing client
    -- reference
    local id = self.ids:gen()
    self.entities[entity] = id
    entity.id = id
    entity.map = self

    -- reference client bound entity
    if entity.client then
      entity.client.entities[entity] = true
    end

    -- send entity packet to bound or all map clients
    if entity.nettype then
      if entity.client then
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

      entity.entities = {}
    end

    -- send entity packet to bound or all map clients
    if entity.nettype then
      if entity.client then
        entity.client:send(Client.makePacket(net.ENTITY_REMOVE, id))
      else
        self:broadcastPacket(net.ENTITY_REMOVE, id)
      end
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

-- serialize map data for a specific client
function Map:serializeNet(client)
  local data = {
    w = self.w,
    h = self.h,
    tileset = self.tileset,
    tiledata = self.tiledata
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
