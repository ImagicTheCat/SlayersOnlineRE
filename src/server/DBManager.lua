local effil = require("effil")
local msgpack = require("MessagePack")

-- define async database interface

local DBManager = class("DBManager")

-- thread
local function thread(ch_in, ch_out, db, user, password, host, port)
  local CONNECT_DELAY = 5 -- seconds
  local mysql_driver = require("luasql.mysql")
  local mysql_env = mysql_driver.mysql()
  local msgpack = require("MessagePack")
  local ffi = require("ffi")
  ffi.cdef("unsigned int sleep(unsigned int nb_sec);")
  local C = ffi.C
  local con

  -- connect to DB (loop)
  local function connect()
    local connecting = true
    while connecting do
      con = mysql_env:connect(db, user, password, host, port)
      if con then
        print("connected to database")
        connecting = false
      else
        print("connection to database failed, waiting "..CONNECT_DELAY.."s")
        C.sleep(CONNECT_DELAY)
      end
    end
  end

  -- return affected, last insert id
  -- or rows
  -- or nil, error
  local function process_query(query)
    local r, err = con:execute(query)
    if r == nil then -- error
      print(err, "["..query.."]")
      return r,err
    elseif type(r) ~= "userdata" then -- returns affected, last insert id
      return r, con:getlastautoid()
    else -- return rows
      local rows = {}
      local row = {}
      while r:fetch(row, "a") do
        table.insert(rows, row)
        row = {}
      end
      return msgpack.pack(rows)
    end
  end

  connect() -- connect to DB

  -- process queries
  local query, params = ch_in:pop()
  while query do
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

    local a,b = process_query(query)
    while a == nil and not con:ping() do -- error and invalid connection
      print("disconnected from database")
      connect()
      a,b = process_query(query) -- try again
    end

    -- returns
    ch_out:push(a,b)
    -- next
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

  self.running = true
end

function DBManager:tick()
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
    end
  end
end

-- (async)
-- perform query, returned row fields data are textual
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

-- perform query (no wait)
function DBManager:_query(query, params)
  if not query then
    error("query is nil")
  end

  -- add no callback flag
  table.insert(self.queries, false)

  -- send to channel
  self.ch_out:push(query, msgpack.pack(params or {}))
end


function DBManager:close()
  if self.running then
    self.running = false

    self.ch_out:push(nil) -- end thread loop
    local status, err = self.thread:wait()
    if err then
      error(err)
    end
  end
end

return DBManager
