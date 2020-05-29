-- simple quota class
local Quota = class("Quota")

-- max: maximum allowed value
-- callback(quota): called when the quota is exceeded
function Quota:__construct(max, callback)
  self.value = 0
  self.max = max
  self.callback = callback
end

function Quota:set(value)
  self.value = value
  if self.value > self.max then -- exceeded
    self:callback()
    self.value = 0
  end
end

function Quota:add(value) self:set(self.value+value) end

return Quota
