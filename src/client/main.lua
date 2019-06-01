local Luaoop = require("Luaoop")
class = Luaoop.class
local Client = require("Client")

local cfg = require("config")

local client

function love.load()
  client = Client(cfg)
end

function love.update(dt)
  client:tick(dt)
end

function love.draw()
  client:draw()
end
