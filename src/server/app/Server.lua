-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

local ljuv = require("ljuv")
local enet = require("enet")
local vips = require("vips")
local sbuffer = require("string.buffer")
local msgpack = require("MessagePack")
local sqlite = require("lsqlite3")
local lfs = require("lfs")
local Client = require("app.Client")
local LivingEntity = require("app.entities.LivingEntity")
local Map = require("app.Map")
local utils = require("app.utils")
local Deserializer = require("app.Deserializer")
local DBManager = require("app.DBManager")
local net = require("app.protocol")
local EventCompiler = require("app.EventCompiler")
local SpellCompiler = require("app.SpellCompiler")
local commands = require("app.commands")

-- Check SQLite3 error.
local function sql_assert(db, code)
  if code ~= sqlite.OK and code ~= sqlite.DONE then
    error("sqlite("..code.."): "..db:errmsg(), 2)
  end
end

local Server = class("Server")

-- Console thread.
local function console_thread(channel)
  local ljuv = require "ljuv"
  channel = ljuv.import(channel)
  while true do channel:push(io.stdin:read("*l")) end
end

-- parse [cmd arg1 arg2 arg\ 3 ...]
-- return command args
function Server.parseCommand(str)
  local args = {}
  str = string.gsub(str, "\\ ", "\\s")
  for arg in string.gmatch(str, "([^ ]+)") do
    arg = string.gsub(arg, "\\s", " ")
    table.insert(args, arg)
  end
  return args
end

function Server.checkCommandSide(side, client)
  return side == "shared" or
      client and side == "client" or
      not client and side == "server"
end

local function compileSpells(self)
  local header = "local state = ...;"
  local function compile(compiler, str, chunkname) -- return f or nil
    local code, err = compiler(str)
    if not code then
      print("ERROR compiling "..chunkname.."\n"..err.."\n")
      return
    end
    --print("-- "..chunkname.." --\n"..str.."\n=>\n"..code.."\n--")
    local f, err = loadstring(header..code, "=["..chunkname.."]")
    if not f then
      print("ERROR compiling "..chunkname.."\n"..err.."\n-- Lua --\n"..code.."\n--------a\n-")
      return
    end
    setfenv(f, LivingEntity.spell_env)
    return f
  end
  local c_expr, c_stmts = SpellCompiler.compileExpression, SpellCompiler.compileStatements
  for _, spell in ipairs(self.project.spells) do
    local prefix = "spell("..spell.name.."):"
    spell.area_func = compile(c_expr, spell.area_expr, prefix.."area")
    spell.aggro_func = compile(c_expr, spell.aggro_expr, prefix.."aggro")
    spell.duration_func = compile(c_expr, spell.duration_expr, prefix.."duration")
    spell.hit_func = compile(c_expr, spell.hit_expr, prefix.."hit")
    spell.effect_func = compile(c_stmts, spell.effect_expr, prefix.."effect")
  end
end

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
  print("compile spells...")
  compileSpells(self)
  print("spells compiled")
  -- make directories
  lfs.mkdir("data")
  -- open cache
  do
    local code
    self.cache = sqlite.open("data/cache")
    assert(self.cache, "couldn't open cache")
    sql_assert(self.cache, self.cache:execute("CREATE TABLE IF NOT EXISTS maps(id TEXT PRIMARY KEY, mtime INTEGER, data BLOB)"))
    self.cache_map_stmt, code = self.cache:prepare("SELECT data FROM maps WHERE id = ?1 AND mtime >= ?2")
    if not self.cache_map_stmt then sql_assert(self.cache, code) end
    self.cache_mapset_stmt, code = self.cache:prepare("INSERT INTO maps(id, mtime, data) VALUES(?1, ?2, ?3) ON CONFLICT(id) DO UPDATE SET mtime = ?2, data = ?3")
    if not self.cache_mapset_stmt then sql_assert(self.cache, code) end
  end
  -- load maps data
  print("load maps data...")
  self.cache:execute("BEGIN")
  for id in pairs(self.project.maps) do self:loadMapData(id) end
  self.cache:execute("COMMIT")
  print("maps data loaded")
  --
  self.clients = {} -- map of peer => client
  self.clients_by_id = {} -- map of user id => logged client
  self.clients_by_pseudo = {} -- map of pseudo (lowercase) => logged client
  self.maps = {} -- map of id => map instances
  self.vars = {} -- server variables, map of id (str) => value (string or number)
  self.changed_vars = {} -- map of server var id
  self.commands = {} -- map of id => callback
  self.motd = self.cfg.motd
  self.groups = {} -- player groups, map of id => map of client
  self.free_skins = {} -- set of skin names
  -- DB
  local cfg_db = self.cfg.db
  self.db = DBManager("data/server.db")
  -- Loading.
  async(function()
    -- prepare queries
    require("app.queries")(self.db)
    -- load vars
    local count = 0
    local rows = self.db:query("server/getVars").rows
    for i, row in ipairs(rows) do
      self.vars[row.id] = row.value
      count = count+1
    end
    print(count.." server vars loaded")
    -- init vars
    for k,v in pairs(self.cfg.server_vars_init) do
      self:setVariable(k,v)
    end
    -- load free skins
    do
      local rows = self.db:query("server/getFreeSkins").rows
      for _, row in ipairs(rows) do self.free_skins[row.name] = true end
    end
  end)
  -- create host
  self.host = enet.host_create(self.cfg.host, self.cfg.max_clients)
  print("listening to \""..self.cfg.host.."\"...")
  -- console thread
  self.console_channel = ljuv.new_channel()
  loop:thread(console_thread, assert, ljuv.export(self.console_channel))
  -- Timers.
  do
    local last_time = loop:now()
    -- server tick
    self.tick_timer = itimer(1/self.cfg.tickrate, function()
      local time = loop:now()
      local dt = time-last_time
      last_time = time
      self:tick(dt)
    end)
  end
  self.save_timer = itimer(self.cfg.save_period, function() async(self.save, self) end)
  -- event/timer tick
  local event_period = 0.03*1/self.cfg.event_frequency_factor
  local event_timer_ticks = math.floor(1/self.cfg.event_frequency_factor)
  self.event_timer = itimer(event_period, function()
    for peer, client in pairs(self.clients) do
      client:eventTick(event_timer_ticks)
    end
  end)
  -- minute tick
  self.minute_timer = itimer(60, function()
    for peer, client in pairs(self.clients) do
      client:minuteTick()
    end
  end)
