local Base = require("ALGUI.ext.Renderer")
local XPBar = require("gui.XPBar")
local Phial = require("gui.Phial")
local Window = require("gui.Window")
local Text = require("gui.Text")
local TextInput = require("gui.TextInput")
local ChatHistory = require("gui.ChatHistory")
local GridInterface = require("gui.GridInterface")
local Inventory = require("gui.Inventory")
local TextureAtlas = require("TextureAtlas")

local Renderer = class("Renderer", Base)

-- STATICS

function Renderer.loadSystemBorders(x, y, w, h, margin)
  local borders = {
    x = x,
    y = y,
    w = w,
    h = h,
    margin = margin
  }

  -- corners
  -- top
  borders.ctl = love.graphics.newQuad(x,y,margin,margin,160,80)
  borders.ctr = love.graphics.newQuad(x+w-margin,y,margin,margin,160,80)
  -- bottom
  borders.cbl = love.graphics.newQuad(x,y+h-margin,margin,margin,160,80)
  borders.cbr = love.graphics.newQuad(x+w-margin,y+h-margin,margin,margin,160,80)

  -- middle
  borders.mt = love.graphics.newQuad(x+margin,y,y+h-margin*2,margin,160,80)
  borders.mb = love.graphics.newQuad(x+margin,y+h-margin,w-margin*2,margin,160,80)
  borders.ml = love.graphics.newQuad(x,margin,margin,h-margin*2,160,80)
  borders.mr = love.graphics.newQuad(x+w-margin,margin,margin,h-margin*2,160,80)

  return borders
end

function Renderer.loadSystem(client)
  local system = {}

  system.tex = client:loadTexture("resources/textures/system.png")
  system.background = love.graphics.newQuad(0,0,32,32,160,80)

  system.up_arrow = love.graphics.newQuad(40,8,16,8,160,80)
  system.down_arrow = love.graphics.newQuad(40,16,16,8,160,80)

  system.window_borders = Renderer.loadSystemBorders(32, 0, 32, 32, 5)
  system.select_borders = Renderer.loadSystemBorders(64, 0, 32, 32, 5)

  return system
end

-- WIDGETS DRAW

local widgets = {}

widgets[XPBar] = function(self, widget)
  local w, h = self.xp_tex:getDimensions()
  love.graphics.draw(self.xp_tex, 0, 0, 0, widget.w/w, widget.h/h)
end

widgets[Phial] = function(self, widget)
  local frame = math.floor(scheduler.time/Phial.STEP_DELAY)%3

  local full_quad = self.phials_atlas:getQuad((widget.ptype == "health" and 1 or 3), frame)
  local vx,vy,vw,vh = full_quad:getViewport()
  local sub_quad = love.graphics.newQuad(vx, vy, vw, vh*(Phial.SHIFT+(1-Phial.SHIFT)*(1-widget.factor)), full_quad:getTextureDimensions())

  -- draw phial texture
  love.graphics.draw(self.phials_tex, self.phials_atlas:getQuad((widget.ptype == "health" and 0 or 2), frame), 0, 0, 0, widget.w/self.phials_atlas.cell_w, widget.h/self.phials_atlas.cell_h)

  -- draw empty phial overlay texture
  love.graphics.draw(self.phials_tex, sub_quad, 0, 0, 0, widget.w/self.phials_atlas.cell_w, widget.h/self.phials_atlas.cell_h)
end

widgets[Window] = function(self, widget)
  -- background
  love.graphics.draw(self.system.tex, self.system.background, 1, 1, 0, (widget.w-2)/32, (widget.h-2)/32)

  love.graphics.push()
  love.graphics.scale(self.system_scale)
  self:drawBorders(self.system.window_borders, 0, 0, widget.w/self.system_scale, widget.h/self.system_scale)
  love.graphics.pop()
end

widgets[Text] = function(self, widget)
  love.graphics.draw(widget.display_text)
end

widgets[TextInput] = function(self, widget)
  -- H-scroll
  local x = math.min(0, widget.w-widget.display_text:getWidth())
  love.graphics.draw(widget.display_text, x, 0)
