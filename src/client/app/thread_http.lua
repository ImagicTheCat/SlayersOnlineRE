-- HTTP request thread
local http = require("socket.http")
local utils = require("app.lib.utils")

local cin, cout = ...
while true do
  local req = cin:demand()
  if not req[1] then return end -- exit
  -- process
  local body, code = http.request(req[1])
  if body and code == 200 then
    cout:push(utils.pack(love.data.newByteData(body)))
  else
    cout:push(utils.pack(nil, code))
  end
end
