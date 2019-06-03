local Luaoop = require("Luaoop")
class = Luaoop.class
local Client = require("Client")

local cfg = require("config")

local client

function love.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  client = Client(cfg)
end

function love.update(dt)
  client:tick(dt)
end

function love.draw()
  client:draw()
end

function love.keypressed(key, scancode)
  if scancode == "w" then client:setOrientation(0)
  elseif scancode == "d" then client:setOrientation(1)
  elseif scancode == "s" then client:setOrientation(2)
  elseif scancode == "a" then client:setOrientation(3) end
end
