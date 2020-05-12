-- Script to convert indexed color PNG without alpha to RGB with alpha (based
-- on the first indexed color for transparency).
-- dependencies:
--- LuaJIT (Lua 5.1)
--- print_palette program
--- lua-vips
-- params: <input path> <output path>

local vips = require("vips")
local in_path, out_path = ...
if not in_path or not out_path then error("missing <input path> <output path>") end

-- find first palette color

local p = io.popen("./print_palette \""..in_path.."\"")
local out = p:read("*a")
p:close()

local r,g,b = string.match(out, "(%d+) (%d+) (%d+)")
r,g,b = tonumber(r), tonumber(g), tonumber(b)

-- convert PNG
local in_img = vips.Image.new_from_file(in_path)
if r and in_img:bands() == 3 then
  in_img = in_img:bandjoin({255}) -- add alpha channel
  -- replace first indexed color by transparency
  local out_img = in_img:equal({r,g,b,255}):bandand():ifthenelse({r,g,b,0}, in_img)
  out_img:write_to_file(out_path)
else -- identity
  in_img:write_to_file(out_path)
end
