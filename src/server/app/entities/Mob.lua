local LivingEntity = require("app.entities.LivingEntity")
local utils = require("app.utils")
-- deferred
local Client
timer(0.01, function()
  Client = require("app.Client")
end)

local Mob = class("Mob", LivingEntity)

local AGGRO_RANGE = 8 -- radius in cells

-- data: mob data
-- area: (optional) bound mob area
function Mob:__construct(data, area)
  LivingEntity.__construct(self)
  self.nettype = "Mob"
  self.data = data
  self:setOrientation(2)
  self:setCharaset({
    path = string.sub(data.charaset, 9), -- remove Chipset\ part
    x = 0, y = 0,
    w = data.w,
    h = data.h
  })
  -- remove Sound\ parts
  self:setSounds(string.sub(data.attack_sound, 7), string.sub(data.hurt_sound, 7))
  self.speed = data.speed
  self.obstacle = data.obstacle
  self.max_health = data.health
  self.health = self.max_health
  self.ch_attack = data.attack
  self.ch_defense = data.defense
  self.min_damage = data.damage
  self.max_damage = data.damage
  self.spell_blocked = false
  self.area = area
  -- Players to kill, map of user id => kill priority.
  -- Will persist even if a player moves to another map, disconnects or dies.
  self.bingobook = {}
  -- self.target
end

function Mob:canMove()
  return not self.spell_blocked and
      self.data.type ~= "static" and self.data.type ~= "breakable"
end

-- (async) Wait with the ability to wake-up.
-- delay: seconds
local function waitAction(self, delay)
  local task = async(); self.wait_task = task
  local rtimer = timer(delay, task); task:wait()
  rtimer:close(); self.wait_task = nil
end

-- Seek target, if not in range move towards it (AI).
-- target: Entity
-- range: cells
-- return true if in range
local function seekTarget(self, target, range)
  local dx, dy = target.x-self.x, target.y-self.y
  if math.sqrt(dx*dx+dy*dy) > range*16 then -- too far, seek target
    if self:canMove() then -- move to target
      local sdx, sdy = utils.sign(dx), utils.sign(dy)
      if math.abs(dx) > math.abs(dy) then
        if self:isCellPassable(self.cx+sdx, self.cy) then
          self:moveToCell(self.cx+sdx, self.cy)
        elseif self:isCellPassable(self.cx, self.cy+sdy) then
          self:moveToCell(self.cx, self.cy+sdy)
        end
      else
        if self:isCellPassable(self.cx, self.cy+sdy) then
          self:moveToCell(self.cx, self.cy+sdy)
        elseif self:isCellPassable(self.cx+sdx, self.cy) then
          self:moveToCell(self.cx+sdx, self.cy)
        end
      end
    end
  else return true end
end

