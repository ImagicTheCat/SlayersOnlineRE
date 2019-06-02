local IdManager = require("lib/IdManager")
local Client = require("Client")
local net = require("protocol")

local Map = class("Map")

-- STATICS

-- return list of x_low, x_high, y_low, y_high... from the tileset for each map tile (or nil)
function Map.loadTileData(id)
  local file, err = io.open("resources/maps/"..id..".map")
  if file then
    local tiledata = {}

    local line
    repeat
      line = file:read("*l")
      if line then
        table.insert(tiledata, tonumber(line))
      end
    until not line

    return tiledata
  end
end

-- METHODS

function Map:__construct(server, id)
  self.server = server
  self.id = id
  self.ids = IdManager()

  self.entities = {} -- map of entity => id
  self.clients = {} -- map of clients

  -- load map data
  self.w = 10
  self.h = 10
  self.tileset = "test.png"
  self.tiledata = Map.loadTileData(id)
  if not self.tiledata then
    print("error loading tiledata for map \""..self.id.."\"")
  end
end

function Map:addEntity(entity)
  -- remove the entity from the previous map
  if entity.map then
    entity.map:removeEntity(entity)
  end

  -- send entity packet to all map clients
  if entity.nettype then
    local packet = Client.makePacket(net.ENTITY_ADD, entity:serializeNet())
    for client in pairs(self.clients) do
      client:send(packet)
    end
  end

  -- reference
  local id = self.ids:gen()
  self.entities[entity] = id
  entity.id = id
  entity.map = self

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
      local packet = Client.makePacket(net.ENTITY_REMOVE, id)
      for client in pairs(self.clients) do
        client:send(packet)
      end
    end

    entity:onMapChange() -- removal event
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

return Map
