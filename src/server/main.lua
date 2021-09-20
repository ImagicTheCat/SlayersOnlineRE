-- Slayers Online RE - a rewrite from scratch of Slayers Online
-- Copyright (c) 2019 ImagicTheCat

local ev = require("ev")
local Luaoop = require("Luaoop")
class = Luaoop.class
local Luaseq = require("Luaseq")
async = Luaseq.async

local config = require("config")

-- global utils

-- return current loop time in seconds
function clock()
  return ev.Loop.default:now()
end

-- Execute callback after delay (seconds).
-- return timer (timer:remove() to prevent callback)
function timer(delay, cb)
  local timer = ev.Timer.new(function(loop, timer, revents)
    cb()
    timer:stop(loop)
  end, delay)
  function timer:remove()
    self:stop(ev.Loop.default)
  end
  timer:start(ev.Loop.default)
  return timer
end

-- Execute callback with period (seconds).
-- return timer (timer:remove() to stop interval)
function itimer(delay, cb)
  local timer = ev.Timer.new(function(loop, timer, revents)
    cb()
  end, delay, delay)
  function timer:remove()
    self:stop(ev.Loop.default)
  end
  timer:start(ev.Loop.default)
  return timer
end

-- create server
local Server = require("Server")

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
