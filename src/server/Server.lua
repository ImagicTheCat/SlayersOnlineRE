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

-- map of command id => {handler, usage, description}
-- handler(server, client, args)
--- client: client or nil if emitted from the server
--- args: command arguments list (first is command id/name)
--- should return true if the command is invalid
-- usage: one line command arguments summary (ex: "<arg1> <arg2> ...")
-- description: command description

local commands = {}

commands.help = {function(self, client, args)
  local id = args[2]
  if id then -- single command
    local cmd = commands[id]
    if cmd then -- found
      local lines = {}
      table.insert(lines, "  "..id.." "..cmd[2])
      table.insert(lines, "    "..cmd[3])

      if client then
        client:sendChatMessage(table.concat(lines, "\n"))
      else
        print(table.concat(lines, "\n"))
      end
    else
      local msg = "help: unknown command \""..id.."\""
      if client then
        client:sendChatMessage(msg)
      else
        print(msg)
      end
    end
  else -- all commands
    local lines = {}
    table.insert(lines, "Commands:")
    for id, cmd in pairs(commands) do
      table.insert(lines, "  "..id.." "..cmd[2])
      table.insert(lines, "    "..cmd[3])
    end

    if client then
      client:sendChatMessage(table.concat(lines, "\n"))
    else
      print(table.concat(lines, "\n"))
    end
  end
end, "[command]", "list all commands or print info for a single command"}

local bind_blacklist = {
  ["return"] = true,
  escape = true
}
commands.bind = {function(self, client, args)
  if client then
    local scancode, control = args[2], args[3]
    if not scancode then return true end

    if control then
      if not bind_blacklist[scancode] then
        client:applyConfig({scancode_controls = {[scancode] = control}})
        client:sendChatMessage("bound \""..scancode.."\" to \""..control.."\"")
      else
        client:sendChatMessage("scancode \""..scancode.."\" can't be re-mapped")
      end
    else
      local controls = client.player_config.scancode_controls
      local control = (controls and controls[scancode] or "none")
      client:sendChatMessage("\""..scancode.."\" is bound to \""..control.."\"")
    end
  end
end, "<scancode> [control]", [[show or map a LÖVE/SDL scancode to a control
    scancodes: https://love2d.org/wiki/Scancode
    controls: none, up, right, down, left, interact, attack, return, menu]]
}

commands.volume = {function(self, client, args)
  if client then
    local vtype, volume = args[2], tonumber(args[3])
    if vtype and volume then
      client:applyConfig({volume = {[vtype] = volume}})
    else
      return true
    end
  end
end, "<type> <volume>", [[set volume
    types: master
    volume: 0-1]]
}

commands.gui = {function(self, client, args)
  if client then
    local param, value = args[2], args[3]
    if not param or not value then return true end

    if param == "font_size" then
      client:applyConfig({gui = {font_size = tonumber(value) or 25}})
    else
      client:sendChatMessage("invalid parameter \""..param.."\"")
    end
  end
end, "<parameter> <value>", [[set GUI parameters
    - font_size (size in pixels)]]
}

commands.memory = {function(self, client, args)
  if not client then
    local MB = collectgarbage("count")*1024/1000000
    print("Lua main memory usage: "..MB.." MB")
  end
end, "", "print memory used by Lua"}

commands.count = {function(self, client, args)
  local count = 0
  for _ in pairs(self.clients) do
    count = count+1
  end

  if client then
    client:sendChatMessage(count.." online players")
  else
    print(count.." online players")
  end
end, "", "print number of online players"}

commands.where = {function(self, client, args)
  if client then
    if client.map then
      client:sendChatMessage(client.map.id.." "..client.cx..","..client.cy)
    else
      client:sendChatMessage("not on a map")
    end
  end
end, "", "print location"}

commands.skin = {function(self, client, args)
  if client then
    if not args[2] then return true end

    local skin = args[2] or ""
    client:setSkin(skin)
    client:sendChatMessage("skin set to \""..skin.."\"")
  end
end, "<skin_name>", "change skin"}

commands.tp = {function(self, client, args)
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
      return true
    end
  end
end, "<map> <cx> <cy>", "teleport to coordinates"}

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
  print("load project \""..self.cfg.project_name.."\"...")

  self.project = Deserializer.loadProject(self.cfg.project_name)
  print("- "..self.project.map_count.." maps loaded")
  print("- "..self.project.class_count.." classes loaded")
  print("- "..self.project.object_count.." objects loaded")
  print("- "..self.project.mob_count.." mobs loaded")
  print("- "..self.project.spell_count.." spells loaded")
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
  print("listening to \""..self.cfg.host.."\"...")

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
      self:processCommand(nil, args)
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

-- client: client or nil from server console
function Server:processCommand(client, args)
  -- dispatch command
  local command = commands[args[1]]
  if command then
    if command[1](self, client, args) then
      local msg = "usage: "..args[1].." "..command[2]
      if client then
        client:sendChatMessage(msg)
      else
        print(msg)
      end
    end
  else
    local msg = "unknown command \""..args[1].."\" (command \"help\" to list all)"
    if client then
      client:sendChatMessage(msg)
    else
      print(msg)
    end
  end
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
