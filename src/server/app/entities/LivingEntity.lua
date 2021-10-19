local utils = require("app.lib.utils")
local Entity = require("app.Entity")
local XPtable = require("app.XPtable")
local cfg = require("config")
-- deferred
local Client, Projectile, Mob
timer(0.01, function()
  Client = require("app.Client")
  Projectile = require("app.entities.Projectile")
  Mob = require("app.entities.Mob")
end)

local LivingEntity = class("LivingEntity", Entity)

-- STATICS

-- return dx,dy (direction) or nil on invalid orientation (0-3)
function LivingEntity.orientationVector(orientation)
  if orientation == 0 then return 0,-1
  elseif orientation == 1 then return 1,0
  elseif orientation == 2 then return 0,1
  elseif orientation == 3 then return -1,0 end
end

-- return orientation
function LivingEntity.vectorOrientation(dx, dy)
  local g_x = (math.abs(dx) > math.abs(dy))
  if dy < 0 and not g_x then return 0
  elseif dx > 0 and g_x then return 1
  elseif dy > 0 and not g_x then return 2
  else return 3 end
end

-- convert game speed to px/s
function LivingEntity.pixelSpeed(speed)
  return speed*4*16
end

-- PRIVATE METHODS

-- Function vars definitions, map of id => function.
-- form: %var(...)%
-- function(state, args...)
local function_vars = {}

function function_vars:rand(max)
  if max then
    return math.random(0, (max or 1)-1)
  end
end
function function_vars:min(a, b)
  if a and b then
    return math.min(a or 0, b or 0)
  end
end
function function_vars:max(a, b)
  if a and b then
    return math.max(a or 0, b or 0)
  end
end

-- Caster var accessor definitions, map of id => function.
-- function(caster, value): should return on get mode
--- value: nil on get mode
local caster_vars = {}

function caster_vars:Force(value)
  if not value then return self.strength_pts or 0
  else
    if class.is(self, Client) then
      self.strength_pts = value
      self:updateCharacteristics()
    end
  end
end
function caster_vars:Dext(value)
  if not value then return self.dexterity_pts or 0
  else
    if class.is(self, Client) then
      self.dexterity_pts = value
      self:updateCharacteristics()
    end
  end
end
function caster_vars:Constit(value)
  if not value then return self.constitution_pts or 0
  else
    if class.is(self, Client) then
      self.constitution_pts = value
      self:updateCharacteristics()
    end
  end
end
function caster_vars:Magie(value)
  if not value then return self.magic_pts or 0
  else
    if class.is(self, Client) then
      self.magic_pts = value
      self:updateCharacteristics()
    end
  end
end
function caster_vars:Attaque(value)
  if not value then return self.ch_attack
  else
    self.ch_attack = value
    if class.is(self, Client) then
      self.client:send(Client.makePacket(net.STATS_UPDATE, {
        attack = self.client.ch_attack,
      }))
    end
  end
end
function caster_vars:Defense(value)
  if not value then return self.ch_defense
  else
    self.ch_defense = value
    if class.is(self, Client) then
      self.client:send(Client.makePacket(net.STATS_UPDATE, {
        defense = self.client.ch_defense,
      }))
    end
  end
end
function caster_vars:Dommage(value)
  if not value then return self.min_damage end
end
function caster_vars:Vie(value, state)
  if value then
    -- effect
    local delta = value-self.health
    if delta > 0 then self:emitHint({{0,1,0}, utils.fn(delta)})
    elseif delta < 0 then
      self:broadcastPacket("damage", -delta)
      -- add damages to bingo book
      if class.is(self, Mob) and class.is(state.caster, Client) then
        self:addToBingoBook(state.caster, -delta)
      end
    end
    self:setHealth(value)
  else
    return self.health
  end
end
function caster_vars:VieMax(value)
  if not value then return self.max_health end
end
function caster_vars:CurrentMag(value)
  if value then self:setMana(value)
  else return self.mana end
end
function caster_vars:MagMax(value)
  if not value then
    return self.max_mana
  end
end
function caster_vars:Alignement(value)
  if not value then return self.alignment or 0
  else
    if class.is(self, Client) then
      local delta = value-self.alignment
      self:emitHint(utils.fn(delta, true).." alignement")
      self:setAlignment(value)
    end
  end
