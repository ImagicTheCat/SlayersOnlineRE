-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

local LivingEntity = require("app.entities.LivingEntity")

local Mob = class("Mob", LivingEntity)

-- STATICS

-- METHODS

function Mob:__construct(data)
  LivingEntity.__construct(self, data)
end

return Mob
