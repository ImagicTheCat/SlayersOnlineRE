
local Inventory = class("Inventory")

-- PRIVATE STATICS

local q_get_items = "SELECT id, amount FROM users_items WHERE user_id = {1} AND inventory = {2}"
local q_set_item = "INSERT INTO users_items(user_id, inventory, id, amount) VALUES({1},{2},{3},{4}) ON DUPLICATE KEY UPDATE amount = {4}"
local q_rm_item = "DELETE FROM users_items WHERE user_id = {1} AND inventory = {2} AND id = {3}"

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

  local rows = db:query(q_get_items, {self.user_id, self.id})

  for _, row in ipairs(rows) do
    local id = tonumber(row.id)
    local amount = tonumber(row.amount)

    self.items[id] = amount
  end
end

-- (async)
-- db: DBManager
function Inventory:save(db)
  for id in pairs(self.changed_items) do
    local amount = self.items[id]
    if amount and amount > 0 then
      db:query(q_set_item, {self.user_id, self.id, id, amount})
    else
      db:query(q_rm_item, {self.user_id, self.id, id})
    end
  end

  self.changed_items = {}
end

-- set item amount
function Inventory:set(id, amount)
  if amount > 0 then
    self.items[id] = amount
  else
    self.items[id] = nil
  end

  self.changed_items[id] = true
end

-- take one item
-- return true on success
function Inventory:take(id)
  local amount = self.items[id]
  if amount and amount > 0 then
    self:set(id, amount-1)
    return true
  end
end

-- put one item
-- return true on success
function Inventory:put(id)
  if self:getAmount() < self.max then
    self:set(id, (self.items[id] or 0)+1)
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

return Inventory