end

widgets[GridInterface.Overlay] = function(self, widget)
  local MARGIN = GridInterface.MARGIN
  local grid = widget.parent
  local blink = (scheduler.time%1 < 0.5) -- used for 0.5s blinking interval
  local cell = grid.cells[grid:getIndex(grid.cx, grid.cy)]

  -- draw selection
  if cell and cell[2] then
    love.graphics.push()
    love.graphics.translate(cell[1].x-MARGIN, cell[1].y-MARGIN)
    love.graphics.scale(self.system_scale)

    if blink then love.graphics.setColor(1,1,1,0.75) end
    self:drawBorders(self.system.select_borders, 0, 0, (cell[1].w+MARGIN*2)/self.system_scale, (cell[1].h+MARGIN*2)/self.system_scale)
    if blink then love.graphics.setColor(1,1,1) end

    love.graphics.pop()
  end

  if blink then
    -- draw blinking arrows
    --- up (top-right corner)
    if grid.iy < 0 then
      love.graphics.draw(self.system.tex, self.system.up_arrow, widget.w-16*self.system_scale-4, -grid.iy+4, 0, self.system_scale)
    end

    --- down (bottom-right corner)
    if widget.h+grid.iy > grid.h+MARGIN*2 then
      love.graphics.draw(self.system.tex, self.system.down_arrow, widget.w-16*self.system_scale-4, -grid.iy+grid.h-8*self.system_scale-4, 0, self.system_scale)
    end
  end
end

widgets[ChatHistory] = widgets[Window]
widgets[Inventory] = widgets[Window]

-- METHODS

function Renderer:__construct(client)
  self.phials_atlas = TextureAtlas(0,0,64,216,16,72)
  self.phials_tex = client:loadTexture("resources/textures/phials.png")
  self.xp_tex = client:loadTexture("resources/textures/xp.png")
  self.system = Renderer.loadSystem(client)
  self.system_scale = 2
end

-- override
function Renderer:render(gui)
  Base.render(self, gui)
  self:clip()
end

-- override
function Renderer:renderWidget(widget,x,y,scale)
  -- render widget
  local wr = widgets[class.type(widget)]
  if wr then
    love.graphics.push()
    love.graphics.translate(x,y)
    love.graphics.scale(scale)
    self:clip(widget.vx,widget.vy,widget.vw,widget.vh)
    wr(self, widget)
    love.graphics.pop()
  end
end

-- clip using current draw transform state
-- x,y,w,h: (optional) relative surface
function Renderer:clip(x,y,w,h)
  if x then
    local x1,y1 = love.graphics.transformPoint(x,y)
    local x2,y2 = love.graphics.transformPoint(x+w,y+h)
    love.graphics.setScissor(x1,y1,x2-x1,y2-y1)
  else
    love.graphics.setScissor()
  end
end

-- draw rect based on borders
function Renderer:drawBorders(borders, x, y, w, h)
  local b = borders

  -- borders
  --- corners
  love.graphics.draw(self.system.tex, b.ctl, x, y)
  love.graphics.draw(self.system.tex, b.ctr, x+w-b.margin, y)
  love.graphics.draw(self.system.tex, b.cbl, x, y+h-b.margin)
  love.graphics.draw(self.system.tex, b.cbr, x+w-b.margin, y+h-b.margin)
  --- middles
  love.graphics.draw(self.system.tex, b.mt, x+b.margin, y, 0, (w-b.margin*2)/(b.w-b.margin*2), 1)
  love.graphics.draw(self.system.tex, b.mb, x+b.margin, y+h-b.margin, 0, (w-b.margin*2)/(b.w-b.margin*2), 1)
  love.graphics.draw(self.system.tex, b.ml, x, y+b.margin, 0, 1, (h-b.margin*2)/(b.h-b.margin*2))
  love.graphics.draw(self.system.tex, b.mr, x+w-b.margin, y+b.margin, 0, 1, (h-b.margin*2)/(b.h-b.margin*2))
end

return Renderer
