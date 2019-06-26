local utils = {}

function utils.round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

-- split string
-- sep: separator pattern word
function utils.split(str, sep)
  local r = {}

  local cursor = 1, pos, pend
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

return utils
