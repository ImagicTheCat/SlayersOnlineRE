-- https://github.com/ImagicTheCat/SlayersOnlineRE
-- MIT license (see LICENSE, src/server/main.lua or src/client/main.lua)

-- Simple quota system.
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
end

function Quota:add(value)
  self.value = self.value+value
  if not self.exceeded and self.value >= self.max then --- exceeded
    self.exceeded = true
    if self.callback then self:callback() end
  end
end

function Quota:start()
  if self.timer then return end -- already started
  self.timer = itimer(self.period, function()
    self.value = 0
    self.exceeded = false
  end)
end

function Quota:stop()
  if self.timer then
    self.timer:close()
    self.timer = nil
  end
end

return Quota
