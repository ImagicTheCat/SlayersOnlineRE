-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

local ljuv = require "ljuv"
local utils = require "app.utils"
local mutex = require("Luaseq").mutex

-- Define async database interface.
local DBManager = class("DBManager")

-- thread interface
local function interface_loader(db_path)
  -- thread requires
  local utils = require "app.utils"
  local sqlite = require "lsqlite3"

  local interface = {}
  -- error handling
  local function error_handler(err)
    io.stderr:write(debug.traceback("database: "..err, 2).."\n")
  end
  -- state
  local db
  -- Check SQLite3 error.
  local function sql_assert(code)
    if code ~= sqlite.OK and code ~= sqlite.DONE then
      error("sqlite("..code.."): "..db:errmsg(), 2)
    end
  end
  -- init
  local code, err
  db, code, err = sqlite.open(db_path)
  if not db then error("sqlite: "..err) end
  sql_assert(db:execute("PRAGMA foreign_keys=true"))

  local statements = {}

  -- Prepare statement.
  -- query: "{k}" are statement parameters (string/integer)
  function interface.prepare(id, query)
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
  function interface.query(id, params)
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

  function interface.__exit()
    sql_assert(db:close())
  end

  return interface
end

function DBManager:__construct(db_path)
  self.pool = loop:threadpool(1, interface_loader, db_path)
  self.txn = mutex()
end

-- (async) Prepare a statement.
-- id: statement identifier
-- query: SQL query with parameters "{k}"
--- E.g. "SELECT * FROM users WHERE id = {1} AND name = {name}"
-- params: (optional) map of SQL parameter types
function DBManager:prepare(id, query, params)
  self.pool.interface.prepare(id, query, params)
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
  return self.pool.interface.query(id, params)
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

-- (async) Idempotent.
function DBManager:close()
  self.pool:close()
end

return DBManager
