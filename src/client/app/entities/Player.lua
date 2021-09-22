local utf8 = require("utf8")
local utils = require("app.lib.utils")
local LivingEntity = require("app.entities.LivingEntity")
local GUI = require("app.gui.GUI")
local Window = require("app.gui.Window")
local Text = require("app.gui.Text")

local Player = class("Player", LivingEntity)

-- STATICS

local ALIGN_COLORS = {
  {0,0,0}, -- 0-20
  {1,0,0}, -- 21-40
  {0.42,0.7,0.98}, -- 41-60
  {0.83,0.80,0.68}, -- 61-80
  {1,1,1} -- 81-100
}

-- METHODS

function Player:__construct(data)
  LivingEntity.__construct(self, data)

  self.chat_gui = GUI(client, true)
  self.chat_w = Window("both")
  self.chat_text = Text("", 400)
  self.chat_w.content:add(self.chat_text)
  self.chat_gui:add(self.chat_w)

  self.pseudo = data.pseudo
  self.guild = data.guild
  self.alignment = data.alignment
  self.name_tag = love.graphics.newText(client.font)
  self:updateNameTag()
  self.visible = true
end

function Player:updateNameTag()
  local final = self.pseudo
  if #self.guild > 0 then final = final.."["..self.guild.."]" end
  if self.group_data then final = "{"..final.."}" end

  local color = ALIGN_COLORS[math.floor(self.alignment/100*5)+1] or ALIGN_COLORS[5]
  self.name_tag:set({color, final})
end

-- override
function Player:onPacket(action, data)
  LivingEntity.onPacket(self, action, data)

  if action == "ch_visible" then
    self.visible = data
  elseif action == "ch_draw_order" then
    client.map:updateEntityDrawOrder(self, data)
  elseif action == "group_update" then
    self.group_data = data
    self:updateNameTag()
  elseif action == "group_remove" then
    self.group_data = nil
    self:updateNameTag()
  elseif action == "update_alignment" then
    self.alignment = data
    self:updateNameTag()
  end
end

-- override
function Player:drawUnder()
  if self.visible then
    -- draw pseudo
    local inv_scale = 1/client.world_scale
    local x = (self.x+8)-self.name_tag:getWidth()/2*inv_scale
    local y = self.y+16
    love.graphics.setColor(0,0,0,0.50)
    love.graphics.draw(self.name_tag, x+2*inv_scale, y+2*inv_scale, 0, inv_scale) -- shadowing
    love.graphics.setColor(1,1,1)
    love.graphics.draw(self.name_tag, x, y, 0, inv_scale)

    -- draw health (group)
    if self.group_data and self.id ~= client.id then
      local p = self.group_data.health/self.group_data.max_health
      local quad = client.gui_renderer.system.health_qs[math.floor(p*4)+1] or client.gui_renderer.system.health_qs[4]
      love.graphics.draw(client.gui_renderer.system.tex, quad, --
        (self.x+8)-16, self.y+16+self.name_tag:getHeight()*inv_scale, 0, math.floor(p*32)/16, 3/16)
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