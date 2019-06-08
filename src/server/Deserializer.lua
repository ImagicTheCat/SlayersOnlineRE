local struct = require("struct")

local Deserializer = class("Deserializer")

-- STATICS

function Deserializer.readString(file, padding_size)
  local size = struct.unpack("B", file:read(1))
  local str = struct.unpack("c"..size, file:read(size))
  -- padding
  file:seek("cur", padding_size-size)
  return str
end

function Deserializer.readProjectEntry(file)
  local map = {}

  map.name = Deserializer.readString(file, 50)
  map.mtype, map.effect = struct.unpack("BB", file:read(2))
  map.background = Deserializer.readString(file, 50)
  map.music = Deserializer.readString(file, 50)
  map.tileset = Deserializer.readString(file, 50)
  map.width, _, map.height = struct.unpack("BBB", file:read(3))
  file:seek("cur", 51)
  map.death = struct.unpack("B", file:read(1))
  map.si_v, map.v_c = struct.unpack("HH", file:read(4))
  map.svar, map.sval = Deserializer.readString(file, 255), Deserializer.readString(file, 255)

  file:seek("cur", 1)

  return map
end

function Deserializer.readMapEventEntry(file)
  local event = {}

  event.name = Deserializer.readString(file, 50)
  event.set = Deserializer.readString(file, 256)
  event.x = struct.unpack("B", file:read(1))
  file:seek("cur", 3)
  event.y = struct.unpack("B", file:read(1))
  file:seek("cur", 3)
  event.set_x = struct.unpack("<H", file:read(2))
  file:seek("cur", 2)
  event.set_y = struct.unpack("<H", file:read(2))
  file:seek("cur", 2)
  event.active = struct.unpack("B", file:read(1))
  event.obstacle = struct.unpack("B", file:read(1))
  event.transparent = struct.unpack("B", file:read(1))
  event.follow = struct.unpack("B", file:read(1))
  event.animation_type = struct.unpack("B", file:read(1))
  file:seek("cur", 1)
  event.animation_mod = struct.unpack("B", file:read(1))
  file:seek("cur", 1)
  event.speed = struct.unpack("B", file:read(1))
  file:seek("cur", 1)
  event.w = struct.unpack("<H", file:read(2))
  event.h = struct.unpack("<H", file:read(2))
  event.position_type = struct.unpack("B", file:read(1))
  file:seek("cur", 1)
  event.animation_number = struct.unpack("<H", file:read(2))

  file:seek("cur", 2)

  return event
end

function Deserializer.loadProject(name)
  -- .prj
  local file, err = io.open("resources/project/"..name..".prj", "rb")
  if file then
    local prj = {}
    
    -- read map entries
    prj.maps = {}
    prj.map_count = file:seek("end")/778 -- 778 bytes per map entry

    file:seek("set")

    for i=1,prj.map_count do
      local map = Deserializer.readProjectEntry(file)
      prj.maps[map.name] = map
    end

    return prj
  else
    print("error loading project \""..name.."\"")
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

    return tiledata
  else
    print("error loading tiledata for map \""..id.."\"")
  end
end

function Deserializer.loadMapEvents(id)
  local f_evn = io.open("resources/project/Maps/"..id..".evn", "rb")
  local f_ev0 = io.open("resources/project/Maps/"..id..".ev0", "r")

  if f_evn and f_ev0 then
    local events = {}
    local events_per_coords = {}

    -- evn
    local count = f_evn:seek("end")/344 -- 344 bytes per event entry
    f_evn:seek("set")
    
    for i=1,count do
      local event = Deserializer.readMapEventEntry(f_evn)
      table.insert(events, event)

      -- reference per coords
      local key = event.x..","..event.y
      local coords_events = events_per_coords[key]
      if not coords_events then
        coords_events = {}
        events_per_coords[key] = coords_events
      end

      event.conditions = {}
      event.commands = {}
      table.insert(coords_events, event)
    end

    -- ev0
    local line = f_ev0:read("*l")
    while line do
      local ltype,x,y,page,index,instruction = string.match(line, "(..)(%d+),(%d+),(%d+),(%d+)=(.*)")

      if ltype then -- match
        local coords_events = events_per_coords[x..","..y] -- get events by coords
        if coords_events then
          local event = coords_events[tonumber(index)+1] -- get event by page
          if event then
            if ltype == "EV" then -- event commands
              table.insert(event.commands, instruction)
            elseif ltype == "CD" then -- event conditions
              table.insert(event.conditions, instruction)
            end
          end
        end
      end

      line = f_ev0:read("*l")
    end

    return events
  else
    print("error loading events for map \""..id.."\"")
  end
end

return Deserializer
