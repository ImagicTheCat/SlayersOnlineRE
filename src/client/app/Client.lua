local enet = require("enet")
local msgpack = require("MessagePack")
local URL = require("socket.url")
local sha2 = require("sha2")

local utils = require("app.lib.utils")
local Map = require("app.Map")
local LivingEntity = require("app.entities.LivingEntity")
local Mob = require("app.entities.Mob")
local Player = require("app.entities.Player")
local ResourceManager = require("app.ResourceManager")
local GUI = require("app.gui.GUI")
local GUI_Renderer = require("app.gui.Renderer")
local TextInput = require("app.gui.TextInput")
local ChatHistory = require("app.gui.ChatHistory")
local Window = require("app.gui.Window")
local Text = require("app.gui.Text")
local GridInterface = require("app.gui.GridInterface")
local Inventory = require("app.gui.Inventory")
local Chest = require("app.gui.Chest")
local Shop = require("app.gui.Shop")
local Trade = require("app.gui.Trade")
local DialogBox = require("app.gui.DialogBox")
local TextureAtlas = require("app.TextureAtlas")
local Phial = require("app.gui.Phial")
local XPBar = require("app.gui.XPBar")
local net = require("app.protocol")
local client_version = require("app.client_version")
local client_salt = require("app.client_salt")

local Client = class("Client")

-- STATICS

local GAMEPAD_DEAD_RADIUS = 0.4 -- stick dead center radius

-- Packet handlers.
local packet = {}

function packet:PROTOCOL(data)
end
function packet:MOTD_LOGIN(data)
  async(function()
    -- login process
    local pseudo = self:prompt(data.motd.."\n\nPseudo: ")
    local password = self:prompt(data.motd.."\n\nMot de passe: ", "", true)
    local password_hash = sha2.hex2bin(sha2.sha512(client_salt..pseudo:lower()..password))
    self:sendPacket(net.LOGIN, {pseudo = pseudo, password_hash = password_hash})
  end)
end
function packet:MAP(data)
  self:showLoading()
  self.map = Map(data.map)
  self.id = data.id -- entity id
  if self.pick_target then
    -- cancel target pick
    self:sendPacket(net.TARGET_PICK)
    self.pick_target = nil
  end
end
function packet:ENTITY_ADD(data)
  if self.map then self.map:createEntity(data) end
end
function packet:ENTITY_REMOVE(data)
  if self.map then self.map:removeEntity(data) end
end
function packet:ENTITY_PACKET(data)
  if self.map then
    local entity = self.map.entities[data.id]
    if entity then entity:onPacket(data.act, data.data) end
  end
end
function packet:MAP_MOVEMENTS(data)
  if self.map then self.map:onMovementsPacket(data) end
end
function packet:MAP_CHAT(data)
  if self.map then
    local entity = self.map.entities[data.id]
    if class.is(entity, Player) then
      entity:onMapChat(data.msg)
      self.chat_history:addMessage({{0.83,0.80,0.68}, tostring(entity.pseudo)..": ", {1,1,1}, data.msg})
    end
  end
end
function packet:CHAT_MESSAGE_SERVER(data)
  self.chat_history:addMessage({{0,1,0.5}, data})
end
function packet:EVENT_MESSAGE(data)
  self.message_window_text:set(data)
  self.message_window:setVisible(true)
  self.gui:setFocus(self.message_window)