end
function caster_vars:Reputation(value)
  if not value then return self.reputation or 0
  else
    if class.is(self, Client) then
      local delta = value-self.alignment
      self:emitHint(utils.fn(delta, true).." réputation")
      self:setReputation(value)
    end
  end
end
function caster_vars:Gold(value)
  if not value then return self.gold or 0
  else
    if class.is(self, Client) then
      local delta = value-self.gold
      self:emitHint({{1,0.78,0}, utils.fn(delta, true)})
      self:setGold(value)
    end
  end
end
function caster_vars:Lvl(value)
  if not value then return self.level or 0
  else
    if class.is(self, Client) then
      local xp = XPtable[value]
      if xp then
        local delta = xp-self.xp
        self:emitHint({{0,0.9,1}, utils.fn(delta, true)})
        self:setXP(xp)
      end
    end
  end
end
function caster_vars:CurrentXP(value)
  if not value then return self.xp or 0
  else
    if class.is(self, Client) then
      local delta = value-self.xp
      self:emitHint({{0,0.9,1}, utils.fn(delta, true)})
      self:setXP(value)
    end
  end
end
function caster_vars:HandDom(value)
  if not value then return 0 end
end
function caster_vars:IndOff(value)
  if not value then
    local class_data = class.is(self, Client) and server.project.classes[self.class]
    return class_data and class_data.off_index or 0
  end
end
function caster_vars:IndDef(value)
  if not value then
    local class_data = class.is(self, Client) and server.project.classes[self.class]
    return class_data and class_data.def_index or 0
  end
end
function caster_vars:IndPui(value)
  if not value then
    local class_data = class.is(self, Client) and server.project.classes[self.class]
    return class_data and class_data.pow_index or 0
  end
end
function caster_vars:IndVit(value)
  if not value then
    local class_data = class.is(self, Client) and server.project.classes[self.class]
    return class_data and class_data.health_index or 0
  end
end
function caster_vars:IndMag(value)
  if not value then
    local class_data = class.is(self, Client) and server.project.classes[self.class]
    return class_data and class_data.mag_index or 0
  end
end

-- Target var accessor definitions, map of id => function.
-- function(target, value, state): should return on get mode
--- value: nil on get mode
local target_vars = {}

target_vars.Vie = caster_vars.Vie
target_vars.Attaque = caster_vars.Attaque
target_vars.Defense = caster_vars.Defense
target_vars.Dommage = caster_vars.Dommage

function target_vars:Bloque(value, state)
  if not value then return self.spell_blocked and 1 or 0
  else
    if class.is(self, Client) or class.is(self, Mob) then
      self.spell_blocked = value > 0
      state.spell_block = true
    end
  end
end

do -- Build spell execution environment.
  local function sanitize_result(v)
    if v ~= v then return 0 -- NaN
    elseif math.abs(v) == 1/0 then return 0 -- inf
    else return math.floor(v) end
  end
  local function var(state, id, value)
    local caster = state.caster
    if value then
      if class.is(caster, Client) then caster:setVariable(id, value) end
    else
      if class.is(caster, Client) then return caster:getVariable(id) end
      return 0
    end
  end
  local function func_var(state, id, ...)
    local f = function_vars[id]
    if f then return f(state, ...) end
  end
  local function caster_var(state, id, value)
    local f = caster_vars[id]
    if f then
      if value then f(state.caster, value, state)
      else return f(state.caster, nil, state) end
    end
  end
  local function target_var(state, id, value)
    local f = target_vars[id]
    if f then
      if value then f(state.target, value, state)
      else return f(state.target, nil, state) end
    end
  end
  -- spell command
  local function spell(state, id)
    local spell_data = server.project.spells[server.project.spells_by_name[id]]
    if spell_data then state.target:applySpell(state.caster, spell_data) end
  end
  LivingEntity.spell_env = {
    R = sanitize_result,
    var = var,
    caster_var = caster_var,
    target_var = target_var,
    func_var = func_var,
    spell = spell
  }
end

-- METHODS

