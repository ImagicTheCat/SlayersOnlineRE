-- https://github.com/ImagicTheCat/SlayersOnlineRE
-- MIT license (see LICENSE, src/server/main.lua or src/client/main.lua)

-- Compile event conditions/commands to Lua functions.
-- Recursive descent parser with prediction (not LL(k)) and a lexer pass.
--
--[[
EBNF-like:
condition = condition_flag | inventory cmp_op expr | expr cmp_op expr_empty
inventory = '%' 'Inventaire' '%'
condition_flag = 'Appuie sur bouton' | 'Automatique' | 'Auto une seul fois' |
  'En contact' | 'Attaque'
command = call_condition | call | assignment
call = text [args | quoted_args]
call_condition = 'Condition' '(' ''' condition ''' ')'
assignment = lvar '=' (concat | expr)
lvar = var | bool_var | server_var | special_var | event_var
args = '(' expr {',' expr} ')'
quoted_args = '(' ''' expr {''' ',' ''' expr} ''' ')'
cmp_op = '=' | '<=' | '>=' | '<' | '>' | '!='
var = 'Variable' '[' var_index ']'
bool_var = 'Bool' '[' var_index ']'
var_index = range | expr
server_var = 'Serveur' '[' expr ']'
special_var = '%' text '%'
event_var = '%' identifier '.' text '%'
identifier = identifier_item {identifier_item}
identifier_item = '-' | whitespace | text
function_var = '%' text args '%'
input_string = 'InputString' quoted_args
concat = 'Concat' quoted_args
range = text '..' text
expr = expr_item {expr_item}
expr_empty = {expr_item}
expr_item = lvar | function_var | input_string | token

Notes:
- "expr" uses prediction to stop token consumption
]]

local M = {}

local keywords = {"Variable", "Bool", "Serveur", "InputString"}

-- Lexer pass.
-- Extract token strings: grammar symbol, whitespace and text.
-- A symbol token only contains one character.
-- Whitespace matches "%s" pattern.
-- Text can contain anything else.
-- Keywords will be used to fragment the text.
--
-- return list of tokens
--- token: {str, type}
local function lex(str)
  local tokens = {}
  local cur = 1
  local mode
  local function advance(i, new_mode)
    -- find keyword at the end of the current text buffer
    if mode == "text" then
      local buffer = str:sub(cur, i-1)
      for _, keyword in ipairs(keywords) do
        local part = buffer:match("^(.*)"..keyword.."$")
        if part then
          if #part > 0 then table.insert(tokens, {part, mode}) end
          -- insert keyword
          table.insert(tokens, {keyword, mode})
          cur = i
          break
        end
      end
    end
    if mode ~= new_mode then
      if cur < i then table.insert(tokens, {str:sub(cur, i-1), mode}) end
      mode = new_mode; cur = i
    end
  end
  for i=1, #str do
    local c = str:sub(i,i)
    if c:match("[%.%(%)%%%[%],'=<>!%+%-%*/]") then -- symbol
      advance(i, "symbol")
      table.insert(tokens, {c, "symbol"})
      cur = i+1
    elseif c:match("%s") then -- whitespace
      advance(i, "whitespace")
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
---- "identifier": identifier made of text, spaces and '-' symbol
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
      while token and (token[2] == "text" or token[2] == "whitespace" or
          (token[2] == "symbol" and token[1] == '-')) do
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
-- return bool
-- ...: token strings
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

function Parser:cmp_op()
  if self:check('=') then return '=='
  elseif self:check('<', '=') then return '<='
  elseif self:check('>', '=') then return '>='
  elseif self:check('<') then return '<'
  elseif self:check('>') then return '>'
  elseif self:check('!', '=') then return '~='
  end
end

function Parser:range()
  local a = self:token("text")
  if a then
    self:expect('.', '.')
    local b = self:token("text")
    if not b then self:error("expecting integer") end
    -- produce data
    a = tonumber(a[1]); if not a then self:error("invalid range integer") end
    b = tonumber(b[1]); if not b then self:error("invalid range integer") end
    return {a,b}
  end
end

function Parser:var_index()
  if self:predict({nil, "text"}, {'.'}, {'.'}) then return prefix("range", self:range())
  else return prefix("expr", self:expr(false, {{{']'}}})) end
end

function Parser:var()
  if self:check('Variable', '[') then
    local var_index = self:var_index()
    if not var_index then self:error("expecting var index") end
    self:expect(']')
    return var_index
  end
end

