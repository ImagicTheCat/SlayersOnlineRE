-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

-- Commands

local digest = require "openssl.digest"
local msgpack = require "MessagePack"
local sqlite = require "lsqlite3"
local utils = require "app.utils"
local client_salt = require "app.client_salt"
local EventCompiler = require "app.EventCompiler"
local Server
timer(0.01, function() Server = require "app.Server" end)

-- optional require
local profiler
do
  local ok, r = wpcall(require, "jit.p")
  profiler = ok and r
end

-- map of command id => {rank, side, handler, usage, description}
-- rank: 0-10, permissions
--- Each rank inherits from higher ranks permissions.
--- 0: server (the minimum for an user is 1)
--- 10: normal player
-- side: "client", "server", "shared"
-- handler(server, client, args)
--- client: client or nil if emitted from the server
--- args: command arguments list (first is command id/name)
--- should return true if the command is invalid
-- usage: one line command arguments summary (ex: "<arg1> <arg2> ...")
-- description: command description
local commands = {}

commands.help = {10, "shared", function(self, client, args)
  local rank = client and math.max(client.user_rank or 10, 1) or 0
  local id = args[2]
  if id then -- single command
    local cmd = commands[id]
    if cmd and rank <= cmd[1] and Server.checkCommandSide(cmd[2], client) then -- found
      local lines = {}
      table.insert(lines, "  "..id.." "..cmd[4])
      table.insert(lines, "    "..cmd[5])
      if client then
        client:print(table.concat(lines, "\n"))
      else
        print(table.concat(lines, "\n"))
      end
    else
      local msg = "help: commande \""..id.."\" inconnue"
      if client then client:print(msg) else print(msg) end
    end
  else -- general help, all commands
    local lines = {}
    table.insert(lines, [[Commandes (échapper un espace avec '\s' ou '\ '):]])
    for id, cmd in pairs(commands) do
      if rank <= cmd[1] and Server.checkCommandSide(cmd[2], client) then
        table.insert(lines, "  "..id.." "..cmd[4])
        table.insert(lines, "    "..cmd[5])
      end
    end
    if client then
      client:print(table.concat(lines, "\n"))
    else
      print(table.concat(lines, "\n"))
    end
  end
end, "[command]", "lister toutes les commandes ou afficher l'aide d'une commande"}

local bind_sc_blacklist = {
  ["return"] = true,
  escape = true
}
local control_whitelist = {
  none = true,
  up = true,
  right = true,
  down = true,
  left = true,
  interact = true,
  attack = true,
  defend = true,
  quick1 = true,
  quick2 = true,
  quick3 = true,
  ["return"] = true,
  menu = true,
  chat_up = true,
  chat_down = true,
  chat_prev = true,
  chat_next = true,
  fullscreen = true
}

local love_inputs = require("app.love-inputs")

-- Should return the processed value if the path/value is valid, nothing/nil
-- otherwise.
local function check_set_config(param, value)
  local path = utils.split(param, "%.")
  if path[1] == "volume" then
    if #path ~= 2 then return end
    if path[2] == "music" or path[2] == "master" then return tonumber(value) end
  elseif path[1] == "gui" then
    if #path ~= 2 then return end
    if path[2] == "font_size" then return tonumber(value)
    elseif path[2] == "dialog_height" then return tonumber(value)
    elseif path[2] == "chat_height" then return tonumber(value)
    end
  elseif path[1] == "scancode_controls" then
    if #path ~= 2 then return end
    if not control_whitelist[value] then return end
    if not love_inputs.scancodes[path[2]] or bind_sc_blacklist[path[2]] then return end
    return value
  elseif path[1] == "gamepad_controls" then
    if #path ~= 2 then return end
    if not control_whitelist[value] then return end
    if not love_inputs.gamepad_buttons[path[2]] then return end
    return value
  end
end

commands.cfg = {10, "client", function(self, client, args)
  local param, value = args[2], args[3]
  if param then
    if #param > 100 then return true end -- prevent potential DoS attacks
    if value then -- set value
      if value == "default" then -- get default value
        value = utils.clone(utils.tget(self.cfg.player_config, param))
      else -- check param and value
        value = check_set_config(param, value)
      end
      -- apply config
      if value then
        local t = {}; utils.tset(t, param, value)
        client:applyConfig(t)
      else client:print("Paramètre/valeur invalide.") end
    else -- show value
      local value = utils.tget(client.player_config, param)
      if value ~= nil then client:print(utils.dump(value))
      else client:print("Paramètre invalide ou non défini.") end
    end
  else -- show all parameters
    client:print(utils.dump(client.player_config))
  end
end, "[<parameter_path> [<value> | default]]", [[montrer/modifier la configuration de paramètres
    - volume
      - master (0-1)
      - music (0-1 facteur)
    - gui
      - font_size (taille en pixels)
      - dialog_height (0-1 facteur)
      - chat_height (0-1 facteur)
    - scancode_controls.<scancode>
      gamepad_controls.<button>
        scancodes: https://love2d.org/wiki/Scancode
        gamepad: https://love2d.org/wiki/GamepadButton
        contrôles: none, up, right, down, left, interact, attack, defend, quick1, quick2, quick3, return, menu, chat_up, chat_down, chat_prev, chat_next, fullscreen]]}

