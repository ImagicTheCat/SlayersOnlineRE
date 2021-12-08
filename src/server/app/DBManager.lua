local effil = require("effil")
local msgpack = require("MessagePack")
local mutex = require("Luaseq").mutex
local ev = require("ev")
local ev_async = require("app.ev-async")

-- Define async database interface.
local DBManager = class("DBManager")

-- thread
local function thread(async_sz, ch_in, ch_out, db, user, password, host, port)
  -- thread requires
  local mysql = require("mysql")
  local msgpack = require("MessagePack")
  local ffi = require("ffi")
  local ev = require("ev")
  local ev_async = require("app.ev-async")

  ffi.cdef("unsigned int sleep(unsigned int nb_sec);")
  local C = ffi.C
  local function error_handler(err)
    io.stderr:write(debug.traceback("database: "..err, 2).."\n")
  end
  local async_send = ev_async.import(async_sz)
  local con
  local CONNECT_DELAY = 5 -- seconds
  local statements = {}
  -- Prepared statements.
  local function prepare(id, query, params)
    -- convert map params to statement params array
    local bind_params = {}
    local stmt_query = query:gsub("%{([_%w]+)%}", function(param)
      local pid = tonumber(param) or param
      if params[pid] then
        table.insert(bind_params, pid)
        return "?"
      end
    end)
    local types = {}
    for _, pid in ipairs(bind_params) do table.insert(types, params[pid]) end
    local handle = con:prepare(stmt_query)
    local params_in = handle:bind_params(types)
    -- bind result if any
    local fields_out = handle:result_metadata() and handle:bind_result()
    statements[id] = {
      handle = handle, query = query,
      params = params, bind_params = bind_params,
      params_in = params_in,
      fields_out = fields_out
    }
  end
  -- Connect to DB (loop).
  local function connect()
    local connecting = true
    while connecting do
      local ok
      ok, con = pcall(mysql.connect, host, user, password, db)
      if ok then
        -- re-build statements
        for id, stmt in pairs(statements) do prepare(id, stmt.query, stmt.params) end
        print("connected to database")
        connecting = false
      else
        print("connection to database failed, waiting "..CONNECT_DELAY.."s: "..con)
        C.sleep(CONNECT_DELAY)
      end
    end
  end
  local function ping()
    local ok, r = pcall(con.ping, con)
    return ok and r
  end
  local function query(id, params)
    local stmt = statements[id]
    if not stmt then error("prepared statement \""..id.."\" not found") end
    -- set parameters
    for i, bparam in ipairs(stmt.bind_params) do
      stmt.params_in:set(i, params[bparam])
    end
    -- execute
    local ok = xpcall(stmt.handle.exec, error_handler, stmt.handle)
    while not ok and not ping() do -- disconnected ?
      -- re-connect and try again
      connect()
      stmt = statements[id] -- update statement reference
      ok = xpcall(stmt.handle.exec, error_handler, stmt.handle)
    end
    if not ok then error("statement execute failed") end
    -- fetch result
    local r = {
      affected_rows = stmt.handle:affected_rows(),
      insert_id = tonumber(stmt.handle:insert_id()),
    }
    if stmt.fields_out then -- fetch rows
      local rows = {}
      local field_names = {}
      for _, info in stmt.handle:fields() do table.insert(field_names, info.name) end
      while stmt.handle:fetch() do
        local row = {}
        for i, name in ipairs(field_names) do
          local value = stmt.fields_out:get(i)
          -- 64bit integers will be converted to Lua numbers.
          if type(value) == "cdata" then value = tonumber(value) end
          row[name] = value
        end
        table.insert(rows, row)
      end
      r.rows = rows
    end
    return r
  end
  local function raw_query(query)
    -- execute
    local ok = xpcall(con.query, error_handler, con, query)
    while not ok and not ping() do -- disconnected ?
      -- re-connect and try again
      connect()
      ok = xpcall(con.query, error_handler, con, query)
    end
    if not ok then error("query failed") end
  end
  -- Connect to DB.
  connect()
  -- Process commands.
  local cmd, args = ch_in:pop()
  while cmd do -- a nil command ends the thread
    args = msgpack.unpack(args)
    if cmd == "prepare" then
      local ok = xpcall(prepare, error_handler, unpack(args))
      if not ok then io.stderr:write("<= prepare "..args[1].."\n") end
      ch_out:push(msgpack.pack({ok}))
      async_send()
    elseif cmd == "query" then
      local ok, r = xpcall(query, error_handler, unpack(args))
      if not ok then io.stderr:write("<= query "..args[1].."\n") end
      ch_out:push(msgpack.pack({ok, r}))
      async_send()
    elseif cmd == "query-raw" then
      local ok = xpcall(raw_query, error_handler, unpack(args))
      if not ok then io.stderr:write("<= query-raw \""..args[1].."\"\n") end
      ch_out:push(msgpack.pack({ok}))
      async_send()
    end
    -- next
    cmd, args = ch_in:pop()
  end
  con:close()
