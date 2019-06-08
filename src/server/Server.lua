local effil = require("effil")
local enet = require("enet")
local msgpack = require("MessagePack")
local Client = require("Client")
local Map = require("Map")
local utils = require("lib/utils")
local Deserializer = require("Deserializer")

local Server = class("Server")

-- COMMANDS

local function cmd_count(self, sender, args)
  local count = 0
  for _ in pairs(self.clients) do
    count = count+1
  end

  if sender then
    sender:sendChatMessage(count.." online players")
  else
    print(count.." online players")
  end
end

local function cmd_skin(self, sender, args)
  if sender then
    local skin = args[2] or ""
    sender:setSkin(skin)
    sender:sendChatMessage("skin set to \""..skin.."\"")
  end
end

-- CONSOLE THREAD
local function console_main(flags, channel)
  while flags.running do
    local line = io.stdin:read("*l")
    channel:push(line)
  end
end

-- METHODS

function Server:__construct(cfg)
  self.cfg = cfg

  -- load project
  self.project = Deserializer.loadProject(self.cfg.project_name)
  print(self.project.map_count.." project maps loaded.")

  self.clients = {} -- map of peer => client
  self.maps = {} -- map of id => map instances

  self.commands = {} -- map of id => callback

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
  print("Listening to \""..self.cfg.host.."\"...")

  -- register commands
  self:registerCommand("count", cmd_count)
  self:registerCommand("skin", cmd_skin)

  -- console thread
  self.console_flags = effil.table({ running = true })
  self.console_channel = effil.channel()
  self.console = effil.thread(console_main)(self.console_flags, self.console_channel)
end

function Server:close()
  self.console_flags.running = false
  self.tick_task:remove()

  print("shutdown.")
end

function Server:tick(dt)
  -- console
  while self.console_channel:size() > 0 do
    local line = self.console_channel:pop()

    -- parse command
    local args = utils.split(line, " ")
    if #args > 0 then
      local ok = self:processCommand(nil, args)
      if not ok then
        print("unknown command \""..args[1].."\"")
      end
    end
  end

  -- net
  local event = self.host:service()
  while event do
    if event.type == "receive" then
      local client = self.clients[event.peer]
      local packet = msgpack.unpack(event.data)
      client:onPacket(packet[1], packet[2])
    elseif event.type == "connect" then
      local client = Client(self, event.peer)
      self.clients[event.peer] = client

      print("client connection "..tostring(event.peer))
    elseif event.type == "disconnect" then
      local client = self.clients[event.peer]
      client:onDisconnect()
      self.clients[event.peer] = nil

      print("client disconnection "..tostring(event.peer))
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
    local map_data = self:loadMapData(id)
    if map_data then
      map = Map(self, id, map_data)
      self.maps[id] = map
    end
  end

  return map
end

-- return true if the command has been processed or false
function Server:processCommand(sender, args)
  -- dispatch command
  local command = self.commands[args[1]]
  if command then
    command(self, sender, args)
    return true
  else
    return false
  end
end

-- id: string (first command argument)
-- callback(server, sender, args)
--- sender: client or nil from the server
--- args: command arguments (first is command id/name)
function Server:registerCommand(id, callback)
  self.commands[id] = callback
end

function Server:loadMapData(id)
  local map = self.project.maps[id]
  if map then
    map.tiledata = Deserializer.loadMapTiles(id)
    map.events = Deserializer.loadMapEvents(id)

    return map
  end
end

return Server
