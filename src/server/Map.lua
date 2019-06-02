
local Map = class("Map")

-- STATICS

-- return list of x_low, x_high, y_low, y_high... from the tileset for each map tile (or nil)
function Map.loadTileData(id)
  local file, err = io.open("resources/maps/"..id..".map")
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
  end
end

-- METHODS

function Map:__construct(server, id)
  self.server = server
  self.id = id

  -- load map data
  self.w = 10
  self.h = 10
  self.tileset = "test.png"
  self.tiledata = Map.loadTileData(id)
  if not self.tiledata then
    print("error loading tiledata for map \""..self.id.."\"")
  end
end

return Map
