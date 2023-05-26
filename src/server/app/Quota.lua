-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

-- Simple quota system.
-- Used to allow a certain amount of items per period.
local Quota = class("Quota")

-- max: maximum allowed value
-- period: seconds
-- callback(quota): (optional) called when the quota is exceeded
function Quota:__construct(max, period, callback)
  self.value = 0
  self.max = max
  self.period = period
  self.callback = callback
  self.exceeded = false
  self.last_time = loop:now()
end

local function update(self)
  local time = loop:now()
  if time - self.last_time >= self.period then
    self.value, self.exceeded = 0, false
    self.last_time = time
  end
end

-- Add value.
-- Return false if exceeded, true otherwise.
function Quota:add(value)
  update(self)
  self.value = self.value+value
  if not self.exceeded and self.value >= self.max then --- exceeded
    self.exceeded = true
    if self.callback then self:callback() end
  end
  return not self.exceeded
end

-- Check if exceeded.
-- Return false if exceeded, true otherwise.
function Quota:check()
  update(self)
  return not self.exceeded
end

return Quota
