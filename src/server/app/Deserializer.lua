-- https://github.com/ImagicTheCat/SlayersOnlineRE
-- MIT license (see LICENSE, src/server/main.lua or src/client/main.lua)

local struct = require("struct")
local iconv = require("iconv")
local utils = require("app.utils")

local Deserializer = class("Deserializer")

-- STATICS

Deserializer.string_conv = iconv.new("UTF-8", "ISO-8859-1")

function Deserializer.readString(file, padding_size)
  local str = Deserializer.string_conv:iconv(struct.unpack("B c0", file:read(1+padding_size)))
  return str
end

local MAP_TYPES = {
  [0] = "safe",
  "PvE",
  "PvP",
  "PvE-PvP",
  "PvP-noreput",
  "PvP-noreput-pot"
}

local MAP_EFFECTS = {
  [0] = "none",
  "dark-cave",
  "night",
  "heat",
  "rain",
  "snow",
  "fog"
}

-- return map {}
function Deserializer.readProjectEntry(file)
  local map = {}
  map.name = Deserializer.readString(file, 50)
  local type, effect = struct.unpack("BB", file:read(2))
  map.type = MAP_TYPES[type]
  map.effect = MAP_EFFECTS[effect]
  map.background = Deserializer.readString(file, 50)
  map.music = Deserializer.readString(file, 50)
  map.tileset = Deserializer.readString(file, 50)
  map.width, _, map.height = struct.unpack("BBB", file:read(3))
  file:seek("cur", 52)
  map.disconnect_respawn = (struct.unpack("B", file:read(1)) > 0)
  map.si_v, map.v_c = struct.unpack("<i2 i2", file:read(4))
  map.svar, map.sval = Deserializer.readString(file, 255), Deserializer.readString(file, 255)
  return map
end

function Deserializer.readProjectClassEntry(file)
  local cls = {}
  cls.name = Deserializer.readString(file, 50)
  cls.attack_sound = Deserializer.readString(file, 255)
  cls.hurt_sound = Deserializer.readString(file, 255)
  cls.focus_sound = Deserializer.readString(file, 255)
  file:seek("cur",1)
  cls.max_strength, cls.max_dexterity, cls.max_constitution, cls.max_magic = struct.unpack("<i4 i4 i4 i4", file:read(4*4))
  cls.max_level, cls.level_up_points = struct.unpack("<i4 i4", file:read(2*4))
  cls.strength, cls.dexterity, cls.constitution, cls.magic = struct.unpack("<i4 i4 i4 i4", file:read(4*4))
  cls.off_index, cls.def_index, cls.pow_index, cls.health_index, cls.mag_index = struct.unpack("<I2 I2 I2 I2 I2", file:read(5*2))
  file:seek("cur",2)
  return cls
end

local OBJECT_TYPES = {
  [0] = "usable",
  "one-handed-weapon",
  "two-handed-weapon",
  "helmet",
  "armor",
  "shield",
  "quest-item",
  "magic-book"
}

-- return object {}
--- usable_class: index (1-based)
function Deserializer.readProjectObjectEntry(file)
  local obj = {}
  obj.name = Deserializer.readString(file, 50)
  obj.description = Deserializer.readString(file, 50)
  obj.usable_class, obj.type, obj.spell = struct.unpack("<I2 I2 I2", file:read(2*3))
  obj.type = OBJECT_TYPES[obj.type]
  obj.price = struct.unpack("<I4", file:read(4))
  obj.mod_strength, obj.mod_dexterity, obj.mod_constitution, obj.mod_magic = struct.unpack("<I2 I2 I2 I2", file:read(2*4))
  obj.mod_attack_a, obj.mod_attack_b, obj.mod_defense = struct.unpack("<i2 i2 i2", file:read(2*3))
  file:seek("cur", 2)
  obj.mod_hp, obj.mod_mp = struct.unpack("<i4 i4", file:read(4*2))
  obj.req_strength, obj.req_dexterity, obj.req_constitution, obj.req_magic, obj.req_level = struct.unpack("<I2 I2 I2 I2 I2", file:read(2*5))
  file:seek("cur", 2)
  return obj
