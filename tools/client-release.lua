-- Lua 5.1
-- Extract git HEAD hash as client version.
local sh = require "shapi"
local content = sh:__in("../src/shared/app/client_version.lua")()
content = content:gsub("(return \").-(\")", "%1"..sh:git("rev-parse", "HEAD").."%2")
sh:__str_in(content):__out("../src/shared/app/client_version.lua")()
