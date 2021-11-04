
local Inventory = class("Inventory")

-- METHODS

-- inventory: inventory index (unsigned)
-- max: max items
function Inventory:__construct(user_id, inventory, max)
  self.id = inventory
  self.user_id = user_id
  self.max = max

  self.items = {} -- map of id => amount
  self.changed_items = {} -- map of id
end

-- (async)
-- db: DBManager
function Inventory:load(db)
  self.items = {}
  self.changed_items = {}
  local rows = db:query("inventory/getItems", {self.user_id, self.id}).rows
  for _, row in ipairs(rows) do self.items[row.id] = row.amount end
end

-- (async)
-- db: DBManager
function Inventory:save(db)
  local changed_items = self.changed_items
  self.changed_items = {}
  for id in pairs(changed_items) do
    local amount = self.items[id]
    if amount and amount > 0 then
      db:query("inventory/setItem", {self.user_id, self.id, id, amount})
    else
      db:query("inventory/removeItem", {self.user_id, self.id, id})
    end
  end
end

-- set item amount
function Inventory:set(id, amount)
  if amount > 0 then
    self.items[id] = amount
  else
    self.items[id] = nil
  end

  self.changed_items[id] = true
  self:onItemUpdate(id)
end

function Inventory:get(id)
  return self.items[id] or 0
end

-- take one item
-- dry: (optional) if truthy, no effects
-- return true on success
function Inventory:take(id, dry)
  local amount = self.items[id]
  if amount and amount > 0 then
    if not dry then self:set(id, amount-1) end
    return true
  end
end

-- put one item
-- dry: (optional) if truthy, no effects
-- return true on success
function Inventory:put(id, dry)
  if self:getAmount() < self.max then
    if not dry then self:set(id, (self.items[id] or 0)+1) end
    return true
  end
end

-- return items amount
function Inventory:getAmount()
  local total = 0
  for id, amount in pairs(self.items) do
    total = total+amount
  end

  return total
end

-- called when an item slot is updated (amount/nil)
function Inventory:onItemUpdate(id)
end

return Inventory
