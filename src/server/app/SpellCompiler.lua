-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2019 ImagicTheCat

-- Compile spell expression/statements to Lua functions.

--[[
EBNF-like grammar (not exact, for overview):

function_var = '%' keyword args '%'
args = '(' expr {',' expr} ')'
spell_command = 'spell' ':' text
var_target = 'Cible' | 'Wizard'
var = '%' '[' var_target ']' '.' (cvar | keyword) '%'
cvar = 'Variable' '[' expr ']'
assignment = var '=' expr
statement = (assignment | spell_command) ';'
statements = statement {statement}
expr = term {('+' | '-') term}
term = factor {('*' | '/') factor}
factor = ['-'] value
value = var | function_var | number | '(' expr ')'
]]

local lpeg = require "lpeg"

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
local number = C( R"09"^1 * ("." * R"09"^1)^-1 )
local cvar = Ct( Cc"cvar" * T"Variable[" * V"expr" * T"]" )
local var_target = T"Cible" + T"Wizard"
local var = Ct( Cc"var" * T"%[" * C( var_target ) * T"]." * (cvar + keyword) * T"%" )
local args = T"(" * V"expr" * (T"," * V"expr")^0 * T")"
local function_var = Ct( Cc"function_var" * T"%" * keyword * args * T"%" )
local spell_command = Ct( Cc"spell_command" * T"spell:" * C( (1 - P";")^1 ) )
local assignment = Ct( Cc"assignment" * var * T"=" * V"expr" )
local statement = Ct( Cc"statement" * (spell_command + assignment) * T";" )
local statements = Ct( statement^1 )
local value = number + var + function_var + T"(" * V"expr" * T")"
local factor = Ct( Cc"expr" * C(T"-") * value ) + value
local term = Ct( Cc"expr" * factor * (C(S"*/") * factor)^0 )
local expr = Ct( Cc"expr" * term * (C(S"+-") * term)^0 )

local spell_statements = P{
  statements * -1,
  expr = expr
}

local spell_expression = P{
  expr * -1,
  expr = expr
}

-- Code generation

local function escape(str) return string.format("%q", str) end

-- Functions to browse the AST (abstract syntax tree) and generate Lua code by
-- returning strings. Uses a state to generate code and to produce metadata.

local gen = {}

-- Dispatch AST element to its specific handler.
local function dispatch(state, ast) return gen[ast[1]](state, ast) end

local SPELL_TARGETS = {
  Cible = "target",
  Wizard = "caster"
}

function gen.statements(state, ast)
  -- handle list of statements
  local stmts = {}
  for i=1, #ast do table.insert(stmts, dispatch(state, ast[i])) end
  return table.concat(stmts, ";")
end

function gen.statement(state, ast) return dispatch(state, ast[2]) end

function gen.assignment(state, ast)
  local var, expr = ast[2], ast[3]
  local target = SPELL_TARGETS[var[2]]
  local field = var[3]
  if type(field) == "table" then -- cvar
    return "var(state, "..dispatch(state, field[2])..", "..dispatch(state, expr)..")"
  else -- keyword
    return target.."_var(state, "..escape(field)..", "..dispatch(state, expr)..")"
  end
end

function gen.spell_command(state, ast)
  return "spell(state, "..escape(ast[2])..")"
end

function gen.function_var(state, ast)
  local args = { escape(ast[2]) }
  for i=3, #ast do table.insert(args, dispatch(state, ast[i])) end
  return "func_var(state, "..table.concat(args, ", ")..")"
end

function gen.expr(state, ast)
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

function gen.var(state, ast)
  local target = SPELL_TARGETS[ast[2]]
  local field = ast[3]
  if type(field) == "table" then -- cvar
    return "var(state, "..dispatch(state, field[2])..")"
  else -- keyword
    return target.."_var(state, "..escape(field)..")"
  end
end

-- Compilation of statements and expression.

local function compile(mode, code)
  local parser = mode == "statements" and spell_statements or spell_expression
  local gen_root = mode == "statements" and "statements" or "expr"
  local state = {}
  -- error handling
  farthest = 0
  farthest_tokens = {}
  -- parse
  local ast = parser:match(code)
  if not ast then -- error
    local expected_tokens = {}
    for k in pairs(farthest_tokens) do table.insert(expected_tokens, '"'..k..'"') end
    error("unexpected input, expected "..table.concat(expected_tokens, ", ").."\n"..
      code.."\n"..string.rep(" ", farthest - 1).."^")
  end
  return gen[gen_root](state, ast)
end

-- Compile expression to Lua code.
-- return code or (nil, err)
function M.compileExpression(code)
  if code == "" then return "" end
  local ok, r = pcall(compile, "expression", code)
  if not ok then return nil, r else return "return "..r end
end

-- Compile statements to Lua code.
-- return code or (nil, err)
function M.compileStatements(code)
  if code == "" then return "" end
  local ok, r = pcall(compile, "statements", code)
  if not ok then return nil, r else return r end
end

return M
