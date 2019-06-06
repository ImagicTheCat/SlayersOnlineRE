local Luaoop = require("Luaoop")
class = Luaoop.class
local Client = require("Client")

local cfg = require("config")

function love.threaderror(thread, err)
  print("thread error: "..err)
end

function love.load()
  love.keyboard.setKeyRepeat(true)
  love.graphics.setDefaultFilter("nearest", "nearest")
  client = Client(cfg) -- global
end

function love.update(dt)
  client:tick(dt)
end

function love.draw()
  client:draw()
end

function love.keypressed(key, scancode, isrepeat)
  client:onKeyPressed(key, scancode, isrepeat)
end

function love.keyreleased(key, scancode)
  client:onKeyReleased(key, scancode)
end

function love.textinput(data)
  client:onTextInput(data)
end

function love.resize(w, h)
  client:onResize(w, h)
end

function love.quit()
  client:close()
end
