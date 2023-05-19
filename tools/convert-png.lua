local DIR = arg[0]:match("^(.*)/.-$") or "."
local lib = dofile(DIR.."/lib.lua")
lib.setDIR(DIR)

lib.convert_png(...)
