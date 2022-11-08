-- https://github.com/ImagicTheCat/SlayersOnlineRE
-- MIT license (see LICENSE, src/server/main.lua or src/client/main.lua)

-- map of nettype => Entity class
return {
  Entity = require("app.Entity"),
  LivingEntity = require("app.entities.LivingEntity"),
  Player = require("app.entities.Player"),
  Event = require("app.entities.Event"),
  Mob = require("app.entities.Mob")
}