function LivingEntity:__construct()
  Entity.__construct(self)

  self.orientation = 0 -- follow charaset directions (0 top, 1 right, 2 bottom, 3 left)
  self.move_forward = false
  self.speed = 1 -- game speed
  self.move_time = 0
  self.ghost = false
  self.acting = false
  self.health, self.max_health = 100, 100
  self.mana, self.max_mana = 100, 100
  self.ch_attack, self.ch_defense = 0, 0 -- attack/defense characteristics
  self.min_damage, self.max_damage = 0, 0
  self.charaset = {
    path = "charaset.png",
    x = 0, y = 0,
    w = 24, h = 32
  }
  -- self.attack_sound
  -- self.hurt_sound
end

-- override
function LivingEntity:serializeNet()
  local data = Entity.serializeNet(self)

  data.orientation = self.orientation
  data.charaset = self.charaset
  data.attack_sound = self.attack_sound
  data.hurt_sound = self.hurt_sound
  data.ghost = self.ghost

  return data
end

function LivingEntity:setGhost(flag)
  self.ghost = flag
  self:broadcastPacket("ch_ghost", flag)
end

function LivingEntity:setSounds(attack_sound, hurt_sound)
  self.attack_sound = attack_sound
  self.hurt_sound = hurt_sound
  self:broadcastPacket("ch_sounds", {self.attack_sound, self.hurt_sound})
end

function LivingEntity:setOrientation(orientation)
  if self.orientation ~= orientation and orientation >= 0 and orientation < 4 then
    self.orientation = orientation
    self:broadcastPacket("ch_orientation", orientation)
  end
end

function LivingEntity:setMoveForward(move_forward)
  if self.move_forward ~= move_forward then
    self.move_forward = move_forward
    if self.move_forward then
      -- end timers/tasks
      if self.move_task then
        local task = self.move_task
        self.move_task = nil
        task(false)
      end
      if self.move_timer then self.move_timer:remove() end
      if self.move_final_timer then self.move_final_timer:remove() end
      -- movement
      self.move_time = clock()
      self.move_timer = itimer(1/cfg.tickrate, function()
        local dt = clock()-self.move_time
        local speed = LivingEntity.pixelSpeed(self.speed)
        if self.acting then speed = speed/2 end -- slow movement when acting
        -- move following the orientation
        local dx, dy = LivingEntity.orientationVector(self.orientation)
        local dist = math.floor(speed*dt) -- pixels traveled
        if dist > 0 and self.map then
          local nx, ny = self.x+dx*dist, self.y+dy*dist
          local dcx, dcy = nx-self.cx*16, ny-self.cy*16
          if dcx ~= 0 then dcx = dcx/math.abs(dcx) end
          if dcy ~= 0 then dcy = dcy/math.abs(dcy) end
          -- check collision with the 3 cells in the movement direction
          local col_x = dcx ~= 0 and not self.map:isCellPassable(self, self.cx+dcx, self.cy)
          local col_y = dcy ~= 0 and not self.map:isCellPassable(self, self.cx, self.cy+dcy)
          local col_xy = (dcx ~= 0 or dcy ~= 0) and not self.map:isCellPassable(self, self.cx+dcx, self.cy+dcy)
          if col_x or col_y or col_xy then -- collision
            -- stop/snap on current cell for the movement axis / orthogonal movement axis
            --- stop: prevent moving into blocking cells
            --- snap: allow easier movements at the edges of cells
            if dx ~= 0 then -- x movement
              if not col_x then -- snap
                self:updatePosition(self.x, self.cy*16)
              else -- stop
                self:updatePosition(self.cx*16, self.y)
              end
            else -- y movement
              if not col_y then -- snap
                self:updatePosition(self.cx*16, self.y)
              else -- stop
                self:updatePosition(self.x, self.cy*16)
              end
            end
          else
            self:updatePosition(nx, ny)
          end
          self.move_time = self.move_time+dist/speed -- sub traveled time
        end
      end)
    else
      if self.move_timer then
        self.move_timer:remove()
        self.move_timer = nil
        -- final teleport
        self.move_final_timer = timer(0.25, function()
          self:teleport(self.x, self.y) -- end position
        end)
      end
    end
  end
end