end
function packet:EVENT_INPUT_QUERY(data)
  self.input_query_title:set(data.title)
  self.input_query_grid:init(1, #data.options)
  for i, option in ipairs(data.options) do
    self.input_query_grid:set(0,i-1,Text(option),true)
  end
  self.input_query:setVisible(true)
  self.gui:setFocus(self.input_query_grid)
end
function packet:EVENT_INPUT_STRING(data)
  async(function()
    local str = self:prompt(data.title)
    self:sendPacket(net.EVENT_INPUT_STRING_ANSWER, str)
  end)
end
function packet:PLAYER_CONFIG(data)
  -- apply player config
  utils.mergeInto(data, self.player_config)
  self:onApplyConfig(data)
end
function packet:INVENTORY_UPDATE_ITEMS(data)
  self.inventory.content:updateItems(data)
  if self.inventory.visible then
    self.inventory.content:updateContent()
  end
  self.chest.content_l:updateItems(data)
  if self.chest.visible then
    self.chest.content_l:updateContent()
  end
  self.trade.content_inv:updateItems(data)
  if self.trade.visible then
    self.trade.content_inv:updateContent()
  end
  self:updateInfoOverlay()
end
function packet:SPELL_INVENTORY_UPDATE_ITEMS(data)
  self.spell_inventory.content:updateItems(data)
  if self.spell_inventory.visible then
    self.spell_inventory.content:updateContent()
  end
  self:updateInfoOverlay()
end
function packet:CHEST_OPEN(data)
  self.chest.title:set(data[1])
  self.chest.content_r:updateItems(data[2], true)
  self.chest.content_r:updateContent()
  self.chest.content_l:updateContent()
  self.chest:setVisible(true)
  self.gui:setFocus(self.chest.content_l.grid)
end
function packet:CHEST_UPDATE_ITEMS(data)
  self.chest.content_r:updateItems(data)
  self.chest.content_r:updateContent()
end
function packet:SHOP_OPEN(data)
  self.shop:setVisible(true)
  self.shop:open(unpack(data))
  self.gui:setFocus(self.shop.menu)
end
function packet:STATS_UPDATE(data)
  -- Update statistics (sparse).
  -- Some statistics may not be basic character stats (e.g. inventory_size).
  local stats = data -- updated stats
  utils.mergeInto(stats, self.stats)
  -- Process updates.
  if stats.name then self.g_stats:set(0,0, Text("Nom: "..stats.name)) end
  if stats.class then self.g_stats:set(0,1, Text("Classe: "..stats.class)) end
  if stats.level then self.g_stats:set(0,2, Text("Niveau: "..stats.level)) end
  if stats.gold then
    self.g_stats:set(0,3, Text("Or: "..utils.fn(stats.gold)))
    self.chest.gold_l_display:set(utils.fn(stats.gold))
    self.shop.content:moveSelect(0,0) -- actualize
  end
  if stats.chest_gold then
    self.chest.gold_r_display:set(utils.fn(stats.chest_gold))
  end
  if stats.alignment then
    self.g_stats:set(1,0, Text("Alignement: "..stats.alignment))
    self:updateInfoOverlay()
  end
  if stats.health or stats.max_health then
    self.health_phial.factor = self.stats.health/self.stats.max_health
    self.g_stats:set(1,1, Text("Vie: "..utils.fn(self.stats.health).." / "..utils.fn(self.stats.max_health)))
  end
  if stats.mana or stats.max_mana then
    self.mana_phial.factor = self.stats.mana/self.stats.max_mana
    self.g_stats:set(1,2, Text("Mana: "..utils.fn(self.stats.mana).." / "..utils.fn(self.stats.max_mana)))
  end
  if stats.strength then self.g_stats:set(0,5, Text("Force: "..utils.fn(stats.strength)), true) end
  if stats.dexterity then self.g_stats:set(0,6, Text("Dextérité: "..utils.fn(stats.dexterity)), true) end
  if stats.constitution then self.g_stats:set(0,7, Text("Constitution: "..utils.fn(stats.constitution)), true) end
  if stats.magic then self.g_stats:set(0,8, Text({{0,0,0}, "Magie: "..utils.fn(stats.magic)})) end
  if stats.points then self.g_stats:set(0,9, Text("Points restants: "..utils.fn(stats.points))) end
  if stats.helmet_slot then self.g_stats:set(0,11, Text("Casque: "..stats.helmet_slot.name), true) end
  if stats.armor_slot then self.g_stats:set(0,12, Text("Armure: "..stats.armor_slot.name), true) end
  if stats.weapon_slot then self.g_stats:set(0,13, Text("Arme: "..stats.weapon_slot.name), true) end
  if stats.shield_slot then self.g_stats:set(0,14, Text("Bouclier: "..stats.shield_slot.name), true) end
  if stats.attack then self.g_stats:set(1,5, Text("Attaque: "..utils.fn(stats.attack))) end
  if stats.defense then self.g_stats:set(1,6, Text("Défense: "..utils.fn(stats.defense))) end
  if stats.reputation then self.g_stats:set(1,7, Text("Réputation: "..utils.fn(stats.reputation))) end
  if stats.xp or stats.next_xp or stats.current_xp then
    self.xp_bar.factor = (stats.xp-stats.current_xp)/(stats.next_xp-stats.current_xp)
    self.g_stats:set(1,8, Text("XP: "..utils.fn(stats.xp).." / "..utils.fn(stats.next_xp)))
  end
end
function packet:PLAY_MUSIC(data)
  if data then
    async(function()
      if client.rsc_manager:requestResource("audio/"..data) then
        client:playMusic("resources/audio/"..data)
      else print("failed to load music \""..data.."\"") end
    end)
  end
end
function packet:STOP_MUSIC(data) self.music_source:stop() end
function packet:PLAY_SOUND(data)
  if data then
    async(function()
      if client.rsc_manager:requestResource("audio/"..data) then
        client:playSound("resources/audio/"..data)
      else print("failed to load sound \""..data.."\"") end
    end)
  end
end
function packet:SCROLL_TO(data)
  local tx, ty = data[1], data[2]
  local ox, oy = 0, 0
  if self.scroll then -- continue scroll
    ox, oy = self.scroll.tx, self.scroll.ty
  else -- scroll from player
    local player = self.map.entities[self.id]
    if player then ox, oy = player.x, player.y end
  end
  local dx, dy = tx-ox, ty-oy
  self.scroll = {
    x = ox, y = oy, -- progress
    tx = tx, ty = ty, -- target
    ox = ox, oy = oy, -- origin
    duration = math.sqrt(dx*dx+dy*dy)/64, -- 4 cells/s
    time = 0
  }
end
function packet:SCROLL_RESET(data) self.scroll = nil end
function packet:VIEW_SHIFT_UPDATE(data) self.view_shift = data end
function packet:GLOBAL_CHAT(data)
  self.chat_history:addMessage({{0.68,0.57,0.81}, data.pseudo.."(all): ", {1,1,1}, data.msg})
end
function packet:GROUP_CHAT(data)
  self.chat_history:addMessage({{0.97,0.65,0.32}, data.pseudo.."(grp): ", {1,1,1}, data.msg})
end
function packet:GUILD_CHAT(data)
  self.chat_history:addMessage({{0.42,0.7,0.98}, data.pseudo.."(gui): ", {1,1,1}, data.msg})
end
function packet:PRIVATE_CHAT(data)
  self.chat_history:addMessage({{0.45,0.83,0.22}, data.pseudo.."(msg): ", {1,1,1}, data.msg})
end
function packet:TARGET_PICK(data)
  local entities = {}
  if self.map then -- add valid entities
    local player = self.map.entities[self.id]
    if player then
      for id, entity in pairs(self.map.entities) do
        local dx = math.abs(player.x-entity.x)
        local dy = math.abs(player.y-entity.y)
        if dx <= data.radius and dy <= data.radius and entity ~= player --
          and (data.type == "player" and class.is(entity, Player) --
          or data.type == "mob" and (class.is(entity, Mob) or class.is(entity, Player))) then
          table.insert(entities, {id, math.sqrt(dx*dx+dy*dy)})
        end
      end
    end
  end
  if #entities > 0 then
    -- sort entities by distance
    table.sort(entities, function(a,b) return a[2] < b[2] end)
    self.pick_target = {
      entities = entities, -- list of entities {id, dist}
      selected = 1
    }
  else
    self:sendPacket(net.TARGET_PICK) -- end/cancel
  end
end
function packet:TRADE_OPEN(data)
  self.trade.title_l:set(data.title_l)
  self.trade.title_r:set(data.title_r)
  self.trade.content_inv:updateContent()
  self.trade:setVisible(true)
  self.gui:setFocus(self.trade.content_inv.grid)
end
function packet:TRADE_LEFT_UPDATE_ITEMS(data)
  self.trade.content_l:updateItems(data)
  self.trade.content_l:updateContent()
end
function packet:TRADE_RIGHT_UPDATE_ITEMS(data)
  self.trade.content_r:updateItems(data)
  self.trade.content_r:updateContent()
end
function packet:TRADE_SET_GOLD(data)
  self.trade.gold_r:set(1,0, Text(utils.fn(data)))
end
function packet:TRADE_LOCK(data) self.trade:updateLock(data) end
function packet:TRADE_PEER_LOCK(data) self.trade:updatePeerLock(data) end
function packet:TRADE_CLOSE(data)
  self.trade:setVisible(false)
  -- clear
  self.trade.content_l:updateItems({}, true)
  self.trade.content_l:updateContent()
  self.trade.content_r:updateItems({}, true)
  self.trade.content_r:updateContent()
  self.trade.gold_r:set(1,0, Text("0"))
  self.trade.gold_l_input:set("0")
  self.trade:updateLock(false)
  self.trade:updatePeerLock(false)
  self.gui:setFocus()
end
function packet:DIALOG_QUERY(data)
  if data.no_busy or (not self.gui.focus and not self.pick_target) then -- not busy
    async(function()
      self:sendPacket(net.DIALOG_RESULT, self:dialog(data.ftext, data.options))
    end)
  else self:sendPacket(net.DIALOG_RESULT) end -- busy, cancel
end
function packet:MAP_EFFECT(data)
  self.map_effect = data
  if self.map_effect == "rain" and not self.fx_rain then
    async(function()
      if self.rsc_manager:requestResource("textures/sets/pluie.png") then
        self.fx_rain = love.graphics.newParticleSystem(self:loadTexture("resources/textures/sets/pluie.png"))
        self.fx_rain:setEmissionRate(20)
        self.fx_rain:setSpeed(64)
        self.fx_rain:setParticleLifetime(20*16/64)
        self.fx_rain:setEmissionArea("uniform", love.graphics.getWidth()/self.world_scale, 16)
        self.fx_rain:setDirection(3*math.pi/4)
        self.fx_rain:start()
      else print("failed to load resource \"pluie.png\"") end
    end)
  elseif self.map_effect == "snow" and not self.fx_snow then
    async(function()
      if self.rsc_manager:requestResource("textures/sets/neige.png") then
        self.fx_snow = love.graphics.newParticleSystem(self:loadTexture("resources/textures/sets/neige.png"))
        self.fx_snow:setEmissionRate(10)
        self.fx_snow:setSpeed(32)
        self.fx_snow:setParticleLifetime(16*16/32)
        self.fx_snow:setEmissionArea("uniform", love.graphics.getWidth()/self.world_scale, 16)
        self.fx_snow:setDirection(math.pi/2)
        self.fx_snow:setSizes(1, 0.5)
        self.fx_snow:setSpread(0.25)
        self.fx_snow:start()
      else print("failed to load resource \"neige.png\"") end
    end)
  elseif self.map_effect == "fog" and not self.fx_fog then
    async(function()
      if self.rsc_manager:requestResource("textures/sets/brouillard.png") then
        self.fx_fog = {}
        self.fx_fog.tex = self:loadTexture("resources/textures/sets/brouillard.png")
        self.fx_fog.tex:setWrap("repeat")
        local w,h = self.fx_fog.tex:getDimensions()
        self.fx_fog.quad = love.graphics.newQuad(0, 0, w*2, h*2, w, h)
        self.fx_fog.speed = 2 -- world units/s
      else print("failed to load resource \"brouillard.png\"") end
    end)
  end
end
function packet:MAP_PLAY_ANIMATION(data)
  if self.map then self.map:playAnimation(unpack(data, 1, data.n)) end
end
function packet:MAP_PLAY_SOUND(data)
  if self.map then self.map:playSound(unpack(data, 1, data.n)) end
end

-- METHODS

function Client:__construct(cfg)
  self.cfg = cfg

  -- setup love
  love.keyboard.setKeyRepeat(true)
  love.graphics.setDefaultFilter("nearest", "nearest")
  love.audio.setVolume(0.5)
  love.audio.setOrientation(0,0,-1,0,1,0) -- listener facing playground

  self.host = enet.host_create()
  self.peer = self.host:connect(self.cfg.remote)

  self.move_forward = false
  self.orientation = 0
  self.view_shift = {0,0}
  self.camera = {0,0} -- view/camera position

  self.orientation_stack = {}
  self.controls = {} -- map of control id (string) when pressed
  -- repeated controls, map of control id => repeat interval (seconds)
  self.controls_repeat = {
    attack = 0.25,
    defend = 0.25
  }

  self.player_config = {
    scancode_controls = {
      w = "up",
      d = "right",
      s = "down",
      a = "left",
      space = "attack",
      lalt = "defend",
      e = "interact",
      ["return"] = "return",
      escape = "menu",
      acback = "menu", -- android escape key
      ["1"] = "quick1",
      ["2"] = "quick2",
      ["3"] = "quick3",
      pagedown = "chat_up",
      pageup = "chat_down",
      f11 = "fullscreen"
    },
    gamepad_controls = {
      dpup = "up",
      dpright = "right",
      dpdown = "down",
      dpleft = "left",
      x = "attack",
      b = "defend",
      a = "interact",
      back = "return",
      start = "menu",
      y = "quick1",
      rightshoulder = "quick2",
      leftshoulder = "quick3"
    },
    gui = {
      font_size = 25,
      dialog_height = 0.25,
      chat_height = 0.25
    },
    quick_actions = {},
    volume = {
      master = 1,
      music = 0.75
    }
  }

  self.touches = {} -- map of id => control

  self.rsc_manager = ResourceManager()
  self.last_manifest_save = scheduler.time
  self.stats = {}

  self.textures = {} -- map of texture path => image
  self.atlases = {} -- cached texture atlases
  self.map_effect = "none"

  self.sound_sources = {} -- list of source
  self.sounds = {} -- map of path => sound data

  self.title_screen = self:loadTexture("resources/textures/title_screen.jpg")

  -- list of loading screen paths
  self.loading_screens = love.filesystem.getDirectoryItems("resources/textures/loadings")
  self.loading_screen_fade = 1

  self.font = love.graphics.newFont("resources/font.ttf", self.player_config.gui.font_size)
  love.graphics.setFont(self.font)

  self.info_overlay = love.graphics.newText(self.font)

  self.gui = GUI(self)
  self.gui_renderer = GUI_Renderer(self)

  self.world_scale = 4
  self.phials_scale = 3
  self.xp_scale = 3

  -- Mobile UI.
  self.mobile = {
    enabled = false,
    textures = {
      quick1 = self:loadTexture("resources/textures/mobile/quick1.png"),
      quick2 = self:loadTexture("resources/textures/mobile/quick2.png"),
      quick3 = self:loadTexture("resources/textures/mobile/quick3.png"),
      stick_cursor = self:loadTexture("resources/textures/mobile/stick_cursor.png"),
      defend = self:loadTexture("resources/textures/mobile/defend.png"),
      chat = self:loadTexture("resources/textures/mobile/chat.png"),
      attack = self:loadTexture("resources/textures/mobile/attack.png"),
      interact = self:loadTexture("resources/textures/mobile/interact.png"),
      stick = self:loadTexture("resources/textures/mobile/stick.png")
    },
    hbar = {"quick1", "quick2", "quick3"},
    vbar = {"interact", "attack", "defend"},
    stick = {0,0}, -- cursor x,y axis [-1,1] bottom-left origin
    -- boundaries
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
    scale = 3
  }
  do -- detect mobile platform
    local os = love.system.getOS()
    if os == "Android" or os == "iOS" then self.mobile.enabled = true end
  end

  self.health_phial = Phial("health")
  self.gui:add(self.health_phial)

  self.mana_phial = Phial("mana")
  self.gui:add(self.mana_phial)

  self.xp_bar = XPBar()
  self.gui:add(self.xp_bar)

  self.input_chat = TextInput()
  -- input chat/string valid event
  self.input_chat:listen("control-press", function(widget, id)
    if id == "return" then
      if self.prompt_task then -- input string
        local r = self.prompt_task
        self.prompt_task = nil

        local text = self.input_chat.text
        self.input_chat:set("")
        self.input_chat:setHidden(false)
        self.gui:setFocus()
        self.w_input_chat:setVisible(false)
        self.message_window:setVisible(false)
        self:onResize(love.graphics.getDimensions())

        r(text)
      else -- chat
        self:inputChat(self.input_chat.text)
        self.input_chat:set("")
        self.input_chat:setHidden(false)
        self.gui:setFocus()
        self.w_input_chat:setVisible(false)
        self.chat_history:hide()
      end
    elseif id == "menu" then -- cancel chat
      if not self.prompt_task then
        self.input_chat:set("")
        self.gui:setFocus()
        self.w_input_chat:setVisible(false)
        self.chat_history:hide()
      end
    end
  end)

  self.w_input_chat = Window()
  self.w_input_chat.content:add(self.input_chat)
  self.w_input_chat:setVisible(false)
  self.gui:add(self.w_input_chat)

  self.chat_history = ChatHistory()
  self.chat_history:setVisible(false)
  self.gui:add(self.chat_history)

  -- global GUI controls
  self.gui:listen("control-press", function(gui, id)
    if id == "return" then
      if not gui.focus and not self.pick_target then
        self.w_input_chat:setVisible(true)
        gui:setFocus(self.input_chat)
      end
    elseif id == "menu" then
      if not gui.focus and not self.pick_target then -- open menu
        self.menu:setVisible(true)
        gui:setFocus(self.menu_grid)
      elseif gui.focus == self.menu_grid then -- close menu
        gui:setFocus()
        self.menu:setVisible(false)
      end
    end
  end)

  self.message_window = Window()
  self.message_window_text = Text()
  self.message_window.content:add(self.message_window_text)
  self.message_window:setVisible(false)
  -- message skip event
  self.message_window:listen("control-press", function(widget, id)
    if id == "interact" then
      self:sendPacket(net.EVENT_MESSAGE_SKIP)
      widget:setVisible(false)
      self.gui:setFocus()
    end
  end)
  self.gui:add(self.message_window)

  self.input_query = Window()
  self.input_query:setVisible(false)
  self.input_query_title = Text()
  self.input_query_grid = GridInterface(0,0)
  self.input_query_grid:listen("cell-select", function(widget, cx, cy)
    self:sendPacket(net.EVENT_INPUT_QUERY_ANSWER, cy+1)
    self.input_query:setVisible(false)
    self.gui:setFocus()
  end)
  self.input_query.content:add(self.input_query_title)
  self.input_query.content:add(self.input_query_grid)
  self.gui:add(self.input_query)

  self.input_string_showing = false

  self.menu = Window()
  self.menu:setVisible(false)

  self.menu_grid = GridInterface(1,5)
  self.menu_grid:set(0,0, Text("Inventaire"), true)
  self.menu_grid:set(0,1, Text("Magie"), true)
  self.menu_grid:set(0,2, Text("Statistiques"), true)
  self.menu_grid:set(0,3, Text("Échange"), true)
  self.menu_grid:set(0,4, Text("Quitter"), true)
  self.menu_grid:listen("cell-select", function(grid, cx, cy)
    if cy == 0 then
      self.inventory.content:updateContent()
      self.inventory:setVisible(true)
      self.gui:setFocus(self.inventory.content.grid)
    elseif cy == 1 then
      self.spell_inventory.content:updateContent()
      self.spell_inventory:setVisible(true)
      self.gui:setFocus(self.spell_inventory.content.grid)
    elseif cy == 2 then
      self.w_stats:setVisible(true)
      self.gui:setFocus(self.g_stats)
    elseif cy == 3 then
      self:sendPacket(net.TRADE_SEEK)
      self.gui:setFocus()
      self.menu:setVisible(false)
    elseif cy == 4 then
      love.event.quit()
    end
  end)

  self.menu.content:add(self.menu_grid)
  self.gui:add(self.menu)

  self.inventory = Inventory("item")
  self.inventory:setVisible(false)
  self.inventory.content.grid:listen("control-press", function(grid, id)
    if id == "menu" then
      self.inventory:setVisible(false)
      self.gui:setFocus(self.menu_grid)
    end
  end)
  self.gui:add(self.inventory)

  self.spell_inventory = Inventory("spell")
  self.spell_inventory:setVisible(false)
  self.spell_inventory.content.grid:listen("control-press", function(grid, id)
    if id == "menu" then
      self.spell_inventory:setVisible(false)
      self.gui:setFocus(self.menu_grid)
    end
  end)
  self.gui:add(self.spell_inventory)

  self.chest = Chest()
  self.chest:setVisible(false)
  self.chest:listen("close", function(chest)
    self:sendPacket(net.CHEST_CLOSE)
  end)
  self.gui:add(self.chest)

  self.shop = Shop()
  self.shop:setVisible(false)
  self.shop:listen("close", function(shop)
    self:sendPacket(net.SHOP_CLOSE)
  end)
  self.gui:add(self.shop)

  self.w_stats = Window()
  self.w_stats:setVisible(false)
  self.g_stats = GridInterface(2,15)
  self.w_stats.content:add(self.g_stats)
  self.g_stats:listen("control-press", function(grid, id)
    if id == "menu" then
      self.w_stats:setVisible(false)
      self.gui:setFocus(self.menu_grid)
    end
  end)
  self.g_stats:listen("cell-select", function(grid, cx, cy)
    -- interactions
    --- spend characteristic points
    if cy == 5 then self:spendCharacteristicPoint("strength")
    elseif cy == 6 then self:spendCharacteristicPoint("dexterity")
    elseif cy == 7 then self:spendCharacteristicPoint("constitution")
    --- unequip slots
    elseif cy == 11 then self:unequipSlot("helmet")
    elseif cy == 12 then self:unequipSlot("armor")
    elseif cy == 13 then self:unequipSlot("weapon")
    elseif cy == 14 then self:unequipSlot("shield")
    end
  end)
  self.gui:add(self.w_stats)

  self.trade = Trade()
  self.trade:setVisible(false)
  self.gui:add(self.trade)

  self.dialog_box = DialogBox()
  self.gui:add(self.dialog_box)
  self.dialog_box:setVisible(false)

  -- trigger resize
  self:onResize(love.graphics.getDimensions())
end

function Client:tick(dt)
  -- net
  local event = self.host:service()
  while event do
    if event.type == "connect" then self:onConnect()
    elseif event.type == "disconnect" then self:onDisconnect()
    elseif event.type == "receive" then
      local packet = msgpack.unpack(event.data)
      self:onPacket(packet[1], packet[2])
    end
    -- next
    event = self.host:service()
  end
  -- resource manager
  self.rsc_manager:tick(dt)
  -- map
  if self.map then
    self.map:tick(dt)
    -- effect
    if self.map_effect == "rain" and self.fx_rain then
      self.fx_rain:update(dt)
    elseif self.map_effect == "snow" and self.fx_snow then
      self.fx_snow:update(dt)
    end
  end
  -- movement input
  local control = "up"
  if self.orientation == 1 then control = "right"
  elseif self.orientation == 2 then control = "down"
  elseif self.orientation == 3 then control = "left" end

  self:setMoveForward(not self.gui.focus --
    and (not self.rsc_manager:isBusy() or not self.loading_screen_tex) -- not on loading screen
    and not self.pick_target --
    and self:isControlPressed(control))

  -- GUI
  if not self.prompt_task and self.gui.focus == self.input_chat then
    self.chat_history:show()
  end

  if self.map then
    -- compute camera position
    if self.scroll then -- scrolling
      self.camera = {self.scroll.x+8+self.view_shift[1], self.scroll.y+8+self.view_shift[2]}
    else -- center on player
      local player = self.map.entities[self.id]
      if player then
        self.camera = {player.x+8+self.view_shift[1], player.y+8+self.view_shift[2]}
      end
    end

    love.audio.setPosition(self.camera[1], self.camera[2], 32)

    -- scrolling
    if self.scroll then
      if self.scroll.time < self.scroll.duration then
        self.scroll.time = self.scroll.time+dt
        local t = math.min(self.scroll.time/self.scroll.duration, 1)
        -- move on square diagonal, then move on the rest of a single component
        local dx, dy = self.scroll.tx-self.scroll.ox, self.scroll.ty-self.scroll.oy
        local square = math.min(math.abs(dx), math.abs(dy))
        local square_duration = square*math.sqrt(2)/math.sqrt(dx*dx+dy*dy)
        if t <= square_duration then -- diagonal
          self.scroll.x = math.floor(utils.lerp(self.scroll.ox,
            self.scroll.ox+square*utils.sign(dx), t/square_duration))
          self.scroll.y = math.floor(utils.lerp(self.scroll.oy,
            self.scroll.oy+square*utils.sign(dy), t/square_duration))
        else -- rest
          local ox = self.scroll.ox+square*utils.sign(dx)
          local oy = self.scroll.oy+square*utils.sign(dy)
          self.scroll.x = (ox ~= self.scroll.tx and math.floor(utils.lerp(ox, self.scroll.tx,
            (t-square_duration)/(1-square_duration))) or ox)
          self.scroll.y = (oy ~= self.scroll.ty and math.floor(utils.lerp(oy, self.scroll.ty,
            (t-square_duration)/(1-square_duration))) or oy)
        end
      elseif not self.scroll.done then
        self.scroll.done = true
        self:sendPacket(net.SCROLL_END)
      end
    end
  end

  -- remove stopped sources
  for i=#self.sound_sources,1,-1 do
    if not self.sound_sources[i]:isPlaying() then
      table.remove(self.sound_sources, i)
    end
  end

  -- loading screen
  if self.loading_screen_tex then
    if self.loading_screen_time > 0 then -- fade-out
      self.loading_screen_time = self.loading_screen_time-dt

      if self.loading_screen_time <= 0 then
        self.loading_screen_tex = nil -- remove loading screen
      end
    else
      if not self.rsc_manager:isBusy() then
        self.loading_screen_time = self.loading_screen_fade -- next step, fade-out
        -- potential manifest save when the loading end
        if scheduler.time-self.last_manifest_save >= 300 then
          self.rsc_manager:saveLocalManifest()
          self.last_manifest_save = scheduler.time
        end
      end
    end
  end
end

function Client:onPacket(protocol, data)
  local handler = packet[net[protocol]]
  if handler then handler(self, data) end
end

-- unsequenced: unsequenced if true/passed, reliable otherwise
function Client:sendPacket(protocol, data, unsequenced)
  self.peer:send(msgpack.pack({protocol, data}), 0, (unsequenced and "unsequenced" or "reliable"))
end

function Client:onConnect()
  self:sendPacket(net.VERSION_CHECK, client_version)
  async(function()
    -- load remote manifest
    if not self.rsc_manager:loadRemoteManifest() then
      print("couldn't reach remote resources repository manifest")
      self.chat_history:addMessage({{0,1,0.5}, "Impossible de joindre le dépôt distant de ressources."})
      return
    end
  end)
end

function Client:onDisconnect()
  self.chat_history:addMessage({{0,1,0.5}, "Déconnecté du serveur."})
end

function Client:close()
  self.rsc_manager:close()
  self.peer:disconnect()
  while self.peer:state() ~= "disconnected" do -- wait for disconnection
    self.host:service(100)
  end
  self.rsc_manager:saveLocalManifest()
end

function Client:onApplyConfig(config)
  if config.volume then -- set volume
    if config.volume.master then
      love.audio.setVolume(config.volume.master)
    end

    if config.volume.music and self.music_source then
      self.music_source:setVolume(config.volume.music)
    end
  end

  if config.gui then
    if config.gui.font_size then -- reload font
      self.font = love.graphics.newFont("resources/font.ttf", config.gui.font_size)
      love.graphics.setFont(self.font)

      self:onSetFont()
    end

    self:onResize(love.graphics.getDimensions()) -- trigger GUI update
  end

  -- force quick action update
  if config.quick_actions then
    self.inventory.content.dirty = true
    if self.inventory.visible then
      self.inventory.content:updateContent()
    end

    self.spell_inventory.content.dirty = true
    if self.spell_inventory.visible then
      self.spell_inventory.content:updateContent()
    end
    self:updateInfoOverlay()
  end
end

-- update info overlay content
function Client:updateInfoOverlay()
  local ftext = {}
  if self.stats.alignment then table.insert(ftext, "Align: "..self.stats.alignment) end
  for i, quick in ipairs(self.player_config.quick_actions) do
    if quick.type == "item" then
      local item = self.inventory.content.items[quick.id]
      if item then
        table.insert(ftext, item.amount <= 5 and {1,0,0} or {1,1,1})
        table.insert(ftext, "\nQ"..i..": "..item.name.." ("..item.amount..")")
      end
    elseif quick.type == "spell" then
      local spell = self.spell_inventory.content.items[quick.id]
      if spell then
        table.insert(ftext, {1,1,1})
        table.insert(ftext, "\nQ"..i..": "..spell.name)
      end
    end
  end
  self.info_overlay:set(ftext)
end

function Client:onResize(w, h)
  -- Contrain windowed dimensions to prevent abnormal ratio.
  -- Prevent problematic resize loop with delay.
  if not love.window.getFullscreen() then
    if self.resize_timer then self.resize_timer:remove() end
    self.resize_timer = scheduler:timer(1, function()
      local MAX_RATIO = 2
      local ratio = w/h
      if ratio > MAX_RATIO then
        w = MAX_RATIO*h
        love.window.setMode(w, h, {resizable = true})
      end
    end)
  end
  self.world_scale = math.ceil(h/16/15) -- display 15 tiles max (height)
  -- GUI
  self.gui:setSize(w,h)

  local xp_w = self.gui_renderer.xp_tex:getWidth()
  local xp_h = self.gui_renderer.xp_tex:getHeight()
  local phials_w = self.gui_renderer.phials_atlas.cell_w
  local phials_h = self.gui_renderer.phials_atlas.cell_h

  self.phials_scale = utils.floorScale((h/3/phials_h), phials_h)
  self.xp_scale = math.min(self.phials_scale, utils.floorScale((w-phials_w*self.phials_scale*2)/xp_w, xp_w))
  self.mobile.scale = utils.floorScale(h/3/self.mobile.textures.stick:getHeight(), self.mobile.textures.stick:getHeight())

  local input_chat_y = h-self.font:getHeight()-2-12
  local message_height = math.floor(self.player_config.gui.dialog_height*h)
  local chat_height = math.floor(self.player_config.gui.chat_height*(input_chat_y-4))

  if self.prompt_task then
    self.w_input_chat:setPosition(2, message_height+2)
    self.w_input_chat:setSize(w-4, self.font:getHeight()+12)
  else
    self.w_input_chat:setPosition(2, input_chat_y)
    self.w_input_chat:setSize(w-4, self.font:getHeight()+12)
  end

  self.health_phial:setSize(phials_w*self.phials_scale, phials_h*self.phials_scale)
  self.mana_phial:setSize(phials_w*self.phials_scale, phials_h*self.phials_scale)

  self.health_phial:setPosition(0, input_chat_y-self.health_phial.h)
  self.mana_phial:setPosition(w-self.mana_phial.w, input_chat_y-self.mana_phial.h)

  self.chat_history:setPosition(2+self.health_phial.w, input_chat_y-2-chat_height)
  self.chat_history:setSize(w-4-self.health_phial.w*2, chat_height)

  self.xp_bar:setSize(xp_w*self.xp_scale, xp_h*self.xp_scale)
  self.xp_bar:setPosition(math.floor(w/2-self.xp_bar.w/2), h-self.xp_bar.h)

  self.mobile.left = self.health_phial.x+self.health_phial.w
  self.mobile.right = self.mana_phial.x
  self.mobile.top = 0
  self.mobile.bottom = self.xp_bar.y

  self.message_window:setPosition(2, 2)
  self.message_window:setSize(w-4, message_height)
  self.input_query:setPosition(2, 2)
  self.input_query:setSize(w-4, message_height)

  local w_menu = self.font:getWidth("Statistiques")+24
  local h_menu = (self.font:getHeight()+6)*5+12
  self.menu:setPosition(2, math.floor(h/2-h_menu/2))
  self.menu:setSize(w_menu, h_menu)

  self.inventory:setPosition(self.menu.w+2, 2)
  self.inventory:setSize(w-4-self.menu.w, h-4)

  self.spell_inventory:setPosition(self.menu.w+2, 2)
  self.spell_inventory:setSize(w-4-self.menu.w, h-4)

  self.w_stats:setPosition(self.menu.w+2, 2)
  self.w_stats:setSize(w-4-self.menu.w, h-4)

  self.chest:setPosition(2,2)
  self.chest:setSize(w-4,h-4)

  self.shop:setPosition(2,2)
  self.shop:setSize(w-4,h-4)

  self.trade:setPosition(2,2)
  self.trade:setSize(w-4,h-4)

  self.dialog_box:updateLayout(math.floor(w*0.75), 0)
  self.dialog_box:setPosition(math.floor(w/2-self.dialog_box.w/2), math.floor(h/2-self.dialog_box.h/2))

  -- FX
  if self.fx_rain then
    self.fx_rain:setEmissionArea("uniform", w/self.world_scale, 16)
  end
  if self.fx_snow then
    self.fx_snow:setEmissionArea("uniform", w/self.world_scale, 16)
  end
end

function Client:onSetFont()
  self.gui:trigger("font-update")

  if self.map then
    for id, entity in pairs(self.map.entities) do
      if class.is(entity, Player) then
        entity.name_tag:setFont(self.font)
        entity.chat_gui:trigger("font-update")
      end
    end
  end

  self.info_overlay:setFont(self.font)
end

function Client:onTextInput(data)
  self.gui:triggerTextInput(data)
end

function Client:onKeyPressed(keycode, scancode, isrepeat)
  self.gui:triggerKeyPress(keycode, scancode, isrepeat)
  -- control handling
  local control = self.player_config.scancode_controls[scancode]
  if control then self:pressControl(control) end
  -- input chat copy/paste
  if not isrepeat and love.keyboard.isDown("lctrl") then
    if keycode == "c" then
      self:pressControl("copy")
      self:releaseControl("copy")
    elseif keycode == "v" then
      self:pressControl("paste")
      self:releaseControl("paste")
    end
  end
end

function Client:onKeyReleased(keycode, scancode)
  self.gui:triggerKeyRelease(keycode, scancode)

  local control = self.player_config.scancode_controls[scancode]
  if control then
    self:releaseControl(control)
  end
end

-- Gamepad handling.

function Client:onGamepadPressed(joystick, button)
  -- control handling
  local control = self.player_config.gamepad_controls[button]
  if control then
    self:pressControl(control)
  end
end

function Client:onGamepadReleased(joystick, button)
  local control = self.player_config.gamepad_controls[button]
  if control then
    self:releaseControl(control)
  end
end

function Client:onGamepadAxis(joystick, axis, value)
  -- simulate directionals from left stick
  if axis == "leftx" then
    if value <= -GAMEPAD_DEAD_RADIUS then self:pressControl("left") else self:releaseControl("left") end
    if value >= GAMEPAD_DEAD_RADIUS then self:pressControl("right") else self:releaseControl("right") end
  elseif axis == "lefty" then
    if value <= -GAMEPAD_DEAD_RADIUS then self:pressControl("up") else self:releaseControl("up") end
    if value >= GAMEPAD_DEAD_RADIUS then self:pressControl("down") else self:releaseControl("down") end
  -- simulate chat scrolling
  elseif axis == "righty" then
    if value <= -GAMEPAD_DEAD_RADIUS then self:pressControl("chat_down") else self:releaseControl("chat_down") end
    if value >= GAMEPAD_DEAD_RADIUS then self:pressControl("chat_up") else self:releaseControl("chat_up") end
  end
end

-- Touch handling (e.g. mobile).

-- x,y: touch position
-- mode: (optional) "unbound"
-- return (ax,ay) or nothing if outside joystick area
local function computeJoystickAxis(self, x, y, mode)
  local mobile = self.mobile
  local tex = mobile.textures.stick
  local jx, jy = mobile.left, mobile.bottom-tex:getHeight()*mobile.scale
  local jw, jh = tex:getHeight()*mobile.scale, tex:getWidth()*mobile.scale
  if mode ~= "unbound" and not utils.pointInRect(x, y, jx, jy, jw, jh) then return end
  return (x-jx-jw/2)/(jw/2), -(y-jy-jh/2)/(jh/2)
end

local function getTouchedControl(self, x, y)
  local mobile = self.mobile
  local chat_dim = {mobile.textures.chat:getDimensions()}
  local scale = mobile.scale
  -- chat, top left
  if utils.pointInRect(x, y, mobile.left, mobile.top,
      chat_dim[1]*scale, chat_dim[2]*scale) then return "return" end
  -- horizontal bar, top right
  local offset = 0
  for _, el in ipairs(mobile.hbar) do
    local tex = mobile.textures[el]
    offset = offset-tex:getWidth()*scale
    if utils.pointInRect(x, y, mobile.right+offset, mobile.top,
        tex:getWidth()*scale, tex:getHeight()*scale) then
      return el
    end
  end
  -- vertical bar, bottom right
  local offset, max = 0, 0
  for _, el in ipairs(mobile.vbar) do
    local tex = mobile.textures[el]
    max = math.max(max, tex:getWidth()*scale)
    offset = offset-tex:getHeight()*scale
    if utils.pointInRect(x, y, mobile.right-max, mobile.bottom+offset,
        tex:getWidth()*scale, tex:getHeight()*scale) then
      return el
    end
  end
end

local STICK_QUADRANTS = {"right", "up", "left", "down"}
local function updateStickControls(self, ax, ay)
  local a = math.atan2(ay, ax)
  local radius = math.sqrt(ax*ax+ay*ay)
  local display_radius = math.min(radius, 0.75)
  self.mobile.stick = {display_radius*math.cos(a), display_radius*math.sin(a)}
  if radius < GAMEPAD_DEAD_RADIUS then -- dead zone
    if self.stick_control then
      self:releaseControl(self.stick_control)
      self.stick_control = nil
    end
    return
  end
  -- Find control quadrant based on the axis vector.
  if a < 0 then a = a+math.pi*2 end -- [0, 2*PI]
  local quadrant = (math.floor((a+math.pi/4)/(math.pi/2)))%4+1
  local control = STICK_QUADRANTS[quadrant]
  -- apply
  if control ~= self.stick_control then
    if self.stick_control then self:releaseControl(self.stick_control) end
    self.stick_control = control
    self:pressControl(control)
  end
end

-- touch controls handling
function Client:onTouchPressed(id, x, y)
  local w, h = love.graphics.getDimensions()
  -- virtual joystick
  local ax, ay = computeJoystickAxis(self, x, y)
  if ax then
    updateStickControls(self, ax, ay)
    self.touches[id] = "vjoystick" -- special
  else -- other controls
    local control = getTouchedControl(self, x, y)
    if control then
      self.touches[id] = control
      self:pressControl(control)
    end
  end
end

function Client:onTouchMoved(id, x, y)
  local w, h = love.graphics.getDimensions()
  -- virtual joystick movements
  local ax, ay = computeJoystickAxis(self, x, y, "unbound")
  if self.touches[id] == "vjoystick" and ax then
    updateStickControls(self, ax, ay)
  end
end

function Client:onTouchReleased(id, x, y)
  local control = self.touches[id]
  if control then
    if control == "vjoystick" then -- special
      if self.stick_control then self:releaseControl(self.stick_control) end
      self.stick_control = nil
      self.mobile.stick = {0,0}
    else -- regular
      self:releaseControl(control)
    end
    self.touches[id] = nil
  end
end

function Client:onWheelMoved(x,y)
  local mx, my = love.mouse.getPosition()
  self.gui:triggerPointerWheel(0, mx, my, y)
end

-- abstraction layer for controls
function Client:pressControl(id)
  -- chat scrolling (repeatable)
  if self.chat_history.visible then
    if id == "chat_up" then self.chat_history:scroll(-50)
    elseif id == "chat_down" then self.chat_history:scroll(50) end
  end
  -- Non-OS repeatable inputs.
  local control = self.controls[id]
  if not control then -- not already pressed
    local interval = self.controls_repeat[id]
    if interval then -- repeated, bind timer
      self.controls[id] = scheduler:timer(interval, function()
        -- press again
        self:releaseControl(id)
        self:pressControl(id)
      end)
    else
      self.controls[id] = true
    end
    -- toggle fullscreen
    if id == "fullscreen" then
      if love.window.getFullscreen() then
        love.window.setMode(800, 600, {fullscreen = false, resizable = true})
      else
        love.window.setMode(800, 600, {fullscreen = true})
      end
    end
    -- gameplay handling
    local pickt = self.pick_target
    if not self.gui.focus and pickt and self.map then
      if id == "left" or id == "up" then -- previous
        pickt.selected = pickt.selected-1
        if pickt.selected <= 0 then pickt.selected = #pickt.entities end
        self:playSound("resources/audio/Cursor1.wav")
      elseif id == "right" or id == "down" then -- next
        pickt.selected = pickt.selected+1
        if pickt.selected > #pickt.entities then pickt.selected = 1 end
        self:playSound("resources/audio/Cursor1.wav")
      elseif id == "interact" then -- valid
        local entry = pickt.entities[pickt.selected]
        self:sendPacket(net.TARGET_PICK, entry and entry[1])
        self.pick_target = nil
        self:playSound("resources/audio/Item1.wav")
      elseif id == "menu" then -- cancel
        self:sendPacket(net.TARGET_PICK)
        self.pick_target = nil
      end
    elseif not self.gui.focus then -- character controls
      if id == "up" then self:pressOrientation(0)
      elseif id == "right" then self:pressOrientation(1)
      elseif id == "down" then self:pressOrientation(2)
      elseif id == "left" then self:pressOrientation(3)
      elseif id == "attack" then self:inputAttack()
      elseif id == "defend" then self:inputDefend()
      elseif id == "interact" then self:inputInteract()
      elseif id == "quick1" then self:doQuickAction(1)
      elseif id == "quick2" then self:doQuickAction(2)
      elseif id == "quick3" then self:doQuickAction(3)
      end
    end
  end
  -- GUI handling (repeatable)
  -- Need to be after gameplay handling to prevent changes to the UI state
  -- before the checks.
  self.gui:triggerControlPress(id)
end

function Client:releaseControl(id)
  local control = self.controls[id]
  if control then
    local timer = self.controls[id]
    if type(timer) == "table" then timer:remove() end
    self.controls[id] = nil

    -- handling
    self.gui:triggerControlRelease(id)

    if id == "up" then self:releaseOrientation(0)
    elseif id == "right" then self:releaseOrientation(1)
    elseif id == "down" then self:releaseOrientation(2)
    elseif id == "left" then self:releaseOrientation(3)
    end
  end
end

function Client:isControlPressed(id)
  return (self.controls[id] ~= nil)
end

-- (async) prompt text
-- will replace message window and input chat content
-- value: (optional) default text value
-- hidden: (optional) if true, hide the input text
-- return entered text
function Client:prompt(title, value, hidden)
  local r = async()
  self.prompt_task = r

  self.message_window_text:set(title)
  self.message_window:setVisible(true)

  self:onResize(love.graphics.getDimensions())
  self.w_input_chat:setVisible(true)
  if hidden then self.input_chat:setHidden(true) end
  self.input_chat:set(value or "")
  self.gui:setFocus(self.input_chat)

  return r:wait()
end

-- (async) open dialog box
-- text: formatted text
-- options: list of formatted texts
-- return selected option index or nil if cancelled
function Client:dialog(text, options)
  self.dialog_task = async()
  self.dialog_box:set(text, options)
  self.dialog_box:setVisible(true)
  local prev_focus = self.gui.focus
  self.gui:setFocus(self.dialog_box.grid)
  self:onResize(love.graphics.getDimensions()) -- trigger GUI update
  -- (should use the GUI as a layout widget to prevent this kind of fixes)

  local r = self.dialog_task:wait()
  self.dialog_task = nil
  self.gui:setFocus(prev_focus)
  self.dialog_box:setVisible(false)
  return r
end

-- input a chat message to the remote server
function Client:inputChat(msg)
  if string.len(msg) > 0 then
    self:sendPacket(net.INPUT_CHAT, msg)
  end
end

function Client:draw()
  local w,h = love.graphics.getDimensions()

  -- title screen
  if not self.id then
    local tw, th = self.title_screen:getDimensions()
    local factor = math.min(w/tw, h/th)
    love.graphics.draw(self.title_screen, math.floor(w/2-tw*factor/2), math.floor(h/2-th*factor/2), 0, factor)
  end

  -- map
  if self.map then
    -- background (extend width to stay compatible with original 20x15 cells)
    if self.map.background then
      love.graphics.draw(self.map.background, 0, 0, 0,
        self.world_scale*w/320, self.world_scale)
    end

    -- content
    love.graphics.push()

    -- center map render
    love.graphics.translate(math.floor(w/2), math.floor(h/2))

    love.graphics.scale(self.world_scale) -- pixel scale
    love.graphics.translate(-self.camera[1], -self.camera[2])
    self.map:draw()

    -- draw target picking selection
    if self.pick_target then
      local entry = self.pick_target.entities[self.pick_target.selected]
      local entity = self.map.entities[entry and entry[1]]
      if class.is(entity, LivingEntity) and scheduler.time%1 < 0.5 then -- blinking
        self.gui_renderer:drawBorders(self.gui_renderer.system.window_borders,
          entity.x-math.floor((entity.atlas.cell_w-16)/2),
          entity.y+16-entity.atlas.cell_h,
          entity.atlas.cell_w,
          entity.atlas.cell_h)
      end
    end

    love.graphics.pop()

    -- effect
    if self.map_effect == "dark-cave" then
      love.graphics.setBlendMode("multiply", "premultiplied")
      love.graphics.setColor(0.4,0.4,0.4)
      love.graphics.rectangle("fill", 0, 0, w, h)
      love.graphics.setColor(1,1,1)
      love.graphics.setBlendMode("alpha")
    elseif self.map_effect == "night" then
      love.graphics.setBlendMode("multiply", "premultiplied")
      love.graphics.setColor(0,0.4,1)
      love.graphics.rectangle("fill", 0, 0, w, h)
      love.graphics.setColor(1,1,1)
      love.graphics.setBlendMode("alpha")
    elseif self.map_effect == "heat" then
      love.graphics.setBlendMode("add")
      love.graphics.setColor(1,0.1,0.1,0.5)
      love.graphics.rectangle("fill", 0, 0, w, h)
      love.graphics.setColor(1,1,1)
      love.graphics.setBlendMode("alpha")
    elseif self.map_effect == "rain" then
      if self.fx_rain then
        love.graphics.draw(self.fx_rain, w, -32*self.world_scale, 0, self.world_scale)
      end
    elseif self.map_effect == "snow" then
      if self.fx_snow then
        love.graphics.draw(self.fx_snow, 0, -32*self.world_scale, 0, self.world_scale)
      end
    elseif self.map_effect == "fog" then
      if self.fx_fog then
        local tw, ws = self.fx_fog.tex:getWidth(), self.world_scale
        local x = -((math.floor(scheduler.time*self.fx_fog.speed*ws)%(tw*ws)))
        local y = math.floor(math.cos(scheduler.time*0.1)*4*ws)-4*ws
        love.graphics.setColor(1,1,1,0.6)
        love.graphics.draw(self.fx_fog.tex, self.fx_fog.quad, x, y, 0, ws)
        love.graphics.setColor(1,1,1)
      end
    end
  end

  -- info overlay
  --- shadow
  love.graphics.setColor(0,0,0,0.50)
  love.graphics.draw(self.info_overlay, w-self.info_overlay:getWidth()-2, 6)
  love.graphics.setColor(1,1,1)
  love.graphics.draw(self.info_overlay, w-self.info_overlay:getWidth()-4, 4)

  -- interface
  self.gui_renderer:render(self.gui)

  -- mobile interface
  if self.mobile.enabled then
    local mobile = self.mobile
    local scale = mobile.scale
    local texs = mobile.textures
    -- lower opacity when in GUI
    if self.gui.focus then love.graphics.setColor(1,1,1,0.25) end
    -- chat, top left
    love.graphics.draw(texs.chat, mobile.left, mobile.top, 0, scale)
    -- stick and cursor, bottom left
    love.graphics.draw(texs.stick, mobile.left, mobile.bottom-texs.stick:getHeight()*scale, 0, scale)
    local cx = math.floor((mobile.stick[1]+1)/2*texs.stick:getWidth()) -
      math.floor(texs.stick_cursor:getWidth()/2)
    local cy = math.floor((mobile.stick[2]+1)/2*texs.stick:getHeight()) +
      math.floor(texs.stick_cursor:getHeight()/2)
    love.graphics.draw(texs.stick_cursor, mobile.left+cx*scale, mobile.bottom-cy*scale, 0, scale)
    -- horizontal bar, top right
    local offset = 0
    for _, el in ipairs(mobile.hbar) do
      local tex = texs[el]
      offset = offset-tex:getWidth()*scale
      love.graphics.draw(tex, mobile.right+offset, mobile.top, 0, scale)
    end
    -- vertical bar, bottom right
    local offset, max = 0, 0
    for _, el in ipairs(mobile.vbar) do
      local tex = texs[el]
      max = math.max(max, tex:getWidth()*scale)
      offset = offset-tex:getHeight()*scale
      love.graphics.draw(tex, mobile.right-max, mobile.bottom+offset, 0, scale)
    end
    love.graphics.setColor(1,1,1)
  end

  -- loading screen
  if self.loading_screen_tex then
    local opacity = (self.loading_screen_time > 0 and self.loading_screen_time or 1)
    local tw, th = self.loading_screen_tex:getDimensions()
    local factor = math.min(w/tw, h/th)

    love.graphics.setColor(0,0,0, opacity)
    local miss_h = math.max(0, math.floor((h-th*factor)/2))
    local miss_w = math.max(0, math.floor((w-tw*factor)/2))
    love.graphics.rectangle("fill", 0, 0, w, miss_h) -- top band
    love.graphics.rectangle("fill", 0, h-miss_h, w, miss_h) -- bottom band
    love.graphics.rectangle("fill", 0, 0, miss_w, h) -- left band
    love.graphics.rectangle("fill", w-miss_w, 0, miss_w, h) -- right band

    love.graphics.setColor(1,1,1, opacity)
    love.graphics.draw(self.loading_screen_tex, miss_w, miss_h, 0, (w-miss_w*2)/tw, (h-miss_h*2)/th)
    love.graphics.setColor(1,1,1)
  end

  -- resource manager info
  if self.rsc_manager:isBusy() then
    local text = love.graphics.newText(self.font, self.rsc_manager.busy_hint)
    love.graphics.setColor(0,0,0)
    love.graphics.rectangle("fill", love.graphics.getWidth()-text:getWidth(), 0, text:getWidth(), text:getHeight())
    love.graphics.setColor(1,1,1)
    love.graphics.draw(text, love.graphics.getWidth()-text:getWidth(), 0)
  end
end

function Client:setOrientation(orientation)
  self.orientation = orientation
  self:sendPacket(net.INPUT_ORIENTATION, orientation)
end

function Client:setMoveForward(move_forward)
  if self.move_forward ~= move_forward then
    self.move_forward = move_forward
    self:sendPacket(net.INPUT_MOVE_FORWARD, move_forward)
  end
end

function Client:inputAttack()
  self:sendPacket(net.INPUT_ATTACK)
end

function Client:inputDefend()
  self:sendPacket(net.INPUT_DEFEND)
end

function Client:inputInteract()
  self:sendPacket(net.INPUT_INTERACT)
end

function Client:pressOrientation(orientation)
  table.insert(self.orientation_stack, orientation)
  self:setOrientation(orientation)
end

function Client:releaseOrientation(orientation)
  for i=#self.orientation_stack,1,-1 do
    if self.orientation_stack[i] == orientation then
      table.remove(self.orientation_stack, i)
    end
  end

  local last = #self.orientation_stack
  if last > 0 then
    self:setOrientation(self.orientation_stack[last])
  end
end

-- chest interactions

function Client:storeGold(amount)
  self:sendPacket(net.GOLD_STORE, amount)
end

function Client:withdrawGold(amount)
  self:sendPacket(net.GOLD_WITHDRAW, amount)
end

function Client:storeItem(id)
  self:sendPacket(net.ITEM_STORE, id)
end

function Client:withdrawItem(id)
  self:sendPacket(net.ITEM_WITHDRAW, id)
end

-- shop interactions

function Client:buyItem(id, amount)
  self:sendPacket(net.ITEM_BUY, {id, amount})
end

function Client:sellItem(id, amount)
  self:sendPacket(net.ITEM_SELL, id)
end

function Client:loadTexture(path)
  local image = self.textures[path]
  if not image then
    image = love.graphics.newImage(path)
    self.textures[path] = image
  end
  return image
end

-- Get cached texture atlas.
function Client:getTextureAtlas(x, y, tw, th, w, h)
  local key = table.concat({x,y,tw,th,w,h}, ",")
  local atlas = self.atlases[key]
  if not atlas then
    atlas = TextureAtlas(x,y,tw,th,w,h)
    self.atlases[key] = atlas
  end
  return atlas
end

-- inventory interactions

function Client:trashItem(id)
  self:sendPacket(net.ITEM_TRASH, id)
end

function Client:useItem(id)
  self:sendPacket(net.ITEM_USE, id)
end

function Client:castSpell(id)
  self:sendPacket(net.SPELL_CAST, id)
end

-- stat interactions

-- id: string
--- "strength"
--- "dexterity"
--- "constitution"
function Client:spendCharacteristicPoint(id)
  self:sendPacket(net.SPEND_CHARACTERISTIC_POINT, id)
end

function Client:equipItem(id)
  self:sendPacket(net.ITEM_EQUIP, id)
end

-- id: string
--- "helmet"
--- "armor"
--- "weapon"
--- "shield"
function Client:unequipSlot(id)
  self:sendPacket(net.SLOT_UNEQUIP, id)
end

-- n: quick action index (1-3)
-- type: "item" or "spell"
-- id: item/spell id (nil to unbind)
function Client:bindQuickAction(n, type, id)
  self:sendPacket(net.QUICK_ACTION_BIND, {n = n, type = type, id = id})
end

-- return true if a bound quick action
function Client:isQuickAction(n, type, id)
  local q = self.player_config.quick_actions[n]
  return q and q.type == type and q.id == id
end

function Client:doQuickAction(n)
  local q = self.player_config.quick_actions[n]
  if q then
    if q.type == "item" then
      self:useItem(q.id)
    elseif q.type == "spell" then
      self:castSpell(q.id)
    end
  end
end

function Client:setTradeGold(gold)
  self:sendPacket(net.TRADE_SET_GOLD, gold)
end

function Client:putTradeItem(id)
  self:sendPacket(net.TRADE_PUT_ITEM, id)
end

function Client:takeTradeItem(id)
  self:sendPacket(net.TRADE_TAKE_ITEM, id)
end

-- lock/accept trade
function Client:lockTrade()
  self:sendPacket(net.TRADE_LOCK)
end

function Client:closeTrade()
  self:sendPacket(net.TRADE_CLOSE)
end

function Client:playMusic(path)
  if self.music_path ~= path then
    if self.music_source then
      self.music_source:stop()
    end

    self.music_source = love.audio.newSource(path, "stream")
    self.music_source:setLooping(true)
    self.music_source:play()
    self.music_source:setVolume(self.player_config.volume.music)

    self.music_path = path
  end
end

-- play a relative sound source and return it
-- return source
function Client:playSound(path)
  local data = self.sounds[path]
  if not data then -- load
    data = love.sound.newSoundData(path)
    self.sounds[path] = data
  end

  local source = love.audio.newSource(data, "static")
  source:setRelative(true)
  source:play()

  table.insert(self.sound_sources, source)

  return source
end

function Client:showLoading()
  if #self.loading_screens > 0 then
    local path = self.loading_screens[math.random(1, #self.loading_screens)]

    self.loading_screen_tex = self:loadTexture("resources/textures/loadings/"..path)
    self.loading_screen_time = 0
  end
end

return Client
