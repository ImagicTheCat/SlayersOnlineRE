local effil = require("effil")
local enet = require("enet")
local vips = require("vips")
local sha2 = require("sha2")
local msgpack = require("MessagePack")
local Client = require("app.Client")
local LivingEntity = require("app.entities.LivingEntity")
local Map = require("app.Map")
local utils = require("app.lib.utils")
local Deserializer = require("app.Deserializer")
local DBManager = require("app.DBManager")
local net = require("app.protocol")
local EventCompiler = require("app.EventCompiler")
local SpellCompiler = require("app.SpellCompiler")
local client_salt = require("app.client_salt")

-- optional require
local profiler
do
  local ok, r = pcall(require, "jit.p")
  profiler = ok and r
end

local Server = class("Server")

-- PRIVATE STATICS
local GROUP_ID_LIMIT = 100

-- COMMANDS

-- map of command id => {rank, handler, usage, description}
-- rank: 0-10, permissions
--- Each rank inherits from higher ranks permissions.
--- 0: server (the minimum for a user is 1)
--- 10: normal player
-- handler(server, client, args)
--- client: client or nil if emitted from the server
--- args: command arguments list (first is command id/name)
--- should return true if the command is invalid
-- usage: one line command arguments summary (ex: "<arg1> <arg2> ...")
-- description: command description

local commands = {}

commands.help = {10, function(self, client, args)
  local rank = client and math.max(client.user_rank or 10, 1) or 0

  local id = args[2]
  if id then -- single command
    local cmd = commands[id]
    if cmd and rank <= cmd[1] then -- found
      local lines = {}
      table.insert(lines, "  "..id.." "..cmd[3])
      table.insert(lines, "    "..cmd[4])

      if client then
        client:sendChatMessage(table.concat(lines, "\n"))
      else
        print(table.concat(lines, "\n"))
      end
    else
      local msg = "help: commande \""..id.."\" inconnue"
      if client then
        client:sendChatMessage(msg)
      else
        print(msg)
      end
    end
  else -- all commands
    local lines = {}
    table.insert(lines, "Commandes:")
    for id, cmd in pairs(commands) do
      if rank <= cmd[1] then
        table.insert(lines, "  "..id.." "..cmd[3])
        table.insert(lines, "    "..cmd[4])
      end
    end

    if client then
      client:sendChatMessage(table.concat(lines, "\n"))
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
  fullscreen = true
}
commands.bind = {10, function(self, client, args)
  if client then
    if not args[2] or #args[2] >= 50 then return true end
    local control = args[3]
    local itype, input = string.match(args[2], "(%w+):(%w+)")

    if itype == "sc" then -- scancode
      if control then
        if not control_whitelist[control] then return true end
        if not bind_sc_blacklist[input] then
          client:applyConfig({scancode_controls = {[input] = control}})
          client:sendChatMessage("scancode \""..input.."\" assigné à \""..control.."\"")
        else
          client:sendChatMessage("scancode \""..input.."\" ne peut pas être réassigné")
        end
      else
        local controls = client.player_config.scancode_controls
        local control = (controls and controls[input] or "none")
        client:sendChatMessage("scancode \""..input.."\" est assigné à \""..control.."\"")
      end
    elseif itype == "gp" then -- gamepad
      if control then
        if not control_whitelist[control] then return true end
        client:applyConfig({gamepad_controls = {[input] = control}})
        client:sendChatMessage("gamepad \""..input.."\" assigné à \""..control.."\"")
      else
        local controls = client.player_config.gamepad_controls
        local control = (controls and controls[input] or "none")
        client:sendChatMessage("gamepad \""..input.."\" est assigné à \""..control.."\"")
      end
    else
      client:sendChatMessage("type d'input invalide")
    end
  end
end, "<type:input> [control]", [[afficher ou assigner un (LÖVE/SDL) scancode à un contrôle
    types: sc (scancode) / gp (gamepad)
      scancodes: https://love2d.org/wiki/Scancode
      gamepad: https://love2d.org/wiki/GamepadButton
    contrôles: none, up, right, down, left, interact, attack, defend, quick1, quick2, quick3, return, menu, chat_up, chat_down, fullscreen]]
}

