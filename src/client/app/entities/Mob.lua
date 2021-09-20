local LivingEntity = require("app.entities.LivingEntity")

local Mob = class("Mob", LivingEntity)

-- STATICS

-- METHODS

function Mob:__construct(data)
  LivingEntity.__construct(self, data)
end

return Mob