end

function DBManager:__construct(db, user, password, host, port)
  -- create thread and channels
  self.ch_out = effil.channel()
  self.ch_in = effil.channel()
  self.async_watcher = ev.Async.new(function() self:tick() end)
  self.async_watcher:start(ev.Loop.default)
  local async_sz = ev_async.export(ev.Loop.default, self.async_watcher)
  self.thread = effil.thread(thread)(async_sz, self.ch_in, self.ch_out, db, user, password, host, port)
  self.tasks = {} -- queue (list) of tasks
  self.running = true
  self.txn = mutex()
end

-- (async) Prepare a statement.
-- id: statement identifier
-- query: SQL query with parameters "{k}"
--- E.g. "SELECT * FROM users WHERE id = {1} AND name = {name}"
-- params: (optional) map of SQL parameter types
function DBManager:prepare(id, query, params)
  local task = async()
  self.ch_in:push("prepare", msgpack.pack({id, query, params or {}}))
  table.insert(self.tasks, task)
  if not task:wait() then error("prepare failed") end
end

-- (async) Query.
-- Note: 64bit integers will be truncated to Lua numbers (2^53).
--
-- id: statement identifier
-- params: (optional) map of parameter values
-- return result {} or false on failure
--- affected_rows
--- insert_id
--- rows, list of row, map of field => value
function DBManager:query(id, params)
  local task = async()
  self.ch_in:push("query", msgpack.pack({id, params or {}}))
  table.insert(self.tasks, task)
  local ok, r = task:wait()
  if not ok then error("query failed") end
  return r
end

-- (async) Raw query.
-- No result, internally used for transactions. Some MariaDB servers don't
-- support transaction queries in prepared statements.
function DBManager:rawQuery(query)
  local task = async()
  self.ch_in:push("query-raw", msgpack.pack({query}))
  table.insert(self.tasks, task)
  if not task:wait() then error("raw query failed") end
end

local function txn_error_handler(err)
  io.stderr:write(debug.traceback("database TXN: "..err, 2).."\n")
end

-- (async) Wrap code as SQL transaction. Mutex protected.
-- COMMIT on success, ROLLBACK on error.
-- return boolean status
function DBManager:transactionWrap(f)
  self.txn:lock()
  self:rawQuery("START TRANSACTION")
  local ok = xpcall(f, txn_error_handler)
  if ok then self:rawQuery("COMMIT") else self:rawQuery("ROLLBACK") end
  self.txn:unlock()
  return ok
end

function DBManager:tick()
  local status, err = self.thread:status()
  if err then self:close() end
  -- Fetch queries.
  while self.ch_out:size() > 0 do
    local r = self.ch_out:pop()
    local task = table.remove(self.tasks, 1)
    if task then task(unpack(msgpack.unpack(r))) end
  end
end

function DBManager:close()
  if self.running then
    self.running = false
    self.ch_in:push(nil) -- end thread loop
    self.async_watcher:stop(ev.Loop.default)
    local status, err = self.thread:wait()
    if err then error("DB thread: "..err) end
  end
end

return DBManager
