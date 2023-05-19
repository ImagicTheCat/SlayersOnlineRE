-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

local msgpack = require "MessagePack"
local utils = require "app.utils"
local URL = require "socket.url"
local threadpool = require "love-threadpool"

local ResourceManager = class("ResourceManager")

-- HTTP interface
local function http_interface()
  local http = require "socket.http"
  local interface = {}

  function interface.requestHTTP(url)
    local body, code = http.request(url)
    if body and code == 200 then
      return love.data.newByteData(body)
    else
      return nil, code
    end
  end

  return interface
end

-- I/O/Compute interface
local function ioc_interface()
  local interface = {}

  function interface.readFile(path) return love.filesystem.read("data", path) end
  function interface.writeFile(path, data) return love.filesystem.write(path, data) end
  function interface.hash(hashf, data) return love.data.hash(hashf, data) end

  return interface
end

function ResourceManager:__construct()
  self.http_pool = threadpool.new(1, http_interface)
  self.ioc_pool = threadpool.new(1, ioc_interface)
  self.busy_hint = "" -- hint to display
  self.local_index = {} -- map of path => hash
  self.remote_index = {} -- map of path => hash
  self.resource_tasks = {} -- map of path => async task
  -- create dirs
  love.filesystem.createDirectory("resources_repository/textures/sets")
  love.filesystem.createDirectory("resources_repository/audio")
  -- mount downloads
  if not love.filesystem.mount("resources_repository", "resources") then
    warn("couldn't mount resources repository")
  end
  self:loadLocalIndex()
end

function ResourceManager:isBusy()
  return next(self.http_pool.tasks) or next(self.ioc_pool.tasks)
end

-- (async) Request HTTP file body.
-- url: valid url, must be escaped if necessary
-- return body as Data or (nil, err) on failure
function ResourceManager:requestHTTP(url)
  self.busy_hint = "Downloading "..url.."..."
  return self.http_pool.interface.requestHTTP(url)
end

-- (async)
-- data: Data
-- return hash (string)
function ResourceManager:hash(hashf, data)
  return self.ioc_pool.interface.hash(hashf, data)
end

-- (async)
-- data: Data
-- return [love.filesystem.write proxy]
function ResourceManager:writeFile(path, data)
  self.busy_hint = "Writing "..path.."..."
  return self.ioc_pool.interface.writeFile(path, data)
end

-- (async)
-- return [love.filesystem.read proxy]
function ResourceManager:readFile(path)
  self.busy_hint = "Reading "..path.."..."
  return self.ioc_pool.interface.readFile(path)
end

function ResourceManager:tick(dt)
  self.http_pool:tick()
  self.ioc_pool:tick()
end

function ResourceManager:close()
  self.http_pool:close()
  self.ioc_pool:close()
end

function ResourceManager:loadLocalIndex()
  local ok, data = wpcall(msgpack.unpack, love.filesystem.read("local.index"))
  if ok then self.local_index = data end
end

function ResourceManager:saveLocalIndex()
  love.filesystem.write("local.index", msgpack.pack(self.local_index))
end

-- (async)
-- return true on success or false
function ResourceManager:loadRemoteIndex()
  -- request
  local raw_data = self:requestHTTP(client.cfg.resource_repository.."repository.index")
  if not raw_data then return false end
  -- unpack
  local ok, data = wpcall(msgpack.unpack, raw_data:getString())
  if not ok then return false end
  self.remote_index = data
  return true
end

-- (async) request a resource from the repository
-- will wait until the resource is checked/downloaded (handle simultaneous requests)
-- path: relative to the repository
-- return true on success, false if the resource is unavailable
function ResourceManager:requestResource(path)
  -- guard
  local task = self.resource_tasks[path]
  if task then task:wait() end
  -- create request
  task = async()
  self.resource_tasks[path] = task
  local ret = false
  local lhash = self.local_index[path]
  local rhash = self.remote_index[path]
  if rhash then
    if not lhash then -- verify/re-hash
      print("try to re-hash resource "..path)
      local data = self:readFile("resources_repository/"..path)
      -- re-add index entry
      if data then
        lhash = self:hash("sha1", data)
        self.local_index[path] = lhash
      end
    end
    if not lhash or lhash ~= rhash then -- download/update
      print("download resource "..path)
      local data, err = self:requestHTTP(client.cfg.resource_repository..URL.escape(path))
      if data then
        -- write file
        local ok, err = self:writeFile("resources_repository/"..path, data)
        if ok then -- add index entry
          self.local_index[path] = self:hash("sha1", data)
          ret = true
        else warn(err) end
      else warn("download error "..path..": "..err) end
    else -- already same as remote
      ret = true
    end
  end
  -- end guard
  self.resource_tasks[path] = nil
  task:complete(ret)
  return ret
end

return ResourceManager
