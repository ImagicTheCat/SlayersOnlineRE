-- https://github.com/ImagicTheCat/SlayersOnlineRE
-- MIT license (see LICENSE, src/server/main.lua or src/client/main.lua)

local Widget = require("ALGUI.Widget")

local XPBar = class("XPBar", Widget)

function XPBar:__construct()
  Widget.__construct(self)
  self.factor = 0
end

return XPBar
