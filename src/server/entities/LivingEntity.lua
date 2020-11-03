local Entity = require("Entity")
local utils = require("lib.utils")
local cfg = require("config")
-- deferred
local Client
task(0.01, function()
  Client = require("Client")
end)

local LivingEntity = class("LivingEntity", Entity)

-- STATICS

LivingEntity.spell_patterns = {
  vfunction = "%%([%w_]+)%((.-)%)%%", -- %func(...)%
  caster_var = "%%%[Wizard%]%.([^%.%s%%%(%)]+)%%", -- %[Wizard].var%
  target_var = "%%%[Cible%]%.([^%.%s%%%(%)]+)%%", -- %[Cible].var%
  spell_ins = "^%s*spell:%s*([^%.%%%(%)]+)%s*$", -- spell: name
  assignment_ins = "^%s*(.-)=(.*)$" -- var=value
}

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
  dx = dx/math.abs(dx)
  dy = dy/math.abs(dy)

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

-- spell var function definitions, map of id => function
-- function(target, args...): should return a number or a string
--- args...: passed string expressions (after substitution)

local spell_vfunctions = {}

function spell_vfunctions:rand(max)
  if max then
    return math.random(0, (utils.computeExpression(max) or 1)-1)
  end
end

function spell_vfunctions:min(a, b)
  if a and b then
    return math.min(utils.computeExpression(a) or 0, utils.computeExpression(b) or 0)
  end
end

function spell_vfunctions:max(a, b)
  if a and b then
    return math.max(utils.computeExpression(a) or 0, utils.computeExpression(b) or 0)
  end
end

-- caster var accessor definitions, map of id => function
-- function(caster, value): should return a number or a string on get mode
--- value: passed string expression (after substitution) on set mode (nil on get mode)

local caster_vars = {}

function caster_vars:Force(value)
  if not value then
    return self.strength_pts or 0
  end
end

function caster_vars:Dext(value)
  if not value then
    return self.dexterity_pts or 0
  end
end

function caster_vars:Constit(value)
  if not value then
    return self.constitution_pts or 0
  end
end

function caster_vars:Magie(value)
  if not value then
    return self.magic_pts or 0
  end
end

function caster_vars:Attaque(value)
  if not value then
    return self.ch_attack
  end
end

function caster_vars:Defense(value)
  if not value then
    return self.ch_defense
  end
end

function caster_vars:Vie(value)
  if value then
    -- effect
    value = utils.computeExpression(value) or 0
    local delta = value-self.health
    if delta > 0 then self:emitHint({{0,1,0}, utils.fn(delta)})
    elseif delta < 0 then self:broadcastPacket("damage", delta) end

    self:setHealth(value)
  else
    return self.health
  end
end

function caster_vars:VieMax(value)
  if not value then
    return self.max_health
  end
end

function caster_vars:CurrentMag(value)
  if value then
    self:setMana(utils.computeExpression(value) or 0)
  else
    return self.mana
  end
end

function caster_vars:MagMax(value)
  if not value then
    return self.max_mana
  end
end

function caster_vars:Alignement(value)
  if not value then
    return self.alignment or 0
  end
end

function caster_vars:Reputation(value)
  if not value then
    return self.reputation or 0
  end
end

function caster_vars:Gold(value)
  if not value then
    return self.gold or 0
  end
end

function caster_vars:Lvl(value)
  if not value then
    return self.level or 0
  end
end

function caster_vars:CurrentXP(value)
  if not value then
    return self.xp or 0
  end
end

function caster_vars:Dommage(value)
  if not value then
    return 0
  end
end

function caster_vars:HandDom(value)
  if not value then
    return 0
  end
end

function caster_vars:IndOff(value)
  if not value then
    local class_data = server.project.classes[self.class]
    return class_data and class_data.off_index or 0
  end
end

function caster_vars:IndDef(value)
  if not value then
    local class_data = server.project.classes[self.class]
    return class_data and class_data.def_index or 0
  end
end

