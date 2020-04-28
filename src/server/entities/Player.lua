local net = require("protocol")
local LivingEntity = require("entities.LivingEntity")
local Mob = require("entities.Mob")

local Player = class("Player", LivingEntity)

-- STATICS

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
    self:damage(attacker:computeAttack(self))
    self.last_attacker = attacker
    return true
  end
end

-- override
function Player:serializeNet()
  local data = LivingEntity.serializeNet(self)
  data.pseudo = self.pseudo
  return data
end

function Player:mapChat(msg)
  if self.map then
    self.map:broadcastPacket(net.MAP_CHAT, {id = self.id, msg = msg})
  end
end

return Player
