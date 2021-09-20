local Widget = require("ALGUI.Widget")

local Phial = class("Phial", Widget)

Phial.STEP_DELAY = 2/3 -- animation step duration (anim_duration/3)
Phial.SHIFT = 21/72 -- empty progress display shift

-- METHODS

-- ptype: "health" or "mana"
function Phial:__construct(ptype)
  Widget.__construct(self)

  self.ptype = ptype
  self.factor = 0
end

return Phial