-- (async)
-- blocking: if passed/true, async and wait until it reaches the destination
-- speed_factor: (optional)
-- return true on success when blocking
function LivingEntity:moveToCell(cx, cy, blocking, speed_factor)
  -- end previous task
  if self.move_task then
    local task = self.move_task
    self.move_task = nil
    task(false)
  end
  if blocking then self.move_task = async() end
  -- init
  local dx, dy = cx*16-self.x, cy*16-self.y
  local speed = LivingEntity.pixelSpeed(self.speed)*(speed_factor or 1) -- pixels per second
  local dist = math.sqrt(dx*dx+dy*dy)
  local duration = dist/speed
  local time = clock()
  local x, y = self.x, self.y
  self:setOrientation(LivingEntity.vectorOrientation(dx,dy))
  self:broadcastPacket("move_to_cell", {cx = cx, cy = cy, speed = speed})
  -- movement
  if self.move_timer then self.move_timer:remove() end
  self.move_timer = itimer(1/cfg.tickrate, function()
    local progress = (clock()-time)/duration
    if progress <= 1 then
      self.x = utils.lerp(x, cx*16, progress)
      self.y = utils.lerp(y, cy*16, progress)
      self:updateCell()
    else -- end
      self:teleport(cx*16, cy*16)
      self.move_timer:remove()
      self.move_timer = nil
      if blocking then
        local task = self.move_task
        self.move_task = nil
        task(true)
      end
    end
  end)
  if blocking then return self.move_task:wait() end
end

-- (async)
-- Move to entity. The targeted entity will be followed if moving.
-- target: Entity
-- speed_factor: (optional)
-- return true on success, false on target loss
function LivingEntity:moveToEntity(target, speed_factor)
  -- movements
  while self.map and self.map == target.map and
      self.cx ~= target.cx or self.cy ~= target.cy do
    local dx, dy = utils.dvec(target.cx-self.cx, target.cy-self.cy)
    if not self:moveToCell(self.cx+dx, self.cy+dy, true, speed_factor) then break end
  end
  return self.map and self.map == target.map and
      self.cx == target.cx and self.cy == target.cy
end

-- Do an action (visual effect).
-- action: string
--- "attack"
--- "defend"
--- "cast"
--- "use"
-- return success boolean
function LivingEntity:act(action, duration)
  if not self.acting then
    -- do animation
    self.acting = action
    self:broadcastPacket("act", {self.acting, duration})
    timer(duration, function() self.acting = false end)
    return true
  end
  return false
end

function LivingEntity:attack()
  if self:act("attack", 1) then
    -- Check if the attacker and the attacked are on the same realm.
    -- E.g. client bound entities.
    local client = (class.is(self, Client) and self or self.client)
    local entities = self:raycastEntities(1)
    for _, entity in ipairs(entities) do
      if class.is(entity, LivingEntity) and (not entity.client or entity.client == client) then
        if entity:onAttack(self) then break end
      end
    end
  end
end

function LivingEntity:defend()
  if self:act("defend", 1) then
    -- TODO
  end
end

function LivingEntity:setHealth(health)
  local old_health = self.health
  self.health = utils.clamp(health, 0, self.max_health)
  if old_health > 0 and self.health == 0 then self:onDeath() end
end

function LivingEntity:setMana(mana)
  self.mana = utils.clamp(mana, 0, self.max_mana)
end

function LivingEntity:onDeath()
end

-- amount: nil for miss event
function LivingEntity:damage(amount)
  self:broadcastPacket("damage", amount)
  if amount then
    self:setHealth(self.health-amount)
  end
end

-- attacker: living entity attacking
-- should return true on hit
function LivingEntity:onAttack(attacker)
end

-- compute attack damages against another living entity
-- target: LivingEntity
-- return damages on hit or nil if missed
function LivingEntity:computeAttack(target)
  if math.random(self.ch_attack) > math.random(target.ch_defense) then
    return math.random(self.min_damage, self.max_damage)
  end
end

