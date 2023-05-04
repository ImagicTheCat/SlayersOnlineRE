-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

-- Compile event conditions/commands to Lua functions.

--[[
EBNF-like grammar (not exact, for overview):

condition = condition_flag | inventory cmp_op expr | expr cmp_op expr
inventory = '%' 'Inventaire' '%'
condition_flag = 'Appuie sur bouton' | 'Automatique' | 'Auto une seul fois' |
  'En contact' | 'Attaque'
command = call_condition | call | assignment
call = keyword [args | quoted_args]
call_condition = 'Condition' '(' ''' condition ''' ')'
assignment = lvar '=' (concat | expr)
lvar = var | bool_var | server_var | special_var | event_var
args = '(' expr {',' expr} ')'
quoted_args = '(' ''' expr {''' ',' ''' expr} ''' ')'
cmp_op = '=' | '<=' | '>=' | '<' | '>' | '!='
var = 'Variable' '[' var_index ']'
bool_var = 'Bool' '[' var_index ']'
var_index = uint ['..' uint]
server_var = 'Serveur' '[' expr ']'
special_var = '%' keyword '%'
event_var = '%' text '.' keyword '%'
function_var = '%' keyword args '%'
input_string = 'InputString' quoted_args
concat = 'Concat' quoted_args
expr = expr_calc | expr_string
factor = number | expr_construct | '(' expr_calc ')'
term = factor {('*' | '/') factor}
expr_calc = term {('+' | '-') term}
expr_string = {expr_construct | text}
expr_construct = lvar | function_var | input_string token
]]

local lpeg = require "lpeg"
local utils = require "app.utils"

local M = {}

-- Parser

local P, S, R, V = lpeg.P, lpeg.S, lpeg.R, lpeg.V
local C, Cc, Ct = lpeg.C, lpeg.Cc, lpeg.Ct

--- Error handling system

local farthest_tokens = {}
local farthest = 0
local function report_token(s, i, token)
  if i > farthest then
    farthest = i
    farthest_tokens = {}
  end
  if i >= farthest then farthest_tokens[token] = true end
  return false
end

local function T(token) return P(token) + lpeg.Cmt(Cc(token), report_token) * P(false) end

--- Grammar

local keyword = C( R("az", "AZ", "09")^1 )
local event_var = Ct( Cc"event_var" * T"%" * C( (1 - P".")^1 ) * T"." * keyword * T"%" )
local special_var = Ct( Cc"special_var" * T"%" * keyword * T"%" )
local number = C( P"-"^-1 * R"09"^1 * ("." * R"09"^1)^-1 )
local uint = C( R"09"^1 )
local index_range = uint * (T".." * uint)^-1
local bool_var = Ct( Cc"bool_var" * T"Bool[" * index_range * T"]" )
local var = Ct( Cc"var" * T"Variable[" * index_range * T"]" )
local lvar = var + bool_var + special_var + event_var + V"server_var"
local expr_construct = lvar + V"function_var" + V"input_string"

-- expr_calc
local factor = number + expr_construct + T"(" * V"expr_calc" * T")"
local term = Ct( Cc"expr_calc" * factor * (C(S"*/") * factor)^0 )
local expr_calc = Ct( Cc"expr_calc" * term * (C(S"+-") * term)^0 )

