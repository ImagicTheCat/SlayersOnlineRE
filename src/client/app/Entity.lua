-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat


local Entity = class("Entity")

function Entity:__construct(data)
  self.nettype = data.nettype
  self.id = data.id
  self.x = data.x
  self.y = data.y
  self.top = self.y -- top position of the displayed entity (used for sorting)
  self.draw_order = 0 -- 0: dynamic, -1: back, 1: front (must be set at construction)
  self.afterimage_duration = 0 -- configured duration for the afterimage when removed (seconds)
  -- self.afterimage -- opacity factor when the entity is an afterimage
end

function Entity:onPacket(action, data)
  if action == "teleport" then
    self.x, self.y = unpack(data)
  end
end

function Entity:tick(dt)
  self.top = self.y
end

function Entity:draw()
  love.graphics.rectangle("line", self.x, self.y, 16 ,16)
end

function Entity:drawUnder()
end

function Entity:drawOver()
end

return Entity
