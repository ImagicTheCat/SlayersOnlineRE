local effil = require("effil")
local msgpack = require("MessagePack")

-- Define async database interface.
local DBManager = class("DBManager")

-- thread
local function thread(ch_in, ch_out, db, user, password, host, port)
  local mysql = require("mysql")
  local msgpack = require("MessagePack")
  local ffi = require("ffi")
  ffi.cdef("unsigned int sleep(unsigned int nb_sec);")
  local C = ffi.C
  local function error_handler(err)
    io.stderr:write(debug.traceback("DB: "..err, 2).."\n")
  end
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
    local ok = pcall(stmt.handle.exec, stmt.handle)
    while not ok and not ping() do -- disconnected ?
      -- re-connect and try again
      connect()
      stmt = statements[id] -- update statement reference
      ok = pcall(stmt.handle.exec, stmt.handle)
    end
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
  -- Connect to DB.
  connect()
  -- Process commands.
  local cmd, args = ch_in:pop()
  while cmd do -- a nil command ends the thread
    args = msgpack.unpack(args)
    if cmd == "prepare" then
      local ok = xpcall(prepare, error_handler, unpack(args))
      if not ok then io.stderr:write("<= prepare "..args[1].."\n") end
    elseif cmd == "query" then
      local ok, r = xpcall(query, error_handler, unpack(args))
      if not ok then io.stderr:write("<= query "..args[1].."\n") end
      ch_out:push(ok and msgpack.pack(r))
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
  self.thread = effil.thread(thread)(self.ch_in, self.ch_out, db, user, password, host, port)
  self.queries = {} -- list of query callbacks, queue
  self.running = true
end

-- Prepare a statement.
-- id: statement identifier
-- query: SQL query with parameters "{k}"
--- E.g. "SELECT * FROM users WHERE id = {1} AND name = {name}"
-- params: (optional) map of SQL parameter types
function DBManager:prepare(id, query, params)
  self.ch_in:push("prepare", msgpack.pack({id, query, params or {}}))
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
  table.insert(self.queries, task)
  return task:wait()
end

-- Query (no result).
-- id: statement identifier
-- params: (optional) map of parameter values
function DBManager:_query(id, params)
  self.ch_in:push("query", msgpack.pack({id, params or {}}))
  table.insert(self.queries, false) -- dummy task
end

function DBManager:tick()
  local status, err = self.thread:status()
  if err then self:close() end
  -- Fetch queries.
  while self.ch_out:size() > 0 do
    local r = self.ch_out:pop()
    local task = table.remove(self.queries, 1)
    if task then task(r and msgpack.unpack(r)) end
  end
end

function DBManager:close()
  if self.running then
    self.running = false
    self.ch_in:push(nil) -- end thread loop
    local status, err = self.thread:wait()
    if err then error("DB thread: "..err) end
  end
end

return DBManager
