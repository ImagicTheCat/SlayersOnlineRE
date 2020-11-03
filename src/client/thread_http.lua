-- HTTP request thread
local http = require("socket.http")

local cin, cout = ...
while true do
  local req = cin:demand()
  if not req[1] then return end -- exit
  -- process
  local body, code = http.request(req[1])
  if body and code == 200 then
    cout:push({love.data.newByteData(body)})
  else
    cout:push({})
  end
end