end


local MOB_TYPES = {
  [0] = "defensive",
  "aggressive",
  "static",
  "breakable"
}

function Deserializer.readProjectMobEntry(file)
  local mob = {}
  mob.name = Deserializer.readString(file, 50)
  mob.type, mob.level = struct.unpack("BB", file:read(2))
  mob.type = MOB_TYPES[mob.type]
  mob.charaset = Deserializer.readString(file, 100)
  mob.attack_sound = Deserializer.readString(file, 100)
  mob.hurt_sound = Deserializer.readString(file, 100)
  mob.focus_sound = Deserializer.readString(file, 100)
  file:seek("cur", 1)
  mob.speed, mob.w, mob.h = struct.unpack("<I2 I2 I2", file:read(2*3))
  mob.attack, mob.defense, mob.damage = struct.unpack("<I2 I2 I2", file:read(2*3))
  file:seek("cur", 2)
  mob.health = struct.unpack("<I4", file:read(4))
  mob.xp_min, mob.xp_max, mob.gold_min, mob.gold_max = struct.unpack("<I4 I4 I4 I4", file:read(4*4))
  mob.loot_object, mob.loot_chance = struct.unpack("<I2 I2", file:read(2*2))
  mob.var_id, mob.var_increment = struct.unpack("<i2 I2", file:read(2*2))
  mob.spells = {}
  -- 10 spells id
  for i=1,10 do
    mob.spells[i] = {struct.unpack("<I2", file:read(2))}
  end
  -- 10 spells number
  for i=1,10 do
    mob.spells[i][2] = struct.unpack("<I2", file:read(2))
  end
  mob.obstacle = (struct.unpack("B", file:read(1)) > 0)
  file:seek("cur", 3)
  return mob
end

local SPELL_TYPES = {
  [0] = "unique",
  "fireball",
  "AoE",
  "teleport",
  "resurrect",
  "jump-attack",
  "sneak-attack"
}

local SPELL_TARGET_TYPES = {
  [0] = "player",
  "mob-player",
  "self",
  "around"
}

local SPELL_POSITION_TYPES = {
  [0] = "above",
  "dynamic"
}

-- return spell {}
function Deserializer.readProjectSpellEntry(file)
  local spell = {}
  spell.name = Deserializer.readString(file, 50)
  spell.description = Deserializer.readString(file, 50)
  spell.set = Deserializer.readString(file, 255)
  spell.sound = Deserializer.readString(file, 255)
  spell.area_expr = Deserializer.readString(file, 255)
  spell.aggro_expr = Deserializer.readString(file, 255)
  spell.duration_expr = Deserializer.readString(file, 255)
  spell.hit_expr = Deserializer.readString(file, 255)
  spell.effect_expr = Deserializer.readString(file, 255)
  file:seek("cur", 2)
  spell.x, spell.y, spell.w, spell.h, spell.opacity = struct.unpack("<i4 i4 I4 I4 I4", file:read(4*5))
  spell.position_type, spell.anim_duration = struct.unpack("<I2 I2", file:read(2*2))
  spell.position_type = SPELL_POSITION_TYPES[spell.position_type]
  spell.usable_class, spell.type = struct.unpack("<I2 I2", file:read(2*2))
  spell.mp, spell.req_level, spell.target_type, spell.cast_duration = struct.unpack("<I4 I2 I2 I2", file:read(4+2*3))
  spell.type = SPELL_TYPES[spell.type]
  spell.target_type = SPELL_TARGET_TYPES[spell.target_type]
  file:seek("cur", 2)
  return spell
end

local EVENT_ANIMATION_TYPES = utils.bimap{
  [0] = "static",
  "static-character",
  "character-random",
  "visual-effect",
  "character-follow"
}

Deserializer.EVENT_ANIMATION_TYPES = EVENT_ANIMATION_TYPES

local EVENT_POSITION_TYPES = {
  [0] = "dynamic",
  "front",
  "back"
}

