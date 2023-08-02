-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

-- Client packet handlers (`self` is the Client object).

local Text = require "app.gui.Text"
local net = require "app.protocol"
local client_salt = require "app.client_salt"
local utils = require "app.utils"
local Map = require "app.Map"
local Player = require "app.entities.Player"

local packet = {}

function packet:MOTD_LOGIN(data)
  asyncR(function()
    -- login process
    local pseudo = self:prompt(data.motd.."\n\nPseudo: ")
    local password = self:prompt(data.motd.."\n\nMot de passe: ", "", true)
    local password_hash = love.data.hash("sha512", client_salt..pseudo:lower()..password)
    self:sendPacket(net.LOGIN, {pseudo = pseudo, password_hash = password_hash})
  end)
end

function packet:MAP(data)
  self:showLoading()
  self.map = Map(data.map)
  self.id = data.id -- entity id
  if self.pick_entity then
    -- cancel entity pick
    self:sendPacket(net.ENTITY_PICK)
    self.pick_entity = nil
  end
end

function packet:ENTITY_ADD(data)
  if self.map then self.map:createEntity(data) end
end

function packet:ENTITY_REMOVE(data)
  if self.map then self.map:removeEntity(data) end
end

function packet:ENTITY_PACKET(data)
  if self.map then
    local entity = self.map.entities[data.id]
    if entity then entity:onPacket(data.act, data.data) end
  end
end

function packet:MAP_MOVEMENTS(data)
  if self.map then self.map:onMovementsPacket(data) end
end

function packet:MAP_CHAT(data)
  if self.map then
    local entity = self.map.entities[data.id]
    if xtype.is(entity, Player) then
      entity:onMapChat(data.msg)
      self.chat_history:addMessage({{0.83,0.80,0.68}, tostring(entity.pseudo)..": ", {1,1,1}, data.msg})
    end
  end
end

function packet:CHAT_MESSAGE(data)
  self.chat_history:addMessage(data)
end

function packet:EVENT_MESSAGE(data)
  self.message_window_text:set(data)
  self.message_window:setVisible(true)
  self.gui:setFocus(self.message_window)
end

