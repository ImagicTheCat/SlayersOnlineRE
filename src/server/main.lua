-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

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
sigint:start_oneshot(2, function()
  print() -- Ctrl-C new line
  stop()
end)

-- SIGTERM
local sigterm = loop:signal()
sigterm:start_oneshot(15, stop)

-- run app
loop:run()
