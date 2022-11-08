-- https://github.com/ImagicTheCat/SlayersOnlineRE
-- MIT license (see LICENSE, src/server/main.lua or src/client/main.lua)

local LivingEntity = require("app.entities.LivingEntity")

local Mob = class("Mob", LivingEntity)

-- STATICS

-- METHODS

function Mob:__construct(data)
  LivingEntity.__construct(self, data)
end

return Mob
