local enet = require("enet")

local Client = class("Client")

function Client:__construct(cfg)
  self.cfg = cfg

  self.host = enet.host_create()
  self.host:connect(self.cfg.remote)
end

function Client:tick(dt)
  -- net
  local event = self.host:service()
  while event do
    print(event.type, event.peer)

    event = self.host:service()
  end
end

function Client:draw()
end

return Client