-- Cast a spell.
-- target: LivingEntity
-- spell: spell data
-- mode: (optional) "nocast" to bypass cast
function LivingEntity:castSpell(target, spell, mode)
  local cast_duration = (mode ~= "nocast" and spell.cast_duration*0.03 or 0.001)
  -- cast spell
  if spell.type == "sneak-attack" then -- special case, attacking
    if mode ~= "nocast" then self:act("attack", cast_duration) end
    timer(cast_duration, function()
      -- find target
      local entities = self:raycastEntities(1)
      for _, entity in ipairs(entities) do
        if entity == target then
          target:applySpell(self, spell)
          break
        end
      end
    end)
  else -- regular cases, spell casting
    if mode ~= "nocast" then self:act("cast", cast_duration) end
    timer(cast_duration, function()
      if mode ~= "nocast" then self:emitHint({{0.77,0.18,1}, spell.name}) end
      if spell.type == "fireball" then
        local proj = Projectile()
        proj:setCharaset({
          path = spell.set:sub(9), -- remove Chipset/ part
          x = spell.x, y = spell.y, w = spell.w, h = spell.h
        })
        self.map:addEntity(proj)
        proj:teleport(self.x, self.y)
        proj:launch(target, function() target:applySpell(self, spell) end)
      elseif spell.type == "resurrect" then
        target:resurrect()
        target:applySpell(self, spell)
      elseif spell.type == "jump-attack" then
        async(function()
         if self:moveToEntity(target, 3) then target:applySpell(self, spell) end
        end)
      else target:applySpell(self, spell) end
    end)
  end
end

local function spell_error_handler(err)
  io.stderr:write(debug.traceback("spell: "..err, 2).."\n")
end

-- Protected call of spell functions.
local function spellEval(f, ...)
  if f then
    local ok, r = xpcall(f, spell_error_handler, ...)
    if ok then return r end
  end
end

-- Apply spell step effects (self is target).
local function applySpellStep(state)
  -- unblock target
  if state.spell_block then
    state.spell_block = false
    state.target.spell_blocked = false
  end
  -- apply
  --- trigger aggressivity
  if class.is(state.caster, Client) and class.is(state.target, Mob) then
    state.target:addToBingoBook(state.caster, 0)
  end
  --- hit
  local spell = state.spell
  local hit = spellEval(spell.hit_func, state) or 1
  if hit > 0 then -- success
    if spell.type ~= "AoE" then
      -- audio/visual effects
      if #spell.set > 0 then
        state.target:emitAnimation(string.sub(spell.set, 9), -- remove Chipset\ part
          spell.x, spell.y, spell.w, spell.h, spell.anim_duration*0.03, spell.opacity/255)
      end
      if #spell.sound > 0 then state.target:emitSound(string.sub(spell.sound, 7)) end -- remove Sound\ part
    end
    -- effect
    spellEval(spell.effect_func, state)
  else
    state.target:damage(nil) -- miss
  end
end

-- Apply spell effects (self is target).
-- caster: LivingEntity
-- spell: spell data
function LivingEntity:applySpell(caster, spell)
  local state = {caster = caster, target = self, spell = spell}
  local area = spellEval(spell.area_func, state) or 0
  local aggro = spellEval(spell.aggro_func, state) or 0
  local steps = spellEval(spell.duration_func, state) or 1
  local duration = spell.anim_duration*0.03
  if spell.type == "AoE" then -- special case, spawn AoE on the map
    local map = caster.map
    -- compute pixel area
    local tiles_per_axis = (area == 0 and 1 or area*2)
    local w, h = tiles_per_axis*spell.w, tiles_per_axis*spell.h
    local x, y = self.x+8, self.y+8
    local x1, y1 = x-math.floor(w/2)+spell.x, y-math.floor(h/2)+spell.y
    local x2, y2 = x1+w, y1+h
    async(function()
      for i=1, steps do
        -- interrupt effect if invalid
        if not map == caster.map then break end
        -- audio/visual effects
        if #spell.set > 0 then
          for tile_i=1, tiles_per_axis do
            for tile_j=1, tiles_per_axis do
              map:playAnimation(spell.set:sub(9), -- remove Chipset\ part
                x1+(tile_i-1)*spell.w, y1+(tile_j-1)*spell.h, spell.w, spell.h,
                duration, spell.opacity/255)
            end
          end
        end
        if #spell.sound > 0 then
          map:playSound(spell.sound:sub(7), x, y) -- remove Sound\ part
        end
        -- effect, for each touched cell
        for cx=math.floor(x1/16), math.ceil(x2/16) do
          for cy=math.floor(y1/16), math.ceil(y2/16) do
            local cell = map:getCell(cx, cy)
            if cell then
              for entity in pairs(cell) do
                -- check touch
                local touched = false
                if spell.target_type == "mob-player" or spell.target_type == "around" then
                  if class.is(caster, Client) then
                    touched = class.is(entity, Mob) or class.is(entity, Client) and caster:canFight(entity)
                  elseif class.is(caster, Mob) then
                    touched = class.is(entity, Client)
                  end
                elseif spell.target_type == "player" then
                  if class.is(caster, Client) then
                    touched = class.is(entity, Client) and entity ~= caster
                  elseif class.is(caster, Mob) then
                    touched = class.is(entity, Mob) and entity ~= caster
                  end
                end
                -- apply
                if touched then
                  applySpellStep({caster = caster, target = entity, spell = spell})
                end
              end
            end
          end
        end
        -- next
        wait(duration)
      end
    end)
  else -- regular spell, apply steps
    async(function()
      for i=1, steps do
        -- interrupt effect if invalid
        if not self.map then break end
        applySpellStep(state)
        -- next
        wait(duration)
      end
    end)
  end
