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

-- basic deep clone function (doesn't handle circular references)
function utils.clone(t)
  if type(t) == "table" then
    local new = {}
    for k,v in pairs(t) do
      new[k] = clone(v)
    end

    return new
  else
    return t
  end
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

return utils
