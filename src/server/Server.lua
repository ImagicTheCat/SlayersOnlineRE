local effil = require("effil")
local enet = require("enet")
local msgpack = require("MessagePack")
local Client = require("Client")
local Map = require("Map")
local utils = require("lib/utils")
local Deserializer = require("Deserializer")
local magick = require("magick")

local Server = class("Server")

-- STATICS

-- parse [cmd arg1 arg2 "arg 3" ...]
-- return command args
function Server.parseCommand(str)
  str = string.gsub(str, "\"(.-)\"", function(content)
    return string.gsub(content, "%s", "\\s")
  end)

  local args = {}

  for arg in string.gmatch(str, "([^%s]+)") do
    arg = string.gsub(arg, "\\s", " ")
    table.insert(args, arg)
  end

  return args
end

-- COMMANDS

local function cmd_memory(self, client, args)
  if not client then
    local MB = collectgarbage("count")*1024/1000000
    print("Lua main memory usage: "..MB.." MB")
  end
end

local function cmd_count(self, client, args)
  local count = 0
  for _ in pairs(self.clients) do
    count = count+1
  end

  if client then
    client:sendChatMessage(count.." online players")
  else
    print(count.." online players")
  end
end

local function cmd_where(self, client, args)
  if client then
    if client.map then
      client:sendChatMessage(client.map.id.." "..client.cx..","..client.cy)
    else
      client:sendChatMessage("not on a map")
    end
  end
end

local function cmd_skin(self, client, args)
  if client then
    local skin = args[2] or ""
    client:setSkin(skin)
    client:sendChatMessage("skin set to \""..skin.."\"")
  end
end

local function cmd_tp(self, client, args)
  if client then
    local ok

    if #args >= 4 then
      local map_name = args[2]
      local cx, cy = tonumber(args[3]), tonumber(args[4])
      if cx and cy then
        ok = true

        local map = self:getMap(map_name)
        if map then
          client:teleport(cx*16,cy*16)
          map:addEntity(client)
        else
          client:sendChatMessage("invalid map \""..map_name.."\"")
        end
      end
    end

    if not ok then
      client:sendChatMessage("usage: /tp map cx cy")
    end
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
  self.project.tilesets = {} -- map of id => tileset data

  self.clients = {} -- map of peer => client
  self.maps = {} -- map of id => map instances
  self.vars = {} -- server variables, map of id (str) => value (string or number)
  self.var_listeners = {} -- map of id => map of callback

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
  self:registerCommand("memory", cmd_memory)
  self:registerCommand("count", cmd_count)
  self:registerCommand("where", cmd_where)
  self:registerCommand("skin", cmd_skin)
  self:registerCommand("tp", cmd_tp)

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
    local args = Server.parseCommand(line)
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
--- client: client or nil if emitted from the server
--- args: command arguments (first is command id/name)
function Server:registerCommand(id, callback)
  self.commands[id] = callback
end

function Server:loadMapData(id)
  local map = self.project.maps[id]
  if map and not map.loaded then
    map.loaded = true
    map.tiledata = Deserializer.loadMapTiles(id)
    map.events = Deserializer.loadMapEvents(id)

    map.tileset_id = string.sub(map.tileset, 9, string.len(map.tileset)-4)
    map.tileset_data = self:loadTilesetData(map.tileset_id)

    return map
  end
end

function Server:loadTilesetData(id)
  local data = self.project.tilesets[id]

  if not data then -- load tileset data
    local image = magick.load_image("resources/project/Chipset/"..id..".png")
    if image then
      data = {}

      -- dimensions
      data.w, data.h = image:get_width(), image:get_height()
      data.wc, data.hc = data.w/16, data.h/16
      image:destroy()

      -- passable data
      data.passable = Deserializer.loadTilesetPassableData(id)

      self.project.tilesets[id] = data
    else
      print("error loading tileset image \""..id.."\"")
    end
  end

  return data
end

function Server:setVariable(id, value)
  if type(value) == "string" or type(value) == "number" then
    self.vars[id] = value

    -- call listeners
    local listeners = self.var_listeners[id]
    if listeners then
      for callback in pairs(listeners) do
        callback()
      end
    end
  end
end

function Server:getVariable(id)
  return self.vars[id] or 0
end

function Server:listenVariable(id, callback)
  local listeners = self.var_listeners[id]
  if not listeners then
    listeners = {}
    self.var_listeners[id] = listeners
  end

  listeners[callback] = true
end

function Server:unlistenVariable(id, callback)
  local listeners = self.var_listeners[id]
  if listeners then
    listeners[callback] = nil

    if not next(listeners) then
      self.var_listeners[id] = nil
    end
  end
end

return Server
