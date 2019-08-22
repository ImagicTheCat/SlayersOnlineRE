local Widget = require("gui/Widget")

-- textual grid widget
local Selector = class("Selector", Widget)

-- wc, hc: number of columns/rows
function Selector:__construct(client, wc, hc)
  Widget.__construct(self, client)

  self.blink_time = 0

  self:init(wc,hc)
end

function Selector:init(wc, hc)
  self.wc, self.hc = wc, hc
  self.cells = {} -- map of index => {.text, .callback, .disp_text}
  self.cx, self.cy = 0, 0 -- cursor
end

function Selector:clear()
  self.cells = {}
end

-- return cell index
function Selector:getIndex(x, y)
  return y*self.wc+x
end

-- set cell
-- x, y: cell coordinates
-- text: cell text, nil to remove
-- callback(self, x, y, selected): can be nil, called when the cell is selected/"pressed"
--- selected: true if selected, false if overed
function Selector:set(x, y, text, callback)
  if x >= 0 and y >= 0 and x < self.wc and y < self.hc then
    local idx = self:getIndex(x, y)
    if text then
      local disp_text = love.graphics.newText(self.client.font)
      disp_text:set(text)

      self.cells[idx] = {text = text, callback = callback, disp_text = disp_text}
    else
      self.cells[idx] = nil
    end
  end
end

function Selector:moveSelect(dx, dy)
  self.cx = self.cx+dx
  self.cy = self.cy+dy

  if self.cx < 0 then self.cx = (self.wc-(-self.cx)%self.wc)%self.wc else self.cx = self.cx%self.wc end
  if self.cy < 0 then self.cy = (self.hc-(-self.cy)%self.hc)%self.hc else self.cy = self.cy%self.hc end

  -- sound effect
  self:playSound("resources/audio/Cursor1.wav")

  local idx = self:getIndex(self.cx, self.cy)
  local cell = self.cells[idx]
  if cell and cell.callback then
    cell.callback(self, self.cx, self.cy, false)
  end
end

function Selector:select()
  local cx, cy = self.cx, self.cy

  if cx >= 0 and cy >= 0 and cx < self.wc and cy < self.hc then
    local idx = self:getIndex(cx, cy)
    local cell = self.cells[idx]
    if cell and cell.callback then
      -- sound effect
      self:playSound("resources/audio/Item1.wav")

      cell.callback(self, cx, cy, true)
    end
  end
end

function Selector:tick(dt)
  self.blink_time = (self.blink_time+dt)%1
end

-- overload
function Selector:draw()
  local scale = self.client.gui_scale
  local inv_scale = 1/scale

  local cell_w, cell_h = self.w/self.wc, self.client.font:getHeight()*inv_scale+6
  local selected_idx = self:getIndex(self.cx, self.cy)
  local blink = (self.blink_time < 0.5) -- used for 1s blinking states

  -- shift to current selected entry if not visible
  local shift_cy = 0
  local overflow_y = (self.cy+1)*cell_h-self.h
  if overflow_y > 0 then
    shift_cy = math.ceil(overflow_y/cell_h)
  end

  -- compute last visible cell y
  local last_cy = math.min(math.ceil(self.h/cell_h)+shift_cy, self.hc-1)

  for cx=0, self.wc-1 do
    for cy=shift_cy, last_cy do
      local idx = self:getIndex(cx,cy)
      local cell = self.cells[idx]

      local x = self.x+cx*cell_w
      local y = self.y+(cy-shift_cy)*cell_h

      -- clamp render to selector height
      local max_h = math.max(0, math.min(self.y+self.h, y+cell_h)-y)

      love.graphics.setScissor(x*scale, y*scale, cell_w*scale, max_h*scale)

      if cell then
        love.graphics.draw(cell.disp_text, x+3, y+3, 0, inv_scale)
      end

      if idx == selected_idx then -- draw selection
        self:drawBorders(self.system.select_borders, x, y, cell_w, cell_h)
      end
    end
  end

  love.graphics.setScissor()

  if blink then
    -- draw blinking arrows
    --- up
    if shift_cy > 0 then
      love.graphics.draw(self.system.tex, self.system.up_arrow, self.x+self.w-16-4, self.y+4)
    end

    --- down
    if (last_cy-shift_cy+1)*cell_h > self.h then
      love.graphics.draw(self.system.tex, self.system.down_arrow, self.x+self.w-16-4, self.y+self.h-8-4)
    end
  end
end

return Selector
