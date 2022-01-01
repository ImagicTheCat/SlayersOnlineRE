local effil = require("effil")
local msgpack = require("MessagePack")
local mutex = require("Luaseq").mutex
local ev = require("ev")
local ev_async = require("app.ev-async")

-- Define async database interface.
local DBManager = class("DBManager")

-- thread
local function thread(async_sz, ch_in, ch_out, db_path)
  -- thread requires
  local msgpack = require("MessagePack")
  local ev = require("ev")
  local ev_async = require("app.ev-async")
  local sqlite = require("lsqlite3")
  -- error handling
  local function error_handler(err)
    io.stderr:write(debug.traceback("database: "..err, 2).."\n")
  end
  -- state
  local async_send = ev_async.import(async_sz)
  local db
  do
    local code, err
    db, code, err = sqlite.open(db_path)
    if not db then error("sqlite: "..err) end
  end
  -- Check SQLite3 error.
  local function sql_assert(code)
    if code ~= sqlite.OK and code ~= sqlite.DONE then
      error("sqlite("..code.."): "..db:errmsg(), 2)
    end
  end
  -- init
  sql_assert(db:execute("PRAGMA foreign_keys=true"))
  local statements = {}
  -- Prepare statement.
  -- query: "{k}" are statement parameters (string/integer)
  local function prepare(id, query)
    -- Convert map params to statement params array.
    local bound_params = {}
    local count = 0
    local stmt_query = query:gsub("%{([_%w]+)%}", function(param)
      local pid = tonumber(param) or param
      local bound_param = bound_params[pid]
      if not bound_param then
        count = count+1
        bound_params[pid] = count
        bound_param = count
      end
      return "?"..bound_param
    end)
    local handle, code = db:prepare(stmt_query)
    if not handle then sql_assert(code) end
    statements[id] = {bound_params = bound_params, handle = handle}
  end
  -- Execute query.
  -- params: map of parameters
  local function query(id, params)
    local stmt = statements[id]
    if not stmt then error("prepared statement \""..id.."\" not found") end
    stmt.handle:reset()
    -- set parameters
    for pid, n in pairs(stmt.bound_params) do
      local param = params[pid]
      if type(param) == "table" then sql_assert(stmt.handle:bind_blob(n, params[pid][1]))
      else sql_assert(stmt.handle:bind(n, params[pid])) end
    end
    -- execute
    local rows = {}
    for row in stmt.handle:nrows() do table.insert(rows, row) end
    return {rows = rows, rowid = stmt.handle:last_insert_rowid(), changes = db:changes()}
  end
  -- Process commands.
  local cmd, args = ch_in:pop()
  while cmd do -- A nil command ends the thread.
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
    end
    -- next
    cmd, args = ch_in:pop()
  end
  sql_assert(db:close())
end

function DBManager:__construct(db_path)
  -- create channels
  self.ch_out = effil.channel()
  self.ch_in = effil.channel()
  -- create async watcher
  self.async_watcher = ev.Async.new(function() self:tick() end)
  self.async_watcher:start(ev.Loop.default)
  local async_sz = ev_async.export(ev.Loop.default, self.async_watcher)
  -- create thread
  self.thread = effil.thread(thread)(async_sz, self.ch_in, self.ch_out, db_path)
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
  self.ch_in:push("prepare", msgpack.pack({id, query}))
  table.insert(self.tasks, task)
  if not task:wait() then error("prepare failed") end
end

-- (async) Query.
-- Note: 64bit integers will be truncated to Lua numbers (2^53).
--
-- id: statement identifier
-- params: (optional) map of parameter values
-- return result {} or false on failure
--- rows: list of row, map of field => value
--- rowid
--- changes
function DBManager:query(id, params)
  local task = async()
  self.ch_in:push("query", msgpack.pack({id, params or {}}))
  table.insert(self.tasks, task)
  local ok, r = task:wait()
  if not ok then error("query failed") end
  return r
end

local function txn_error_handler(err)
  io.stderr:write(debug.traceback("database TXN: "..err, 2).."\n")
end

-- (async) Wrap code as SQL transaction. Mutex protected.
-- COMMIT on success, ROLLBACK on error.
-- return boolean status
function DBManager:transactionWrap(f)
  self.txn:lock()
  self:query("begin")
  local ok = xpcall(f, txn_error_handler)
  if ok then self:query("commit") else self:query("rollback") end
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
    if status == "failed" then io.stderr:write(debug.traceback("DB thread: "..err)) end
  end
end

return DBManager
