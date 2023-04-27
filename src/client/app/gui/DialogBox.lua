-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

local Window = require("app.gui.Window")
local GridInterface = require("app.gui.GridInterface")
local Text = require("app.gui.Text")

local DialogBox = class("Inventory", Window)

function DialogBox:__construct()
  Window.__construct(self, "vertical")
  self.text = Text()
  self.grid = GridInterface(0,0,"vertical")
  self.grid:listen("cell-select", function(grid, event, cx, cy)
    if client.dialog_task then client.dialog_task:complete(cx+1) end
  end)
  self.grid:listen("control-press", function(grid, event, id)
    if id == "menu" and client.dialog_task then client.dialog_task:complete() end -- cancel
  end)
  self.content:add(self.text)
  self.content:add(self.grid)
end

function DialogBox:set(text, options)
  self.text:set(text)
  self.grid:init(#options, 1)
  for i, option in ipairs(options) do
    self.grid:set(i-1, 0, Text(option), true)
  end
end

return DialogBox
