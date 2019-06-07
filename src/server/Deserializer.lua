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
  end
end

return Deserializer
