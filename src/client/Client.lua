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
local TextureAtlas = require("TextureAtlas")

local Client = class("Client")

local net = {
  PROTOCOL = 0
}

function Client:__construct(cfg)
  self.cfg = cfg

  self.host = enet.host_create()
  self.peer = self.host:connect(self.cfg.remote)

  self.move_forward = false
  self.orientation = 0

  self.orientation_stack = {}

  self.net_manager = NetManager()

  self.textures = {} -- map of texture path => image
  self.skins = {} -- map of skin file => image
  self.loading_skins = {} -- map of skin file => callbacks

  self.font = love.graphics.newFont("resources/font.ttf", 50)
  self.font_target_height = 40 -- pixels

  self.world_scale = 4
  self.gui_scale = 2

  self.input_chat = TextInput(self)
  self.typing = false

  self.chat_history = ChatHistory(self)
  self.chat_history_time = 0

  self.message_window = MessageWindow(self)
  self.message_showing = false

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

  if not self.typing then
    -- movement input
    local key = "w"
    if self.orientation == 1 then key = "d"
    elseif self.orientation == 2 then key = "s"
    elseif self.orientation == 3 then key = "a" end

    self:setMoveForward(love.keyboard.isScancodeDown(key))
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
end

function Client:onPacket(protocol, data)
  if protocol == net.PROTOCOL then
    net = data
  elseif protocol == net.MAP then
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
  end
end

-- unsequenced: unsequenced if true/passed, reliable otherwise
function Client:sendPacket(protocol, data, unsequenced)
  self.peer:send(msgpack.pack({protocol, data}), 0, (unsequenced and "unsequenced" or "reliable"))
end

function Client:onDisconnect()
end

function Client:close()
  self.peer:disconnect()
  while self.peer:state() ~= "disconnected" do -- wait for disconnection
    self.host:service(100)
  end
end

function Client:onResize(w, h)
  self.world_scale = math.ceil(h/16/15) -- display 15 tiles max (height)

  self.xp_scale = utils.clamp(math.floor(w/self.xp_tex:getWidth()), 1, 3)/self.gui_scale

  self.input_chat:update(2/self.gui_scale, (h-45-2)/self.gui_scale, (w-4)/self.gui_scale, 45/self.gui_scale)

  self.phials_w = self.phials_atlas.cell_w*self.phials_scale
  self.phials_h = self.phials_atlas.cell_h*self.phials_scale
  self.phials_y = self.input_chat.y-self.phials_h

  self.chat_history:update(2/self.gui_scale+self.phials_w, self.input_chat.y-(2+200)/self.gui_scale, (w-4)/self.gui_scale-self.phials_w*2, 200/self.gui_scale)

  self.xp_w = self.xp_tex:getWidth()*self.xp_scale
  self.xp_h = self.xp_tex:getHeight()*self.xp_scale
  self.xp_y = h/self.gui_scale-self.xp_h+7*self.xp_scale

  self.message_window:update(2/self.gui_scale, 2/self.gui_scale, (w-4)/self.gui_scale, 200/self.gui_scale)
end

function Client:onTextInput(data)
  if self.typing then
    self.input_chat:input(data)
  end
end

function Client:onKeyPressed(key, scancode, isrepeat)
  if not isrepeat then
    if not self.typing then
      if scancode == "w" then self:pressOrientation(0)
      elseif scancode == "d" then self:pressOrientation(1)
      elseif scancode == "s" then self:pressOrientation(2)
      elseif scancode == "a" then self:pressOrientation(3)
      elseif scancode == "space" then self:inputAttack()
      elseif scancode == "e" then
        if self.message_showing then
          self.message_showing = false
        else
          self:inputInteract()
        end
      end
    end
  end

  if scancode == "backspace" then
    if self.typing then
      self.input_chat:erase(-1)
    end
  elseif scancode == "return" then
    if self.typing then
      self:inputChat(self.input_chat.text)
      self.input_chat:set("")
    end

    self:setTyping(not self.typing)
  end

  if self.typing and love.keyboard.isDown("lctrl") and not isrepeat then -- input chat copy/paste
    if key == "c" then
      love.system.setClipboardText(self.input_chat.text)
    elseif key == "v" then
      self.input_chat:set(self.input_chat.text..love.system.getClipboardText())
    end
  end
end

function Client:onKeyReleased(key, scancode)
  if not self.typing then
    if scancode == "w" then self:releaseOrientation(0)
    elseif scancode == "d" then self:releaseOrientation(1)
    elseif scancode == "s" then self:releaseOrientation(2)
    elseif scancode == "a" then self:releaseOrientation(3) end
  end
end

function Client:setTyping(typing)
  if self.typing ~= typing then
    self.typing = typing

    if self.typing then
      self:setMoveForward(false)
      self.typing = true
    else
      self.typing = false
      self.chat_history_time = 0
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

  if self.message_showing then
    self.message_window:draw()
  end

  love.graphics.pop()
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

-- callback(image)
--- image: skin texture or nil on failure
function Client:loadSkin(file, callback)
  local image = self.skins[file]
  if image then
    callback(image)
  else
    if self.loading_skins[file] then -- already loading
      table.insert(self.loading_skins[file], callback)
    else -- load
      self.loading_skins[file] = {callback}

      client.net_manager:request("http://chipset.slayersonline.net/"..file, function(data)
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
      end)
    end
  end
end

return Client