-- expr pattern generator
local function expr(end_pattern)
  end_pattern = P(end_pattern)
  local expr_string_item = expr_construct + C( (-expr_construct * -end_pattern * 1)^1 )
  local expr_string = Ct( Cc"expr_string" * expr_string_item^0 )
  return (expr_calc * #end_pattern) + expr_string
end

-- (quoted) args pattern generator
-- eol: truthy to match until the end of line
local function gen_args(s_begin, s_sep, s_end, eol)
  local e = expr(P(s_sep) + P(s_end) * (eol and P(-1) or P(true)))
  return T(s_begin) * e * (T(s_sep) * e)^0 * T(s_end)
end

-- args
local quoted_args = gen_args("('", "','", "')")
local quoted_args_eol = gen_args("('", "','", "')", true)
local args = gen_args("(", ",", ")")
local args_eol = gen_args("(", ",", ")", true)

local expr_eol = expr(-1)
local server_var = Ct( Cc"server_var" * T"Serveur[" * expr("]") * T"]" )
local input_string = Ct( Cc"input_string" * T"InputString" * quoted_args )
local function_var = Ct( Cc"function_var" * T"%" * keyword * args * T"%" )
local concat = Ct( Cc"concat" * T"Concat" * quoted_args_eol )
local assignment = Ct( Cc"assignment" * lvar * T"=" * (concat + expr_eol) )
local call = Ct( Cc"call" * keyword * (quoted_args_eol + args_eol)^-1 )
local condition_flag = C( T"Appuie sur bouton" + T"Automatique" + T"Auto une seul fois" + T"En contact" + T"Attaque" )
local cmp_op = C( T"=" + T"<=" + T">=" + T"<" + T">" + T"!=" )

-- condition patterns
local condition; do
  local expr_end = expr(P"')" + -1)
  local condition_inv = Ct( Cc"condition_inv" * T"%Inventaire%" * cmp_op * expr_end )
  condition = condition_flag + condition_inv + Ct( Cc"condition_expr" * expr(cmp_op) * cmp_op * expr_end )
end

local call_condition = Ct( Cc"call_condition" * T"Condition('" * condition * T"')" )
local command = assignment + call_condition + call
local comment = P"//" * P(1)^0

--- Final line/instruction patterns

local l_command = P{
  command + comment,
  -- refs
  expr_calc = expr_calc,
  server_var = server_var,
  input_string = input_string,
  function_var = function_var
}

local l_condition = P{
  condition + comment,
  -- refs
  expr_calc = expr_calc,
  server_var = server_var,
  input_string = input_string,
  function_var = function_var
}

-- Code generation

local function escape(str) return string.format("%q", str) end

-- Functions to browse the AST (abstract syntax tree) and generate Lua code by
-- returning strings. Uses a state to generate code and to produce metadata.

local gen = {}

-- Dispatch AST element to its specific handler.
local function dispatch(state, ast) return gen[ast[1]](state, ast) end

function gen.command(state, ast) return dispatch(state, ast) end

local CONDITION_FLAGS = {
  ["Appuie sur bouton"] = "interact",
  ["Automatique"] = "auto",
  ["Auto une seul fois"] = "auto-once",
  ["En contact"] = "contact",
  ["Attaque"] = "attack"
}

function gen.condition(state, ast)
  if type(ast) == "string" then -- build flags metadata
    state.flags[CONDITION_FLAGS[ast]] = true
    return ""
  else
    return dispatch(state, ast)
  end
end

function gen.assignment(state, ast)
  local lhs, rhs = ast[2], ast[3]
  -- lhs: numeric
  if lhs[1] == "var" or lhs[1] == "bool_var" then
    assert(rhs[1] ~= "concat" and rhs[1] ~= "expr_string", "string expression into numeric variable")
    if #lhs > 2 then -- range
      local a, b = tonumber(lhs[2]), tonumber(lhs[3])
      assert(a < b, "invalid range")
      return "for i="..a..","..b.." do "..lhs[1].."(i, "..dispatch(state, rhs)..") end"
    end
    return lhs[1].."("..lhs[2]..", "..dispatch(state, rhs)..")"
  end
  -- lhs: other
  local prefix
  if lhs[1] == "special_var" then
    prefix = lhs[1].."("..escape(lhs[2])
  elseif lhs[1] == "event_var" then
    prefix = lhs[1].."("..escape(lhs[2])..", "..escape(lhs[3])
  elseif lhs[1] == "server_var" then
    prefix = lhs[1].."("..dispatch(state, lhs[2])
  end
  if rhs[1] == "concat" then -- rhs: concat
    assert(#rhs == 2, "wrong number of concat arguments")
    return prefix..", "..prefix..").."..dispatch(state, rhs[2])..")"
  else -- rhs: expr
    return prefix..", "..dispatch(state, rhs)..")"
  end
end

function gen.call_condition(state, ast)
  local condition = ast[2]
  local label = "::condition"..state.condition_count.."::"
  state.condition_count = state.condition_count+1
  if type(condition) == "string" then
    return label.." if state.condition ~= "..escape(condition).." then goto condition"..state.condition_count.." end"
  else
    return label.." if not ("..dispatch(state, condition)..") then goto condition"..state.condition_count.." end"
  end
end

function gen.condition_expr(state, ast)
  local lhs, op, rhs = ast[2], ast[3], ast[4]
  -- conversion to Lua operators
  if op == "!=" then op = "~=" end
  if op == "=" then op = "==" end
  -- generate
  if op == "==" or op == "~=" then -- string comparison
    return "S("..dispatch(state, lhs)..") "..op.." S("..dispatch(state, rhs)..")"
  else
    return dispatch(state, lhs).." "..op.." "..dispatch(state, rhs)
  end
end

function gen.condition_inv(state, ast)
  local cmp_op, expr = ast[2], ast[3]
  if cmp_op == "=" then
    return "inventory("..dispatch(state, expr)..") > 0"
  elseif cmp_op == "!=" then
    return "inventory("..dispatch(state, expr)..") == 0"
  else
    error("invalid inventory condition operator")
  end
end

function gen.call(state, ast)
  local id = ast[2]
  -- build call code
  local args = { escape(id) }
  for i=3, #ast do table.insert(args, dispatch(state, ast[i])) end
  local call_code = "func("..table.concat(args, ", ")..")"
  -- implement query control flow
  if id == "InputQuery" then
    return "state.qresult = "..call_code
  elseif id == "OnResultQuery" then
    assert(#ast == 3, "wrong number of arguments to OnResultQuery")
    local label = "::query"..state.query_count.."::"
    state.query_count = state.query_count+1
    return label.." if state.qresult ~= "..(args[2] or "").." then goto query"..state.query_count.." end"
  elseif id == "QueryEnd" then
    local label = "::query"..state.query_count.."::"
    state.query_count = state.query_count+1
    return label
  else
    return call_code
  end
end

function gen.expr_calc(state, ast)
  local args = {}
  for i=2, #ast do
    local arg = ast[i]
    if type(arg) == "string" then -- operator or number
      table.insert(args, arg)
    else -- other
      table.insert(args, dispatch(state, arg))
    end
  end
  -- no parenthesis for singleton
  return #args == 1 and table.concat(args) or "("..table.concat(args)..")"
end

function gen.expr_string(state, ast)
  local args = {}
  for i=2, #ast do
    local arg = ast[i]
    if type(arg) == "string" then -- literal string
      table.insert(args, escape(arg))
    else -- other
      table.insert(args, dispatch(state, arg))
    end
  end
  if #args == 0 then
    return [[""]]
  else
    return table.concat(args, "..")
  end
end

function gen.var(state, ast)
  assert(#ast == 2, "range as variable index")
  return "var("..ast[2]..")"
end

function gen.bool_var(state, ast)
  assert(#ast == 2, "range as variable index")
  return "bool_var("..ast[2]..")"
end

function gen.special_var(state, ast)
  return "special_var("..escape(ast[2])..")"
end

function gen.event_var(state, ast)
  return "event_var("..escape(ast[2])..", "..escape(ast[3])..")"
end

function gen.server_var(state, ast)
  return "server_var("..dispatch(state, ast[2])..")"
end

function gen.function_var(state, ast)
  local args = { escape(ast[2]) }
  for i=3, #ast do table.insert(args, dispatch(state, ast[i])) end
  return "func_var("..table.concat(args, ", ")..")"
end

function gen.input_string(state, ast)
  local args = { escape("InputString") }
  for i=3, #ast do table.insert(args, dispatch(state, ast[i])) end
  return "func("..table.concat(args, ", ")..")"
end

-- Compilation of instructions and pages

local function compileInstruction(itype, state, instruction)
  local parser = itype == "condition" and l_condition or l_command
  -- error handling
  farthest = 0
  farthest_tokens = {}
  -- parse
  local ast = parser:match(instruction)
  if not ast then -- error
    local expected_tokens = {}
    for k in pairs(farthest_tokens) do table.insert(expected_tokens, '"'..k..'"') end
    error("unexpected input, expected "..table.concat(expected_tokens, ", ").."\n"..
      instruction.."\n"..string.rep(" ", farthest - 1).."^")
  end
  if type(ast) == "number" then return "" end -- void instruction, comment
  return gen[itype](state, ast)
end

-- Compile condition page/block.
-- return (code, flags) or (nil, err)
function M.compileConditions(instructions)
  local state = {flags = {}}
  local lines = {}
  local empty = true
  for i, instruction in ipairs(instructions) do
    local ok, r = pcall(compileInstruction, "condition", state, instruction)
    if not ok then return nil, "CD:"..i..":"..instruction.."\n"..r end
    assert(r, "missing generated code")
    -- match an editor line with a Lua line
    if r == "" then
      table.insert(lines, "")
    else
      table.insert(lines, empty and r or " and "..r)
      empty = false
    end
  end
  return (empty and "return true " or "return ")..table.concat(lines, "\n"), state.flags
end

-- Compile command page/block.
-- return code or (nil, err)
function M.compileCommands(instructions)
  local state = {query_count = 0, condition_count = 0}
  local lines = {}
  for i, instruction in ipairs(instructions) do
    local ok, r = pcall(compileInstruction, "command", state, instruction)
    if not ok then return nil, "EV:"..i..":"..instruction.."\n"..r end
    -- match an editor line with a Lua line
    table.insert(lines, r or "")
  end
  -- end conditions label
  table.insert(lines, "::condition"..state.condition_count..":: ::query"..state.query_count.."::")
  return table.concat(lines, "\n")
end

-- Validate instructions.
-- Seek for errors without stopping at the first of a page.
local function validate(itype, instructions)
  local errors = {}
  local state = {query_count = 0, condition_count = 0, flags = {}}
  for i, instruction in ipairs(instructions) do
    local ok, err = pcall(compileInstruction, itype, state, instruction)
    if not ok then
      table.insert(errors, {
        i = i, instruction = instruction,
        error = err
      })
    end
  end
  return errors
end

function M.validateConditions(instructions) return validate("condition", instructions) end
function M.validateCommands(instructions) return validate("command", instructions) end

return M