function Parser:bool_var()
  if self:check('Bool', '[') then
    local var_index = self:var_index()
    if not var_index then self:error("expecting var index") end
    self:expect(']')
    return var_index
  end
end

function Parser:server_var()
  if self:check('Serveur', '[') then
    local expr = self:expr(false, {{{']'}}})
    if not expr then self:error("expecting expression") end
    self:expect(']')
    return expr
  end
end

function Parser:special_var()
  if self:check('%') then
    local id = self:token("text")
    if not id then self:error("expecting identifier") end
    self:expect('%')
    return id[1]
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
  if self:predictAny({{'-', "symbol"}}, {{nil, "whitespace"}}, {{nil, "text"}}) then
    return self:token()
  end
end

function Parser:event_var()
  if self:check('%') then
    local event_id = self:identifier()
    if not event_id then self:error("expecting event identifier") end
    self:expect('.')
    local var_id = self:token("text")
    if not var_id then self:error("expecting variable identifier") end
    self:expect('%')
    return {event_id, var_id[1]}
  end
end

function Parser:lvar() -- left value var, LHS
  local lvar = prefix("var", self:var()) or
    prefix("bool_var", self:bool_var()) or
    prefix("server_var", self:server_var())
  if not lvar then
    if self:predict({'%'}, {nil, "text"}, {'%'}) then
      lvar = prefix("special_var", self:special_var())
    elseif self:predict({'%'}, "identifier", {'.'}, {nil, "text"}, {'%'}) then
      lvar = prefix("event_var", self:event_var())
    end
  end
  return lvar
end

-- end_token: (optional) additional prediction token to end the argument production
-- return code
function Parser:args(end_token)
  if self:check('(') then
    local args = {}
    repeat
      -- end expression at "," or ")"
      local expr = self:expr(true, { {{','}}, {{')'}, end_token} })
      if not expr then self:error("expecting expression") end
      table.insert(args, expr)
    until not self:check(',')
    self:expect(')')
    return table.concat(args, ", ")
  end
end

-- end_token: (optional) additional prediction token to end the argument production
-- return code
function Parser:quoted_args(end_token)
  if self:check('(', "'") then
    local args = {}
    repeat
      -- end expression at "','" or "')"
      local expr = self:expr(true, {{{"'"}, {','}, {"'"}}, {{"'"}, {')'}, end_token}})
      if not expr then self:error("expecting expression") end
      table.insert(args, expr)
    until not self:check("'", ',', "'")
    self:expect("'", ')')
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
    return "func_var(\""..id[1].."\", "..args..")"
  end
end

