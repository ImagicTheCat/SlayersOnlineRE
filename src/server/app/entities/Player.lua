-- https://github.com/ImagicTheCat/SlayersOnlineRE
-- MIT license (see LICENSE, src/server/main.lua or src/client/main.lua)

local net = require("app.protocol")
local LivingEntity = require("app.entities.LivingEntity")
local Mob = require("app.entities.Mob")
-- deferred require
local Map, Client
timer(0.01, function()
  Map = require("app.Map")
  Client = require("app.Client")
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
