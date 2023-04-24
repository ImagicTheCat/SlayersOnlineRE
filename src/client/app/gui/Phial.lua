-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

local Widget = require("ALGUI.Widget")

local Phial = class("Phial", Widget)

Phial.STEP_DELAY = 2/3 -- animation step duration (anim_duration/3)
Phial.SHIFT = 21/72 -- empty progress display shift

-- ptype: "health" or "mana"
function Phial:__construct(ptype)
  Widget.__construct(self)
  self.ptype = ptype
  self.factor = 0
end

return Phial
