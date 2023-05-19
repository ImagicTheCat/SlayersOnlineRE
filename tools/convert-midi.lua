local DIR = arg[0]:match("^(.*)/.-$") or "."
local lib = dofile(DIR.."/lib.lua")
lib.setDIR(DIR)

local sf_path = os.getenv("SOUNDFONT_PATH") or DIR.."/gm.sf2"
local in_path, out_path = ...
lib.convert_midi(in_path, out_path, sf_path)