function Deserializer.readMapEventEntry(file)
  local event = {}
  event.name = Deserializer.readString(file, 50)
  event.set = Deserializer.readString(file, 256)
  event.x = struct.unpack("B", file:read(1))
  file:seek("cur", 3)
  event.y = struct.unpack("B", file:read(1))
  file:seek("cur", 3)
  event.set_x = struct.unpack("<I2", file:read(2))
  file:seek("cur", 2)
  event.set_y = struct.unpack("<I2", file:read(2))
  file:seek("cur", 2)
  event.active = struct.unpack("B", file:read(1)) > 0
  event.obstacle = struct.unpack("B", file:read(1)) > 0
  event.transparent = struct.unpack("B", file:read(1)) > 0
  event.follow = struct.unpack("B", file:read(1)) > 0
  event.animation_type = EVENT_ANIMATION_TYPES[struct.unpack("B", file:read(1))]
  file:seek("cur", 1)
  event.animation_mod = struct.unpack("B", file:read(1)) -- (follow stop, anim top-down, look at)
  file:seek("cur", 1)
  event.speed = struct.unpack("b", file:read(1))
  file:seek("cur", 1)
  event.w = struct.unpack("<I2", file:read(2))
  event.h = struct.unpack("<I2", file:read(2))
  event.position_type = EVENT_POSITION_TYPES[struct.unpack("B", file:read(1))]
  file:seek("cur", 1)
  event.animation_number = struct.unpack("<I2", file:read(2)) -- (animation number, anim left-right)
  file:seek("cur", 2)
  return event
end

-- return area {}
--- type: -1 no spawn, >= 0 mob id
function Deserializer.readMapMobAreaEntry(file)
  local area = {}
  area.x1, area.x2, area.y1, area.y2 = struct.unpack("<I4 I4 I4 I4", file:read(4*4))
  file:seek("cur", 4)
  area.max_mobs, area.type = struct.unpack("<I4 i4", file:read(4*2))
  file:seek("cur", 4)
  area.spawn_speed = struct.unpack("<I4", file:read(4))
  area.server_var = Deserializer.readString(file, 255)
  area.server_var_expr = Deserializer.readString(file, 255)
  return area
end

function Deserializer.loadProject(name)
  -- open files
  local file_prj = io.open("resources/project/"..name..".prj", "rb")
  local file_cls = io.open("resources/project/"..name..".cls", "rb")
  local file_mag = io.open("resources/project/"..name..".mag", "rb")
  local file_mon = io.open("resources/project/"..name..".mon", "rb")
  local file_obj = io.open("resources/project/"..name..".obj", "rb")

  if file_prj and file_cls and file_mag and file_mon and file_obj then
    local prj = {}
    
    -- read map entries
    prj.maps = {}
    prj.map_count = file_prj:seek("end")/778 -- 778 bytes per entry

    file_prj:seek("set")

    for i=1,prj.map_count do
      local map = Deserializer.readProjectEntry(file_prj)
      map.index = i
      prj.maps[map.name] = map
    end

    file_prj:close()

    -- read class entries
    prj.classes = {}
    prj.class_count = file_cls:seek("end")/872 -- 872 bytes per entry

    file_cls:seek("set")

    for i=1,prj.class_count do
      local class = Deserializer.readProjectClassEntry(file_cls)
      table.insert(prj.classes, class)
    end

    file_cls:close()

    -- read object entries
    prj.objects = {}
    prj.objects_by_name = {} -- map of name => id
    prj.object_count = file_obj:seek("end")/148 -- 148 bytes per entry

    file_obj:seek("set")

    for i=1,prj.object_count do
      local object = Deserializer.readProjectObjectEntry(file_obj)
      table.insert(prj.objects, object)
      prj.objects_by_name[object.name] = i -- index by name
    end

    file_obj:close()

    -- read mob entries
    prj.mobs = {}
    prj.mobs_by_name = {} -- map of name => id
    prj.mob_count = file_mon:seek("end")/544 -- 544 bytes per entry

    file_mon:seek("set")

    for i=1,prj.mob_count do
      local mob = Deserializer.readProjectMobEntry(file_mon)
      table.insert(prj.mobs, mob)
      prj.mobs_by_name[mob.name] = i -- index by name
    end

    file_mon:close()

    -- read spell entries
    prj.spells = {}
    prj.spells_by_name = {} -- map of name => id
    prj.spell_count = file_mag:seek("end")/1936 -- 1936 bytes per entry

    file_mag:seek("set")

    for i=1,prj.spell_count do
      local spell = Deserializer.readProjectSpellEntry(file_mag)
      table.insert(prj.spells, spell)
      prj.spells_by_name[spell.name] = i
    end

    file_mag:close()

    return prj
  else
    print("error loading project \""..name.."\"")
  end