local volume_types = {
  master = true,
  music = true
}
commands.volume = {10, function(self, client, args)
  if client then
    local vtype, volume = args[2], tonumber(args[3])
    if vtype and volume_types[vtype] and volume then
      client:applyConfig({volume = {[vtype] = volume}})
    else
      return true
    end
  end
end, "<type> <volume>", [[changer le volume
    types: master, music
    volume: 0-1]]
}

commands.gui = {10, function(self, client, args)
  if client then
    local param, value = args[2], args[3]
    if not param or not value then return true end

    if param == "font_size" then
      client:applyConfig({gui = {font_size = tonumber(value) or 25}})
    elseif param == "dialog_height" then
      client:applyConfig({gui = {dialog_height = tonumber(value) or 0.25}})
    elseif param == "chat_height" then
      client:applyConfig({gui = {chat_height = tonumber(value) or 0.25}})
    else
      client:sendChatMessage("invalid parameter \""..param.."\"")
    end
  end
end, "<parameter> <value>", [[changer les paramètres de la GUI
    - font_size (taille en pixels)
    - dialog_height (0-1 facteur)
    - chat_height (0-1 facteur)]]
}

commands.memory = {0, function(self, client, args)
  if not client then
    local MB = collectgarbage("count")*1024/1000000
    print("Mémoire utilisée (Lua GC): "..MB.." Mo")
  end
end, "", "afficher la mémoire utilisée par la VM Lua"}

commands.dump = {0, function(self, client, args)
  if client then return end
  if args[2] == "chipsets" then
    -- dump chipsets paths
    local f_maps = "dump_chipsets_maps.txt"
    local f_mobs = "dump_chipsets_mobs.txt"
    local f_spells = "dump_chipsets_spells.txt"
    --- map chipsets
    print("write "..f_maps.."...")
    local f = io.open(f_maps, "w")
    for _, map in pairs(self.project.maps) do
      f:write(map.name.."\n")
      f:write("  - tileset: "..map.tileset.."\n")
      f:write("  - background: "..map.background.."\n")
      for _, event in ipairs(map.events or {}) do
        for page_index, page in ipairs(event.pages) do
          if #page.set > 0 then
            f:write("  - ("..event.x..","..event.y..") P"..page_index..": "..page.set.."\n")
          end
        end
      end
    end
    f:close()
    --- mob chipsets
    print("write "..f_mobs.."...")
    f = io.open(f_mobs, "w")
    for _, mob in ipairs(self.project.mobs) do
      f:write(mob.name..": "..mob.charaset.."\n")
    end
    f:close()
    --- spell chipsets
    print("write "..f_spells.."...")
    f = io.open(f_spells, "w")
    for _, spell in ipairs(self.project.spells) do
      f:write(spell.name..": "..spell.set.."\n")
    end
    f:close()
    print("done")
  else return true end
end, "chipsets", "dump project data"}