-- return code
function Parser:input_string()
  if self:check('InputString') then
    local args = self:quoted_args()
    if not args then self:error("expecting quoted arguments") end
    return "func(\"InputString\""..(#args > 0 and ", "..args..")" or ")")
  end
end

-- return code
function Parser:concat()
  if self:check('Concat') then
    local args = self:quoted_args()
    if not args then self:error("expecting quoted arguments") end
    return args
  end
end

function Parser:inventory()
  return self:check('%', 'Inventaire', '%')
end

function Parser:expr_item()
  if self:predict({'%'}, {nil, "text"}, {'('}) then
    return prefix("code", self:function_var())
  else
    -- Generate lvar expr code.
    local lvar = self:lvar()
    if lvar then
      local code
      if lvar[1] == "var" or lvar[1] == "bool_var" then
        local var_index = lvar[2]
        if var_index[1] == "range" then
          self:error("a range is invalid in an expression")
        else -- expr
          code = lvar[1].."("..var_index[2]..")"
        end
      elseif lvar[1] == "server_var" then code = "server_var("..lvar[2]..")"
      elseif lvar[1] == "special_var" then code = "special_var(\""..lvar[2].."\")"
      elseif lvar[1] == "event_var" then
        local event_var = lvar[2]
        code = "event_var(\""..event_var[1].."\", \""..event_var[2].."\")"
      end
      if not code then self:error("no code generated for lvar") end
      lvar = code
    end
    return prefix("code", lvar) or
      prefix("code", self:input_string()) or
      prefix("token", self:token())
  end
end

local function escape_token(str)
  -- escape ", \, but allow \n
  return (str:gsub("\\([^n])", "\\\\%1") --
    :gsub("\\$", "\\\\") --
    :gsub("\"", "\\\""))
end

-- end_predictions: (optional) list of predictions to end the expression
-- return code
function Parser:expr(allow_empty, end_predictions)
  -- check for first item
  if (not end_predictions or not self:predictAny(unpack(end_predictions))) then
    local first_item = self:expr_item()
    if first_item then
      local items = {first_item}
      -- take more items
      while (not end_predictions or not self:predictAny(unpack(end_predictions))) do
        local item = self:expr_item()
        if not item then break end
        table.insert(items, item)
      end
      -- Generate code.
      -- We must detect if the expression is a computation or a concatenation.
      -- A computation will produce an integer from the expression, whereas a
      -- concatenation will produce a string. We try the computation first.
      local parts = {}
      -- A valid computation has multiple items or a single one, a number.
      local valid_computation = (#items > 1 or
        (items[1][1] == "token" and tonumber(items[1][2][1])))
      -- A valid computation has only number/whitespace tokens and other non-tokens.
      for _, item in ipairs(items) do -- add code or token str
        if item[1] == "token" then -- token, check if not text (except number)
          local token = item[2]
          if token[2] == "text" and not tonumber(token[1]) then
            valid_computation = false; break
          end
          table.insert(parts, token[1])
        else table.insert(parts, "N("..item[2]..")") end -- code
      end
      -- Check for valid computation expression.
      local code = "R("..table.concat(parts)..")"
      if not valid_computation or not loadstring("return "..code) then
        -- fallback to concatenation
        local parts = {}
        local i = 1
        while i <= #items do -- each item
          local item = items[i]
          if item[1] == "token" then -- token, quoted with escape
            local tokens = {}
            repeat -- aggregate tokens as one
              table.insert(tokens, escape_token(item[2][1]))
              i = i+1
              item = items[i]
            until not item or item[1] ~= "token"
            table.insert(parts, "\""..table.concat(tokens).."\"")
          else table.insert(parts, "S("..item[2]..")"); i = i+1 end -- raw code
        end
        code = table.concat(parts, "..")
      end
      return code
    end
  end
  if allow_empty then return "\"\"" end -- empty string
end

function Parser:condition_flag()
  -- handle special flag conditions
  if self:check('Appuie', ' ', 'sur', ' ', 'bouton') then return "interact"
  elseif self:check('Automatique') then return "auto"
  elseif self:check('Auto', ' ', 'une', ' ', 'seul', ' ', 'fois') then return "auto-once"
  elseif self:check('En', ' ', 'contact') then return "contact"
  elseif self:check('Attaque') then return "attack"
  end
end

-- end_predictions: (optional) list of predictions to end the right expression
function Parser:condition(end_predictions)
  -- flag
  local cflag = self:condition_flag()
  if cflag then return {"flag", cflag} end
  -- inventory comparison
  if self:inventory() then
    local op = self:cmp_op()
    if not op then self:error("expecting comparison operator") end
    local expr = self:expr(true, end_predictions)
    if not expr then self:error("expecting expression") end
    if op == "==" then return {"code", "inventory("..expr..")>0"}
    elseif op == "~=" then return {"code", "inventory("..expr..")==0"}
    else self:error("invalid inventory comparison operator") end
  end
  -- expression comparison
  local lexpr = self:expr(false, { {{'='}}, {{'<'}}, {{'>'}}, {{'!'}} })
  if lexpr then
    local op = self:cmp_op()
    if not op then self:error("expecting comparison operator") end
    local rexpr = self:expr(true, end_predictions)
    if not rexpr then self:error("expecting expression") end
    -- Convert both operands to string or number based on the operator.
    if op == "==" or op == "~=" then
      return {"code", "S("..lexpr..")"..op.."S("..rexpr..")"}
    else
      return {"code", "N("..lexpr..")"..op.."N("..rexpr..")"}
    end
  end
end

-- return code
function Parser:call()
  local id = self:token("text")
  if id then
    local args = self:quoted_args("end") or self:args("end")
    -- generate code
    --- regular call
    local call = "func(\""..id[1].."\""..(args and ", "..args..")" or ")")
    --- query control flow
    if id[1] == "InputQuery" then
      return "state.qresult = "..call
    elseif id[1] == "OnResultQuery" then
      local label = "::query"..self.queries.."::"
      self.queries = self.queries+1
      return label.."; if state.qresult ~= "..(args or "").." then goto query"..self.queries.." end"
    elseif id[1] == "QueryEnd" then
      local label = "::query"..self.queries.."::"
      self.queries = self.queries+1
      return label
    else return call end
  end
end

-- return code
function Parser:call_condition()
  if self:check('Condition', '(', "'") then
    local condition = self:condition({{{"'"}, {')'}}})
    if not condition then self:error("expecting condition") end
    self:expect("'", ')')
    -- generate code
    local label = "::condition"..self.conditions.."::"
    self.conditions = self.conditions+1
    if condition[1] == "flag" then
      return label.."; if state.condition ~= \""..condition[2].."\" then goto condition"..self.conditions.." end"
    else -- comparison code
      return label.."; if not ("..condition[2]..") then goto condition"..self.conditions.." end"
    end
  end
end

-- return code
function Parser:assignment()
  local lvar = self:lvar()
  if lvar then
    self:expect('=')
    -- check for concat or expression
    local concat = self:concat()
    local expr
    if concat then -- Concat(...)
      if lvar[1] == "server_var" then
        expr = "S(server_var("..lvar[2].."))..("..concat..")"
      elseif lvar[1] == "special_var" then
        expr = "S(special_var(\""..lvar[2].."\"))..("..concat..")"
      elseif lvar[1] == "event_var" then
        local event_var = lvar[2]
        expr = "S(event_var(\""..event_var[1].."\", \""..event_var[2].."\"))..("..concat..")"
      end
    else expr = self:expr(true) end
    if not expr then self:error("expecting expression") end
    -- generate code
    local code
    if lvar[1] == "var" or lvar[1] == "bool_var" then
      local var_index = lvar[2]
      if var_index[1] == "range" then
        local range = var_index[2]
        code = "for i="..range[1]..","..range[2].." do "..lvar[1].."(i, "..expr..") end"
      else -- expr
        code = lvar[1].."("..var_index[2]..", "..expr..")"
      end
    elseif lvar[1] == "server_var" then code = "server_var("..lvar[2]..", "..expr..")"
    elseif lvar[1] == "special_var" then code = "special_var(\""..lvar[2].."\", "..expr..")"
    elseif lvar[1] == "event_var" then
      local event_var = lvar[2]
      code = "event_var(\""..event_var[1].."\", \""..event_var[2].."\", "..expr..")"
    end
    if not code then self:error("no assignment code generated") end
    return code
  end
end

function Parser:command()
  if self:predict({'%'}) or self:predict({nil, "text"}, {'['}) then
    return self:assignment()
  else
    return self:call_condition() or self:call()
  end
end

-- Compilation.

-- Compile condition instruction to Lua code.
local function compileCondition(p, instruction)
  if not instruction:match("^//") then -- ignore comment
    p:init(lex(instruction))
    local condition = p:condition()
    if not condition then p:error("expecting condition") end
    if p.i <= #p.tokens then p:error("unexpected token") end
    if condition[1] == "flag" then
      p.flags[condition[2]] = true
    else return condition[2] end -- code
  end
end

-- Compile condition block.
-- return (code, flags) or (nil, err)
function M.compileConditions(instructions)
  local p = setmetatable({flags = {}}, {__index = Parser})
  local lines = {}
  for i, instruction in ipairs(instructions) do
    local ok, r = pcall(compileCondition, p, instruction)
    if not ok then return nil, "CD:"..i..":"..instruction.."\n"..r end
    -- match an editor line with a Lua line
    table.insert(lines, r and "and "..r or "")
  end
  return "return true "..table.concat(lines, "\n"), p.flags
end

-- Compile command instruction to Lua code.
local function compileCommand(p, instruction)
  if not instruction:match("^//") then -- ignore comment
    p:init(lex(instruction))
    local command = p:command()
    if not command then p:error("expecting command") end
    if p.i <= #p.tokens then p:error("unexpected token") end
    return command
  end
end

-- Compile command block.
-- return code or (nil, err)
function M.compileCommands(instructions)
  local p = setmetatable({conditions = 0, queries = 0}, {__index = Parser})
  local lines = {}
  for i, instruction in ipairs(instructions) do
    local ok, r = pcall(compileCommand, p, instruction)
    if not ok then return nil, "EV:"..i..":"..instruction.."\n"..r end
    -- match an editor line with a Lua line
    table.insert(lines, r or "")
  end
  -- end conditions label
  table.insert(lines, "::condition"..p.conditions..":: ::query"..p.queries.."::")
  return table.concat(lines, "\n")
end

-- Validate instructions.
local function validate(compile_func, instructions)
  local errors = {}
  local p = setmetatable({flags = {}, conditions = 0, queries = 0}, {__index = Parser})
  for i, instruction in ipairs(instructions) do
    local ok, err = pcall(compile_func, p, instruction)
    if not ok then
      table.insert(errors, {
        i = i, instruction = instruction,
        error = err,
        parser = p
      })
    end
  end
  return errors
end

function M.validateConditions(instructions) return validate(compileCondition, instructions) end
function M.validateCommands(instructions) return validate(compileCommand, instructions) end

return M
