local effil = require("effil")
local msgpack = require("MessagePack")

-- define async database interface

local DBManager = class("DBManager")

-- thread
local function thread(ch_in, ch_out, db, user, password, host, port)
  local mysql_driver = require("luasql.mysql")
  local mysql_env = mysql_driver.mysql()
  local msgpack = require("MessagePack")

  local con = mysql_env:connect(db, user, password, host, port)
  if con then
    print("connected to database")
  else
    print("couldn't connect to database")
    return
  end

  local query, params = ch_in:pop()
  while query do
    local a, b = nil, nil

    params = msgpack.unpack(params)

    -- replace params
    for k,v in pairs(params) do
      local ptype = type(v)
      local param = con:escape(tostring(v))

      if ptype ~= "number" then
        param = "\'"..param.."\'"
      end
  
      query = string.gsub(query,"%{"..k.."%}", param)
    end

    -- do query
    local r,err = con:execute(query)
    if r == nil then -- error
      print(err.."[ "..query.." ]")
    elseif type(r) ~= "userdata" then -- returns affected, last insert id
      a = r
      b = con:getlastautoid()
    else -- return rows
      a = {}
      local row = {}
      while r:fetch(row, "a") do
        table.insert(a, row)
        row = {}
      end

      a = msgpack.pack(a)
    end

    -- returns
    ch_out:push(a,b)

    query, params = ch_in:pop()
  end

  con:close()
  mysql_env:close()
end

function DBManager:__construct(db, user, password, host, port)
  -- create channel and thread
  self.ch_out = effil.channel()
  self.ch_in = effil.channel()
  self.thread = effil.thread(thread)(self.ch_out, self.ch_in, db, user, password, host, port)
  self.queries = {} -- list of query callbacks, queue

  -- start task (25 tps)
  self.task = itask(1/25, function() self:do_task() end)

  self.running = true
end

function DBManager:do_task()
  local status, err = self.thread:status()
  if err then
    self:close()
  end

  -- process results
  if self.ch_in:size() > 0 then
    local a, b = self.ch_in:pop()
    local r = table.remove(self.queries, 1)
    if r then
      if a and not b then
        a = msgpack.unpack(a)
      end

      r(a,b) -- send return values
    else
      print("invalid database thread message")
    end
  end
end

-- (async)
-- perform query, row fields data are textual
-- return affected, lastid OR rows OR nil on error
function DBManager:query(query, params)
  if not query then
    error("query is nil")
  end

  local r = async()

  -- add query callback
  table.insert(self.queries, r)

  -- send to channel
  self.ch_out:push(query, msgpack.pack(params or {}))

  return r:wait()
end

function DBManager:close()
  if self.running then
    self.running = false

    self.ch_out:push(nil) -- end thread loop
    local status, err = self.thread:wait()
    if err then
      error(err)
    end
    self.task:remove() -- end task
  end
end

return DBManager
