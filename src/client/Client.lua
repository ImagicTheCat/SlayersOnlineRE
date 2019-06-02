local enet = require("enet")
local msgpack = require("MessagePack")
local Map = require("Map")
local LivingEntity = require("entities/LivingEntity")

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

  -- map
  if self.map then
    self.map:tick(dt)
  end
end

function Client:onPacket(protocol, data)
  if protocol == net.PROTOCOL then
    net = data
  elseif protocol == net.MAP then
    self.map = Map(data.map)
    self.id = data.id -- entity id

    self:setMoveForward(true)
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

function Client:draw()
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
end

function Client:setOrientation(orientation)
  if self.orientation ~= orientation then
    self.orientation = orientation
    self:sendPacket(net.INPUT_ORIENTATION, orientation)
  end
end

function Client:setMoveForward(move_forward)
  if self.move_forward ~= move_forward then
    self.move_forward = move_forward
    self:sendPacket(net.INPUT_MOVE_FORWARD, move_forward)
  end
end

return Client
