-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

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
