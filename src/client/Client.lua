local enet = require("enet")
local utils = require("lib/utils")
local msgpack = require("MessagePack")
local Map = require("Map")
local LivingEntity = require("entities/LivingEntity")
local Player = require("entities/Player")
local NetManager = require("NetManager")
local URL = require("socket.url")
local TextInput = require("gui/TextInput")
local ChatHistory = require("gui/ChatHistory")
local MessageWindow = require("gui/MessageWindow")
local InputQuery = require("gui/InputQuery")
local TextureAtlas = require("TextureAtlas")

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
      ["return"] = "return"
    },
    gui = {
      font_size = 25
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

  self.world_scale = 4
  self.gui_scale = 2

  self.input_chat = TextInput(self)
  self.typing = false

  self.chat_history = ChatHistory(self)
  self.chat_history_time = 0

  self.message_window = MessageWindow(self)
  self.message_showing = false

  self.input_query = InputQuery(self)
  self.input_query_showing = false

  self.input_string_showing = false

  self.phials_atlas = TextureAtlas(0,0,64,216,16,72)
  self.phials_tex = self:loadTexture("resources/textures/phials.png")
  self.phials_time = 0
  self.phials_delay = 2/3 -- animation step duration (anim_duration/3)
  self.phials_index = 0
  self.phials_scale = 3/self.gui_scale
  self.phials_ps = 21/72 -- empty progress display shift
  self.phials_h = 0
  self.phials_w = 0
  self.phials_y = 0

  self.health_max = 100
  self.health = 100

  self.mana_max = 100
  self.mana = 100

  self.xp_tex = self:loadTexture("resources/textures/xp.png")
  self.xp_scale = 3/self.gui_scale
  self.xp_w = 0
  self.xp_h = 0
  self.xp_y = 0

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
  if not self.typing then
    local control = "up"
    if self.orientation == 1 then control = "right"
    elseif self.orientation == 2 then control = "down"
    elseif self.orientation == 3 then control = "left" end

    self:setMoveForward(self:isControlPressed(control))
  end

  if self.chat_history_time > 0 then
    self.chat_history_time = self.chat_history_time-dt
  end

  -- phials animation
  self.phials_time = self.phials_time+dt
  if self.phials_time > self.phials_delay then
    local steps = math.floor(self.phials_time/self.phials_delay)
    self.phials_index = (self.phials_index+steps)%3
    self.phials_time = self.phials_time-steps*self.phials_delay
  end

  if self.map then
    -- set listener on player
    local player = self.map.entities[self.id]
    if player then
      love.audio.setPosition(player.x, player.y, 0)
    end
  end

  -- remove stopped sources
  for i=1,#self.sound_sources do
    if not self.sound_sources[i]:isPlaying() then
      self.sound_sources[i] = nil
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
        self.chat_history:add({{0,0.5,1}, tostring(entity.id)..": ", {1,1,1}, data.msg})
        self.chat_history_time = 10
      end
    end
  elseif protocol == net.CHAT_MESSAGE_SERVER then
    self.chat_history:add({{0,1,0.5}, data})
    self.chat_history_time = 10
  elseif protocol == net.EVENT_MESSAGE then
    self.message_window:set(data)
    self.message_showing = true
  elseif protocol == net.EVENT_INPUT_QUERY then
    self.input_query:set(data.title, data.options)
    self.input_query_showing = true
  elseif protocol == net.EVENT_INPUT_STRING then
    self.message_window:set(data)
    self.input_string_showing = true
    self:setTyping(true)
  elseif protocol == net.PLAYER_CONFIG then
    -- apply player config
    utils.mergeInto(data, self.player_config)
    self:onApplyConfig(data)
  end
end

-- unsequenced: unsequenced if true/passed, reliable otherwise
function Client:sendPacket(protocol, data, unsequenced)
  self.peer:send(msgpack.pack({protocol, data}), 0, (unsequenced and "unsequenced" or "reliable"))
end

function Client:onDisconnect()
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
      self:onResize(love.graphics.getDimensions()) -- trigger GUI update
    end
  end
end

function Client:onResize(w, h)
  self.world_scale = math.ceil(h/16/15) -- display 15 tiles max (height)

  self.xp_scale = utils.floorScale(w/self.xp_tex:getWidth()/self.gui_scale, self.xp_tex:getWidth())

  self.input_chat:update(2/self.gui_scale, (h-self.font:getHeight()-2-12)/self.gui_scale, (w-4)/self.gui_scale, (self.font:getHeight()+12)/self.gui_scale)

  self.phials_scale = utils.floorScale((h*0.40/self.phials_atlas.cell_h)/self.gui_scale, self.phials_atlas.cell_h)

  self.phials_w = self.phials_atlas.cell_w*self.phials_scale
  self.phials_h = self.phials_atlas.cell_h*self.phials_scale
  self.phials_y = self.input_chat.y-self.phials_h

  self.chat_history:update(2/self.gui_scale+self.phials_w, self.input_chat.y-(2+200)/self.gui_scale, (w-4)/self.gui_scale-self.phials_w*2, 200/self.gui_scale)

  self.xp_w = self.xp_tex:getWidth()*self.xp_scale
  self.xp_h = self.xp_tex:getHeight()*self.xp_scale
  self.xp_y = h/self.gui_scale-self.xp_h+7*self.xp_scale

  self.message_window:update(2/self.gui_scale, 2/self.gui_scale, (w-4)/self.gui_scale, 200/self.gui_scale)
  self.input_query:update(2/self.gui_scale, 2/self.gui_scale, (w-4)/self.gui_scale, 200/self.gui_scale)
end

function Client:onSetFont()
  self.input_chat.display_text:setFont(self.font)
  self.chat_history.text:setFont(self.font)
  self.message_window.text:setFont(self.font)
  self.input_query.text:setFont(self.font)

  if self.map then
    for id, entity in pairs(self.map.entities) do
      if class.is(entity, Player) then
        entity.chat_text:setFont(self.font)
      end
    end
  end
end

function Client:onTextInput(data)
  if self.typing then
    self.input_chat:input(data)
  end
end

function Client:onKeyPressed(key, scancode, isrepeat)
  -- control handling
  if not isrepeat then
    local control = self.player_config.scancode_controls[scancode]
    if control then
      self:pressControl(control)
    end
  end

  -- input text handling
  if scancode == "backspace" then
    if self.typing then
      self.input_chat:erase(-1)
    end
  end

  -- input chat copy/paste
  if not isrepeat and love.keyboard.isDown("lctrl") then
    if key == "c" then
      self:pressControl("copy")
      self:releaseControl("copy")
    elseif key == "v" then
      self:pressControl("paste")
      self:releaseControl("paste")
    end
  end
end

function Client:onKeyReleased(key, scancode)
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

    -- handling

    -- character controls
    if not self.typing then
      if id == "up" then
        if self.input_query_showing then
          self.input_query.selector:moveSelect(0,-1)
        else
          self:pressOrientation(0)
        end
      elseif id == "right" then self:pressOrientation(1)
      elseif id == "down" then
        if self.input_query_showing then
          self.input_query.selector:moveSelect(0,1)
        else
          self:pressOrientation(2)
        end
      elseif id == "left" then self:pressOrientation(3)
      elseif id == "attack" then self:inputAttack()
      elseif id == "interact" then
        if self.message_showing then
          self:sendPacket(net.EVENT_MESSAGE_SKIP)
          self.message_showing = false
        elseif self.input_query_showing then
          self.input_query_showing = false
          self.input_query.selector:select()
          self:sendPacket(net.EVENT_INPUT_QUERY_ANSWER, self.input_query.options[self.input_query.selected] or "")
        else
          self:inputInteract()
        end
      end
    end

    -- input text
    if id == "return" then -- valid text input
      if self.typing then
        if self.input_string_showing then -- input string
          self:sendPacket(net.EVENT_INPUT_STRING_ANSWER, self.input_chat.text)
          self.input_string_showing = false
        else -- chat
          self:inputChat(self.input_chat.text)
        end

        self.input_chat:set("")
      end

      self:setTyping(not self.typing)
    end

    if self.typing then
      if id == "copy" then
        love.system.setClipboardText(self.input_chat.text)
      elseif id == "paste" then
        self.input_chat:set(self.input_chat.text..love.system.getClipboardText())
      end
    end
  end
end

function Client:releaseControl(id)
  local control = self.controls[id]
  if control then
    self.controls[id] = nil

    -- handling
    if id == "up" then self:releaseOrientation(0)
    elseif id == "right" then self:releaseOrientation(1)
    elseif id == "down" then self:releaseOrientation(2)
    elseif id == "left" then self:releaseOrientation(3) end
  end
end

function Client:isControlPressed(id)
  return (self.controls[id] ~= nil)
end

function Client:setTyping(typing)
  if self.typing ~= typing then
    self.typing = typing

    if self.typing then
      self:setMoveForward(false)
      self.typing = true

      local s = self.gui_scale
      love.keyboard.setTextInput(true, self.input_chat.x*s, self.input_chat.y*s, self.input_chat.w*s, self.input_chat.h*s)
    else
      self.typing = false
      self.chat_history_time = 0

      love.keyboard.setTextInput(false)
    end
  end
end

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
  love.graphics.push()
  love.graphics.scale(self.gui_scale)

  --- xp
  love.graphics.draw(self.xp_tex, w/self.gui_scale*0.5-self.xp_w/2, self.xp_y, 0, self.xp_scale)

  --- phials (full pass, then empty pass)
  local phealth_quad = self.phials_atlas:getQuad(1, self.phials_index)
  local hx, hy, hw, hh = phealth_quad:getViewport()
  local health_quad = love.graphics.newQuad(hx, hy, hw, hh*(self.phials_ps+(1-self.phials_ps)*(1-self.health/self.health_max)), phealth_quad:getTextureDimensions())

  love.graphics.draw(self.phials_tex, self.phials_atlas:getQuad(0, self.phials_index), 0, self.phials_y, 0, self.phials_scale)
  love.graphics.draw(self.phials_tex, health_quad, 0, self.phials_y, 0, self.phials_scale)

  local pmana_quad = self.phials_atlas:getQuad(3, self.phials_index)
  local mx, my, mw, mh = pmana_quad:getViewport()
  local mana_quad = love.graphics.newQuad(mx, my, mw, mh*(self.phials_ps+(1-self.phials_ps)*(1-self.mana/self.mana_max)), pmana_quad:getTextureDimensions())

  love.graphics.draw(self.phials_tex, self.phials_atlas:getQuad(2, self.phials_index), w/self.gui_scale-self.phials_atlas.cell_w*self.phials_scale, self.phials_y, 0, self.phials_scale)
  love.graphics.draw(self.phials_tex, mana_quad, w/self.gui_scale-self.phials_atlas.cell_w*self.phials_scale, self.phials_y, 0, self.phials_scale)

  if self.typing then
    self.input_chat:draw()
  end

  if self.typing or self.chat_history_time > 0 then
    self.chat_history:draw()
  end

  if self.message_showing or self.input_string_showing then
    self.message_window:draw()
  end

  if self.input_query_showing then
    self.input_query:draw()
  end

  love.graphics.pop()

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

      local data = client.net_manager:request(self.cfg.skin_repository..file)
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

-- play a source and return it
-- x,y: (optional) spatialized if passed
-- volume: (optional)
-- pitch: (optional)
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