end

-- get all entities in sight (nearest first)
-- dist: ray distance in cells
-- return list of entities
function LivingEntity:raycastEntities(dist)
  local entities = {}

  if self.map then
    local dx, dy = LivingEntity.orientationVector(self.orientation)

    if dx ~= 0 then -- x axis
      local dc = self.y-self.cy*16
      if dc ~= 0 then dc = dc/math.abs(dc) end

      for i=self.cx, self.cx+dist*dx, dx do
        for j=self.cy,self.cy+dc,(dc ~= 0 and dc or 1) do
          local cell = self.map:getCell(i,j)
          if cell then
            for entity in pairs(cell) do
              table.insert(entities, entity)
            end
          end
        end
      end
    else -- y axis
      local dc = self.x-self.cx*16
      if dc ~= 0 then dc = dc/math.abs(dc) end

      for i=self.cy, self.cy+dist*dy, dy do
        for j=self.cx,self.cx+dc,(dc ~= 0 and dc or 1) do
          local cell = self.map:getCell(j,i)
          if cell then
            for entity in pairs(cell) do
              table.insert(entities, entity)
            end
          end
        end
      end
    end
  end

  return entities
end

-- Check if there is a line of sight to another cell.
function LivingEntity:hasLOS(tx, ty)
  if self.map then
    local cx, cy = self.cx, self.cy
    while cx ~= tx or cy ~= ty do
      local dx, dy = utils.dvec(tx-cx, ty-cy)
      cx, cy = cx+dx, cy+dy
      if cx == tx and cy == ty then return true end
      if not self.map:isCellPassable(self, cx, cy) then return false end
    end
    return true
  end
end

-- charaset: {.path, .x, .y, .w, .h}
--- path: empty string => invisible
--- x,y: atlas origin
--- w,h: cell dimensions
function LivingEntity:setCharaset(charaset)
  self.charaset = charaset
  self:broadcastPacket("ch_charaset", self.charaset)
end

-- play sound on self
function LivingEntity:emitSound(sound)
  self:broadcastPacket("emit_sound", sound)
end

function LivingEntity:emitHint(colored_text)
  self:broadcastPacket("emit_hint", colored_text)
end

-- path: set path
-- x,y: world offset
-- w,h: frame dimensions
-- duration: seconds
-- alpha: (optional) 0-1
function LivingEntity:emitAnimation(path, x, y, w, h, duration, alpha)
  self:broadcastPacket("emit_animation", {
    path = path,
    x = x, y = y,
    w = w, h = h,
    duration = duration,
    alpha = alpha
  })
end

-- continuous movement update (should end with a teleport)
function LivingEntity:updatePosition(x, y)
  self.x = x
  self.y = y
  self:updateCell()

  if self.map then -- reference for next net update
    self.map.living_entity_updates[self] = true
  end
end

-- override
function LivingEntity:onMapChange()
  self:setMoveForward(false)
end

return LivingEntity