-- async
local function AI_thread(self)
  self.ai_running = true
  while self.map do
    do -- target acquisition
      -- detect players if aggressive
      if self.data.type == "aggressive" then
        for client in pairs(self.map.clients) do
          local dx, dy = client.x-self.x, client.y-self.y
          local dist = math.sqrt(dx*dx+dy*dy)
          if dist <= AGGRO_RANGE*16 then
            self:addToBingoBook(client, 1-dist/(AGGRO_RANGE*16))
          end
        end
      end
      -- select highest valid player from bingo book
      local targets = {}
      for user_id, priority in pairs(self.bingobook) do
        local client = server.clients_by_id[user_id]
        if client and self.map == client.map and not client.ghost then
          table.insert(targets, {client, priority})
        end
      end
      table.sort(targets, function(a,b) return a[2] > b[2] end)
      self.target = targets[1] and targets[1][1]
    end
    -- active behavior
    if not self.acting and not self:isMoving() then
      if self.target then -- combat mode
        local spell = self:selectSpell()
        if spell then -- cast a spell
          if spell.target_type == "self" or spell.target_type == "around" then -- self
            self:castSpell(self, spell)
          elseif spell.target_type == "player" then -- mobs (allies)
            -- find mobs in range
            local targets = {}
            for mob in pairs(self.map.mobs) do
              local dx, dy = mob.x-self.x, mob.y-self.y
              if math.sqrt(dx*dx+dy*dy) <= AGGRO_RANGE*16 then
                table.insert(targets, mob)
              end
            end
            if #targets > 0 then self:castSpell(targets[math.random(1, #targets)], spell) end
          elseif seekTarget(self, self.target, spell.type == "sneak-attack" and 1 or AGGRO_RANGE) then
            -- players (enemies)
            self:setOrientation(LivingEntity.vectorOrientation(self.target.x-self.x, self.target.y-self.y))
            self:castSpell(self.target, spell)
          end
        else -- regular attack
          if seekTarget(self, self.target, 1) then
            self:setOrientation(LivingEntity.vectorOrientation(self.target.x-self.x, self.target.y-self.y))
            self:attack()
          end
        end
      else -- idle mode
        if self:canMove() then -- random movements
          -- search for a passable cell
          local done, ncx, ncy
          local dirs = {0,1,2,3}
          while not done and #dirs > 0 do
            local i = math.random(1, #dirs)
            local orientation = dirs[i]
            table.remove(dirs, i)
            local dx, dy = LivingEntity.orientationVector(orientation)
            ncx, ncy = self.cx+dx, self.cy+dy
            if self:isCellPassable(ncx, ncy) then done = true end
          end
          if done then self:moveToCell(ncx, ncy) end
        end
      end
    end
    -- next
    waitAction(self, self.target and 0.5 or math.max(0.5, utils.randf(1.5, 7.5)/self.speed))
  end
  self.ai_running = nil
end

function Mob:addToBingoBook(client, amount)
  local user_id = client.user_id
  if not user_id then return end
  self.bingobook[user_id] = (self.bingobook[user_id] or 0)+amount
end

-- Select spell to cast.
-- return spell data or nil on failure
function Mob:selectSpell()
  for i=1,10 do
    local id, probability = unpack(self.data.spells[i])
    local spell = server.project.spells[id]
    if spell and math.random(1, 100) <= probability then return spell end
  end
end

function Mob:isCellPassable(cx,cy)
  if self.map and self.map:isCellPassable(self, cx, cy) then
    local cell = self.map:getCell(cx,cy)
    -- prevent mob stacking
    for entity in pairs(cell or {}) do
      if xtype.is(entity, Mob) then return false end
    end
    -- prevent mob from leaving bound area
    if self.area then
      local data = self.area.data
      if cx < data.x1 or cx > data.x2 or cy < data.y1 or cy > data.y2 then
        return false
      end
    end
    return true
  else
    return false
  end
end

-- override
function Mob:onAttack(attacker)
  if xtype.is(attacker, Client) then
    local amount = attacker:computeAttack(self)
    self:addToBingoBook(attacker, amount or 0)
    self:damage(amount)
    attacker:triggerGearSpells(self)
    if self.wait_task then self.wait_task() end
    return true
  end
end

-- override
function Mob:onDeath()
  local gold = math.random(self.data.gold_min, self.data.gold_max)
  local xp = math.random(self.data.xp_min, self.data.xp_max)
  local item = server.project.objects[self.data.loot_object]
  local dropped = item and math.random(100) <= self.data.loot_chance
  -- loot distribution
  --- Compute total contribution.
  local total = 0
  for user_id, priority in pairs(self.bingobook) do
    total = total+priority
  end
  if total > 0 then
    -- Distribute.
    -- Use a discrete cumulative distribution function (linear search) for the item.
    -- The shares of disconnected players are lost.
    local item_rand = math.random()*total
    local item_done, item_sum = false, 0
    for user_id, priority in pairs(self.bingobook) do
      local client = server.clients_by_id[user_id]
      if client then
        local fraction = priority/total
        -- special var increment
        local var_id = self.data.var_id
        if var_id >= 0 then
          client:setVariable("var", var_id, client:getVariable("var", var_id)+self.data.var_increment)
        end
        -- stat kill count
        client.play_stats.mob_kills = client.play_stats.mob_kills+1
        -- XP
        local xp_share = math.floor(xp*fraction)
        client:setXP(client.xp+xp_share)
        if xp_share > 0 then client:emitHint({{0,0.9,1}, utils.fn(xp_share, true)}) end
        -- gold
        local gold_share = math.floor(gold*fraction)
        client:setGold(client.gold+gold_share)
        if gold_share > 0 then client:emitHint({{1,0.78,0}, utils.fn(gold_share, true)}) end
        -- notify if on a different map
        if client.map ~= self.map then
          client:print("Loot récupéré du monstre "..self.data.name..
              " depuis la map "..self.map.data.name)
        end
      end
      -- item
      if dropped and not item_done then
        item_sum = item_sum+priority
        if item_rand < item_sum then -- selected
          if client then
            if client.inventory:put(self.data.loot_object) then
              client:emitHint("+ "..item.name)
            end
          end
          item_done = true
        end
      end
    end
  end
  -- remove
  self.map:removeEntity(self)
  if self.area then self.area.mob_count = self.area.mob_count-1 end
end

-- override
function Mob:onMapChange()
  LivingEntity.onMapChange(self)

  if self.map and self.data.type ~= "breakable" then
    if not self.ai_running then async(function() AI_thread(self) end) end
  end
end

return Mob
