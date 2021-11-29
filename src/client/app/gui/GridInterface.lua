local utils = require("app.utils")
local Widget = require("ALGUI.Widget")

-- Textual grid widget.
local GridInterface = class("GridInterface", Widget)
GridInterface.MARGIN = 5

-- Overlay

GridInterface.Overlay = class("GridInterface.Overlay", Widget)

function GridInterface.Overlay:__construct()
  Widget.__construct(self)
  self:setZ(1)
end

function GridInterface.Overlay:updateLayout(w,h)
  self:setSize(w,h)
end

-- GridInterface

local function control_press(self, event, id)
  if id == "up" then
    self:moveSelect(0,-1)
  elseif id == "down" then
    self:moveSelect(0,1)
  elseif id == "left" then
    self:moveSelect(-1,0)
  elseif id == "right" then
    self:moveSelect(1,0)
  elseif id == "interact" then
    self:select()
  end
end

-- wc, hc: number of columns/rows
-- wrap: (optional)
--- "vertical": wrap/extend vertically
-- move_mode: (optional)
--- default: loop mode
--- "move-out": emit move-out(dx, dy) event instead of looping
function GridInterface:__construct(wc, hc, wrap, move_mode)
  Widget.__construct(self)
  self.wrap = wrap
  self.move_mode = move_mode
  self.overlay = GridInterface.Overlay()
  self:add(self.overlay)
  self:init(wc,hc)
  self:listen("control-press", control_press)
end

function GridInterface:init(wc, hc)
  -- remove all widgets
  for idx, cell in pairs(self.cells or {}) do self:remove(cell[1]) end
  self.wc, self.hc = wc, hc
  self.cells = {} -- map of index => {.text, .callback, .disp_text}
  self.cx, self.cy = 0, 0 -- cursor
end

-- return cell index
function GridInterface:getIndex(x, y) return y*self.wc+x end

-- set cell
-- x, y: cell coordinates (>= 0)
-- widget: cell widget, nil to remove
-- selectable: (optional) if truthy, the cell can be selected
function GridInterface:set(x, y, widget, selectable)
  if x >= 0 and y >= 0 and x < self.wc and y < self.hc then
    local idx = self:getIndex(x, y)
    local cell = self.cells[idx]
    -- remove old widget
    if cell then self:remove(cell[1]) end
    if widget then
      self.cells[idx] = {widget, selectable}
      self:add(widget)
    else
      self.cells[idx] = nil
    end
  end
end

-- get cell or nil
function GridInterface:get(x, y)
  if x >= 0 and y >= 0 and x < self.wc and y < self.hc then
    return self.cells[self:getIndex(x,y)]
  end
end

-- check if a cell is selectable
function GridInterface:isSelectable(x, y)
  local cell = self:get(x,y)
  return cell and cell[2]
end

-- dx, dy: -1, 0, 1 (one axis only)
function GridInterface:moveSelect(dx, dy)
  self:emit("move-select", dx, dy)
  -- generic move
  local moved_out = false
  local cT = dx ~= 0 and "cx" or dy ~= 0 and "cy"
  local Tc = dx ~= 0 and "wc" or dy ~= 0 and "hc"
  local dV = dx ~= 0 and dx or dy ~= 0 and dy
  local old_cV = self[cT]
  if cT then
    local its = 0
    repeat
      self[cT], its = self[cT]+dV, its+1
      -- wrap
      if self[cT] < 0 then
        if self.move_mode == "move-out" then
          self[cT] = old_cV
          self:emit("move-out", dx, dy); moved_out = true; break
        else
          self[cT] = self[Tc]-1
        end
      elseif self[cT] == self[Tc] then
        if self.move_mode == "move-out" then
          self[cT] = old_cV
          self:emit("move-out", dx, dy); moved_out = true; break
        else
          self[cT] = 0
        end
      end
    until self:isSelectable(self.cx, self.cy) or its >= self[Tc]
  end
  if not moved_out then
    -- sound effect
    if cT then self.gui:playSound("resources/audio/Cursor1.wav") end
    -- update
    self:emit("cell-focus", self.cx, self.cy)
    self:updateScroll()
  end
end

function GridInterface:setSelect(cx, cy)
  if self:isSelectable(cx, cy) then
    self.cx, self.cy = cx, cy
  else -- find first valid cell
    for i=0, self.wc-1 do
      for j=0, self.hc-1 do
        if self:isSelectable(i,j) then self.cx, self.cy = i,j; goto exit end
      end
    end
  end
  ::exit:: self:moveSelect(0,0)
end

-- return selected widget or nil
function GridInterface:getSelected()
  local idx = self:getIndex(self.cx, self.cy)
  local cell = self.cells[idx]
  return cell and cell[2] and cell[1] -- valid selectable cell
end

function GridInterface:updateScroll()
  local idx = self:getIndex(self.cx, self.cy)
  local cell = self.cells[idx]
  if cell and cell[2] then -- valid selectable cell
    -- offset inner to current selected entry if not visible
    local overflow_y = cell[1].y+cell[1].h+GridInterface.MARGIN-self.h
    self:setInnerOffset(0, overflow_y > 0 and -overflow_y or 0)
  else -- invalid selection, reset inner offset
    self:setInnerOffset(0,0)
  end
end

function GridInterface:select()
  local cx, cy = self.cx, self.cy
  if cx >= 0 and cy >= 0 and cx < self.wc and cy < self.hc then
    if self:isSelectable(self.cx, self.cy) then -- valid selectable cell
      -- sound effect
      self.gui:playSound("resources/audio/Item1.wav")
      self:emit("cell-select", cx, cy)
    end
  end
end

-- override
function GridInterface:updateLayout(w,h)
  local MARGIN = GridInterface.MARGIN
  -- Place widgets line by line with fixed width and height based on max cell
  -- height (vertical flow).
  local y, cell_w = MARGIN, w/self.wc
  for cy=0,self.hc do
    local max_h = 0
    local x = MARGIN
    for cx=0,self.wc do
      local cell = self.cells[self:getIndex(cx,cy)]
      if cell then
        cell[1]:setPosition(x,y)
        cell[1]:updateLayout(cell_w-MARGIN*2, max_h)
        max_h = math.max(max_h, cell[1].h)
        x = x+cell[1].w+MARGIN
      end
    end
    y = y+max_h+MARGIN
  end
  if self.wrap == "vertical" then self:setSize(w,y) else self:setSize(w,h) end
  -- update inner overlay
  self.overlay:updateLayout(self.w,y)
  self:updateScroll()
end

return GridInterface