commands.memory = {0, "server", function(self, client, args)
  local MB = collectgarbage("count")*1024/1000000
  print("Mémoire utilisée (Lua GC): "..MB.." Mo")
end, "", "afficher la mémoire utilisée par la VM Lua"}

commands.dump = {0, "server", function(self, client, args)
  io.open("data/project.db", "w"):close() -- truncate file
  local db = sqlite.open("data/project.db")
  -- Check SQLite3 error.
  local function sql_assert(code)
    if code ~= sqlite.OK and code ~= sqlite.DONE then
      error("sqlite("..code.."): "..db:errmsg(), 2)
    end
  end
  -- create tables
  sql_assert(db:execute([[
CREATE TABLE classes(
  id INTEGER PRIMARY KEY,
  name TEXT,
  attack_sound TEXT,
  hurt_sound TEXT,
  focus_sound TEXT,
  max_strength INTEGER,
  max_dexterity INTEGER,
  max_constitution INTEGER,
  max_magic INTEGER,
  max_level INTEGER,
  level_up_points INTEGER,
  strength INTEGER,
  dexterity INTEGER,
  constitution INTEGER,
  magic INTEGER,
  off_index INTEGER,
  def_index INTEGER,
  pow_index INTEGER,
  health_index INTEGER,
  mag_index INTEGER
);

CREATE TABLE objects(
  id INTEGER PRIMARY KEY,
  name TEXT,
  description TEXT,
  type TEXT,
  price INTEGER,
  usable_class INTEGER REFERENCES classes(id),
  spell INTEGER REFERENCES spells(id),
  mod_strength INTEGER,
  mod_dexterity INTEGER,
  mod_constitution INTEGER,
  mod_magic INTEGER,
  mod_attack_a INTEGER,
  mod_attack_b INTEGER,
  mod_defense INTEGER,
  mod_hp INTEGER,
  mod_mp INTEGER,
  req_strength INTEGER,
  req_dexterity INTEGER,
  req_constitution INTEGER,
  req_magic INTEGER,
  req_level INTEGER
);

CREATE TABLE mobs(
  id INTEGER PRIMARY KEY,
  name TEXT,
  type TEXT,
  obstacle INTEGER,
  level INTEGER,
  charaset TEXT,
  w INTEGER,
  h INTEGER,
  attack_sound TEXT,
  hurt_sound TEXT,
  focus_sound TEXT,
  speed INTEGER,
  attack INTEGER,
  defense INTEGER,
  damage INTEGER,
  health INTEGER,
  xp_min INTEGER,
  xp_max INTEGER,
  gold_min INTEGER,
  gold_max INTEGER,
  loot_object INTEGER REFERENCES objects(id),
  loot_chance INTEGER,
  var_id INTEGER,
  var_increment INTEGER
);

CREATE TABLE mobs_spells(
  mob INTEGER REFERENCES mobs(id),
  "index" INTEGER,
  spell INTEGER REFERENCES spells(id),
  probability INTEGER,
  PRIMARY KEY(mob, "index")
);

CREATE TABLE spells(
  id INTEGER PRIMARY KEY,
  name TEXT,
  description TEXT,
  "set" TEXT,
  sound TEXT,
  area_expr TEXT,
  aggro_expr TEXT,
  duration_expr TEXT,
  hit_expr TEXT,
  effect_expr TEXT,
  x INTEGER,
  y INTEGER,
  w INTEGER,
  h INTEGER,
  opacity INTEGER,
  anim_duration INTEGER,
  usable_class INTEGER REFERENCES classes(id),
  mp INTEGER,
  req_level INTEGER,
  cast_duration INTEGER,
  type TEXT,
  position_type TEXT,
  target_type TEXT
);

CREATE TABLE maps(
  name TEXT PRIMARY KEY,
  type TEXT,
  effect TEXT,
  background TEXT,
  music TEXT,
  tileset TEXT,
  width INTEGER,
  height INTEGER,
  disconnect_respawn INTEGER,
  si_v INTEGER,
  v_c INTEGER,
  svar INTEGER,
  sval INTEGER,
  tiledata BLOB -- msgpack
);

CREATE TABLE maps_mob_areas(
  map INTEGER REFERENCES maps(rowid),
  x1 INTEGER,
  x2 INTEGER,
  y1 INTEGER,
  y2 INTEGER,
  max_mobs INTEGER,
  type INTEGER, -- 0: no spawn, >= 1 mob id
  spawn_speed INTEGER,
  server_var TEXT,
  server_var_expr TEXT
);

CREATE TABLE maps_events(
  map INTEGER REFERENCES maps(rowid),
  x INTEGER,
  y INTEGER
);

CREATE TABLE events_pages(
  event INTEGER REFERENCES maps_events(rowid),
  name TEXT,
  "set" TEXT,
  position_type TEXT,
  x INTEGER,
  y INTEGER,
  w INTEGER,
  h INTEGER,
  animation_number INTEGER,
  active INTEGER,
  obstacle INTEGER,
  transparent INTEGER,
  follow INTEGER,
  animation_type INTEGER,
  animation_mod INTEGER,
  speed INTEGER,
  conditions TEXT,
  commands TEXT
);
  ]]))
  -- insert data
  sql_assert(db:execute("BEGIN"))
  do -- classes
    local stmt = db:prepare("INSERT INTO classes VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
    for i, t in ipairs(self.project.classes) do
      stmt:reset()
      sql_assert(stmt:bind_values(i, t.name, t.attack_sound, t.hurt_sound, t.focus_sound, t.max_strength, t.max_dexterity, t.max_constitution, t.max_magic, t.max_level, t.level_up_points, t.strength, t.dexterity, t.constitution, t.magic, t.off_index, t.def_index, t.pow_index, t.health_index, t.mag_index))
      sql_assert(stmt:step())
    end
  end
  do -- objects
    local stmt = db:prepare("INSERT INTO objects VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
    for i, t in ipairs(self.project.objects) do
      stmt:reset()
      sql_assert(stmt:bind_values(i, t.name, t.description, t.type, t.price, t.usable_class, t.spell, t.mod_strength, t.mod_dexterity, t.mod_constitution, t.mod_magic, t.mod_attack_a, t.mod_attack_b, t.mod_defense, t.mod_hp, t.mod_mp, t.req_strength, t.req_dexterity, t.req_constitution, t.req_magic, t.req_level))
      sql_assert(stmt:step())
    end
  end
  do -- mobs
    local stmt = db:prepare("INSERT INTO mobs VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
    local stmt2 = db:prepare("INSERT INTO mobs_spells VALUES(?,?,?,?)")
    for i, t in ipairs(self.project.mobs) do
      stmt:reset()
      sql_assert(stmt:bind_values(i, t.name, t.type, t.obstacle, t.level, t.charaset, t.w, t.h, t.attack_sound, t.hurt_sound, t.focus_sound, t.speed, t.attack, t.defense, t.damage, t.health, t.xp_min, t.xp_max, t.gold_min, t.gold_max, t.loot_object, t.loot_chance, t.var_id, t.var_increment))
      sql_assert(stmt:step())
      -- spells
      for spell_i, spell in ipairs(t.spells) do
        stmt2:reset()
        sql_assert(stmt2:bind_values(i, spell_i, spell[1], spell[2]))
        sql_assert(stmt2:step())
      end
    end
  end
  do -- spells
    local stmt = db:prepare("INSERT INTO spells VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
    for i, t in ipairs(self.project.spells) do
      stmt:reset()
      sql_assert(stmt:bind_values(i, t.name, t.description, t.set, t.sound, t.area_expr, t.aggro_expr, t.duration_expr, t.hit_expr, t.effect_expr, t.x, t.y, t.w, t.h, t.opacity, t.anim_duration, t.usable_class, t.mp, t.req_level, t.cast_duration, t.type, t.position_type, t.target_type))
      sql_assert(stmt:step())
    end
  end
  do -- maps
    local stmt = db:prepare("INSERT INTO maps VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
    local stmt_area = db:prepare("INSERT INTO maps_mob_areas VALUES(?,?,?,?,?,?,?,?,?,?)")
    local stmt_event = db:prepare("INSERT INTO maps_events VALUES(?,?,?)")
    local stmt_event_page = db:prepare("INSERT INTO events_pages VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
    for _, map in pairs(self.project.maps) do
      stmt:reset()
      sql_assert(stmt:bind_names{map.name, map.type, map.effect, map.background, map.music, map.tileset, map.width, map.height, map.disconnect_respawn, map.si_v, map.v_c, map.svar, map.sval})
      sql_assert(stmt:bind_blob(14, msgpack.pack(map.tiledata)))
      sql_assert(stmt:step())
      local map_rowid = stmt:last_insert_rowid()
      -- mob areas
      for _, area in ipairs(map.mob_areas) do
        stmt_area:reset()
        sql_assert(stmt_area:bind_values(map_rowid, area.x1, area.x2, area.y1, area.y2, area.max_mobs, area.type+1, area.spawn_speed, area.server_var, area.server_var_expr))
        sql_assert(stmt_area:step())
      end
      -- events
      for _, event in ipairs(map.events) do
        stmt_event:reset()
        sql_assert(stmt_event:bind_values(map_rowid, event.x, event.y))
        sql_assert(stmt_event:step())
        local event_rowid = stmt_event:last_insert_rowid()
        -- pages
        for page_i, page in ipairs(event.pages) do
          stmt_event_page:reset()
          sql_assert(stmt_event_page:bind_values(event_rowid, page.name, page.set, page.position_type, page.x, page.y, page.w, page.h, page.animation_number, page.active, page.obstacle, page.transparent, page.follow, page.animation_type, page.animation_mod, page.speed, table.concat(page.conditions, "\n"), table.concat(page.commands, "\n")))
          sql_assert(stmt_event_page:step())
        end
      end
    end
  end
  sql_assert(db:execute("COMMIT"))
  print("done")
end, "", "dump project data as SQLite database to data/project.db"}

commands.check_resources = {0, "server", function(self, client, args)
  print("check chipsets...")
  -- Check a chipset path.
  local chipset_cache = {}
  local function checkChipset(path)
    if chipset_cache[path] then return end -- prevent checking again
    local tpath = "resources/project/Chipset/"..path:gsub("^Chipset\\", "")
    local f = io.open(tpath)
    if f then f:close() else print("missing chipset \""..path.."\"") end
    chipset_cache[path] = true
  end
  -- Match chipset paths in a string and check them.
  local function checkChipsets(str)
    for path in str:gmatch("Chipset\\.-%.png") do checkChipset(path) end
  end
  for _, map in pairs(self.project.maps) do
    for _, event in ipairs(map.events or {}) do
      for page_index, page in ipairs(event.pages) do
        if #page.set > 0 then checkChipset(page.set) end
        for _, instruction in ipairs(page.conditions) do checkChipsets(instruction) end
        for _, instruction in ipairs(page.commands) do checkChipsets(instruction) end
      end
    end
  end
  for _, mob in ipairs(self.project.mobs) do checkChipset(mob.charaset) end
  for _, spell in ipairs(self.project.spells) do checkChipset(spell.set) end
  print("done")
end, "", "check existence of resources in the project"}

commands.validate = {0, "server", function(self, client, args)
  print("validate map events (instructions)...")
  local function report(prefix, errors)
    for _, err in ipairs(errors) do
      print(prefix..":"..err.i..":"..err.instruction)
      print(err.error)
    end
  end
  for id, map in pairs(self.project.maps) do
    for _, event in ipairs(map.events or {}) do
      for page_index, page in ipairs(event.pages) do
        local cond_errs = EventCompiler.validateConditions(page.conditions)
        local cmd_errs = EventCompiler.validateCommands(page.commands)
        if #cond_errs > 0 or #cmd_errs > 0 then
          print("ERRORS map \""..map.name.."\" event ("..event.x..","..event.y..") P"..page_index)
          report("CD", cond_errs)
          report("EV", cmd_errs)
          print()
        end
      end
    end
  end
  print("done")
end, "", "validate map events"}

commands.compile = {0, "server", function(self, client, args)
  if #args < 6 then return true end
  --
  local map = self.project.maps[args[2]]
  if map then
    local x, y = tonumber(args[3]) or 0, tonumber(args[4]) or 0
    local event
    -- search event
    for _, s_event in ipairs(map.events or {}) do
      if s_event.x == x and s_event.y == y then event = s_event; break end
    end
    if event then
      local page = event.pages[tonumber(args[5]) or 0]
      if page then
        local code, err
        if args[6] == "CD" then
          code, err = EventCompiler.compileConditions(page.conditions)
        else
          code, err = EventCompiler.compileCommands(page.commands)
        end
        if code then
          print("-- Lua --")
          print(code)
          print("---------")
        else print(err) end
      else print("page not found") end
    else print("event not found") end
  else print("map not found") end
end, "<map> <x> <y> <page> <CD|EV>", "debug event compiler (conditions/commands)"}

commands.count = {10, "shared", function(self, client, args)
  local count = 0
  for _ in pairs(self.clients) do
    count = count+1
  end
  if client then
    client:print(count.." joueurs en ligne")
  else
    print(count.." joueurs en ligne")
  end
end, "", "afficher le nombre de joueurs en ligne"}

commands.where = {10, "client", function(self, client, args)
  local target
  if args[2] then
    target = self:getClientByPseudo(args[2])
    if not target then client:print("Joueur introuvable."); return end
  else target = client end
  -- fetch info
  if target.map then
    client:print(target.map.id.." "..target.cx..","..target.cy)
  else
    client:print("Pas sur une map.")
  end
end, "[pseudo]", "afficher sa position ou celle d'un autre joueur"}

commands.skin = {10, "client", function(self, client, args)
  if not args[2] then return true end
  local skin = args[2] or ""
  if self.free_skins[skin] or client.allowed_skins[skin] then
    if client:canChangeSkin() then
      client:setCharaset({
        path = skin,
        x = 0, y = 0,
        w = 24, h = 32
      })
      client:print("skin assigné à \""..skin.."\"")
    else
      client:print("impossible de changer le skin")
    end
  else
    client:print("skin invalide")
  end
end, "<skin_name>", "changer son skin"}

commands.tp = {1, "client", function(self, client, args)
  -- arg checks
  if #args < 4 then return true end
  local arg_offset, pseudo = 0, client.pseudo
  if #args >= 5 then arg_offset, pseudo = 1, args[2] end
  local map_name = args[2+arg_offset]
  local cx, cy = tonumber(args[3+arg_offset]), tonumber(args[4+arg_offset])
  if not (cx and cy) then return true end
  local map = self:getMap(map_name)
  if not map then client:print("map \""..map_name.."\" invalide"); return end
  -- teleport
  local target = self:getClientByPseudo(pseudo)
  if target then -- online
    map:addEntity(target)
    target:teleport(cx*16,cy*16)
    client:print("Téléporté.")
  else -- offline
    asyncR(function()
      self.db:transactionWrap(function()
        -- id
        local r_id = self.db:query("user/getId", {pseudo})
        local user_id = r_id.rows[1] and r_id.rows[1].id
        if not user_id then client:print("Joueur introuvable."); return end
        -- update
        local r_state = self.db:query("user/getState", {user_id})
        local row = r_state.rows[1]
        if row then
          local state = msgpack.unpack(row.state)
          state.location = {
            map = map_name,
            x = cx*16, y = cy*16
          }
          self.db:query("user/setState", {user_id, {msgpack.pack(state)}})
          client:print("Téléporté (hors-ligne).")
        end
      end)
    end)
  end
end, "[pseudo] <map> <cx> <cy>", "se téléporter / téléporter un joueur"}

commands.respawn = {1, "client", function(self, client, args)
  local pseudo = args[2] or client.pseudo
  local target = self:getClientByPseudo(pseudo)
  if target then -- online
    target:respawn()
    client:print("Respawned.")
  else -- offline
    asyncR(function()
      self.db:transactionWrap(function()
        -- id
        local r_id = self.db:query("user/getId", {pseudo})
        local user_id = r_id.rows[1] and r_id.rows[1].id
        if not user_id then client:print("Joueur introuvable."); return end
        -- update
        local r_state = self.db:query("user/getState", {user_id})
        local row = r_state.rows[1]
        if row then
          local state = msgpack.unpack(row.state)
          local spawn = state.respawn_point or server.cfg.spawn_location
          state.location = {
            map = spawn.map,
            x = spawn.cx*16,
            y = spawn.cy*16
          }
          self.db:query("user/setState", {user_id, {msgpack.pack(state)}})
          client:print("Respawned (hors-ligne).")
        end
      end)
    end)
  end
end, "[pseudo]", "respawn soi-même ou un autre joueur"}

commands.chest = {1, "client", function(self, client, args)
  asyncR(function() client:openChest("Coffre.") end)
end, "", "ouvrir son coffre"}

commands.kill = {10, "client", function(self, client, args)
  client:setHealth(0)
end, "", "se suicider"}

-- global chat
commands.all = {10, "client", function(self, client, args)
  if client.user_id and client:canChat() then
    if not client.chat_quota:check() then
      local max, period = unpack(self.cfg.quotas.chat_all)
      client:print("Quota de chat global atteint ("..max.." message(s) / "..period.."s).")
      return
    end
    -- send
    local ftext = {{0.68,0.57,0.81}, client.pseudo.."(all): ",
        {1,1,1}, table.concat(args, " ", 2)}
    -- broadcast to all logged clients
    for id, recipient in pairs(self.clients_by_id) do
      if not recipient.ignores.all and not recipient.ignores.all_chan then
        recipient:sendChatMessage(ftext)
      end
    end
    -- quota
    client.chat_quota:add(1)
  end
end, "", "chat global"}

commands.roll = {10, "client", function(self, client, args)
  if client.status == "logged" and client:canChat() then
    local sides = math.max(2, math.floor(tonumber(args[2]) or 6))
    local n = math.random(1, sides)
    local hl_color = {0, 1, 0.5} -- highlight
    client:emitChatAction({"lance un ", hl_color, "d"..sides, {1,1,1},
      " et fait ", hl_color, n, {1,1,1}, "."})
  end
end, "[sides]", "lancer un dé"}

commands.stats = {10, "client", function(self, client, args)
  if client.status ~= "logged" then return end
  local h_played = client.play_stats.played + os.time()-client.login_timestamp
  h_played = math.floor(h_played/3600)
  client:print("Statistiques:\n"..
    "- Vous avez joué "..utils.fn(h_played).." heure(s) depuis le "..
    os.date("!%d/%m/%Y", client.play_stats.creation_timestamp)..".\n"..
    "- Vous avez parcouru "..utils.fn(math.floor(client.play_stats.traveled)).." mètre(s).\n"..
    "- Vous avez sciemment tué "..utils.fn(client.play_stats.mob_kills).." créature(s).\n"..
    "- Vous êtes mort "..utils.fn(client.play_stats.deaths).." fois.")
end, "", "voir ses statistiques de jeu"}

-- server chat
commands.say = {0, "server", function(self, client, args)
  -- broadcast to all logged clients
  for id, recipient in pairs(self.clients_by_id) do
    recipient:print(table.concat(args, " ", 2))
  end
end, "", "envoyer un message serveur"}

-- account creation
commands.create_account = {0, "server", function(self, client, args)
  if #args < 3 or #args[2] == 0 or #args[3] == 0 then return true end -- wrong parameters
  local pseudo = args[2]
  local client_password = digest.new("sha512"):final(client_salt..pseudo:lower()..args[3])
  -- generate salt
  local urandom = io.open("/dev/urandom")
  if not urandom then warn("couldn't open /dev/urandom"); return end
  local salt = urandom:read(64)
  if not salt or #salt ~= 64 then warn("couldn't read /dev/urandom"); return end
  urandom:close()
  -- create account
  local password = digest.new("sha512"):final(salt..client_password)
  asyncR(function()
    self.db:transactionWrap(function()
      self.db:query("user/createAccount", {
        pseudo = args[2],
        salt = {salt},
        password = {password},
        rank = tonumber(args[4]) or 10,
        timestamp = os.time()
      })
    end)
  end)
  print("compte créé")
end, "<pseudo> <password> [rank]", "créer un compte"}

local GROUP_ID_LIMIT = 100

-- join group
commands.join = {10, "client", function(self, client, args)
  if not client:canChangeGroup() then
    client:print("Changement de groupe impossible."); return
  end
  if not args[2] or #args[2] <= GROUP_ID_LIMIT then
    client:setGroup(args[2])
  else
    client:print("Nom de groupe trop long.")
  end
end, "[groupe]", "rejoindre un groupe ou quitter l'actuel si non spécifié"}

-- group chat
commands.party = {10, "client", function(self, client, args)
  if client.user_id and client:canChat() then
    local group = client.group and self.groups[client.group]
    if group then
      -- send
      local ftext = {{0.97,0.65,0.32}, client.pseudo.."(grp): ",
          {1,1,1}, table.concat(args, " ", 2)}
      -- broadcast to all group members
      for recipient in pairs(group) do
        if not recipient.ignores.all and not recipient.ignores.group then
          recipient:sendChatMessage(ftext)
        end
      end
    else client:print("Pas dans un groupe.") end
  end
end, "", "chat de groupe"}

-- show groups
commands.groups = {1, "shared", function(self, client, args)
  for id, group in pairs(self.groups) do
    local count = 0
    for _ in pairs(group) do count = count+1 end
    if client then client:print(id..": "..count) else print(id, count) end
  end
end, "", "lister les groupes"}

commands.uset = {0, "server", function(self, client, args)
  -- check arguments
  if not args[2] or #args[2] == 0 or not args[3] or #args[3] == 0 then return true end
  local pseudo, prop = args[2], args[3]
  if prop == "rank" then
    asyncR(function()
      self.db:transactionWrap(function()
        local result = self.db:query("user/setRank", {pseudo = pseudo, rank = tonumber(args[4]) or 10})
        print(result.changes.." affected row(s)")
      end)
    end)
  elseif prop == "guild" then
    asyncR(function()
      self.db:transactionWrap(function()
        local result = self.db:query("user/setGuild", {
          pseudo = pseudo,
          guild = args[4] or "" ,
          rank = tonumber(args[5]) or 0,
          title = args[6] or ""
        })
        print(result.changes.." affected row(s)")
      end)
    end)
  else return true end
end, "<pseudo> <rank|guild> ...", [=[changer des données persistantes d'un utilisateur
    rank: [1-10]
    guild: <name> [rank] [title]]=]}

-- guild chat
commands.guild = {10, "client", function(self, client, args)
  if client.user_id and client:canChat() then
    if #client.guild > 0 then
      local ftext = {{0.42,0.7,0.98}, client.pseudo.."(gui): ",
          {1,1,1}, table.concat(args, " ", 2)}
      -- broadcast to all guild members
      for id, recipient in pairs(self.clients_by_id) do
        if recipient.guild == client.guild and not recipient.ignores.all --
          and not recipient.ignores.guild then recipient:sendChatMessage(ftext) end
      end
    else client:print("Pas dans une guilde.") end
  end
end, "", "chat de guilde"}

-- private chat
local EEgg_self_talk = {
  "Euh... C'est moi...",
  "C'est encore moi.",
  "Parfois, dans la solitude, je repense à cette gemme. A quoi servait-elle ? Dans une profonde introspection, entre deux clics, j'entrevoyais le génie ou l'absurdité de son existence. Mais quel était le rapport avec Pâques... Ah ! Je me parle encore à moi-même !",
  "Il est écrit dans les tablettes de Skélos, que seul un Gnome des forêts du Nord unijambiste dansant à la pleine lune au milieu des douzes statuettes enroulées dans du jambon ouvrira la porte de Zaral Bak et permettra l'accomplissement de la prophétie... Mais pourquoi je pense à ça moi.",
  "Un jour, peut-être, j'arriverais à communiquer avec d'autres personnes. En ne tapant pas mon propre pseudo, par exemple."
}
commands.msg = {10, "client", function(self, client, args)
  if client.user_id and client:canChat() then
    if not args[2] or #args[2] == 0 then return true end
    local recipient = self:getClientByPseudo(args[2])
    if recipient then
      if recipient == client then -- easter egg: speak to self
        client:sendChatMessage({{0.45,0.83,0.22}, client.pseudo.."(msg): ",
            {1,1,1}, EEgg_self_talk[math.random(#EEgg_self_talk)]})
      else
        local ftext = {{0.45,0.83,0.22}, client.pseudo.."(msg): ",
            {1,1,1}, table.concat(args, " ", 3)}
        client:sendChatMessage(ftext)
        if not recipient.ignores.msg and not recipient.ignores.msg_players[client.pseudo] then
          recipient:sendChatMessage(ftext)
        end
      end
    else client:print("Joueur introuvable.") end
  end
end, "<pseudo> ...", "chat privé"}

-- announce
commands.ann = {1, "client", function(self, client, args)
  if client.status == "logged" then
    local msg = table.concat(args, " ", 2)
    -- broadcast to all logged clients
    for id, recipient in pairs(self.clients_by_id) do
      if recipient.user_rank > 1 then
        recipient:sendChatMessage({{0.94,0.71,0.94}, "ANNONCE: ", {1,1,1}, msg})
      else
        recipient:sendChatMessage({{0.94,0.71,0.94}, client.pseudo.."(ann): ", {1,1,1}, msg})
      end
    end
  end
end, "", "annonce"}

-- admin message
commands.adm = {1, "client", function(self, client, args)
  if client.status == "logged" then
    local msg = table.concat(args, " ", 2)
    -- broadcast to all logged clients
    for id, recipient in pairs(self.clients_by_id) do
      if recipient.user_rank > 1 then
        recipient:sendChatMessage({{0.97,0.78,0.61}, "ADMIN: ", {1,1,1}, msg})
      else
        recipient:sendChatMessage({{0.97,0.78,0.61}, client.pseudo.."(admin): ", {1,1,1}, msg})
      end
    end
  end
end, "", "message admin"}

-- admin map message
commands.admmap = {1, "client", function(self, client, args)
  if client.status == "logged" and client.map then
    local msg = table.concat(args, " ", 2)
    -- broadcast to all logged clients
    for recipient in pairs(client.map.clients) do
      if recipient.user_rank > 1 then
        recipient:sendChatMessage({{0.97,0.78,0.61}, "ADMIN MAP: ", {1,1,1}, msg})
      else
        recipient:sendChatMessage({{0.97,0.78,0.61}, client.pseudo.."(map): ", {1,1,1}, msg})
      end
    end
  end
end, "", "message admin de map"}

-- give item
commands.giveitem = {1, "client", function(self, client, args)
  if #args < 2 then return true end -- wrong parameters
  local id = self.project.objects_by_name[args[2]]
  if id then
    for i=1,math.floor(tonumber(args[3]) or 1) do client.inventory:put(id) end
    client:print("Objet(s) créé(s).")
  else client:print("Objet invalide.") end
end, "<name> [amount]", "créer des objets"}

-- give spell
commands.givespell = {1, "client", function(self, client, args)
  if #args < 2 then return true end -- wrong parameters
  local id = self.project.spells_by_name[args[2]]
  if id then
    for i=1,math.floor(tonumber(args[3]) or 1) do
      client.spell_inventory:put(id)
    end
    client:print("Magie(s) créée(s).")
  else client:print("Magie invalide.") end
end, "<name> [amount]", "créer des magies"}

-- give gold
commands.givegold = {1, "client", function(self, client, args)
  if #args < 2 then return true end -- wrong parameters
  local amount = math.floor(tonumber(args[2]) or 0)
  client:setGold(client.gold+amount)
  client:print("Or créé ("..amount..").")
end, "<amount>", "créer de l'or"}

commands.time = {10, "shared", function(self, client, args)
  local formatted = os.date("%d/%m/%Y %H:%M")
  if client then client:print(formatted)
  else print(formatted) end
end, "", "afficher la date et l'heure"}

commands.reput = {10, "client", function(self, client, args)
  if #args < 2 then return true end
  local target = self:getClientByPseudo(args[2])
  if target then client:print(args[2].." a "..target.reputation.." de réputation.")
  else client:print("Joueur introuvable.") end
end, "<pseudo>", "afficher la réputation d'un joueur connecté"}

commands.lvl = {10, "client", function(self, client, args)
  if #args < 2 then return true end
  local target = self:getClientByPseudo(args[2])
  if target then client:print(args[2].." est niveau "..target.level..".")
  else client:print("Joueur introuvable.") end
end, "<pseudo>", "afficher le niveau d'un joueur connecté"}

commands.ignore = {10, "client", function(self, client, args)
  local itype = args[2]
  if not itype then
    client.ignores.all = not client.ignores.all
    client:print("Tous canaux: "..(client.ignores.all and "ignorés" or "visibles"))
  elseif itype == "all" then
    client.ignores.all_chan = not client.ignores.all_chan
    client:print("Canal public: "..(client.ignores.all_chan and "ignoré" or "visible"))
  elseif itype == "guild" then
    client.ignores.guild_chan = not client.ignores.guild_chan
    client:print("Canal de guilde: "..(client.ignores.guild_chan and "ignoré" or "visible"))
  elseif itype == "party" then
    client.ignores.group_chan = not client.ignores.group_chan
    client:print("Canal de groupe: "..(client.ignores.group_chan and "ignoré" or "visible"))
  elseif itype == "announce" then
    client.ignores.announce_chan = not client.ignores.announce_chan
    client:print("Canal d'annonce: "..(client.ignores.announce_chan and "ignoré" or "visible"))
  elseif itype == "msg" then
    client.ignores.msg = not client.ignores.msg
    client:print("Messages privés: "..(client.ignores.msg and "ignorés" or "visibles"))
  elseif itype == "player" then
    if not args[3] then return true end
    local target = self:getClientByPseudo(args[3])
    if target then
      client.ignores.msg_players[args[3]] = not client.ignores.msg_players[args[3]]
      client:print("Messages privés ("..args[3].."): "..(client.ignores.msg_players[args[3]] and "ignorés" or "visibles"))
    else client:print("Joueur introuvable.") end
  elseif itype == "trade" then
    client.ignores.trade = not client.ignores.trade
    client:print("Échanges: "..(client.ignores.trade and "ignorés" or "acceptés"))
  else return true end
end, "<all|guild|party|announce|msg|player|trade> [pseudo]", "ignorer/dé-ignorer"}

local profiling = false
commands.profiler = {0, "server", function(self, client, args)
  if not profiler then print("profiler unavailable"); return end
  if args[2] == "start" then
    if not profiling then
      local out = args[3] or "profile.out"
      local opts = args[4] or "lv"
      print("profiler started; output: "..out.."; options: "..opts)
      profiler.start(opts, out)
      profiling = true
    else
      print("already profiling")
    end
  elseif args[2] == "stop" then
    if profiling then
      profiler.stop()
      print("profiler stopped")
      profiling = false
    else
      print("not profiling")
    end
  else return true end
end, "<start|stop> [output_path] [options]", "LuaJIT profiler"}

commands.ban = {2, "shared", function(self, client, args)
  local pseudo, reason, hours = args[2], args[3], tonumber(args[4]) or 1
  if not pseudo or #pseudo == 0 or not reason or #reason == 0 then return true end
  asyncR(function()
    self.db:transactionWrap(function()
      -- set ban
      local changes = self.db:query("user/setBan", {pseudo = pseudo, timestamp = os.time()+math.floor(hours*3600)}).changes
      -- output
      if not client then print(changes == 0 and "player not found" or "player banned")
      else client:print(changes == 0 and "Joueur introuvable." or "Joueur banni.") end
    end)
    -- kick
    local target = self:getClientByPseudo(pseudo)
    if target then target:kick("Banni "..hours.." heure(s): "..reason) end
  end)
end, "<pseudo> <reason> [hours]", "bannir un joueur (1 heure par défaut, non entier possible)"}

commands.unban = {2, "shared", function(self, client, args)
  local pseudo = args[2]
  if not pseudo or #pseudo == 0 then return true end
  asyncR(function()
    self.db:transactionWrap(function()
      -- set ban
      local changes = self.db:query("user/setBan", {pseudo = pseudo, timestamp = 0}).changes
      -- output
      if not client then print(changes == 0 and "player not found or not banned" or "player unbanned")
      else client:print(changes == 0 and "Joueur introuvable ou non banni." or "Joueur débanni.") end
    end)
  end)
end, "<pseudo>", "débannir un joueur"}

commands.kick = {2, "shared", function(self, client, args)
  local pseudo, reason = args[2], args[3]
  if not pseudo or #pseudo == 0 or not reason or #reason == 0 then return true end
  -- kick
  local target = self:getClientByPseudo(pseudo)
  if target then target:kick(reason) end
  -- output
  if not client then print(not target and "player not found" or "player kicked")
  else client:print(not target and "Joueur introuvable." or "Joueur kické.") end
end, "<pseudo> <reason>", "kick un joueur"}

commands.delete_account = {0, "server", function(self, client, args)
  local pseudo = args[2]
  if not pseudo or #pseudo == 0 then return true end
  if self:getClientByPseudo(pseudo) then print("user is online"); return end
  asyncR(function()
    self.db:transactionWrap(function()
      local changes = self.db:query("user/deleteAccount", {pseudo}).changes
      print(changes == 0 and "account not found" or "account deleted")
    end)
  end)
end, "<pseudo>", "supprimer un compte"}

commands.reset = {0, "server", function(self, client, args)
  local pseudo = args[2]
  if not pseudo or #pseudo == 0 then return true end
  if self:getClientByPseudo(pseudo) then print("user is online"); return end
  asyncR(function()
    self.db:transactionWrap(function()
      local r_id = self.db:query("user/getId", {pseudo})
      local user_id = r_id.rows[1] and r_id.rows[1].id
      if not user_id then print("user not found"); return end
      self.db:query("user/setData", {
        level = 1,
        alignment = 100,
        reputation = 0,
        gold = 0,
        chest_gold = 0,
        xp = 0,
        strength_pts = 0,
        dexterity_pts = 0,
        constitution_pts = 0,
        magic_pts = 0,
        remaining_pts = 0,
        weapon_slot = 0,
        shield_slot = 0,
        helmet_slot = 0,
        armor_slot = 0,
        user_id = user_id
      })
      self.db:query("user/setState", {user_id, {msgpack.pack({})}})
      self.db:query("user/deleteVars", {user_id})
      self.db:query("user/deleteBoolVars", {user_id})
      self.db:query("user/deleteItems", {user_id})
      print("user reset")
    end)
  end)
end, "<pseudo>", "reset un personnage"}

return commands