end

-- (async, reentrant)
-- return boolean status (success/failure)
function Server:save()
  -- guard
  if self.saving then return false end
  self.saving = true

  local start_time = loop:now()
  local ok = self.db:transactionWrap(function()
    -- save vars (clone for concurrent access)
    local changed_vars = self.changed_vars
    self.changed_vars = {}
    for var in pairs(changed_vars) do
      self.db:query("server/setVar", {var, self.vars[var]})
    end
    -- save clients
    for _, client in pairs(utils.clone(self.clients, 1)) do
      if client.status == "logged" then client:save() end
    end
  end)
  local elapsed = loop:now()-start_time
  print("server save: "..(ok and "committed" or "aborted").." ("..utils.round(elapsed, 3).."s)")

  -- end guard
  self.saving = false
  return true
end

-- (async)
function Server:close()
  -- guard
  if self.closing then return end
  self.closing = true

  self.event_timer:close()
  self.minute_timer:close()
  self.save_timer:close()
  -- disconnect clients
  for peer, client in pairs(self.clients) do
    peer:disconnect()
    client:onDisconnect()
  end
  self:save()
  self.host:flush()
  self.db:close()
  self.tick_timer:close()
  sql_assert(self.cache, self.cache:close())
  print("shutdown.")

  -- end guard
  self.closing = nil
end

