-- execute inside repository directory
-- will produce repository.manifest file
local out = io.open("repository.manifest", "w")

local find = io.popen("find . -type f -exec md5sum {} \\;", "r")
local line
repeat
  line = find:read("*l")

  if line then
    local hash, path = string.match(line, "^(%x-)%s+%./(.*)$")
    if hash then
      local entry = path.."="..hash.."\n"
      out:write(entry)
    end
  end
until not line

find:close()
out:close()
