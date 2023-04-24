-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

local msgpack = require("MessagePack")
local sha2 = require("sha2")
local utils = require("app.utils")
local URL = require("socket.url")

local ResourceManager = class("ResourceManager")

function ResourceManager:__construct()
  -- create HTTP thread
  self.http_thread = love.thread.newThread("app/thread_http.lua")
  self.http_cin = love.thread.newChannel()
  self.http_cout = love.thread.newChannel()
  self.http_thread:start(self.http_cin, self.http_cout)
  self.http_tasks = {}
  -- create I/O/Compute thread
  self.ioc_thread = love.thread.newThread("app/thread_ioc.lua")
  self.ioc_cin = love.thread.newChannel()
  self.ioc_cout = love.thread.newChannel()
  self.ioc_thread:start(self.ioc_cin, self.ioc_cout)
  self.ioc_tasks = {}

  self.busy_hint = "" -- hint to display
  self.local_manifest = {} -- map of path => hash
  self.remote_manifest = {} -- map of path => hash
  self.resource_tasks = {} -- map of path => async task
  -- create dirs
  love.filesystem.createDirectory("resources_repository/textures/sets")
  love.filesystem.createDirectory("resources_repository/audio")
  -- mount downloads
  if not love.filesystem.mount("resources_repository", "resources") then
    print("couldn't mount resources repository")
  end
  self:loadLocalManifest()
end

function ResourceManager:isBusy()
  return self.http_tasks[1] or self.ioc_tasks[1]
end

-- (async) Request HTTP file body.
-- url: valid url, must be escaped if necessary
-- return body as Data or (nil, err) on failure
function ResourceManager:requestHTTP(url)
  self.busy_hint = "Downloading "..url.."..."
  local r = async()
  table.insert(self.http_tasks, r)
  self.http_cin:push({url})
  return r:wait()
end

-- (async)
-- data: Data
-- return hash (string)
function ResourceManager:computeMD5(data)
  local r = async()
  table.insert(self.ioc_tasks, r)
  self.ioc_cin:push({"md5", data})
  return r:wait()
end

-- (async)
-- data: Data
-- return [love.filesystem.write proxy]
function ResourceManager:writeFile(path, data)
  self.busy_hint = "Writing "..path.."..."
  local r = async()
  table.insert(self.ioc_tasks, r)
  self.ioc_cin:push({"write-file", path, data})
  return r:wait()
end

-- (async)
-- return [love.filesystem.read proxy]
function ResourceManager:readFile(path)
  self.busy_hint = "Reading "..path.."..."
  local r = async()
  table.insert(self.ioc_tasks, r)
  self.ioc_cin:push({"read-file", path})
  return r:wait()
end

function ResourceManager:tick(dt)
  -- http requests
  local r = self.http_cout:pop()
  while r do
    local cb = table.remove(self.http_tasks, 1)
    cb(unpack(r, 1, r.n))
    r = self.http_cout:pop()
  end
  -- ioc queries
  r = self.ioc_cout:pop()
  while r do
    local cb = table.remove(self.ioc_tasks, 1)
    cb(unpack(r, 1, r.n))
    r = self.ioc_cout:pop()
  end
end

function ResourceManager:close()
  self.http_cin:push({})
  self.http_thread:wait()
  self.ioc_cin:push({})
  self.ioc_thread:wait()
end

function ResourceManager:loadLocalManifest()
  local ok, data = pcall(msgpack.unpack, love.filesystem.read("local.manifest"))
  if ok then self.local_manifest = data end
end

-- (async)
-- return true on success or false
function ResourceManager:loadRemoteManifest()
  local data = self:requestHTTP(client.cfg.resource_repository.."repository.manifest")
  if data then
    local lines = utils.split(data:getString(), "\n")
    for _, line in ipairs(lines) do
      local path, hash = string.match(line, "^(.*)=(%x*)$")
      if path then
        self.remote_manifest[path] = hash
      end
    end
    return true
  else
    return false
  end
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
  local lhash = self.local_manifest[path]
  local rhash = self.remote_manifest[path]
  if rhash then
    if not lhash then -- verify/re-hash
      print("try to re-hash resource "..path)
      local data = self:readFile("resources_repository/"..path)
      -- re-add manifest entry
      if data then
        lhash = self:computeMD5(data)
        self.local_manifest[path] = lhash
      end
    end
    if not lhash or lhash ~= rhash then -- download/update
      print("download resource "..path)
      local data, err = self:requestHTTP(client.cfg.resource_repository..URL.escape(path))
      if data then
        -- write file
        local ok, err = self:writeFile("resources_repository/"..path, data)
        if ok then -- add manifest entry
          self.local_manifest[path] = self:computeMD5(data)
          ret = true
        else print(err) end
      else print("download error "..path..": "..err) end
    else -- already same as remote
      ret = true
    end
  end
  -- end guard
  self.resource_tasks[path] = nil
  task(ret)
  return ret
end

function ResourceManager:saveLocalManifest()
  love.filesystem.write("local.manifest", msgpack.pack(self.local_manifest))
end

return ResourceManager