function packet:EVENT_INPUT_QUERY(data)
  self.input_query_title:set(data.title)
  self.input_query_grid:init(1, #data.options)
  for i, option in ipairs(data.options) do
    self.input_query_grid:set(0,i-1,Text(option),true)
  end
  self.input_query:setVisible(true)
  self.gui:setFocus(self.input_query_grid)
end

function packet:EVENT_INPUT_STRING(data)
  asyncR(function()
    local str = self:prompt(data.title)
    self:sendPacket(net.EVENT_INPUT_STRING_ANSWER, str)
  end)
end

function packet:PLAYER_CONFIG(data)
  -- apply player config
  utils.mergeInto(data, self.player_config)
  self:onApplyConfig(data)
end

function packet:INVENTORY_UPDATE_ITEMS(data)
  self.inventory.content:updateItems(data)
  if self.inventory.visible then
    self.inventory.content:updateContent()
  end
  self.chest.content_l:updateItems(data)
  if self.chest.visible then
    self.chest.content_l:updateContent()
  end
  self.trade.content_inv:updateItems(data)
  if self.trade.visible then
    self.trade.content_inv:updateContent()
  end
  self:updateInfoOverlay()
end

function packet:SPELL_INVENTORY_UPDATE_ITEMS(data)
  self.spell_inventory.content:updateItems(data)
  if self.spell_inventory.visible then
    self.spell_inventory.content:updateContent()
  end
  self:updateInfoOverlay()
end

function packet:CHEST_OPEN(data)
  self.chest.title:set(data[1])
  self.chest.content_r:updateItems(data[2], true)
  self.chest.content_r:updateContent()
  self.chest.content_l:updateContent()
  self.chest:setVisible(true)
  self.gui:setFocus(self.chest.content_l.grid)
end

function packet:CHEST_UPDATE_ITEMS(data)
  self.chest.content_r:updateItems(data)
  self.chest.content_r:updateContent()
end

function packet:SHOP_OPEN(data)
  self.shop:setVisible(true)
  self.shop:open(unpack(data))
  self.gui:setFocus(self.shop.menu)
end

function packet:STATS_UPDATE(data)
  -- Update statistics (sparse).
  -- Some statistics may not be basic character stats (e.g. inventory_size).
  local stats = data -- updated stats
  utils.mergeInto(stats, self.stats)
  -- Process updates.
  if stats.name then self.g_stats:set(0,0, Text("Nom: "..stats.name)) end
  if stats.class then self.g_stats:set(0,1, Text("Classe: "..stats.class)) end
  if stats.level then self.g_stats:set(0,2, Text("Niveau: "..stats.level)) end
  if stats.gold then
    self.g_stats:set(0,3, Text("Or: "..utils.fn(stats.gold)))
    self.chest.gold_l_display:set(utils.fn(stats.gold))
    self.shop.content:moveSelect(0,0) -- actualize
  end
  if stats.chest_gold then
    self.chest.gold_r_display:set(utils.fn(stats.chest_gold))
  end
  if stats.alignment then
    self.g_stats:set(1,0, Text("Alignement: "..stats.alignment))
    self:updateInfoOverlay()
  end
  if stats.health or stats.max_health then
    self.health_phial.factor = self.stats.health/self.stats.max_health
    self.g_stats:set(1,1, Text("Vie: "..utils.fn(self.stats.health).." / "..utils.fn(self.stats.max_health)))
  end
  if stats.mana or stats.max_mana then
    self.mana_phial.factor = self.stats.mana/self.stats.max_mana
    self.g_stats:set(1,2, Text("Mana: "..utils.fn(self.stats.mana).." / "..utils.fn(self.stats.max_mana)))
  end
  if stats.strength then self.g_stats:set(0,5, Text("Force: "..utils.fn(stats.strength)), true) end
  if stats.dexterity then self.g_stats:set(0,6, Text("Dextérité: "..utils.fn(stats.dexterity)), true) end
  if stats.constitution then self.g_stats:set(0,7, Text("Constitution: "..utils.fn(stats.constitution)), true) end
  if stats.magic then self.g_stats:set(0,8, Text({{0,0,0}, "Magie: "..utils.fn(stats.magic)})) end
  if stats.points then self.g_stats:set(0,9, Text("Points restants: "..utils.fn(stats.points))) end
  if stats.helmet_slot then self.g_stats:set(0,11, Text("Casque: "..stats.helmet_slot.name), true) end
  if stats.armor_slot then self.g_stats:set(0,12, Text("Armure: "..stats.armor_slot.name), true) end
  if stats.weapon_slot then self.g_stats:set(0,13, Text("Arme: "..stats.weapon_slot.name), true) end
  if stats.shield_slot then self.g_stats:set(0,14, Text("Bouclier: "..stats.shield_slot.name), true) end
  if stats.attack then self.g_stats:set(1,5, Text("Attaque: "..utils.fn(stats.attack))) end
  if stats.defense then self.g_stats:set(1,6, Text("Défense: "..utils.fn(stats.defense))) end
  if stats.reputation then self.g_stats:set(1,7, Text("Réputation: "..utils.fn(stats.reputation))) end
  if stats.xp or stats.next_xp or stats.current_xp then
    self.xp_bar.factor = (stats.xp-stats.current_xp)/(stats.next_xp-stats.current_xp)
    self.g_stats:set(1,8, Text("XP: "..utils.fn(stats.xp).." / "..utils.fn(stats.next_xp)))
  end
end

function packet:PLAY_MUSIC(data)
  if data then
    asyncR(function()
      if client.rsc_manager:requestResource("audio/"..data) then
        client:playMusic("resources/audio/"..data)
      else warn("failed to load music \""..data.."\"") end
    end)
  end
end

function packet:STOP_MUSIC(data) self.music_source:stop() end

function packet:PLAY_SOUND(data)
  if data then
    asyncR(function()
      if client.rsc_manager:requestResource("audio/"..data) then
        client:playSound("resources/audio/"..data)
      else warn("failed to load sound \""..data.."\"") end
    end)
  end
end

function packet:SCROLL_TO(data)
  local tx, ty = data[1], data[2]
  local ox, oy = 0, 0
  if self.scroll then -- continue scroll
    ox, oy = self.scroll.tx, self.scroll.ty
  else -- scroll from player
    local player = self.map.entities[self.id]
    if player then ox, oy = player.x, player.y end
  end
  local dx, dy = tx-ox, ty-oy
  self.scroll = {
    x = ox, y = oy, -- progress
    tx = tx, ty = ty, -- target
    ox = ox, oy = oy, -- origin
    duration = math.sqrt(dx*dx+dy*dy)/64, -- 4 cells/s
    time = 0
  }
end

function packet:SCROLL_RESET(data) self.scroll = nil end

function packet:VIEW_SHIFT_UPDATE(data) self.view_shift = data end

function packet:ENTITY_PICK(data)
  local entities = {}
  if self.map then
    for _, id in ipairs(data) do table.insert(entities, self.map.entities[id]) end
  end
  if #entities > 0 then
    self.pick_entity = {entities = entities, selected = 1}
  else -- end/cancel
    self:sendPacket(net.ENTITY_PICK)
  end
end

function packet:TRADE_OPEN(data)
  self.trade.title_l:set(data.title_l)
  self.trade.title_r:set(data.title_r)
  self.trade.content_inv:updateContent()
  self.trade:setVisible(true)
  self.gui:setFocus(self.trade.content_inv.grid)
end

function packet:TRADE_LEFT_UPDATE_ITEMS(data)
  self.trade.content_l:updateItems(data)
  self.trade.content_l:updateContent()
end

function packet:TRADE_RIGHT_UPDATE_ITEMS(data)
  self.trade.content_r:updateItems(data)
  self.trade.content_r:updateContent()
end

function packet:TRADE_SET_GOLD(data)
  self.trade.gold_r:set(1,0, Text(utils.fn(data)))
end

function packet:TRADE_STEP(step) self.trade:updateStep(step) end

function packet:TRADE_PEER_STEP(step) self.trade:updatePeerStep(step) end

function packet:TRADE_CLOSE(data)
  self.trade:setVisible(false)
  -- clear
  self.trade.content_l:updateItems({}, true)
  self.trade.content_l:updateContent()
  self.trade.content_r:updateItems({}, true)
  self.trade.content_r:updateContent()
  self.trade.gold_r:set(1,0, Text("0"))
  self.trade.gold_l_input:set("0")
  self.trade:updateStep("initiated")
  self.trade:updatePeerStep("initiated")
  self.gui:setFocus()
end

function packet:DIALOG_QUERY(data)
  if data.no_busy or (not self.gui.focus and not self.pick_entity) then -- not busy
    asyncR(function()
      self:sendPacket(net.DIALOG_RESULT, self:dialog(data.ftext, data.options))
    end)
  else self:sendPacket(net.DIALOG_RESULT) end -- busy, cancel
end

function packet:MAP_EFFECT(data)
  self.map_effect = data
  if self.map_effect == "rain" and not self.fx_rain then
    asyncR(function()
      if self.rsc_manager:requestResource("textures/sets/pluie.png") then
        local tex = self:loadTexture("resources/textures/sets/pluie.png", "non-fatal")
        if tex then
          self.fx_rain = love.graphics.newParticleSystem(tex)
          self.fx_rain:setEmissionRate(20)
          self.fx_rain:setSpeed(64)
          self.fx_rain:setParticleLifetime(20*16/64)
          self.fx_rain:setEmissionArea("uniform", love.graphics.getWidth()/self.world_scale, 16)
          self.fx_rain:setDirection(3*math.pi/4)
          self.fx_rain:start()
        end
      else warn("failed to load resource \"pluie.png\"") end
    end)
  elseif self.map_effect == "snow" and not self.fx_snow then
    asyncR(function()
      if self.rsc_manager:requestResource("textures/sets/neige.png") then
        local tex = self:loadTexture("resources/textures/sets/neige.png", "non-fatal")
        if tex then
          self.fx_snow = love.graphics.newParticleSystem(tex)
          self.fx_snow:setEmissionRate(10)
          self.fx_snow:setSpeed(32)
          self.fx_snow:setParticleLifetime(16*16/32)
          self.fx_snow:setEmissionArea("uniform", love.graphics.getWidth()/self.world_scale, 16)
          self.fx_snow:setDirection(math.pi/2)
          self.fx_snow:setSizes(1, 0.5)
          self.fx_snow:setSpread(0.25)
          self.fx_snow:start()
        end
      else warn("failed to load resource \"neige.png\"") end
    end)
  elseif self.map_effect == "fog" and not self.fx_fog then
    asyncR(function()
      if self.rsc_manager:requestResource("textures/sets/brouillard.png") then
        local tex = self:loadTexture("resources/textures/sets/brouillard.png", "non-fatal")
        if tex then
          self.fx_fog = {}
          self.fx_fog.tex = tex
          self.fx_fog.tex:setWrap("repeat")
          local w,h = self.fx_fog.tex:getDimensions()
          self.fx_fog.quad = love.graphics.newQuad(0, 0, w*2, h*2, w, h)
          self.fx_fog.speed = 2 -- world units/s
        end
      else warn("failed to load resource \"brouillard.png\"") end
    end)
  end
end

function packet:MAP_PLAY_ANIMATION(data)
  if self.map then self.map:playAnimation(unpack(data, 1, data.n)) end
end

function packet:MAP_PLAY_SOUND(data)
  if self.map then self.map:playSound(unpack(data, 1, data.n)) end
end

return packet
