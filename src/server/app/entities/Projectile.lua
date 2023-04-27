-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

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
  asyncR(function()
    if self:moveToEntity(target) and on_hit then on_hit() end
    self.map:removeEntity(self)
  end)
end

return Projectile
