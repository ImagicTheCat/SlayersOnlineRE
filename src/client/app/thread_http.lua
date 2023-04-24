-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

-- HTTP request thread
local http = require("socket.http")
local utils = require("app.utils")

local cin, cout = ...
while true do
  local req = cin:demand()
  if not req[1] then return end -- exit
  -- process
  local body, code = http.request(req[1])
  if body and code == 200 then
    cout:push(utils.pack(love.data.newByteData(body)))
  else
    cout:push(utils.pack(nil, code))
  end
end
