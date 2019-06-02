local enet = require("enet")
local msgpack = require("MessagePack")
local Client = require("Client")
local Map = require("Map")

local Server = class("Server")

function Server:__construct(cfg)
  self.cfg = cfg
  self.clients = {} -- map of peer => client
  self.maps = {} -- map of id => map instances

  self.last_time = clock()

  -- register tick callback
  self.tick_task = itask(1/self.cfg.tickrate, function()
    local time = clock()
    local dt = time-self.last_time
    self.last_time = time

    self:tick(dt)
  end)

  -- create host
  self.host = enet.host_create(self.cfg.host, self.cfg.max_clients)

  print("listening to \""..self.cfg.host.."\"...")
end

function Server:close()
  self.tick_task:remove()
  print("shutdown.")
end

function Server:tick(dt)
  -- net
  local event = self.host:service()
  while event do
    print(event.type, event.peer)

    if event.type == "receive" then
      local client = self.clients[event.peer]
      local packet = msgpack.unpack(event.data)
      client:onPacket(packet[1], packet[2])
    elseif event.type == "connect" then
      local client = Client(self, event.peer)
      self.clients[event.peer] = client
    elseif event.type == "disconnect" then
      local client = self.clients[event.peer]
      client:onDisconnect()
      self.clients[event.peer] = nil
    end

    event = self.host:service()
  end

  -- maps tick
  for id, map in pairs(self.maps) do
    map:tick(dt)
  end
end

-- return map instance or nil
function Server:getMap(id)
  local map = self.maps[id]

  if not map then -- load
    map = Map(self, id)
    self.maps[id] = map
  end

  return map
end

return Server
