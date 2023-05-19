-- Tool library

local vips = require "vips"
local sh = require "shapi"

local DIR

local M = {}

function M.setDIR(_DIR) DIR = _DIR end

-- Convert indexed color PNG without alpha to RGB with alpha (based
-- on the first indexed color for transparency).
function M.convert_png(in_path, out_path)
  if not in_path or not out_path then error("missing <input path> <output path>") end
  -- find first palette color
  local r, g, b = sh:__p(DIR.."/print_palette", in_path)():match("(%d+) (%d+) (%d+)")
  r, g, b = tonumber(r), tonumber(g), tonumber(b)
  -- convert PNG
  local in_img = vips.Image.new_from_file(in_path)
  if r and in_img:bands() == 3 then
    in_img = in_img:bandjoin{255} -- add alpha channel
    -- replace first indexed color by transparency
    local out_img = in_img:equal{r,g,b,255}:bandand():ifthenelse({r,g,b,0}, in_img)
    out_img:write_to_file(out_path)
  else
    sh:cp(in_path, out_path)()
  end
end

-- Convert midi file to ogg using a soundfont (ex: tools/gm.sf2 Windows GM).
function M.convert_midi(in_path, out_path, sf_path)
  assert(in_path and out_path, "missing in/out paths")
  assert(sf_path, "missing soundfont path")
  -- convert
  sh:__err("/dev/null"):fluidsynth("-q", "-F", out_path..".wav", sf_path, in_path)()
  sh:ffmpeg(
    "-v", "8",
    "-y", "-i", out_path..".wav", "-vn",
    "-c:a", "libvorbis", "-b:a", "128k",
    "-filter:a", "loudnorm", "-ar", 44100,
    out_path
  )()
  sh:rm(out_path..".wav")()
end

function M.md5sum(path)
  return sh:md5sum(path):cut("-d", " ", "-f", 1)()
end

return M
