local utf8 = require("utf8")
local utils = require("lib.utils")
local LivingEntity = require("entities.LivingEntity")
local GUI = require("gui.GUI")
local Window = require("gui.Window")
local Text = require("gui.Text")

local Player = class("Player", LivingEntity)

-- STATICS

-- METHODS

function Player:__construct(data)
  LivingEntity.__construct(self, data)

  self.chat_gui = GUI(client, true)
  self.chat_w = Window("both")
  self.chat_text = Text("", 400)
  self.chat_w.content:add(self.chat_text)
  self.chat_gui:add(self.chat_w)

  self.pseudo = data.pseudo
  self.pseudo_text = love.graphics.newText(client.font)
  self.pseudo_text:set(self.pseudo)
  self.visible = true
end

-- override
function Player:onPacket(action, data)
  LivingEntity.onPacket(self, action, data)

  if action == "ch_visible" then
    self.visible = data
  elseif action == "ch_draw_order" then
    client.map:updateEntityDrawOrder(self, data)
  elseif action == "group_update" then
    if not self.group_data then self.pseudo_text:set("{"..self.pseudo.."}") end
    self.group_data = data
  elseif action == "group_remove" then
    self.pseudo_text:set(self.pseudo)
    self.group_data = nil
  end
end

-- override
function Player:drawUnder()
  if self.visible then
    -- draw pseudo
    local inv_scale = 1/client.world_scale
    local x = (self.x+8)-self.pseudo_text:getWidth()/2*inv_scale
    local y = self.y+16
    love.graphics.setColor(0,0,0,0.50)
    love.graphics.draw(self.pseudo_text, x+2*inv_scale, y+2*inv_scale, 0, inv_scale) -- shadowing
    love.graphics.setColor(1,1,1)
    love.graphics.draw(self.pseudo_text, x, y, 0, inv_scale)

    -- draw health (group)
    if self.group_data and self.id ~= client.id then
      local p = self.group_data.health/self.group_data.max_health
      love.graphics.rectangle("fill", (self.x+8)-16, self.y+16+self.pseudo_text:getHeight()*inv_scale, math.floor(p*32), 4)
    end
  end
end

-- override
function Player:draw()
  if self.visible then
    LivingEntity.draw(self)
  end
end

-- override
function Player:drawOver()
  if self.visible then
    LivingEntity.drawOver(self)

    -- draw chat GUI
    if self.chat_timer then
      self.chat_gui:update()
      local inv_scale = 1/client.world_scale
      love.graphics.push()
      love.graphics.translate(self.x+8-self.chat_gui.w/2*inv_scale, self.y-self.chat_gui.h*inv_scale-12)
      love.graphics.scale(inv_scale)
      client.gui_renderer:render(self.chat_gui) -- render
      love.graphics.pop()
    end
  end
end

function Player:onMapChat(msg)
  if self.chat_timer then self.chat_timer:remove() end
  self.chat_timer = scheduler:timer(utils.clamp(utf8.len(msg)/5, 5, 20), function()
    self.chat_timer = nil
  end)

  self.chat_text:set(msg)
end

return Player
