-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

-- map of nettype => Entity class
return {
  Entity = require("app.Entity"),
  LivingEntity = require("app.entities.LivingEntity"),
  Player = require("app.entities.Player"),
  Event = require("app.entities.Event"),
  Mob = require("app.entities.Mob")
}
