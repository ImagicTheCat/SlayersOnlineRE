local enet = require("enet")

local Server = class("Server")

function Server:__construct(cfg)
  self.cfg = cfg

  -- register tick callback
  self.tick_task = itask(1/self.cfg.tickrate, function()
    self:tick()
  end)

  -- create host
  self.host = enet.host_create(self.cfg.host, self.cfg.max_clients)

  print("listening to \""..self.cfg.host.."\"...")
end

function Server:close()
  self.tick_task:remove()
  print("shutdown.")
end

function Server:tick()
  -- net
  local event = self.host:service()
  while event do
    print(event.type, event.peer)

    event = self.host:service()
  end
end

return Server