function caster_vars:IndPui(value)
  if not value then
    local class_data = server.project.classes[self.class]
    return class_data and class_data.pow_index or 0
  end
end

function caster_vars:IndVit(value)
  if not value then
    local class_data = server.project.classes[self.class]
    return class_data and class_data.health_index or 0
  end
end

function caster_vars:IndMag(value)
  if not value then
    local class_data = server.project.classes[self.class]
    return class_data and class_data.mag_index or 0
  end
end

-- target var accessor definitions, map of id => function
-- function(target, value): should return a number or a string on get mode
--- value: passed string expression (after substitution) on set mode (nil on get mode)

local target_vars = {}

function target_vars:Vie(value)
  if value then
    -- effect
    value = utils.computeExpression(value) or 0
    local delta = value-self.health
    if delta > 0 then self:emitHint({{0,1,0}, utils.fn(delta)})
    elseif delta < 0 then self:broadcastPacket("damage", delta) end

    self:setHealth(value)
  else
    return self.health
  end
end

function target_vars:Attaque(value)
  if not value then
    return self.ch_attack
  end
end

function target_vars:Defense(value)
  if not value then
    return self.ch_defense
  end
end

function target_vars:Bloque(value)
  if not value then
    return 0
  end
end

function target_vars:Dommage(value)
  if not value then
    return 0
  end
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

  -- self.charaset {.path, .x, .y, .w, .h, .is_skin}
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
      self.move_time = clock()

      if self.move_task then self.move_task:remove() end
      if self.move_final_task then self.move_final_task:remove() end

      self.move_task = itask(1/cfg.tickrate, function()
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
      self.move_task:remove()
      self.move_task = nil

      -- final teleport
      self.move_final_task = task(0.25, function()
        self:teleport(self.x, self.y) -- end position
      end)
    end
  end
end

-- (async)
-- blocking: if passed/true, async and wait until it reaches the destination
function LivingEntity:moveToCell(cx, cy, blocking)
  local r
  if blocking then r = async() end

  -- basic implementation
  local dx, dy = cx*16-self.x, cy*16-self.y
  local speed = LivingEntity.pixelSpeed(self.speed) -- pixels per second
  self:setOrientation(LivingEntity.vectorOrientation(dx,dy))
  self:broadcastPacket("move_to_cell", {cx = cx, cy = cy, speed = speed})

  local dist = math.sqrt(dx*dx+dy*dy)
  local duration = dist/speed
  local time = clock()
  local x, y = self.x, self.y

  if self.move_task then self.move_task:remove() end

  self.move_task = itask(1/cfg.tickrate, function()
    local progress = (clock()-time)/duration
    if progress <= 1 then
      self.x = utils.lerp(x, cx*16, progress)
      self.y = utils.lerp(y, cy*16, progress)
      self:updateCell()
    else -- end
      self:teleport(cx*16, cy*16)
      self.move_task:remove()
      self.move_task = nil

      if blocking then
        r()
      end
    end
  end)

  if blocking then r:wait() end
end

-- action: string
--- "attack"
--- "defend"
--- "cast"
--- "use"
function LivingEntity:act(action, duration)
  if not self.acting then
    self.acting = action

    if action == "attack" then
      -- attack check
      local client = (class.is(self, Client) and self or self.client)
      local entities = self:raycastEntities(1)
      for _, entity in ipairs(entities) do
        if class.is(entity, LivingEntity) and (not entity.client or entity.client == client) then
          if entity:onAttack(self) then break end
        end
      end
    end

    -- TODO: defend effect

    -- do animation
    self:broadcastPacket("act", {self.acting, duration})
    task(duration, function() self.acting = false end)
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

-- apply spell (self is target)
-- caster: spell caster (LivingEntity)
-- spell: spell data
function LivingEntity:applySpell(caster, spell)
  local CE, ES = utils.computeExpression, self.spellExpressionSubstitution
  local area = CE(ES(self, caster, spell.area_expr)) or 0
  local aggro = CE(ES(self, caster, spell.aggro_expr)) or 0
  local duration = CE(ES(self, caster, spell.duration_expr)) or 1
  local hit = CE(ES(self, caster, spell.hit_expr)) or 1

  if hit > 0 then -- success
    -- audio/visual effects
    if #spell.set > 0 then
      self:emitAnimation(string.sub(spell.set, 9), -- remove Chipset\ part
        spell.x, spell.y, spell.w, spell.h, spell.anim_duration*0.03, spell.opacity/255)
    end
    if #spell.sound > 0 then self:emitSound(string.sub(spell.sound, 7)) end -- remove Sound\ part

    -- instructions
    self:spellExecuteInstructions(caster, spell.effect_expr)
  else
    self:damage(nil) -- miss
  end
end

-- process the string to substitute all spell language patterns (self is target)
-- caster: spell caster (LivingEntity)
-- return processed string
function LivingEntity:spellExpressionSubstitution(caster, str)
  local pat = LivingEntity.spell_patterns

  -- variable functions "%func(...)%"
  str = utils.gsub(str, pat.vfunction, function(id, content)
    local f = spell_vfunctions[id]
    if f then
      -- process function arguments
      local args = utils.split(content, ",")
      for i=1,#args do
        args[i] = self:spellExpressionSubstitution(caster, args[i])
      end
      return f(self, unpack(args))
    else print("spell: variable function \""..id.."\" not implemented") end
  end)

  -- caster vars
  str = string.gsub(str, pat.caster_var, function(id)
    -- check for client variable
    local v_id = string.match(id, "Variable%[(%d+)%]")
    if v_id then
      return class.is(caster, Client) and caster:getVariable("var", tonumber(v_id)) or 0
    else -- regular variable
      local f = caster_vars[id]
      if f then return f(caster)
      else print("spell: caster variable \""..id.."\" not implemented") end
    end
  end)

  -- target vars
  str = string.gsub(str, pat.target_var, function(id)
    local f = target_vars[id]
    if f then return f(self)
    else print("spell: target variable \""..id.."\" not implemented") end
  end)

  return str
end

-- execute spell instructions (self is target)
-- caster: spell caster (LivingEntity)
function LivingEntity:spellExecuteInstructions(caster, str)
  local pat = LivingEntity.spell_patterns

  local spells = {}
  local instructions = utils.split(str, ";")
  for i, instruction in ipairs(instructions) do
    -- spell instruction
    local spell = string.match(instruction, pat.spell_ins)
    if spell then table.insert(spells, spell); break end

    -- assignment
    local lhs, rhs = string.match(instruction, pat.assignment_ins)
    if lhs then
      -- compute rhs
      local rhs = self:spellExpressionSubstitution(caster, rhs)

      -- parse lhs var type and id
      local lhs_type, lhs_id
      lhs_id = string.match(lhs, pat.caster_var)
      if lhs_id then lhs_type = "caster"
      else
        lhs_id = string.match(lhs, pat.target_var)
        if lhs_id then lhs_type = "target" end
      end

      -- assignment
      if lhs_type == "caster" then
        -- check for client variable
        local v_id = string.match(id, "Variable%[(%d+)%]")
        if v_id then
          if class.is(caster, Client) then
            caster:setVariable("var", tonumber(v_id), utils.computeExpression(rhs) or 0)
          end
        else -- regular variable
          local f = caster_vars[id]
          if f then f(caster, rhs)
          else print("spell: caster variable \""..id.."\" not implemented") end
        end
      elseif lhs_type == "target" then
        local f = target_vars[lhs_id]
        if f then f(self, rhs)
        else print("spell: target variable \""..id.."\" not implemented") end
      end
    end
  end

  -- apply spells
  for _, name in pairs(spells) do
    local spell = server.project.spells[server.project.spells_by_name[name]]
    if spell then self:applySpell(caster, spell)
    else print("spell: spell \""..name.."\" not found") end
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

-- charaset: {.path, .x, .y, .w, .h, .is_skin}
--- x,y: atlas origin
--- w,h: cell dimensions
--- is_skin: if true, use remote skin repository instead of resources
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
