-- HTTP request thread
local http = require("socket.http")

local channel_in = love.thread.getChannel("http.in")
local channel_out = love.thread.getChannel("http.out")

local running = true
while running do
  local data = channel_in:demand()
  if not data.url then -- exit
    running = false
  else
    local body, code = http.request(data.url)
    if body and code == 200 then
      channel_out:push({body = body})
    else
      channel_out:push({})
    end
  end
end
