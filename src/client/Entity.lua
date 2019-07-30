
local Entity = class("Entity")

function Entity:__construct(data)
  self.nettype = data.nettype
  self.id = data.id
  self.x = data.x
  self.y = data.y
  self.draw_order = 0 -- 0: dynamic, -1: back, 1: front (must be set at construction)
end

function Entity:onPacket(action, data)
  if action == "teleport" then
    self.x, self.y = unpack(data)
  end
end

function Entity:tick(dt)
end

function Entity:draw()
  love.graphics.rectangle("line", self.x, self.y, 16 ,16)
end

function Entity:drawUnder()
end

function Entity:drawOver()
end

return Entity
