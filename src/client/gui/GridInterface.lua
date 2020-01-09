local Widget = require("ALGUI.Widget")

-- textual grid widget
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

local function control_press(self, id)
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

-- METHODS

-- wc, hc: number of columns/rows
-- wrap: (optional)
--- "vertical": wrap/extend vertically
function GridInterface:__construct(wc, hc, wrap)
  Widget.__construct(self)

  self.wrap = wrap
  self.overlay = GridInterface.Overlay()
  self:add(self.overlay)
  self:init(wc,hc)
  self:listen("control-press", control_press)
end

function GridInterface:init(wc, hc)
  -- remove all widgets
  for idx, cell in pairs(self.cells or {}) do
    self:remove(cell[1])
  end

  self.wc, self.hc = wc, hc
  self.cells = {} -- map of index => {.text, .callback, .disp_text}
  self.cx, self.cy = 0, 0 -- cursor
end

-- return cell index
function GridInterface:getIndex(x, y)
  return y*self.wc+x
end

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

function GridInterface:moveSelect(dx, dy)
  self:trigger("move-select", dx, dy)

  -- X
  local sdx = dx/math.abs(dx) -- sign
  local its, limit = 0, self.wc*math.abs(dx)
  while dx ~= 0 and its < limit do -- move cursor on selectables
    self.cx = self.cx+sdx
    self.cx = (self.cx < 0 and (self.wc-(-self.cx)%self.wc)%self.wc or self.cx%self.wc)

    -- step on selectable
    local cell = self.cells[self:getIndex(self.cx, self.cy)]
    if cell and cell[2] then dx = dx-sdx end
    its = its+1
  end

  -- Y
  local sdy = dy/math.abs(dy) -- sign
  its, limit = 0, self.hc*math.abs(dy)
  while dy ~= 0 and its < limit do -- move cursor on selectables
    self.cy = self.cy+sdy
    self.cy = (self.cy < 0 and (self.hc-(-self.cy)%self.hc)%self.hc or self.cy%self.hc)

    -- step on selectable
    local cell = self.cells[self:getIndex(self.cx, self.cy)]
    if cell and cell[2] then dy = dy-sdy end
    its = its+1
  end

  -- sound effect
  self.gui:playSound("resources/audio/Cursor1.wav")

  local idx = self:getIndex(self.cx, self.cy)
  local cell = self.cells[idx]
  if cell and cell[2] then -- valid selectable cell
    self:trigger("cell-focus", self.cx, self.cy)
  end

  self:updateScroll()
end

function GridInterface:updateScroll()
  local idx = self:getIndex(self.cx, self.cy)
  local cell = self.cells[idx]
  if cell and cell[2] then -- valid selectable cell
    -- shift inner to current selected entry if not visible
    local overflow_y = cell[1].y+cell[1].h+GridInterface.MARGIN-self.h
    self:setInnerShift(0, overflow_y > 0 and -overflow_y or 0)
  else
    -- invalid selection, reset inner shift
    self:setInnerShift(0,0)
  end
end

function GridInterface:select()
  local cx, cy = self.cx, self.cy

  if cx >= 0 and cy >= 0 and cx < self.wc and cy < self.hc then
    local idx = self:getIndex(cx, cy)
    local cell = self.cells[idx]
    if cell and cell[2] then -- valid selectable cell
      -- sound effect
      self.gui:playSound("resources/audio/Item1.wav")
      self:trigger("cell-select", cx, cy)
    end
  end
end

-- override
function GridInterface:updateLayout(w,h)
  local MARGIN = GridInterface.MARGIN

  -- place widgets line by line with fixed width and height based on max cell height
  -- (vertical flow)
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

  if self.wrap == "vertical" then
    self:setSize(w,y)
  else
    self:setSize(w,h)
  end

  self.overlay:updateLayout(self.w,y) -- update inner overlay
  self:updateScroll()
end

return GridInterface
