local LivingEntity = require("app.entities.LivingEntity")
local utils = require("app.lib.utils")
-- deferred
local Player
timer(0.01, function()
  Player = require("app.entities.Player")
end)

local Mob = class("Mob", LivingEntity)

-- STATICS

Mob.Type = {
  DEFENSIVE = 0,
  AGGRESSIVE = 1,
  STATIC = 2,
  BREAKABLE = 3
}

-- METHODS

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

  self.speed = data.speed
  self.obstacle = data.obstacle
  self.max_health = data.health
  self.health = self.max_health
  self.ch_attack = data.attack
  self.ch_defense = data.defense
  self.min_damage = data.damage
  self.max_damage = data.damage


  self.highest_damage_received = 0
  self.area = area

  -- remove Sound\ parts
  self:setSounds(string.sub(data.attack_sound, 7), string.sub(data.hurt_sound, 7))

  -- self.target -- player aggro
end

-- (re)launch/do AI timer
-- (starts a unique loop, will call itself again)
function Mob:doAI()
  if self.map then
    if self.ai_timer then -- remove previous timer if not done
      self.ai_timer:remove()
      self.ai_timer = nil
    end

    if self.target and self.target.ghost then self.target = nil end -- lose target if ghost
    -- lose target if aggressive and the target is gone
    if self.data.type == Mob.Type.AGGRESSIVE and self.target and self.target.map ~= self.map then
      self.target = nil
    end

    local aggro = (self.target and self.target.map == self.map)
    self.ai_timer = timer(utils.randf(1, 5)/self.speed*(aggro and 0.25 or 1.5), function()
      if self.map then
        if aggro then -- aggro mode
          local dcx, dcy = self.target.cx-self.cx, self.target.cy-self.cy
          if math.abs(dcx)+math.abs(dcy) > 1 then -- too far, seek target
            if self.data.type ~= Mob.Type.STATIC then -- move to target
              local dx, dy = utils.sign(dcx), utils.sign(dcy)
              if dx ~= 0 and math.abs(dcx) > math.abs(dy) and self:isCellPassable(self.cx+dx, self.cy) then
                self:moveToCell(self.cx+dx, self.cy)
              elseif dy ~= 0 and self:isCellPassable(self.cx, self.cy+dy) then
                self:moveToCell(self.cx, self.cy+dy)
              end
            end
          else -- close to target, try attack
            self:setOrientation(LivingEntity.vectorOrientation(self.target.x-self.x, self.target.y-self.y))
            self:act("attack", 1)
          end
        else -- idle mode
          -- random movement
          if self.data.type ~= Mob.Type.STATIC and self.data.type ~= Mob.Type.BREAKABLE then
            local ok
            local ncx, ncy
            -- search for a passable cell
            local i = 1
            while not ok and i <= 10 do
              local orientation = math.random(0,3)
              local dx, dy = LivingEntity.orientationVector(orientation)
              ncx, ncy = self.cx+dx, self.cy+dy
              ok = self:isCellPassable(ncx, ncy)
              i = i+1
            end

            if ok then
              self:moveToCell(ncx, ncy)
            end
          end

          if not aggro and self.data.type == Mob.Type.AGGRESSIVE then -- find target
            -- target nearest player
            if next(self.map.clients) then
              local players = {}
              for client in pairs(self.map.clients) do
                local dx, dy = client.x-self.x, client.y-self.y
                table.insert(players, {client, math.sqrt(dx*dx+dy*dy)})
              end
              table.sort(players, function(a,b) return a[2] < b[2] end)
              self.target = players[1][1]
            end
          end
        end

        -- next AI tick
        self.ai_timer = nil
        self:doAI()
      end
    end)
  end
end

function Mob:isCellPassable(cx,cy)
  if self.map and self.map:isCellPassable(self, cx, cy) then
    local cell = self.map:getCell(cx,cy)
    -- prevent mob stacking
    for entity in pairs(cell or {}) do
      if class.is(entity, Mob) then return false end
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
  if class.is(attacker, Player) then
    self.last_attacker = attacker
    local amount = attacker:computeAttack(self)

    if self.data.type ~= Mob.Type.BREAKABLE then -- update target
      -- update target if without target or on max damage
      if not (self.target and self.target.map == self.map) or (amount and amount >= self.highest_damage_received) then
        self.highest_damage_received = amount or 0
        self.target = attacker
        self:doAI() -- update timer
      end
    end

    self:damage(amount)
    return true
  end
end

-- override
function Mob:onDeath()
  -- loot/var
  local killer = self.last_attacker
  if killer then
    -- special var increment
    local var_id = self.data.var_id
    if var_id >= 0 then
      killer:setVariable("var", var_id, killer:getVariable("var", var_id)+self.data.var_increment)
    end

    -- XP
    local xp = math.random(self.data.xp_min, self.data.xp_max)
    killer:setXP(killer.xp+xp)
    if xp > 0 then killer:emitHint({{0,0.9,1}, utils.fn(xp, true)}) end

    -- gold
    local gold = math.random(self.data.gold_min, self.data.gold_max)
    killer:setGold(killer.gold+gold)
    if gold > 0 then killer:emitHint({{1,0.78,0}, utils.fn(gold, true)}) end

    -- object
    local item = killer.server.project.objects[self.data.loot_object]
    if item and math.random(100) <= self.data.loot_chance then
      killer.inventory:put(self.data.loot_object)
      killer:emitHint("+ "..item.name)
    end
  end

  -- remove
  self.map:removeEntity(self)
  if self.area then self.area.mob_count = self.area.mob_count-1 end
end

-- override
function Mob:onMapChange()
  LivingEntity.onMapChange(self)

  if self.map and self.data.type ~= Mob.Type.BREAKABLE then
    self:doAI()
  end
end

return Mob