function Server:tick(dt)
  -- console
  repeat
    local ok, line = self.console_channel:try_pull()
    -- parse command
    if ok then
      local args = Server.parseCommand(line)
      if #args > 0 then
        self:processCommand(nil, args)
      end
    end
  until not ok
  -- net
  local event = self.host:service()
  while event do
    if event.type == "receive" then
      local client = self.clients[event.peer]
      -- quotas
      client.packets_quota:add(1)
      client.data_quota:add(#event.data)
      -- packet
      local ok, packet = pcall(msgpack.unpack, event.data)
      if ok then client:onPacket(packet[1], packet[2]) end
    elseif event.type == "connect" then
      -- disable throttle deceleration (issue with unsequenced packets not sent)
      event.peer:throttle_configure(5000, 1, 0)
      local client = Client(event.peer)
      self.clients[event.peer] = client
      print("client connection "..tostring(event.peer))
    elseif event.type == "disconnect" then
      local client = self.clients[event.peer]
      self.clients[event.peer] = nil
      print("client disconnection "..tostring(event.peer))
      async(function() client:onDisconnect() end)
    end

    event = self.host:service()
  end
  -- maps tick
  for id, map in pairs(self.maps) do map:tick(dt) end
end

-- case insensitive
function Server:getClientByPseudo(pseudo)
  return self.clients_by_pseudo[pseudo:lower()]
end

-- return map instance or nil
function Server:getMap(id)
  local map = self.maps[id]
  if not map then -- load
    local map_data = self.project.maps[id]
    if map_data and map_data.loaded then
      map = Map(id, map_data)
      self.maps[id] = map
    else print("couldn't load \""..id.."\" map data") end
  end
  return map
end

-- client: client or nil from server console
function Server:processCommand(client, args)
  -- dispatch command
  local rank = client and math.max(client.user_rank or 10, 1) or 0
  local command = commands[args[1]]
  if command and rank <= command[1] and Server.checkCommandSide(command[2], client) then
    if command[3](self, client, args) then
      local msg = "utilisation: "..args[1].." "..command[4]
      if client then
        client:print(msg)
      else
        print(msg)
      end
    end
  else
    local msg = "commande \""..args[1].."\" inconnue (commande \"help\" pour la liste)"
    if client then
      client:print(msg)
    else
      print(msg)
    end
  end
end

function Server:loadMapData(id)
  local map = self.project.maps[id]
  if map then
    if not map.loaded then
      map.tiledata = Deserializer.loadMapTiles(id)
      map.events = Deserializer.loadMapEvents(id) or {}
      map.mob_areas = Deserializer.loadMapMobAreas(id) or {}
      map.tileset_id = string.sub(map.tileset, 9, string.len(map.tileset)-4)
      map.tileset_data = self:loadTilesetData(map.tileset_id)
      map.loaded = (map.tiledata and map.events and map.mob_areas and map.tileset_data)
      -- Compile events (with on disk caching).
      -- load cache
      local cache = {}
      local cache_modified = false
      -- Load cache if source .ev0 is not newer.
      local mtime = lfs.attributes("resources/project/Maps/"..id..".ev0", "modification")
      local stmt = self.cache_map_stmt
      stmt:reset()
      sql_assert(self.cache, stmt:bind(1, id))
      sql_assert(self.cache, stmt:bind(2, mtime))
      for row in stmt:nrows() do
        local ok, cache_data = pcall(sbuffer.decode, row.data)
        if ok then cache = cache_data else print("ERROR cache corrupted for "..id) end
      end
      --- compile
      local header = "local state, var, bool_var, server_var, special_var, func_var, event_var, func, inventory = ...; local S, N, R = S, N, R;"
      local function to_number(v) return v and tonumber(v) or 0 end
      local env = {S = tostring, N = to_number, R = utils.sanitizeInt}
      local function compileConditions(page, chunkname) -- return error or nil
        local code, flags = EventCompiler.compileConditions(page.conditions)
        if not code then return flags end
        local f, err = loadstring(header..code, chunkname)
        if not f then return err.."\n-- Lua --\n"..code.."\n---------" end
        setfenv(f, env)
        page.conditions_func = f
        page.conditions_flags = flags
      end
      local function compileCommands(page, chunkname) -- return error or nil
        local code, err = EventCompiler.compileCommands(page.commands)
        if not code then return err end
        local f, err = loadstring(header..code, chunkname)
        if not f then return err.."\n-- Lua --\n"..code.."\n---------" end
        setfenv(f, env)
        page.commands_func = f
      end
      for event_index, event in ipairs(map.events or {}) do
        -- event cache
        local event_cache = cache[event_index]
        if not event_cache then event_cache = {}; cache[event_index] = event_cache end
        for page_index, page in ipairs(event.pages) do
          -- page cache
          local page_cache = event_cache[page_index]
          if not page_cache then page_cache = {}; event_cache[page_index] = page_cache end
          do -- conditions
            local chunkname = "=["..map.name.."("..event.x..","..event.y..") P"..page_index.." CD]"
            if page_cache.conditions_func then -- from cache
              local f, err = loadstring(page_cache.conditions_func, chunkname)
              if f then
                setfenv(f, env)
                page.conditions_func = f
                page.conditions_flags = page_cache.conditions_flags
              else
                print("ERROR loading from cache conditions map \""..map.name.."\" event ("..event.x..","..event.y..") P"..page_index..": "..err)
              end
            else -- compile
              local err = compileConditions(page, chunkname)
              if err then
                print("ERROR compiling conditions map \""..map.name.."\" event ("..event.x..","..event.y..") P"..page_index)
                print(err)
                print()
              else -- update cache
                page_cache.conditions_func = string.dump(page.conditions_func)
                page_cache.conditions_flags = page.conditions_flags
                cache_modified = true
              end
            end
          end
          do -- commands
            local chunkname = "=["..map.name.."("..event.x..","..event.y..") P"..page_index.." EV]"
            if page_cache.commands_func then -- from cache
              local f, err = loadstring(page_cache.commands_func, chunkname)
              if f then
                setfenv(f, env)
                page.commands_func = f
              else
                print("ERROR loading from cache commands map \""..map.name.."\" event ("..event.x..","..event.y..") P"..page_index..": "..err)
              end
            else -- compile
              local err = compileCommands(page, chunkname)
              if err then
                print("ERROR compiling commands map \""..map.name.."\" event ("..event.x..","..event.y..") P"..page_index)
                print(err)
                print()
              else -- update cache
                page_cache.commands_func = string.dump(page.commands_func)
                cache_modified = true
              end
            end
          end
        end
      end
      if cache_modified then -- save cache
        local stmt = self.cache_mapset_stmt
        stmt:reset()
        sql_assert(self.cache, stmt:bind(1, id))
        sql_assert(self.cache, stmt:bind(2, mtime))
        sql_assert(self.cache, stmt:bind_blob(3, sbuffer.encode(cache)))
        sql_assert(self.cache, stmt:step())
      end
    end
  end
end

function Server:loadTilesetData(id)
  local data = self.project.tilesets[id]

  if not data then -- load tileset data
    local ok, image = pcall(vips.Image.new_from_file, "resources/project/Chipset/"..id..".png")
    if ok then
      data = {}

      -- dimensions
      data.w, data.h = image:width(), image:height()
      data.wc, data.hc = data.w/16, data.h/16

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
  id, value = tostring(id), tostring(value)
  self.changed_vars[id] = true
  self.vars[id] = value
end

function Server:getVariable(id)
  return self.vars[tostring(id)] or 0
end

return Server
