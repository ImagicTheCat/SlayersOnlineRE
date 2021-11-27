-- Slayers Online RE - a rewrite from scratch of Slayers Online
-- Copyright (c) 2019 ImagicTheCat

local ev = require("ev")
local Luaoop = require("Luaoop")
class = Luaoop.class
xtype = require("xtype")
local Luaseq = require("Luaseq")
async = Luaseq.async

local config = require("config")

-- global utils

-- Return current loop time in seconds.
function clock()
  return ev.Loop.default:now()
end

-- Execute callback after delay (seconds).
-- return timer (timer:remove() to prevent callback)
function timer(delay, cb)
  local timer = ev.Timer.new(function() cb() end, delay)
  function timer:remove() self:stop(ev.Loop.default) end
  timer:start(ev.Loop.default)
  return timer
end

-- Execute callback with period (seconds).
-- return timer (timer:remove() to stop interval)
function itimer(delay, cb)
  local timer = ev.Timer.new(function() cb() end, delay, delay)
  function timer:remove() self:stop(ev.Loop.default) end
  timer:start(ev.Loop.default)
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

-- create server
local Server = require("app.Server")

server = Server(config) -- global

-- loop

-- loop stop function (with async support)
local function stop()
  async(function()
    server:close()
    ev.Loop.default:unloop()
  end)
end

-- register close signals

-- SIGINT
local sigint = ev.Signal.new(function(loop, sig)
  print() -- Ctrl-C new line
  stop()
end, 2)
sigint:start(ev.Loop.default)

-- SIGTERM
local sigterm = ev.Signal.new(function(loop, sig)
  stop()
end, 15)
sigterm:start(ev.Loop.default)

-- start loop
ev.Loop.default:loop()
