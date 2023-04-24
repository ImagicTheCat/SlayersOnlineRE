-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

local Widget = require("ALGUI.Widget")

local XPBar = class("XPBar", Widget)

function XPBar:__construct()
  Widget.__construct(self)
  self.factor = 0
end

return XPBar
