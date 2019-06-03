-- HTTP request thread
local http = require("socket.http")

local channel_in = love.thread.getChannel("http.in")
local channel_out = love.thread.getChannel("http.out")

local running = true
while running do
  local id, url = unpack(channel_in:demand())
  if id < 0 then -- exit
    running = false
  else
    local body, code = http.request(url)
    if body and code == 200 then
      channel_out:push({id, body})
    else
      channel_out:push({id})
    end
  end
end
