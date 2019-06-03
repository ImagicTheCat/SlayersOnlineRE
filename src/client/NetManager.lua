local IdManager = require("lib/IdManager")

local NetManager = class("NetManager")

function NetManager:__construct()
  -- create HTTP thread
  self.thread = love.thread.newThread("main_http.lua")
  self.thread:start()

  self.http_channel_in = love.thread.getChannel("http.in")
  self.http_channel_out = love.thread.getChannel("http.out")

  self.ids = IdManager()
  self.requests = {}
end

-- callback(data)
--- data: body data or nil on failure
function NetManager:request(url, callback)
  local id = self.ids:gen()

  self.requests[id] = callback
  self.http_channel_in:push({id, url})
end

function NetManager:tick(dt)
  local data = self.http_channel_out:pop()
  if data then
    local id, body = unpack(data)
    local callback = self.requests[id]
    self.ids:free(id)

    if callback then callback(body) end
  end
end

return NetManager
