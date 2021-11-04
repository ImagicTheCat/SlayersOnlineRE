local utils = {}

function utils.round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

-- split string
-- sep: separator pattern word
function utils.split(str, sep)
  local r = {}

  local cursor = 1
  local pos, pend
  repeat
    pos, pend = string.find(str, sep, cursor)
    if pos then
      table.insert(r, string.sub(str, cursor, pos-1))
      cursor = pend+1
    end
  until not pos 

  if cursor <= string.len(str) then
    table.insert(r, string.sub(str, cursor))
  end

  return r
end

function utils.clamp(x, a, b)
  return math.max(math.min(x, b), a)
end

function utils.randf(a, b)
  return math.random()*(b-a)+a
end

function utils.sign(x)
  return x == 0 and 0 or (x > 0 and 1 or -1)
end

-- f_bytecode: if passed/true, will allow bytecode
function utils.loadstring(code, f_bytecode)
  if not f_bytecode and code:byte(1) == 27 then return nil end
  return loadstring(code)
end

function utils.pointInRect(x, y, rx, ry, rw, rh)
  return (x >= rx and y >= ry and x <= rx+rw and y <= ry+rh)
end

function utils.lerp(a, b, x)
  return a*(1-x)+b*x
end

-- merge a into b (deep)
-- replace all keys of b by a keys, unless both keys are tables => recursive merge
-- a, b: tables
function utils.mergeInto(a, b)
  for k,v in pairs(a) do
    if type(v) == "table" and type(b[k]) == "table" then -- merge
      utils.mergeInto(v, b[k])
    else -- raw set
      b[k] = v
    end
  end
end

-- return fixed scale (to get integer mult/div on the passed size)
function utils.floorScale(scale, size)
  if scale < 1 then return math.floor(scale*size)/size
  else return math.floor(scale) end
end

-- Basic deep clone function (doesn't handle circular references).
-- t: a Lua value
-- depth: (optional) maximum depth
--- 0: return the passed value
--- 1: clone the value, not children
function utils.clone(t, depth)
  if depth == 0 then return t end
  if type(t) == "table" then
    local new = {}
    for k,v in pairs(t) do new[k] = utils.clone(v, depth and depth-1) end
    return new
  else return t end
end

local function hex_conv(c)
  return string.format('%02X', string.byte(c))
end

-- convert string to hexadecimal
function utils.hex(str)
  return string.gsub(str, '.', hex_conv)
end

-- pure Lua gsub (work with coroutines)
-- callback(...): pass captures, should return replacement value
function utils.gsub(str, pattern, callback)
  local parts = {}

  local cursor = 1
  local pb, pe
  repeat
    local rfind = {string.find(str, pattern, cursor)}
    pb, pe = rfind[1], rfind[2]
    if not pb then -- not found
      pb = string.len(str)+1
      pe = pb
    end

    -- between part: cursor to found
    table.insert(parts, string.sub(str, cursor, pb-1))

    -- found part
    if pb <= string.len(str) then
      table.insert(parts, callback(unpack(rfind, 3)) or found_part)
    end

    cursor = pe+1
  until cursor > string.len(str)

  return table.concat(parts)
end

-- dump value (deep)
-- v: value
-- level: (optional) current level (default: 0)
-- return string
function utils.dump(v, level)
  if not level then level = 0 end
  if type(v) == "table" then
    local lines = {}
    for sk,sv in pairs(v) do
      table.insert(lines, string.rep(" ", level*2)..sk.." = "..(type(sv) == "table" and "\n" or "")..utils.dump(sv, level+1))
    end
    return table.concat(lines, "\n")
  else
    return tostring(v)
  end
end

-- process/compute string expression using basic Lua features
-- return computed number (integer) or nil on failure
function utils.computeExpression(str)
  if string.find(str, "[^%.%*/%-%+%(%)%d%s]") then return end -- reject on unallowed characters

  local expr = "return "..str
  local f = utils.loadstring(expr)
  local ok, r = pcall(f)
  if ok then
    local n = tonumber(r)
    if n and n == n and math.abs(n) ~= 1/0 then -- reject NaN/inf values
      return utils.round(n)
    end
  end
end

-- format number (with 3 digits separation)
-- sign: if passed/truthy, keep positive sign symbol
-- return string
function utils.fn(n, sign)
  local formatted = n, k
  repeat
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1 %2')
  until k == 0
  if sign and n > 0 then return "+"..formatted
  else return formatted end
end

function utils.pack(...) return {n = select("#", ...), ...} end

-- Bi-directional map.
-- Build a table with (k,v) pairs and (v,k) pairs.
-- v: (optional) override value for all (v,k) pairs
function utils.bimap(t, v)
  local nt = {}
  for mk, mv in pairs(t) do
    nt[mk] = mv
    nt[mv] = (v ~= nil and v or mk)
  end
  return nt
end

-- Compute direction vector (no diagonal) from delta.
function utils.dvec(dx, dy)
  local g_x = math.abs(dx) > math.abs(dy)
  if dy < 0 and not g_x then return 0,-1
  elseif dx > 0 and g_x then return 1,0
  elseif dy > 0 and not g_x then return 0,1
  elseif dx < 0 and g_x then return -1,0
  else return 0,0 end
end

function utils.sanitizeInt(v)
  if v ~= v then return 0 -- NaN
  elseif math.abs(v) == 1/0 then return 0 -- inf
  else return math.floor(v) end
end

return utils
