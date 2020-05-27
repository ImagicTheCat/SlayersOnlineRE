local net = require("protocol")
local LivingEntity = require("entities.LivingEntity")
local Mob = require("entities.Mob")
-- deferred require
local Map, Client
task(0.01, function()
  Map = require("Map")
  Client = require("Client")
end)

local Player = class("Player", LivingEntity)

-- STATICS

local MAP_CHAT_RADIUS = 15 -- cells

-- METHODS

function Player:__construct()
  LivingEntity.__construct(self)

  self.pseudo = "<anonymous>"
  self.attack_sound = "Blow1.wav"
  self.hurt_sound = "Kill1.wav"
end

-- override
function Player:onAttack(attacker)
  if self.ghost or attacker == self then return end

  if class.is(attacker, Mob) then
    self:damage(attacker:computeAttack(self))
    return true
  elseif class.is(attacker, Player) then
    if self.map and self.map.data.type == Map.Type.PVE then return false end

    -- alignment loss
    local amount = attacker:computeAttack(self)
    if amount and self.map and self.map.data.type == Map.Type.PVE_PVP then
      attacker:setAlignment(attacker.alignment-5)
    end
    self:damage(amount)
    self.last_attacker = attacker
    return true
  end
end

-- override
function Player:serializeNet()
  local data = LivingEntity.serializeNet(self)
  data.pseudo = self.pseudo
  data.guild = self.guild
  return data
end

function Player:mapChat(msg)
  if self.map then
    -- send message to all client in chat radius
    local p = Client.makePacket(net.MAP_CHAT, {id = self.id, msg = msg})
    for client in pairs(self.map.clients) do
      local dx = math.abs(self.x-client.x)
      local dy = math.abs(self.y-client.y)
      if dx <= MAP_CHAT_RADIUS*16 and dy <= MAP_CHAT_RADIUS*16 then client:send(p) end
    end
  end
end

return Player
