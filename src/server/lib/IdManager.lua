
local IdManager = class("IdManager")

function IdManager:__construct()
  self:clear()
end

function IdManager:clear()
  self.max = 0
  self.ids = {}
end

-- return a new id
function IdManager:gen()
  if #self.ids > 0 then
    return table.remove(self.ids)
  else
    local r = self.max
    self.max = self.max+1
    return r
  end
end

-- free a previously generated id
function IdManager:free(id)
  table.insert(self.ids,id)
end

return IdManager
