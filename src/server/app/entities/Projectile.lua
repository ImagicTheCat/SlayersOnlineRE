-- https://github.com/ImagicTheCat/SlayersOnlineRE
-- MIT license (see LICENSE, src/server/main.lua or src/client/main.lua)

local utils = require("app.utils")
local LivingEntity = require("app.entities.LivingEntity")

local Projectile = class("Projectile", LivingEntity)

function Projectile:__construct()
  LivingEntity.__construct(self)
  self.nettype = "LivingEntity"
end

-- target: Entity
-- on_hit(): (optional) called if the projectile hits the target
function Projectile:launch(target, on_hit)
  self.target = target
  async(function()
    if self:moveToEntity(target) and on_hit then on_hit() end
    self.map:removeEntity(self)
  end)
end

return Projectile
