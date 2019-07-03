local Window = require("gui/Window")
local Selector = require("gui/Selector")

local Menu = class("Menu", Window)

local function m_all(selector, x, y, selected)
end

function Menu:__construct(client)
  Window.__construct(self, client)

  self.selector = Selector(client, 1, 5)
end

-- overload
function Menu:update(x, y, w, h)
  Window.update(self,x,y,w,h)

  self.selector:update(x+3,y+3,w-6,h-6)

  self.selector:set(0,0, "Inventory", m_all)
  self.selector:set(0,1, "Spells", m_all)
  self.selector:set(0,2, "Stats", m_all)
  self.selector:set(0,3, "Trade", m_all)
  self.selector:set(0,4, "Quit", m_all)
end

-- overload
function Menu:draw()
  Window.draw(self)

  self.selector:draw()
end

return Menu
