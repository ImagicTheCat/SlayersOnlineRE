-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

-- I/O/Compute thread
local sha2 = require("sha2")
local utils = require("app.utils")

local cin, cout = ...
while true do
  local query = cin:demand()
  if not query[1] then return end -- exit
  -- process
  if query[1] == "read-file" then
    cout:push(utils.pack(love.filesystem.read("data", query[2])))
  elseif query[1] == "write-file" then
    cout:push(utils.pack(love.filesystem.write(query[2], query[3])))
  elseif query[1] == "md5" then
    cout:push(utils.pack(sha2.md5(query[2]:getString())))
  end
end
