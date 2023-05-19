-- Update resource repository from SO project.
-- parameters: <project path> <repository path>
-- env: SOUNDFONT_PATH

local sh = require "shapi"
local ljuv = require "ljuv"
local lfs = require "lfs"
local async = require("Luaseq").async
local semaphore = require("Luaseq").semaphore
local msgpack = require "MessagePack"

local DIR = arg[0]:match("^(.*)/.-$") or "."
local CPU_COUNT = tonumber(sh:nproc()())
local UNITS = CPU_COUNT*2

local p_path, r_path = ...
assert(p_path and r_path, "missing project or repository path")
local sf_path = os.getenv("SOUNDFONT_PATH") or DIR.."/gm.sf2"

local pool = ljuv.loop:threadpool(CPU_COUNT, function(DIR)
  local I = dofile(DIR.."/lib.lua")
  I.setDIR(DIR)
  return I
end, DIR)

print "Update sounds: wav files..."
sh:rsync("-av", p_path.."/Sound/", "--include", "*/", "--include", "*.wav", "--exclude", "*", r_path.."/audio/"):__out(1)()

async(function()
  local sem = semaphore(UNITS)
  local function wait() for i=1,UNITS do sem:demand() end end
  local function refill() for i=1,UNITS do sem:supply() end end

  print "Update sounds: midi files..."
  for path in lfs.dir(p_path.."/Sound") do
    local base = path:match("(.+)%.mid")
    if base then
      local in_path = p_path.."/Sound/"..base..".mid"
      local out_path = r_path.."/audio/"..base..".ogg"
      print("convert "..in_path.."...")
      if lfs.attributes(in_path, "modification") > (lfs.attributes(out_path, "modification") or 0) then
        sem:demand()
        local function cb(ok, err)
          if not ok then io.stderr:write("error \""..in_path.."\": "..err.."\n") end
          sem:supply()
        end
        pool:call("convert_midi", cb, in_path, out_path, sf_path)
      end
    end
  end
  wait()
  refill()

  print "Update chipsets..."
  for path in lfs.dir(p_path.."/Chipset") do
    local base = path:match("(.+)%.png")
    if base then
      local in_path = p_path.."/Chipset/"..base..".png"
      local out_path = r_path.."/textures/sets/"..base..".png"
      print("convert "..in_path.."...")
      if lfs.attributes(in_path, "modification") > (lfs.attributes(out_path, "modification") or 0) then
        sem:demand()
        local function cb(ok, err)
          if not ok then io.stderr:write("error \""..in_path.."\": "..err.."\n") end
          sem:supply()
        end
        pool:call("convert_png", cb, in_path, out_path)
      end
    end
  end
  wait()
  refill()

  do
    print "Write index..."
    local index = {}
    for path in sh:find(r_path, "-type", "f", "-printf", "%P\n")():gmatch("[^\n]+") do
      sem:demand()
      local function cb(ok, hash_err)
        if not ok then
          io.stderr:write("error \""..path.."\": "..hash_err.."\n")
        else
          index[path] = hash_err
        end
        sem:supply()
      end
      pool:call("compute_md5", cb, r_path.."/"..path)
    end
    wait()

    local file = assert(io.open(r_path.."/repository.index", "w"))
    assert(file:write(msgpack.pack(index)))
    file:close()
  end

  pool:close()
end)

ljuv.loop:run()
