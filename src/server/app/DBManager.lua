-- https://github.com/ImagicTheCat/SlayersOnlineRE
-- MIT license (see LICENSE, src/server/main.lua or src/client/main.lua)

local ljuv = require("ljuv")
local utils = require("app.utils")
local mutex = require("Luaseq").mutex

-- Define async database interface.
local DBManager = class("DBManager")

-- thread
local function thread(async, ch_in, ch_out, db_path)
  -- thread requires
  local utils = require("app.utils")
  local sqlite = require("lsqlite3")
  -- error handling
  local function error_handler(err)
    io.stderr:write(debug.traceback("database: "..err, 2).."\n")
  end
  -- state
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
  local args = utils.pack(ch_in:pull())
  while args[1] do -- A nil command ends the thread.
    if args[1] == "prepare" then
      local ok = xpcall(prepare, error_handler, unpack(args, 2, args.n))
      ch_out:push(ok)
      async()
    elseif args[1] == "query" then
      local ok, r = xpcall(query, error_handler, unpack(args, 2, args.n))
      ch_out:push(ok, r)
      async()
    end
    -- next
    args = utils.pack(ch_in:pull())
  end
  sql_assert(db:close())
end

function DBManager:__construct(db_path)
  -- create channels
  self.ch_in, self.ch_out = ljuv.new_channel(), ljuv.new_channel()
  -- create async handle
  self.async = loop:async(function() self:tick() end)
  -- create thread
  self.thread = ljuv.new_thread(thread, self.async, self.ch_in, self.ch_out, db_path)
  -- watch thread
  self.watcher = itimer(1, function(timer)
    if not self.thread:running() then error("DB thread is dead") end
  end)
  self.tasks = {} -- queue (list) of tasks
  self.txn = mutex()
end

-- (async) Prepare a statement.
-- id: statement identifier
-- query: SQL query with parameters "{k}"
--- E.g. "SELECT * FROM users WHERE id = {1} AND name = {name}"
-- params: (optional) map of SQL parameter types
function DBManager:prepare(id, query, params)
  local task = async()
  self.ch_in:push("prepare", id, query)
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
  self.ch_in:push("query", id, params or {})
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
  -- Fetch results.
  repeat
    local rets = utils.pack(self.ch_out:try_pull())
    if rets[1] then
      local task = table.remove(self.tasks, 1)
      if task then task(unpack(rets, 2, rets.n)) end
    end
  until not ok
end

-- Idempotent.
function DBManager:close()
  if self.closed then return end
  self.closed = true
  self.ch_in:push(nil) -- end thread loop
  self.watcher:close()
  local ok, errtrace = self.thread:join()
  self.async:close()
  if not ok then error("DB thread: "..errtrace, 0) end
end

return DBManager