end

-- id: tileset id
-- return list of passable bools (for each tile, column per column/y first), first part is the low layer, second part is the high layer
function Deserializer.loadTilesetPassableData(id)
  local file = io.open("resources/project/Chipset/"..id..".blk", "rb")
  if file then
    local data = {}

    local size = file:seek("end")
    file:seek("set")

    for i=1,size do
      data[i] = (struct.unpack("B", file:read(1)) > 0)
    end

    file:close()

    return data
  else
    print("error loading passable data for tileset \""..id.."\"")
  end
end

-- return list of x_low, x_high, y_low, y_high... from the tileset for each map tile (or nil)
function Deserializer.loadMapTiles(id)
  local file = io.open("resources/project/Maps/"..id..".map", "r")
  if file then
    local tiledata = {}

    local line
    repeat
      line = file:read("*l")
      if line then
        table.insert(tiledata, tonumber(line))
      end
    until not line

    file:close()

    return tiledata
  else
    print("error loading tiledata for map \""..id.."\"")
  end
end

-- can return nil
function Deserializer.loadMapMobAreas(id)
  local file = io.open("resources/project/Maps/"..id..".zon", "rb")
  if file then
    local count = file:seek("end")/548 -- 548 bytes per entry
    file:seek("set")

    local areas = {}

    for i=1,count do
      local area = Deserializer.readMapMobAreaEntry(file)
      table.insert(areas, area)
    end

    file:close()

    return areas
  end
end

function Deserializer.loadMapEvents(id)
  local f_evn = io.open("resources/project/Maps/"..id..".evn", "rb")
  local f_ev0 = io.open("resources/project/Maps/"..id..".ev0", "r")
  if f_evn and f_ev0 then
    -- load
    local events = {}
    local events_by_coords = {}
    -- evn
    local count = f_evn:seek("end")/344 -- 344 bytes per event entry
    f_evn:seek("set")
    -- read pages
    for i=1,count do
      local page = Deserializer.readMapEventEntry(f_evn)
      page.conditions = {}
      page.commands = {}
      -- reference per coords
      local key = page.x..","..page.y
      local event = events_by_coords[key]
      if not event then -- create event
        event = {
          x = page.x, 
          y = page.y,
          pages = {}
        }
        events_by_coords[key] = event
        table.insert(events, event)
      end
      table.insert(event.pages, page)
    end
    -- ev0
    local line = f_ev0:read("*l")
    while line do
      local ltype, x, y, page, index, instruction =
        string.match(line, "^(..)(%d+),(%d+),(%d+),(%d+)=(.*)\r?$")
      instruction = Deserializer.string_conv:iconv(instruction)
      if ltype then -- match
        local event = events_by_coords[x..","..y] -- get events by coords
        if event then
          local page = event.pages[tonumber(page)+1] -- get event by page
          if page then
            if ltype == "EV" then -- event commands
              page.commands[tonumber(index)+1] = instruction
            elseif ltype == "CD" then -- event conditions
              page.conditions[tonumber(index)+1] = instruction
            end
          end
        end
      end
      line = f_ev0:read("*l")
    end
    f_evn:close(); f_ev0:close()
    return events
  end
end

return Deserializer
