local msgpack = require("MessagePack")
local utils = require("lib/utils")
local sha2 = require("sha2")

local NetManager = class("NetManager")

function NetManager:__construct(client)
  self.client = client

  -- create HTTP thread
  self.thread = love.thread.newThread("main_http.lua")
  self.thread:start()

  self.http_channel_in = love.thread.getChannel("http.in")
  self.http_channel_out = love.thread.getChannel("http.out")

  self.requests = {} -- list of requests (processed in ASC order)

  self.local_manifest = {} -- map of path => hash
  self.remote_manifest = {} -- map of path => hash

  self.resource_requests = {} -- map of path => list of callback

  -- create dirs
  love.filesystem.createDirectory("resources_repository/textures/sets")
  love.filesystem.createDirectory("resources_repository/audio")

  -- mount downloads
  if not love.filesystem.mount("resources_repository", "resources") then
    print("couldn't mount resources repository")
  end

  self:loadLocalManifest()
end

-- (async) request HTTP file body
-- return data or nil on failure
function NetManager:request(url)
  local r = async()

  table.insert(self.requests, {
    callback = r,
    url = url
  })

  self.http_channel_in:push({url = url})

  return r:wait()
end

function NetManager:tick(dt)
  local data = self.http_channel_out:pop()
  if data then
    local request = table.remove(self.requests, 1)
    request.callback(data.body)
  end
end

function NetManager:close()
  self.http_channel_in:push({})
end

function NetManager:loadLocalManifest()
  local data = love.filesystem.read("local.manifest")
  if data then
    self.local_manifest = msgpack.unpack(data)
  end
end

-- (async)
-- return true on success or false
function NetManager:loadRemoteManifest()
  local data = self:request(self.client.cfg.resource_repository.."repository.manifest")
  if data then
    local lines = utils.split(data, "\n")
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
function NetManager:requestResource(path)
  local request = self.resource_requests[path]

  if not request then -- create request
    local ret = false

    request = {}
    self.resource_requests[path] = request

    local lhash = self.local_manifest[path]
    local rhash = self.remote_manifest[path]

    if rhash then
      if not lhash then -- verify/re-hash
        print("try to re-hash resource "..path)
        local data = love.filesystem.read("resources_repository/"..path)
        -- re-add manifest entry
        if data then
          lhash = sha2.md5(data)
          self.local_manifest[path] = lhash
        end
      end

      if not lhash or lhash ~= rhash then -- download/update
        print("download resource "..path)
        local data = self:request(self.client.cfg.resource_repository..path)
        if data then
          -- write file
          local ok, err = love.filesystem.write("resources_repository/"..path, data)
          if ok then -- add manifest entry
            self.local_manifest[path] = sha2.md5(data)
          else
            print(err)
          end

          ret = ok
        end
      else -- already same as remote
        ret = true
      end
    end

    self.resource_requests[path] = nil

    -- return
    for _, callback in ipairs(request) do
      callback(ret)
    end
    return ret
  else -- wait for request completion
    local r = async()
    table.insert(request, r)
    return r:wait()
  end
end

function NetManager:saveLocalManifest()
  love.filesystem.write("local.manifest", msgpack.pack(self.local_manifest))
end

return NetManager
