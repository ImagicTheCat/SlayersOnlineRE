
local NetManager = class("NetManager")

function NetManager:__construct()
  -- create HTTP thread
  self.thread = love.thread.newThread("main_http.lua")
  self.thread:start()

  self.http_channel_in = love.thread.getChannel("http.in")
  self.http_channel_out = love.thread.getChannel("http.out")

  self.requests = {} -- list of requests (processed in ASC order)
end

-- callback(data)
--- data: body data or nil on failure
function NetManager:request(url, callback)
  table.insert(self.requests, {
    callback = callback,
    url = url
  })

  self.http_channel_in:push({url = url})
end

function NetManager:tick(dt)
  local data = self.http_channel_out:pop()
  if data then
    local request = table.remove(self.requests, 1)
    if request.callback then request.callback(data.body) end
  end
end

function NetManager:close()
  self.http_channel_in:push({})
end

return NetManager
