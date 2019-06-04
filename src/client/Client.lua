local enet = require("enet")
local msgpack = require("MessagePack")
local Map = require("Map")
local LivingEntity = require("entities/LivingEntity")
local NetManager = require("NetManager")
local URL = require("socket.url")

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

  self.system_tex = self:loadTexture("resources/textures/system.png")
  self.system_background = love.graphics.newQuad(0,0,32,32,160,80)

  -- top
  self.system_border_ctl = love.graphics.newQuad(32,0,5,5,160,80)
  self.system_border_ctr = love.graphics.newQuad(64-5,0,5,5,160,80)
  -- bottom
  self.system_border_cbl = love.graphics.newQuad(32,32-5,5,5,160,80)
  self.system_border_cbr = love.graphics.newQuad(64-5,32-5,5,5,160,80)

  self.system_border_mt = love.graphics.newQuad(32+5,0,32-10,5,160,80)
  self.system_border_mb = love.graphics.newQuad(32+5,32-5,32-10,5,160,80)
  self.system_border_ml = love.graphics.newQuad(32,5,5,32-10,160,80)
  self.system_border_mr = love.graphics.newQuad(64-5,5,5,32-10,160,80)
end

function Client:tick(dt)
  -- net
  local event = self.host:service()
  while event do
    print(event.type, event.peer)

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
  local key = "w"
  if self.orientation == 1 then key = "d"
  elseif self.orientation == 2 then key = "s"
  elseif self.orientation == 3 then key = "a" end

  self:setMoveForward(love.keyboard.isScancodeDown(key))
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
  end
end

-- unsequenced: unsequenced if true/passed, reliable otherwise
function Client:sendPacket(protocol, data, unsequenced)
  self.peer:send(msgpack.pack({protocol, data}), 0, (unsequenced and "unsequenced" or "reliable"))
end

function Client:onDisconnect()
end

-- render system window
function Client:renderWindow(x, y, w, h)
  -- background
  love.graphics.draw(self.system_tex, self.system_background, x+1, y+1, 0, (w-2)/32, (h-2)/32)

  -- borders
  --- corners
  love.graphics.draw(self.system_tex, self.system_border_ctl, x, y)
  love.graphics.draw(self.system_tex, self.system_border_ctr, x+w-5, y)
  love.graphics.draw(self.system_tex, self.system_border_cbl, x, y+h-5)
  love.graphics.draw(self.system_tex, self.system_border_cbr, x+w-5, y+h-5)
  --- middles
  love.graphics.draw(self.system_tex, self.system_border_mt, x+5, y, 0, (w-10)/22, 1)
  love.graphics.draw(self.system_tex, self.system_border_mb, x+5, y+h-5, 0, (w-10)/22, 1)
  love.graphics.draw(self.system_tex, self.system_border_ml, x, y+5, 0, 1, (h-10)/22)
  love.graphics.draw(self.system_tex, self.system_border_mr, x+w-5, y+5, 0, 1, (h-10)/22)
end

function Client:draw()
  -- map rendering
  if self.map then
    love.graphics.push()
    local w,h = love.graphics.getDimensions()

    -- center map render
    love.graphics.translate(math.floor(w/2), math.floor(h/2))

    love.graphics.scale(4) -- pixel scale

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
  love.graphics.scale(4)
  self:renderWindow(10/4,10/4,400/4,400/4)
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
