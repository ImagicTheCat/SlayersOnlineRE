-- https://github.com/ImagicTheCat/SlayersOnlineRE
-- MIT license (see LICENSE, src/server/main.lua or src/client/main.lua)
--[[
MIT License

Copyright (c) 2019 ImagicTheCat

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local Luaoop = require("Luaoop")
class = Luaoop.class
xtype = require("xtype")
local Luaseq = require("Luaseq")
async = Luaseq.async
local Scheduler = require("ELScheduler")

local Client = require("app.Client")
local cfg = require("config")

function love.threaderror(thread, err)
  print("thread error: "..err)
end

function love.load()
  if love.system.getOS() == "Android" then
    love.window.setMode(800, 600, {fullscreen = true, resizable = true, usedpiscale = false})
  end
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
function love.touchmoved(...) client:onTouchMoved(...) end
function love.touchreleased(...) client:onTouchReleased(...) end
function love.gamepadpressed(...) client:onGamepadPressed(...) end
function love.gamepadreleased(...) client:onGamepadReleased(...) end
function love.gamepadaxis(...) client:onGamepadAxis(...) end
function love.textinput(...) client:onTextInput(...) end
function love.wheelmoved(...) client:onWheelMoved(...) end
function love.resize(...) client:onResize(...) end
function love.threaderror(thread, err) error("thread: "..err) end
function love.quit() client:close() end

-- Debug touch/mobile controls using mouse inputs.
--[[
function love.mousepressed(x, y) client:onTouchPressed("mouse", x, y) end
function love.mousereleased(x, y) client:onTouchReleased("mouse", x, y) end
function love.mousemoved(x, y) client:onTouchMoved("mouse", x, y) end
--]]
