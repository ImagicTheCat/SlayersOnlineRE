-- I/O/Compute thread
local sha2 = require("sha2")
local utils = require("lib.utils")

local cin, cout = ...
while true do
  local query = cin:demand()
  if not query[1] then return end -- exit
  -- process
  if query[1] == "read_file" then
    cout:push(utils.pack(love.filesystem.read("data", query[2])))
  elseif query[1] == "write_file" then
    cout:push(utils.pack(love.filesystem.write(query[2], query[3])))
  elseif query[1] == "md5" then
    cout:push(utils.pack(sha2.md5(query[2]:getString())))
  end
end
