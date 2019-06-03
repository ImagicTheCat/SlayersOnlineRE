local Luaoop = require("Luaoop")
class = Luaoop.class
local Client = require("Client")

local cfg = require("config")

local client

function love.threaderror(thread, err)
  print("thread error: "..err)
end

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
  if scancode == "w" then client:pressOrientation(0)
  elseif scancode == "d" then client:pressOrientation(1)
  elseif scancode == "s" then client:pressOrientation(2)
  elseif scancode == "a" then client:pressOrientation(3)
  elseif scancode == "space" then client:inputAttack() end
end

function love.keyreleased(key, scancode)
  if scancode == "w" then client:releaseOrientation(0)
  elseif scancode == "d" then client:releaseOrientation(1)
  elseif scancode == "s" then client:releaseOrientation(2)
  elseif scancode == "a" then client:releaseOrientation(3) end
end
