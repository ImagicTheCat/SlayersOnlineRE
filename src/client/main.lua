local Luaoop = require("Luaoop")
class = Luaoop.class
local Luaseq = require("Luaseq")
async = Luaseq.async

local Client = require("Client")

local cfg = require("config")

function love.threaderror(thread, err)
  print("thread error: "..err)
end

function love.load()
  client = Client(cfg) -- global
end

function love.update(dt)
  client:tick(dt)
end

function love.draw()
  client:draw()
end

function love.keypressed(...)
  client:onKeyPressed(...)
end

function love.keyreleased(...)
  client:onKeyReleased(...)
end

function love.touchpressed(...)
  client:onTouchPressed(...)
end

function love.touchreleased(...)
  client:onTouchReleased(...)
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
