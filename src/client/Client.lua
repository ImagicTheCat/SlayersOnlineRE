local enet = require("enet")
local utils = require("lib.utils")
local msgpack = require("MessagePack")
local Map = require("Map")
local LivingEntity = require("entities.LivingEntity")
local Player = require("entities.Player")
local NetManager = require("NetManager")
local URL = require("socket.url")
local GUI = require("gui.GUI")
local GUI_Renderer = require("gui.Renderer")
local TextInput = require("gui.TextInput")
local ChatHistory = require("gui.ChatHistory")
local Window = require("gui.Window")
local Text = require("gui.Text")
local GridInterface = require("gui.GridInterface")
local Inventory = require("gui.Inventory")
local Chest = require("gui.Chest")
local Shop = require("gui.Shop")
local TextureAtlas = require("TextureAtlas")
local Phial = require("gui.Phial")
local XPBar = require("gui.XPBar")
local sha2 = require("sha2")
local client_version = require("client_version")

local Client = class("Client")

local net = {
  PROTOCOL = 0
}

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

  self.orientation_stack = {}
  self.controls = {} -- map of control id (string) when pressed

  self.player_config = {
    scancode_controls = {
      w = "up",
      d = "right",
      s = "down",
      a = "left",
      space = "attack",
      e = "interact",
      ["return"] = "return",
      escape = "menu"
    },
    gui = {
      font_size = 25,
      dialog_height = 0.25,
      chat_height = 0.25
    }
  }

  self.touches = {} -- map of id => control

  self.net_manager = NetManager(self)

  self.textures = {} -- map of texture path => image
  self.skins = {} -- map of skin file => image
  self.loading_skins = {} -- map of skin file => callbacks

  self.sound_sources = {} -- list of source
  self.sounds = {} -- map of path => sound data

  -- list of loading screen paths
  self.loading_screens = love.filesystem.getDirectoryItems("resources/textures/loadings")
  self.loading_screen_fade = 1

  self.font = love.graphics.newFont("resources/font.ttf", self.player_config.gui.font_size)
  love.graphics.setFont(self.font)

  self.gui = GUI(self)
  self.gui_renderer = GUI_Renderer(self)

  self.world_scale = 4
  self.phials_scale = 3
  self.xp_scale = 3

  self.stats = {}

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
      if self.prompt_r then -- input string
        local r = self.prompt_r
        self.prompt_r = nil

        local text = self.input_chat.text
        self.input_chat:set("")
        self.gui:setFocus()
        self.w_input_chat:setVisible(false)
        self.message_window:setVisible(false)
        self:onResize(love.graphics.getDimensions())

        r(text)
      else -- chat
        self:inputChat(self.input_chat.text)
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

  -- chat events
  self.gui:listen("control-press", function(gui, id)
    if id == "return" then
      if not gui.focus then
        self.w_input_chat:setVisible(true)
        gui:setFocus(self.input_chat)
      end
    elseif id == "menu" then
      if not gui.focus then -- open menu
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
  self.menu_grid:set(0,0, Text("Inventory"), true)
  self.menu_grid:set(0,1, Text("Spells"), true)
  self.menu_grid:set(0,2, Text("Stats"), true)
  self.menu_grid:set(0,3, Text("Trade"), true)
  self.menu_grid:set(0,4, Text("Quit"), true)
  self.menu_grid:listen("cell-select", function(grid, cx, cy)
    if cy == 0 then
      self.inventory.content:updateContent()
      self.inventory:setVisible(true)
      self.gui:setFocus(self.inventory.content.grid)
    elseif cy == 2 then
      self.w_stats:setVisible(true)
      self.gui:setFocus(self.g_stats)
    elseif cy == 4 then
      love.event.quit()
    end
  end)

  self.menu.content:add(self.menu_grid)
  self.gui:add(self.menu)

  self.inventory = Inventory()
  self.inventory:setVisible(false)
  self.inventory.content.grid:listen("control-press", function(grid, id)
    if id == "menu" then
      self.inventory:setVisible(false)
      self.gui:setFocus(self.menu_grid)
    end
  end)
  self.gui:add(self.inventory)

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
  self.g_stats = GridInterface(2,10)
  self.w_stats.content:add(self.g_stats)
  self.g_stats:listen("control-press", function(grid, id)
    if id == "menu" then
      self.w_stats:setVisible(false)
      self.gui:setFocus(self.menu_grid)
    end
  end)
  self.gui:add(self.w_stats)

  -- trigger resize
  self:onResize(love.graphics.getDimensions())
end

function Client:tick(dt)
  -- net
  local event = self.host:service()
  while event do
    if event.type == "receive" then
      local packet = msgpack.unpack(event.data)
      self:onPacket(packet[1], packet[2])
    elseif event.type == "disconnect" then
      self:onDisconnect()
    end

    event = self.host:service()
  end

  -- net manager
  self.net_manager:tick(dt)

  -- map
  if self.map then
    self.map:tick(dt)
  end

  -- movement input
  local control = "up"
  if self.orientation == 1 then control = "right"
  elseif self.orientation == 2 then control = "down"
  elseif self.orientation == 3 then control = "left" end

  self:setMoveForward(not self.gui.focus and self:isControlPressed(control))

  -- GUI
  if not self.prompt_r and self.gui.focus == self.input_chat then
    self.chat_history:show()
  end

  if self.map then
    -- set listener on player
    local player = self.map.entities[self.id]
    if player then
      love.audio.setPosition(player.x, player.y, 0)
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
      if not self.net_manager.requests[1] then
        self.loading_screen_time = self.loading_screen_fade -- next step, fade-out
      end
    end
  end
end

function Client:onPacket(protocol, data)
  if protocol == net.PROTOCOL then
    net = data
    self:sendPacket(net.VERSION_CHECK, client_version)
  elseif protocol == net.MOTD_LOGIN then
    local motd = data

    async(function()
      -- login process
      --- load remote manifest
      if not self.net_manager:loadRemoteManifest() then
        print("couldn't reach remote resources repository manifest")
        self.chat_history:addMessage({{0,1,0.5}, "Couldn't reach remote resources repository manifest."})
        return
      end

      local pseudo = self:prompt(motd.."\n\nPseudo: ")
      local password = self:prompt(motd.."\n\nPassword: ")

      local pass_hash = sha2.hex2bin(sha2.sha512("<client_salt>"..pseudo..password))
      self:sendPacket(net.LOGIN, {pseudo = pseudo, password = pass_hash})
    end)
  elseif protocol == net.MAP then
    self:showLoading()
    self.map = Map(data.map)
    self.id = data.id -- entity id
  elseif protocol == net.ENTITY_ADD then
    if self.map then
      self.map:createEntity(data)
    end
  elseif protocol == net.ENTITY_REMOVE then
    if self.map then
      self.map:removeEntity(data)
    end
  elseif protocol == net.ENTITY_PACKET then
    if self.map then
      local entity = self.map.entities[data.id]
      if entity then
        entity:onPacket(data.act, data.data)
      end
    end
  elseif protocol == net.MAP_MOVEMENTS then
    if self.map then
      for _, entry in ipairs(data) do
        local id, x, y = unpack(entry)
        local entity = self.map.entities[id]
        if entity and class.is(entity, LivingEntity) then
          entity:onUpdatePosition(x,y)
        end
      end
    end
  elseif protocol == net.MAP_CHAT then
    if self.map then
      local entity = self.map.entities[data.id]
      if class.is(entity, Player) then
        entity:onMapChat(data.msg)
        self.chat_history:addMessage({{0,0.5,1}, tostring(entity.pseudo)..": ", {1,1,1}, data.msg})
      end
    end
  elseif protocol == net.CHAT_MESSAGE_SERVER then
    self.chat_history:addMessage({{0,1,0.5}, data})
  elseif protocol == net.EVENT_MESSAGE then
    self.message_window_text:set(data)
    self.message_window:setVisible(true)
    self.gui:setFocus(self.message_window)
  elseif protocol == net.EVENT_INPUT_QUERY then
    self.input_query_title:set(data.title)
    self.input_query_grid:init(1, #data.options)
    for i, option in ipairs(data.options) do
      self.input_query_grid:set(0,i-1,Text(option),true)
    end
    self.input_query:setVisible(true)
    self.gui:setFocus(self.input_query_grid)
  elseif protocol == net.EVENT_INPUT_STRING then
    async(function()
      local str = self:prompt(data.title)
      self:sendPacket(net.EVENT_INPUT_STRING_ANSWER, str)
    end)
  elseif protocol == net.PLAYER_CONFIG then
    -- apply player config
    utils.mergeInto(data, self.player_config)
    self:onApplyConfig(data)
  elseif protocol == net.INVENTORY_UPDATE_ITEMS then
    self.inventory.content:updateItems(data)
    if self.inventory.visible then
      self.inventory.content:updateContent()
    end

    self.chest.content_l:updateItems(data)
    if self.chest.visible then
      self.chest.content:updateContent()
    end
  elseif protocol == net.CHEST_OPEN then
    self.chest.title:set(data[1])
    self.chest.content_r:updateItems(data[2], true)
    self.chest.content_r:updateContent()
    self.chest.content_l:updateContent()
    self.chest:setVisible(true)
    self.gui:setFocus(self.chest.content_l.grid)
  elseif protocol == net.CHEST_UPDATE_ITEMS then
    self.chest.content_r:updateItems(data)
    self.chest.content_r:updateContent()
  elseif protocol == net.SHOP_OPEN then
    self.shop:setVisible(true)
    self.shop:open(data[1], data[2])
    self.gui:setFocus(self.shop.menu)
  elseif protocol == net.STATS_UPDATE then
    local stats = data
    utils.mergeInto(stats, self.stats)

    -- updates
    if stats.name then self.g_stats:set(0,0, Text("Name: "..stats.name)) end
    if stats.class then self.g_stats:set(0,1, Text("Class: "..stats.class)) end
    if stats.level then self.g_stats:set(0,2, Text("Level: "..stats.level)) end
    if stats.gold then self.g_stats:set(0,3, Text("Gold: "..stats.gold)) end

    if stats.alignment then self.g_stats:set(1,0, Text("Alignment: "..stats.alignment)) end
    if stats.health or stats.max_health then
      self.health_phial.factor = stats.health/stats.max_health
      self.g_stats:set(1,1, Text("Health: "..stats.health.."/"..stats.max_health))
    end
    if stats.mana or stats.max_mana then
      self.mana_phial.factor = stats.mana/stats.max_mana
      self.g_stats:set(1,2, Text("Mana: "..stats.mana.."/"..stats.max_mana))
    end

    if stats.strength then self.g_stats:set(0,5, Text("Strength: "..stats.strength), true) end
    if stats.dexterity then self.g_stats:set(0,6, Text("Dexterity: "..stats.dexterity), true) end
    if stats.constitution then self.g_stats:set(0,7, Text("Constitution: "..stats.constitution), true) end
    if stats.magic then self.g_stats:set(0,8, Text("Magic: "..stats.magic), true) end
    if stats.points then self.g_stats:set(0,9, Text("Remaining points: "..stats.points), true) end

    if stats.attack then self.g_stats:set(1,5, Text("Attack: "..stats.attack)) end
    if stats.defense then self.g_stats:set(1,6, Text("Defense: "..stats.defense)) end
    if stats.reputation then self.g_stats:set(1,7, Text("Reputation: "..stats.reputation)) end
    if stats.xp or stats.max_xp then
      self.xp_bar.factor = stats.xp/stats.max_xp
      self.g_stats:set(1,8, Text("XP: "..stats.xp.."/"..stats.max_xp))
    end
  end
end

-- unsequenced: unsequenced if true/passed, reliable otherwise
function Client:sendPacket(protocol, data, unsequenced)
  self.peer:send(msgpack.pack({protocol, data}), 0, (unsequenced and "unsequenced" or "reliable"))
end

function Client:onDisconnect()
  self.chat_history:addMessage({{0,1,0.5}, "Disconnected from server."})
end

function Client:close()
  self.net_manager:close()
  self.peer:disconnect()
  while self.peer:state() ~= "disconnected" do -- wait for disconnection
    self.host:service(100)
  end

  self.net_manager:saveLocalManifest()
end

function Client:onApplyConfig(config)
  if config.volume then -- set volume
    local master = config.volume.master
    if master then
      love.audio.setVolume(master)
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
end

function Client:onResize(w, h)
  self.gui:setSize(w,h)

  local xp_w = self.gui_renderer.xp_tex:getWidth()
  local xp_h = self.gui_renderer.xp_tex:getHeight()
  local phials_w = self.gui_renderer.phials_atlas.cell_w
  local phials_h = self.gui_renderer.phials_atlas.cell_h

  self.world_scale = math.ceil(h/16/15) -- display 15 tiles max (height)
  self.xp_scale = utils.floorScale(w/xp_w, xp_w)
  self.phials_scale = utils.floorScale((h*0.30/phials_h), phials_h)

  local input_chat_y = h-self.font:getHeight()-2-12
  local message_height = math.floor(self.player_config.gui.dialog_height*h)
  local chat_height = math.floor(self.player_config.gui.chat_height*h)

  if self.prompt_r then
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
  self.xp_bar:setPosition(w/2-self.xp_bar.w/2, h-self.xp_bar.h)

  self.message_window:setPosition(2, 2)
  self.message_window:setSize(w-4, message_height)
  self.input_query:setPosition(2, 2)
  self.input_query:setSize(w-4, message_height)

  local w_menu = self.font:getWidth("Inventory")+24
  local h_menu = (self.font:getHeight()+6)*5+12
  self.menu:setPosition(2, h/2-h_menu/2)
  self.menu:setSize(w_menu, h_menu)

  self.inventory:setPosition(self.menu.w+2, 2)
  self.inventory:setSize(w-4-self.menu.w, h-4)

  self.w_stats:setPosition(self.menu.w+2, 2)
  self.w_stats:setSize(w-4-self.menu.w, h-4)

  self.chest:setPosition(2,2)
  self.chest:setSize(w-4,h-4)

  self.shop:setPosition(2,2)
  self.shop:setSize(w-4,h-4)
end

function Client:onSetFont()
  self.gui:trigger("font-update")

  if self.map then
    for id, entity in pairs(self.map.entities) do
      if class.is(entity, Player) then
        entity.pseudo_text:setFont(self.font)
        entity.chat_gui:trigger("font-update")
      end
    end
  end
end

function Client:onTextInput(data)
  self.gui:triggerTextInput(data)
end

function Client:onKeyPressed(keycode, scancode, isrepeat)
  self.gui:triggerKeyPress(keycode, scancode, isrepeat)

  -- control handling
  if not isrepeat then
    local control = self.player_config.scancode_controls[scancode]
    if control then
      self:pressControl(control)
    end
  end

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

-- touch controls handling
function Client:onTouchPressed(id, x, y)
  local w, h = love.graphics.getDimensions()

  -- detect controls

  -- movement pad (left-bottom side, 50% height square)
  if utils.pointInRect(x, y, 0, h/2, h/2, h/2) then
    -- compute direction
    local dx, dy = x-h/4, y-h/2-h/4 -- shift from pad center

    local g_x = (math.abs(dx) > math.abs(dy))
    dx = dx/math.abs(dx)
    dy = dy/math.abs(dy)

    local control = "down"
    if dy < 0 and not g_x then control = "up"
    elseif dx > 0 and g_x then control = "right"
    elseif dx < 0 and g_x then control = "left" end

    self.touches[id] = control
    self:pressControl(control)
  -- buttons (right side, 100% height, 4x25% height squares)
  elseif utils.pointInRect(x, y, w-h/4, 0, h/4, h) then
    local button = math.floor((h-y)/h*4) -- 0, 1, 2, 3 "buttons" from bottom
    local controls = { -- button controls
      "interact",
      "attack",
      "return"
    }

    local control = controls[button+1]
    if control then
      self.touches[id] = control
      self:pressControl(control)
    end
  end
end

function Client:onTouchReleased(id, x, y)
  local control = self.touches[id]
  if control then
    self:releaseControl(control)
  end
end

-- abstraction layer for controls
function Client:pressControl(id)
  local control = self.controls[id]
  if not control then
    self.controls[id] = true

    -- character controls
    if not self.gui.focus then
      if id == "up" then self:pressOrientation(0)
      elseif id == "right" then self:pressOrientation(1)
      elseif id == "down" then self:pressOrientation(2)
      elseif id == "left" then self:pressOrientation(3)
      elseif id == "attack" then self:inputAttack()
      elseif id == "interact" then self:inputInteract()
      end
    end

    -- handling
    self.gui:triggerControlPress(id)
  end
end

function Client:releaseControl(id)
  local control = self.controls[id]
  if control then
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
-- return entered text
function Client:prompt(title, value)
  local r = async()
  self.prompt_r = r

  self.message_window_text:set(title)
  self.message_window:setVisible(true)

  self:onResize(love.graphics.getDimensions())
  self.w_input_chat:setVisible(true)
  self.input_chat:set(value or "")
  self.gui:setFocus(self.input_chat)

  return r:wait()
end

-- input a chat message to the remote server
function Client:inputChat(msg)
  if string.len(msg) > 0 then
    self:sendPacket(net.INPUT_CHAT, msg)
  end
end

function Client:draw()
  local w,h = love.graphics.getDimensions()

  -- map rendering
  if self.map then
    love.graphics.push()

    -- center map render
    love.graphics.translate(math.floor(w/2), math.floor(h/2))

    love.graphics.scale(self.world_scale) -- pixel scale

    -- center on player
    local player = self.map.entities[self.id]
    if player then
      love.graphics.translate(-player.x-8, -player.y-8)
    end

    self.map:draw()

    love.graphics.pop()
  end

  -- interface rendering
  self.gui_renderer:render(self.gui)

  -- loading screen
  if self.loading_screen_tex then
    local opacity = (self.loading_screen_time > 0 and self.loading_screen_time or 1)
    local tw, th = self.loading_screen_tex:getDimensions()
    local factor = math.ceil(w/tw)

    love.graphics.setColor(0,0,0, opacity)
    local miss_h = (h-th*factor)/2
    love.graphics.rectangle("fill", 0, 0, w, miss_h)
    love.graphics.rectangle("fill", 0, h-miss_h, w, miss_h)

    love.graphics.setColor(1,1,1, opacity)
    love.graphics.draw(self.loading_screen_tex, w/2-tw*factor/2, h/2-th*factor/2, 0, factor)
    love.graphics.setColor(1,1,1)
  end

  -- download info
  local requests = self.net_manager.requests
  if requests[1] then
    local text = love.graphics.newText(self.font, "downloading "..requests[1].url.."...")
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

function Client:loadTexture(path)
  local image = self.textures[path]

  if not image then
    image = love.graphics.newImage(path)
    self.textures[path] = image
  end

  return image
end

-- (async) load remote skin
-- return skin texture or nil on failure
function Client:loadSkin(file)
  local image = self.skins[file]
  if image then
    return image
  else
    local r = async()

    if self.loading_skins[file] then -- already loading
      table.insert(self.loading_skins[file], r)
    else -- load
      self.loading_skins[file] = {r}

      local data = self.net_manager:request(self.cfg.skin_repository..file)
      if data then
        local filedata = love.filesystem.newFileData(data, "skin.png")
        local image = love.graphics.newImage(love.image.newImageData(filedata))
        self.skins[file] = image

        for _, callback in ipairs(self.loading_skins[file]) do
          callback(image)
        end
      else
        for _, callback in ipairs(self.loading_skins[file]) do
          callback()
        end
      end

      self.loading_skins[file] = nil
    end

    return r:wait()
  end
end

function Client:playMusic(path)
  if self.music_path ~= path then
    if self.music_source then
      self.music_source:stop()
    end

    self.music_source = love.audio.newSource(path, "stream")
    self.music_source:setLooping(true)
    self.music_source:play()

    self.music_path = path
  end
end

-- play a sound source and return it
-- return source
function Client:playSound(path)
  local data = self.sounds[path]
  if not data then -- load
    data = love.sound.newSoundData(path)
    self.sounds[path] = data
  end

  local source = love.audio.newSource(data, "static")
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