commands.check_resources = {0, function(self, client, args)
  if client then return end
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

commands.validate = {0, function(self, client, args)
  if client then return end
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

commands.compile = {0, function(self, client, args)
  if client then return end
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

commands.count = {10, function(self, client, args)
  local count = 0
  for _ in pairs(self.clients) do
    count = count+1
  end

  if client then
    client:sendChatMessage(count.." joueurs en ligne")
  else
    print(count.." joueurs en ligne")
  end
end, "", "afficher le nombre de joueurs en ligne"}

commands.where = {10, function(self, client, args)
  if client then
    if client.map then
      client:sendChatMessage(client.map.id.." "..client.cx..","..client.cy)
    else
      client:sendChatMessage("pas sur une map")
    end
  end
end, "", "afficher sa position"}

commands.skin = {10, function(self, client, args)
  if client then
    if not args[2] then return true end

    local skin = args[2] or ""
    if self.free_skins[skin] or client.allowed_skins[skin] then
      if client:canChangeSkin() then
        client:setCharaset({
          path = skin,
          x = 0, y = 0,
          w = 24, h = 32
        })
        client:sendChatMessage("skin assigné à \""..skin.."\"")
      else
        client:sendChatMessage("impossible de changer le skin")
      end
    else
      client:sendChatMessage("skin invalide")
    end
  end
end, "<skin_name>", "changer son skin"}

commands.tp = {1, function(self, client, args)
  if client then
    local ok

    if #args >= 4 then
      local map_name = args[2]
      local cx, cy = tonumber(args[3]), tonumber(args[4])
      if cx and cy then
        ok = true

        local map = self:getMap(map_name)
        if map then
          map:addEntity(client)
          client:teleport(cx*16,cy*16)
        else
          client:sendChatMessage("map \""..map_name.."\" invalide")
        end
      end
    end

    if not ok then
      return true
    end
  end
end, "<map> <cx> <cy>", "se teleporter"}

-- testing command
commands.chest = {1, function(self, client, args)
  if client then
    async(function()
      client:openChest("Test.")
    end)
  end
end, "", "ouvrir son coffre (test)"}

-- testing command
commands.shop = {1, function(self, client, args)
  if client then
    async(function()
      client:openShop("Test.", {1,2,3,4})
    end)
  end
end, "", "ouvrir un magasin (test)"}

-- testing command
commands.pick = {1, function(self, client, args)
  if client then
    async(function()
      local entity = client:requestPickTarget(args[2] or "mob", tonumber(args[3]) or 7)
      client:sendChatMessage("Entité selectionnée: "..tostring(entity))
    end)
  end
end, "[type] [radius]", "selectionner une entité\n"}

-- testing command
commands.kill = {10, function(self, client, args)
  if client then client:setHealth(0) end
end, "", "se suicider"}

-- global chat
commands.all = {10, function(self, client, args)
  if client and client.user_id and client:canChat() then
    if client.chat_quota.exceeded then
      local max, period = unpack(self.cfg.quotas.chat_all)
      client:sendChatMessage("Quota de chat global atteint ("..max.." message(s) / "..period.."s).")
      return
    end
    -- send
    local packet = Client.makePacket(net.GLOBAL_CHAT, {
      pseudo = client.pseudo,
      msg = table.concat(args, " ", 2)
    })
    -- broadcast to all logged clients
    for id, client in pairs(self.clients_by_id) do
      if not client.ignores.all and not client.ignores.all_chan then
        client:send(packet)
      end
    end
    -- quota
    client.chat_quota:add(1)
  end
end, "", "chat global"}

-- server chat
commands.say = {0, function(self, client, args)
  if not client then
    local packet = Client.makePacket(net.CHAT_MESSAGE_SERVER, table.concat(args, " ", 2))

    -- broadcast to all logged clients
    for id, client in pairs(self.clients_by_id) do
      client:send(packet)
    end
  end
end, "", "envoyer un message serveur"}

-- account creation
commands.create_account = {0, function(self, client, args)
  if not client then
    if #args < 3 or #args[2] == 0 or #args[3] == 0 then return true end -- wrong parameters
    local pseudo = args[2]
    local client_password = sha2.hex2bin(sha2.sha512(client_salt..pseudo..args[3]))
    -- generate salt
    local urandom = io.open("/dev/urandom")
    if not urandom then print("couldn't open /dev/urandom"); return end
    local salt = urandom:read(64)
    if not salt or #salt ~= 64 then print("couldn't read /dev/urandom"); return end
    urandom:close()
    -- create account
    local password = sha2.hex2bin(sha2.sha512(salt..client_password))
    self.db:_query("user/createAccount", {
      pseudo = args[2],
      salt = salt,
      password = password,
      rank = tonumber(args[4]) or 10
    })
    print("compte créé")
  end
end, "<pseudo> <password> [rank]", "créer un compte"}

-- join group
commands.join = {10, function(self, client, args)
  if client then
    if not client:canChangeGroup() then
      client:sendChatMessage("Changement de groupe impossible.")
      return
    end

    if not args[2] or #args[2] <= GROUP_ID_LIMIT then
      client:setGroup(args[2])
    else
      client:sendChatMessage("Nom de groupe trop long.")
    end
  end
end, "[groupe]", "rejoindre un groupe ou juste quitter l'actuel si non spécifié"}

-- group chat
commands.party = {10, function(self, client, args)
  if client and client.user_id and client:canChat() then
    local group = client.group and self.groups[client.group]
    if group then
      local packet = Client.makePacket(net.GROUP_CHAT, {
        pseudo = client.pseudo,
        msg = table.concat(args, " ", 2)
      })

      -- broadcast to all group members
      for client in pairs(group) do
        if not client.ignores.all and not client.ignores.group then
          client:send(packet)
        end
      end
    else client:sendChatMessage("Pas dans un groupe.") end
  end
end, "", "chat de groupe"}

-- show groups
commands.groups = {0, function(self, client, args)
  if not client then
    for id, group in pairs(self.groups) do
      local count = 0
      for _ in pairs(group) do count = count+1 end
      print(id, count)
    end
  end
end, "", "lister les groupes"}

commands.uset = {0, function(self, client, args)
  if not client then
    -- check arguments
    if not args[2] or #args[2] == 0 or not args[3] or #args[3] == 0 then return true end

    local pseudo, prop = args[2], args[3]
    if prop == "rank" then
      async(function()
        local result = self.db:query("user/setRank", {pseudo = pseudo, rank = tonumber(args[4]) or 10})
        print(result.affected_rows.." affected row(s)")
      end)
    elseif prop == "guild" then
      async(function()
        local result = self.db:query("user/setGuild", {
          pseudo = pseudo,
          guild = args[4] or "" ,
          rank = tonumber(args[5]) or 0,
          title = args[6] or ""
        })
        print(result.affected_rows.." affected row(s)")
      end)
    else return true end
  end
end, "<pseudo> <rank|guild> ...", [=[changer des données persistantes d'un utilisateur
    rank: [1-10]
    guild: <name> [rank] [title]]=]}

-- guild chat
commands.guild = {10, function(self, client, args)
  if client and client.user_id and client:canChat() then
    if #client.guild > 0 then
      local packet = Client.makePacket(net.GUILD_CHAT, {
        pseudo = client.pseudo,
        msg = table.concat(args, " ", 2)
      })

      -- broadcast to all guild members
      for id, tclient in pairs(self.clients_by_id) do
        if tclient.guild == client.guild and not tclient.ignores.all --
          and not tclient.ignores.guild then tclient:send(packet) end
      end
    else client:sendChatMessage("Pas dans une guilde.") end
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
commands.msg = {10, function(self, client, args)
  if client and client.user_id and client:canChat() then
    if not args[2] or #args[2] == 0 then return true end

    local tclient = self.clients_by_pseudo[args[2]]
    if tclient then
      if tclient == client then -- easter egg: speak to self
        client:send(Client.makePacket(net.PRIVATE_CHAT, {
          pseudo = client.pseudo,
          msg = EEgg_self_talk[math.random(#EEgg_self_talk)]
        }))
      else
        local packet = Client.makePacket(net.PRIVATE_CHAT, {
          pseudo = client.pseudo,
          msg = table.concat(args, " ", 3)
        })

        client:send(packet)
        if not tclient.ignores.msg and not tclient.ignores.msg_players[client.pseudo] then
          tclient:send(packet)
        end
      end
    else client:sendChatMessage("Joueur introuvable.") end
  end
end, "<pseudo> ...", "chat privé"}

-- give item
commands.giveitem = {1, function(self, client, args)
  if client then
    if #args < 2 then return true end -- wrong parameters

    local id = self.project.objects_by_name[args[2]]
    if id then
      for i=1,math.floor(tonumber(args[3]) or 1) do
        client.inventory:put(id)
      end

      client:sendChatMessage("Objet(s) créé(s).")
    end
  end
end, "<name> [amount]", "créer des objets"}

-- give spell
commands.givespell = {1, function(self, client, args)
  if client then
    if #args < 2 then return true end -- wrong parameters

    local id = self.project.spells_by_name[args[2]]
    if id then
      for i=1,math.floor(tonumber(args[3]) or 1) do
        client.spell_inventory:put(id)
      end

      client:sendChatMessage("Magie(s) créée(s).")
    end
  end
end, "<name> [amount]", "créer des magies"}

-- give gold
commands.givegold = {1, function(self, client, args)
  if client then
    if #args < 2 then return true end -- wrong parameters
    local amount = math.floor(tonumber(args[2]) or 0)
    client:setGold(client.gold+amount)
    client:sendChatMessage("Or créé ("..amount..").")
  end
end, "<amount>", "créer de l'or"}

commands.time = {10, function(self, client, args)
  local formatted = os.date("%d/%m/%Y %H:%M")
  if client then client:sendChatMessage(formatted)
  else print(formatted) end
end, "", "afficher la date et l'heure"}

commands.reput = {10, function(self, client, args)
  if #args < 2 then return true end
  if client then
    local target = self.clients_by_pseudo[args[2]]
    if target then client:sendChatMessage(args[2].." a "..target.reputation.." de réputation.")
    else client:sendChatMessage("Joueur introuvable.") end
  end
end, "<pseudo>", "afficher la réputation d'un joueur connecté"}

commands.lvl = {10, function(self, client, args)
  if #args < 2 then return true end
  if client then
    local target = self.clients_by_pseudo[args[2]]
    if target then client:sendChatMessage(args[2].." est niveau "..target.level..".")
    else client:sendChatMessage("Joueur introuvable.") end
  end
end, "<pseudo>", "afficher le niveau d'un joueur connecté"}

commands.ignore = {10, function(self, client, args)
  if client then
    local itype = args[2]
    if not itype then
      client.ignores.all = not client.ignores.all
      client:sendChatMessage("Tous canaux: "..(client.ignores.all and "ignorés" or "visibles"))
    elseif itype == "all" then
      client.ignores.all_chan = not client.ignores.all_chan
      client:sendChatMessage("Canal public: "..(client.ignores.all_chan and "ignoré" or "visible"))
    elseif itype == "guild" then
      client.ignores.guild_chan = not client.ignores.guild_chan
      client:sendChatMessage("Canal de guilde: "..(client.ignores.guild_chan and "ignoré" or "visible"))
    elseif itype == "party" then
      client.ignores.group_chan = not client.ignores.group_chan
      client:sendChatMessage("Canal de groupe: "..(client.ignores.group_chan and "ignoré" or "visible"))
    elseif itype == "announce" then
      client.ignores.announce_chan = not client.ignores.announce_chan
      client:sendChatMessage("Canal d'annonce: "..(client.ignores.announce_chan and "ignoré" or "visible"))
    elseif itype == "msg" then
      client.ignores.msg = not client.ignores.msg
      client:sendChatMessage("Messages privés: "..(client.ignores.msg and "ignorés" or "visibles"))
    elseif itype == "player" then
      if not args[3] then return true end
      local target = self.clients_by_pseudo[args[3]]
      if target then
        client.ignores.msg_players[args[3]] = not client.ignores.msg_players[args[3]]
        client:sendChatMessage("Messages privés ("..args[3].."): "..(client.ignores.msg_players[args[3]] and "ignorés" or "visibles"))
      else client:sendChatMessage("Joueur introuvable.") end
    elseif itype == "trade" then
      client.ignores.trade = not client.ignores.trade
      client:sendChatMessage("Échanges: "..(client.ignores.trade and "ignorés" or "acceptés"))
    else return true end
  end
end, "<all|guild|party|announce|msg|player|trade> [pseudo]", "ignorer/dé-ignorer"}

local profiling = false
commands.profiler = {0, function(self, client, args)
  if not client then
    if not profiler then print("profiler unavailable"); return end
    if args[2] == "start" then
      if not profiling then
        local out = args[3] or "profile.out"
        local opts = args[4] or "F"
        print("profiler started; output: "..out.."; options: "..opts)
        profiler.start(opts, out)
        profiling = true
      else
        print("already profiling")
      end
    elseif args[2] == "stop" then
      if profiling then
        profiler.stop()
        -- Force close output file; fixed in recent LuaJIT 2.1 branch.
        profiler.start("", "/dev/null")
        profiler.stop()
        collectgarbage("collect")
        collectgarbage("collect")
        print("profiler stopped")
        profiling = false
      else
        print("not profiling")
      end
    else return true end
  end
end, "<start|stop> [output_path] [options]", "LuaJIT profiler"}

commands.ban = {2, function(self, client, args)
  local pseudo, reason, hours = args[2], args[3], tonumber(args[4]) or 1
  if not pseudo or #pseudo == 0 or not reason or #reason == 0 then return true end
  async(function()
    -- set ban
    local affected = self.db:query("user/setBan", {pseudo = pseudo, timestamp = os.time()+math.floor(hours*3600)}).affected_rows
    -- output
    if not client then print(affected == 0 and "no-op" or "player banned")
    else client:sendChatMessage(affected == 0 and "no-op" or "Joueur banni.") end
    -- kick
    local target = self.clients_by_pseudo[pseudo]
    if target then target:kick("Banni "..hours.." heure(s): "..reason) end
  end)
end, "<pseudo> <reason> [hours]", "bannir un joueur (1 heure par défaut, virgule possible)"}

commands.unban = {2, function(self, client, args)
  local pseudo = args[2]
  if not pseudo or #pseudo == 0 then return true end
  async(function()
    -- set ban
    local affected = self.db:query("user/setBan", {pseudo = pseudo, timestamp = 0}).affected_rows
    -- output
    if not client then print(affected == 0 and "no-op" or "player unbanned")
    else client:sendChatMessage(affected == 0 and "no-op" or "Joueur débanni.") end
  end)
end, "<pseudo>", "débannir un joueur"}

commands.kick = {2, function(self, client, args)
  local pseudo, reason = args[2], args[3]
  if not pseudo or #pseudo == 0 or not reason or #reason == 0 then return true end
  -- kick
  local target = self.clients_by_pseudo[pseudo]
  if target then target:kick(reason) end
  -- output
  if not client then print(not target and "player not found" or "player kicked")
  else client:sendChatMessage(not target and "Joueur introuvable." or "Joueur kické.") end
end, "<pseudo> <reason>", "kick un joueur"}

-- CONSOLE THREAD
local function console_main(flags, channel)
  while flags.running do
    local line = io.stdin:read("*l")
    channel:push(line)
  end
end

-- STATICS

-- parse [cmd arg1 arg2 "arg 3" ...]
-- return command args
function Server.parseCommand(str)
  str = string.gsub(str, "\"(.-)\"", function(content)
    return string.gsub(content, " ", "\\s")
  end)

  local args = {}

  for arg in string.gmatch(str, "([^ ]+)") do
    arg = string.gsub(arg, "\\s", " ")
    table.insert(args, arg)
  end

  return args
end

-- METHODS

local function compileSpells(self)
  local header = "local state = ...;"
  local function compile(compiler, str, chunkname) -- return f or nil
    local code, err = compiler(str)
    if not code then
      print("ERROR compiling "..chunkname.."\n"..err.."\n")
      return
    end
    --print("-- "..chunkname.." --\n"..str.."\n=>\n"..code.."\n--")
    local f, err = loadstring(header..code, chunkname)
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
  print("spell compiled")
  -- make directories
  os.execute("mkdir -p cache/maps/")
  -- load maps data
  print("load maps data...")
  for id in pairs(self.project.maps) do self:loadMapData(id) end
  print("maps data loaded")
  --
  self.clients = {} -- map of peer => client
  self.clients_by_id = {} -- map of user id => logged client
  self.clients_by_pseudo = {} -- map of pseudo => logged client
  self.maps = {} -- map of id => map instances
  self.vars = {} -- server variables, map of id (str) => value (string or number)
  self.changed_vars = {} -- map of server var id
  self.var_listeners = {} -- map of id => map of callback
  self.commands = {} -- map of id => callback
  self.motd = self.cfg.motd
  self.groups = {} -- player groups, map of id => map of client
  self.free_skins = {} -- set of skin names
  -- DB
  local cfg_db = self.cfg.db
  self.db = DBManager(cfg_db.name, cfg_db.user, cfg_db.password, cfg_db.host, cfg_db.port)
  require("app.queries")(self.db) -- prepare queries
  -- Loading.
  async(function()
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
  self.console_flags = effil.table({ running = true })
  self.console_channel = effil.channel()
  self.console = effil.thread(console_main)(self.console_flags, self.console_channel)
  -- Timers.
  do
    local last_time = clock()
    -- server tick
    self.tick_timer = itimer(1/self.cfg.tickrate, function()
      local time = clock()
      local dt = time-last_time
      last_time = time
      self:tick(dt)
    end)
  end
  self.save_timer = itimer(self.cfg.save_period, function() self:save() end)
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
    self:fetchCommands()
    for peer, client in pairs(self.clients) do
      client:minuteTick()
    end
  end)
end

function Server:save()
  if self.saving then return false end
  self.saving = true
  async(function()
    local start_time = clock()
    local ok = self.db:transactionWrap(function()
      -- save vars
      for var in pairs(self.changed_vars) do
        self.db:_query("server/setVar", {var, self.vars[var]})
      end
      self.changed_vars = {}
      -- Save clients; fragment the task.
      local clients = {}
      for _, client in pairs(self.clients) do table.insert(clients, client) end
      for _, client in ipairs(clients) do
        client:save()
        -- wait
        local tnext = async()
        timer(0.001, tnext)
        tnext:wait()
      end
    end)
    local elapsed = clock()-start_time
    print("server save: "..(ok and "commited" or "aborted").." ("..utils.round(elapsed, 3).."s)")
    self.saving = false
  end)
  return true
end

-- async
function Server:close()
  -- guard
  if self.task_close then return self.task_close:wait() end
  self.task_close = async()

  self.event_timer:remove()
  self.minute_timer:remove()
  self.console_flags.running = false
  self.save_timer:remove()

  -- disconnect clients
  for peer, client in pairs(self.clients) do
    peer:disconnect()
    client:onDisconnect()
  end

  self:save()
  self.host:flush()
  self.db:close()
  self.tick_timer:remove()

  print("shutdown.")

  -- end guard
  self.task_close()
  self.task_close = nil
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
      -- quotas
      client.packets_quota:add(1)
      client.data_quota:add(#event.data)
      -- packet
      local ok, packet = pcall(msgpack.unpack, event.data)
      if ok then client:onPacket(packet[1], packet[2]) end
    elseif event.type == "connect" then
      -- disable throttle deceleration (issue with unsequenced packets not sent)
      event.peer:throttle_configure(5000, 1, 0)
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

  -- DB
  self.db:tick()

  -- maps tick
  for id, map in pairs(self.maps) do
    map:tick(dt)
  end
end

-- return map instance or nil
function Server:getMap(id)
  local map = self.maps[id]
  if not map then -- load
    local map_data = self.project.maps[id]
    if map_data and map_data.loaded then
      map = Map(self, id, map_data)
      self.maps[id] = map
    else print("couldn't load \""..id.."\" map data") end
  end
  return map
end

-- Fetch database commands and execute them.
function Server:fetchCommands()
  async(function()
    local r = self.db:query("server/getCommands")
    if not r then return end
    -- execute commands
    for _, row in ipairs(r.rows) do
      -- parse command
      print("DB> "..row.command)
      local args = Server.parseCommand(row.command)
      if #args > 0 then self:processCommand(nil, args) end
    end
    self.db:_query("server/clearCommands")
  end)
end

-- client: client or nil from server console
function Server:processCommand(client, args)
  -- dispatch command
  local rank = client and math.max(client.user_rank or 10, 1) or 0
  local command = commands[args[1]]
  if command and rank <= command[1] then
    if command[2](self, client, args) then
      local msg = "utilisation: "..args[1].." "..command[3]
      if client then
        client:sendChatMessage(msg)
      else
        print(msg)
      end
    end
  else
    local msg = "commande \""..args[1].."\" inconnue (commande \"help\" pour la liste)"
    if client then
      client:sendChatMessage(msg)
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
      map.events = Deserializer.loadMapEvents(id)
      map.mob_areas = Deserializer.loadMapMobAreas(id) or {}
      map.tileset_id = string.sub(map.tileset, 9, string.len(map.tileset)-4)
      map.tileset_data = self:loadTilesetData(map.tileset_id)
      map.loaded = (map.tiledata and map.events and map.mob_areas and map.tileset_data)
      -- Compile events (with on disk caching).
      -- load cache
      local cache = {}
      local cache_modified = false
      local cache_file = io.open("cache/maps/"..id)
      if cache_file then
        local data = cache_file:read("*a")
        cache_file:close()
        if data then
          local ok, cache_data = pcall(msgpack.unpack, data)
          if ok then cache = cache_data end
        end
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
            local chunkname = map.name.."("..event.x..","..event.y..") P"..page_index.." CD"
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
            local chunkname = map.name.."("..event.x..","..event.y..") P"..page_index.." EV"
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
        local f = io.open("cache/maps/"..id, "w")
        if not f then error("couldn't create cache file for map \""..id.."\"") end
        f:write(msgpack.pack(cache))
        f:close()
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
  -- call listeners
  local listeners = self.var_listeners[id]
  if listeners then
    for callback in pairs(listeners) do
      callback()
    end
  end
end

function Server:getVariable(id)
  return self.vars[tostring(id)] or 0
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
