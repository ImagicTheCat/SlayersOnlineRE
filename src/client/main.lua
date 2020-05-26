-- Slayers Online RE - a rewrite from scratch of Slayers Online
-- Copyright (c) 2019-2020 ImagicTheCat

local Luaoop = require("Luaoop")
class = Luaoop.class
local Luaseq = require("Luaseq")
async = Luaseq.async
local Scheduler = require("ELScheduler")

local Client = require("Client")

local cfg = require("config")

function love.threaderror(thread, err)
  print("thread error: "..err)
end

function love.load()
  scheduler = Scheduler(love.timer.getTime())
  client = Client(cfg) -- global
end

function love.update(dt)
  scheduler:tick(love.timer.getTime())
  client:tick(dt)
end

function love.draw() client:draw() end
function love.keypressed(...) client:onKeyPressed(...) end
function love.keyreleased(...) client:onKeyReleased(...) end
function love.touchpressed(...) client:onTouchPressed(...) end
function love.touchreleased(...) client:onTouchReleased(...) end
function love.gamepadpressed(...) client:onGamepadPressed(...) end
function love.gamepadreleased(...) client:onGamepadReleased(...) end
function love.gamepadaxis(...) client:onGamepadAxis(...) end
function love.textinput(...) client:onTextInput(...) end
function love.wheelmoved(...) client:onWheelMoved(...) end
function love.resize(...) client:onResize(...) end
function love.quit() client:close() end
