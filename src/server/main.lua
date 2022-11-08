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

local ljuv = require("ljuv")
local Luaoop = require("Luaoop")
class = Luaoop.class
xtype = require("xtype")
local Luaseq = require("Luaseq")
async = Luaseq.async

local config = require("config")
math.randomseed(os.time())

-- global utils

loop = ljuv.loop -- main event loop

-- Execute callback after timeout (seconds).
-- return timer (timer:close() to prevent callback)
function timer(timeout, callback)
  local timer = loop:timer()
  timer:start(timeout, 0, function(timer) timer:close(); callback(timer) end)
  return timer
end

-- Execute callback with period (seconds).
-- return timer (timer:close() to stop interval)
function itimer(period, callback)
  local timer = loop:timer()
  timer:start(period, period, callback)
  return timer
end

-- (async)
-- Wait an amount of time.
-- delay: seconds
function wait(delay)
  local task = async()
  timer(delay, task)
  task:wait()
end

-- Create server.
local Server = require("app.Server")

server = Server(config) -- global

-- loop

-- loop stop function (with async support)
local function stop()
  async(function()
    server:close()
    loop:stop()
  end)
end

-- register close signals

-- SIGINT
local sigint = loop:signal()
sigint:start(2, function()
  print() -- Ctrl-C new line
  stop()
end)

-- SIGTERM
local sigterm = loop:signal()
sigterm:start(15, stop)

-- run app

local function error_handler(err)
  io.stderr:write(debug.traceback("loop: "..err, 2).."\n")
end
xpcall(loop.run, error_handler, loop)
server.db:close() -- try to gracefully close the DB whatever happens
