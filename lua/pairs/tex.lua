local lex = require("pairs.lex")
local M = {}

local function syntax_guard(ctx)
  if not ctx.tex then
    return {
      action = "pass",
      reason = ctx.syntax == "unknown" and "syntax_pending" or "tex_context_missing",
    }
  end
  if ctx.tex.blocked then
    return { action = "pass", reason = "tex_literal" }
  end
end

local function pair_action(ctx, key, rule, pair)
  local kind = pair.open == "$$" and "display" or "math"
  local closing = ctx.row == pair.close_row
    and ctx.col >= pair.close_col
    and ctx.col < pair.close_col + #pair.close
  if
    closing and key == pair.close:sub(ctx.col - pair.close_col + 1, ctx.col - pair.close_col + 1)
  then
    if key == "\\" and rule.skip then
      -- A backslash may start a command. Only a subsequent matching final
      -- byte can confirm that the user intended to skip the existing closer.
      return { action = "pass", reason = "math_closer_prefix", defer_close = pair.close }
    end
    return {
      action = rule.skip and "skip" or "pass",
      reason = kind .. "_closer",
      open = pair.open,
      close = pair.close,
      move = 1,
    }
  end
  local empty = ctx.row == pair.open_row
    and ctx.row == pair.close_row
    and ctx.col == pair.open_col + #pair.open
    and ctx.col == pair.close_col
  if empty and key == "<BS>" then
    return {
      action = rule.delete and "delete" or "pass",
      reason = "empty_" .. kind,
      open = pair.open,
      close = pair.close,
    }
  end
  if empty and key == "<CR>" then
    return {
      action = rule.newline and "newline" or "pass",
      reason = "empty_" .. kind,
      open = pair.open,
      close = pair.close,
      indent_offset = 0,
    }
  end
end

local function dollars(ctx, key, rule)
  local adjacent = ctx.line:sub(ctx.col - 1, ctx.col) == "$$"
    and ctx.line:sub(ctx.col + 1, ctx.col + 2) == "$$"
  if key ~= "$" and not ((key == "<BS>" or key == "<CR>") and adjacent) then
    return nil
  end
  local guard = syntax_guard(ctx)
  if guard then
    return guard
  end
  local pair = ctx.tex.pair
  if pair and pair.open == "$$" then
    local action = pair_action(ctx, key, rule, pair)
    if action then
      return action
    end
  end
  if ctx.tex.argument then
    return { action = "pass", reason = "tex_argument_display" }
  end
  if
    key == "$"
    and rule.open
    and ctx.tex.upgrade
    and ctx.line:sub(1, ctx.col):match("^[ \t]*%$$")
    and ctx.line:sub(ctx.col + 1):match("^[ \t]*$")
  then
    return { action = "pair", reason = "display_opening", open = "$", close = "$$" }
  end
  return { action = "pass", reason = "not_display_boundary" }
end

local function slash_math(ctx, key, rules)
  local opening = (key == "(" or key == "[") and "\\" .. key or nil
  local rule = opening and rules[opening]
  if rule and rule ~= false and ctx.line:sub(ctx.col, ctx.col) == "\\" then
    local guard = syntax_guard(ctx)
    if guard then
      return guard
    end
    if opening == "\\[" and ctx.tex.argument then
      return { action = "pass", reason = "tex_argument_display" }
    end
    if
      rule.open
      and ctx.tex.slash_open
      and lex.next_allows_pair(lex.next(ctx.line, ctx.col), ctx.rules)
    then
      -- The backslash has already been typed; only add the final opener byte.
      return { action = "pair", reason = "math_opening", open = key, close = rule.close }
    end
    return { action = "pass", reason = "not_math_opening" }
  end
  local pair = ctx.tex and ctx.tex.pair
  rule = pair and rules[pair.open]
  if pair and pair.open ~= "$$" and rule and rule ~= false then
    local guard = syntax_guard(ctx)
    return guard or pair_action(ctx, key, rule, pair)
  end
  -- Missing/pending context must not synthesize edits to an adjacent empty pair.
  if key == "<BS>" or key == "<CR>" then
    for _, open in ipairs({ "\\(", "\\[" }) do
      local adjacent_rule = rules[open]
      if
        adjacent_rule
        and adjacent_rule ~= false
        and ctx.line:sub(ctx.col - 1, ctx.col) == open
        and ctx.line:sub(ctx.col + 1, ctx.col + 2) == adjacent_rule.close
      then
        return syntax_guard(ctx) or { action = "pass", reason = "not_math_boundary" }
      end
    end
  end
end

function M.decide(ctx, key)
  if ctx.filetype ~= "tex" and ctx.filetype ~= "plaintex" then
    return nil
  end
  local argument = ctx.tex and ctx.tex.argument
  if argument and argument.close and argument.proven then
    local open = argument.close == "}" and "{" or "["
    local rule = ctx.rules[open]
    if rule and rule ~= false then
      if key == argument.close and rule.skip then
        return {
          action = "skip",
          reason = "tex_argument_closer",
          open = open,
          close = argument.close,
          move = 1,
        }
      elseif key == "<BS>" and argument.empty and rule.delete then
        return {
          action = "delete",
          reason = "empty_tex_argument",
          open = open,
          close = argument.close,
        }
      end
    end
  end
  local rules = ctx.multi_rules or {}
  local pair = ctx.tex and ctx.tex.pair
  local rule = pair and rules[pair.open]
  if rule and rule ~= false and rule.space and not ctx.tex.blocked then
    local padding = require("pairs.padding").multi(ctx, key, rule, pair, 0)
    if padding then
      return padding
    end
  end
  local dollar = rules["$$"]
  local action = dollar and dollar ~= false and dollars(ctx, key, dollar) or nil
  return action or slash_math(ctx, key, rules)
end

return M
