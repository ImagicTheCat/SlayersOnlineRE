-- https://github.com/ImagicTheCat/SlayersOnlineRE
-- MIT license (see LICENSE, src/server/main.lua or src/client/main.lua)

-- Compile spell expressions/statements to Lua functions.
-- Recursive descent parser with prediction (not LL(k)) and a lexer pass.
--
--[[
EBNF-like:
function_var = '%' text args '%'
args = '(' expr {',' expr} ')'
identifier = identifier_item {identifier_item}
identifier_item = token - ';'
spell_command = 'spell' ':' identifier
var_target = 'Cible' | 'Wizard'
var = '%' '[' var_target ']' '.' (cvar | text) '%'
cvar = 'Variable' '[' expr ']'
assignment = var '=' expr
statement = assignment | spell_command
statements = {statement ';'}
expr = expr1 {expr_op expr1}
expr_op = '+' | '-'
expr1 = expr2 {expr1_op expr2}
expr1_op = '*' | '/'
expr2 = ['-'] value
value = var | function_var | number | '(' expr ')'
]]

local M = {}

-- Lexer pass.
-- Extract token strings: grammar symbol, numbers and text.
-- A symbol token only contains one character.
-- Text contains anything else.
--
-- return list of tokens
--- token: {str, type}
local function lex(str)
  local tokens = {}
  local cur = 1
  local mode
  local function advance(i, new_mode)
    if mode ~= new_mode then
      if cur < i then table.insert(tokens, {str:sub(cur, i-1), mode}) end
      mode = new_mode; cur = i
    end
  end
  for i=1, #str do
    local c = str:sub(i,i)
    if mode == "number" and c:match("%.") then advance(i, "number")
    elseif c:match("[%.%(%)%%%[%],=%+%-%*/;:]") then -- symbol
      advance(i, "symbol")
      table.insert(tokens, {c, "symbol"})
      cur = i+1
    elseif c:match("%d") then
      advance(i, "number")
    else -- text
      advance(i, "text")
    end
  end
  advance(#str+1, "end")
  return tokens
end

local Parser = {}

function Parser:init(tokens)
  self.tokens = tokens
  self.i, self.pos = 1, 1
end

function Parser:error(err)
  local t = self.tokens[self.i]
  error("parse error at character "..self.pos.." " --
    ..(t and "\""..t[1].."\"" or "<end>")..": "..err)
end

-- Advance by n tokens.
function Parser:advance(n)
  -- accumulate character position
  for i=1,n do
    local t = self.tokens[self.i+i-1]
    self.pos = self.pos+(t and #t[1] or 0)
  end
  self.i = self.i+n
end

-- Tokens prediction.
-- ...: list of match tokens {str, type}, str and type can be omitted with nil
--- special tokens:
---- "end": end of the token stream
---- "identifier": identifier made of tokens, except ';'
-- return bool
function Parser:predict(...)
  local i = 1 -- relative token index
  for _, arg in ipairs({...}) do
    if arg == "end" then
      if self.i+i-1 <= #self.tokens then return false end
      i = i+1
    elseif arg == "identifier" then
      local found = false
      local token = self.tokens[self.i+i-1]
      while token and token[1] ~= ';' do
        i = i+1; found = true
        token = self.tokens[self.i+i-1]
      end
      if not found then return false end
    else -- token matching
      local t = self.tokens[self.i+i-1]
      if not t or (arg[1] and t[1] ~= arg[1]) or (arg[2] and t[2] ~= arg[2]) then
        return false
      end
      i = i+1
    end
  end
  return true
end

-- Multiple tokens predictions.
-- ...: list of list of predict() arguments
-- return bool
function Parser:predictAny(...)
  for i, arg in ipairs({...}) do
    if self:predict(unpack(arg)) then return true end
  end
end

-- Check following tokens and advance on success.
-- ...: token strings
-- return bool
function Parser:check(...)
  local args = {...}
  for i, arg in ipairs(args) do
    local token = self.tokens[self.i+i-1]
    if not token or token[1] ~= arg then return false end
  end
  self:advance(#args)
  return true
end

-- Expect following tokens.
-- ...: token strings
function Parser:expect(...)
  if not self:check(...) then self:error("expecting \""..table.concat({...}).."\"") end
end

-- Prefix a non-terminal produced data while preserving boolean property.
local function prefix(name, data) return data and {name, data} end

-- ttype: (optional) token type
function Parser:token(ttype)
  local t = self.tokens[self.i]
  if t and (not ttype or t[2] == ttype) then
    self:advance(1)
    return t
  end
end

function Parser:identifier()
  local item = self:identifier_item()
  if item then
    local items = {item[1]}
    while item do
      item = self:identifier_item()
      table.insert(items, item and item[1])
    end
    return table.concat(items)
  end
end

function Parser:identifier_item()
  if not self:predict({';'}) then return self:token() end
end

function Parser:spell_command()
  if self:check('spell', ':') then
    local id = self:identifier()
    if not id then self:error("expecting spell identifier") end
    return "spell(state, "..string.format("%q", id)..")"
  end
end

function Parser:var_target()
  if self:check('Wizard') then return "caster"
  elseif self:check('Cible') then return "target" end
end

function Parser:var()
  if self:check('%', '[') then
    -- target
    local target = self:var_target()
    if not target then self:error("expecting var target") end
    self:expect(']', '.')
    -- property
    local prop = prefix("cvar", self:cvar())
    if prop and target ~= "caster" then self:error("invalid target for cvar") end
    if not prop then -- fallback to text
      local text = self:token("text")
      if text then prop = prefix("text", text[1]) end
    end
    if not prop then self:error("expecting var property") end
    self:expect('%')
    return {target, prop}
  end
end

function Parser:cvar()
  if self:check("Variable", '[') then
    local expr = self:expr()
    if not expr then self:error("expecting expression") end
    self:expect(']')
    return expr
  end
end

-- return code
function Parser:args()
  if self:check('(') then
    local args = {}
    repeat
      local expr = self:expr()
      if not expr then self:error("expecting expression") end
      table.insert(args, "R("..expr..")")
    until not self:check(',')
    self:expect(')')
    return table.concat(args, ", ")
  end
end

-- return code
function Parser:function_var()
  if self:check('%') then
    local id = self:token("text")
    if not id then self:error("expecting identifier") end
    local args = self:args({'%'})
    if not args then self:error("expecting arguments") end
    self:expect('%')
    return "func_var(state, \""..id[1].."\", "..args..")"
  end
end

function Parser:assignment()
  local var = self:var()
  if var then
    self:expect('=')
    local expr = self:expr()
    if not expr then self:error("expecting expression") end
    -- generate
    local prop = var[2]
    if prop[1] == "cvar" then return "var(state, R("..prop[2].."), R("..expr.."))"
    else return var[1].."_var(state, \""..prop[2].."\", R("..expr.."))" end
  end
end

function Parser:statement()
  return self:assignment() or self:spell_command()
end

function Parser:statements()
  local code = {}
  repeat
    local statement = self:statement()
    if statement then
      table.insert(code, statement)
      self:expect(';')
    end
  until not statement
  return table.concat(code, "\n")
end

function Parser:expr_op()
  if self:check('+') then return '+'
  elseif self:check('-') then return '-' end
end

function Parser:expr()
  local code = {}
  local expr1 = self:expr1()
  if expr1 then
    table.insert(code, expr1)
    local op = self:expr_op()
    while op do
      local nexpr1 = self:expr1()
      if not nexpr1 then self:error("expecting expression(1)") end
      table.insert(code, op)
      table.insert(code, nexpr1)
      -- next
      op = self:expr_op()
    end
    return table.concat(code)
  end
end

function Parser:expr1_op()
  if self:check('*') then return '*'
  elseif self:check('/') then return '/' end
end

function Parser:expr1()
  local code = {}
  local expr2 = self:expr2()
  if expr2 then
    table.insert(code, expr2)
    local op = self:expr1_op()
    while op do
      local nexpr2 = self:expr2()
      if not nexpr2 then self:error("expecting expression(2)") end
      table.insert(code, op)
      table.insert(code, nexpr2)
      -- next
      op = self:expr1_op()
    end
    return table.concat(code)
  end
end

function Parser:expr2()
  local um = self:check('-')
  local value = self:value()
  if um and not value then self:error("expecting value") end
  if value then return (um and "-" or "")..value end
end

function Parser:value()
  -- var
  local var = self:var()
  if var then
    local prop = var[2]
    if prop[1] == "cvar" then return "var(state, R("..prop[2].."))"
    else return var[1].."_var(state, \""..prop[2].."\")" end
  end
  -- function var
  local fvar = self:function_var()
  if fvar then return fvar end
  -- number
  local number = self:token("number")
  if number then return number[1] end -- (Itsugo)
  -- expr
  if self:check('(') then
    local expr = self:expr()
    if not expr then self:error("expecting expression") end
    self:expect(')')
    return "("..expr..")"
  end
end

-- Compilation.

local function compileExpression(p, str)
  p:init(lex(str))
  local expr = p:expr()
  if p.i <= #p.tokens then p:error("unexpected token") end
  if expr then return "return "..expr else return "" end
end

-- Compile expression to Lua code.
-- return code or (nil, err)
function M.compileExpression(str)
  local p = setmetatable({}, {__index = Parser})
  local ok, r = pcall(compileExpression, p, str)
  if not ok then return nil, r else return r end
end

local function compileStatements(p, str)
  p:init(lex(str))
  local statements = p:statements()
  if not statements then p:error("expecting statements") end
  if p.i <= #p.tokens then p:error("unexpected token") end
  return statements
end

-- Compile statements to Lua code.
-- return code or (nil, err)
function M.compileStatements(str)
  local p = setmetatable({}, {__index = Parser})
  local ok, r = pcall(compileStatements, p, str)
  if not ok then return nil, r else return r end
end

return M
