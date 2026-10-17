-- Padding uses the existing lexer snapshot or parser-proven delimiter boundaries.
local lex = require("pairs.lex")
local M = {}

function M.multi(ctx, key, rule, pair, indent_offset)
  if not rule.space or (key ~= " " and key ~= "<BS>" and key ~= "<CR>") then
    return nil
  end
  local width = key == " " and 0 or 1
  if
    ctx.row ~= pair.open_row
    or ctx.row ~= pair.close_row
    or ctx.col ~= pair.open_col + #pair.open + width
    or pair.close_col ~= ctx.col + width
    or ctx.line:sub(pair.open_col + 1, pair.open_col + #pair.open) ~= pair.open
    or ctx.line:sub(pair.close_col + 1, pair.close_col + #pair.close) ~= pair.close
    or (width == 1 and ctx.line:sub(ctx.col, ctx.col + 1) ~= "  ")
  then
    return nil
  end
  if key == " " then
    return { action = "pair", reason = "empty_multi_space", open = " ", close = " " }
  elseif key == "<BS>" then
    return {
      action = rule.delete and "delete" or "pass",
      reason = rule.delete and "empty_multi_padding" or "action_disabled",
      open = " ",
      close = " ",
    }
  end
  return {
    action = rule.newline and "newline" or "pass",
    reason = rule.newline and "empty_multi_padding" or "action_disabled",
    open = pair.open,
    close = pair.close,
    trim_space = true,
    indent_offset = indent_offset,
  }
end

function M.decide(ctx, key, state)
  if state.quote or ctx.syntax == "string" then
    return nil
  end
  local padded = key ~= " "
  local col = ctx.col
  if padded and (ctx.line:sub(col, col) ~= " " or ctx.line:sub(col + 1, col + 1) ~= " ") then
    return nil
  end
  local opening = col - (padded and 1 or 0) -- 1-based byte of the opener
  if opening < 1 then
    return nil
  end
  local open = ctx.line:sub(opening, opening)
  local rule = ctx.rules[open]
  if not rule or rule == false or not rule.space then
    return nil
  end
  local closing = col + (padded and 2 or 1)
  if
    ctx.line:sub(closing, closing) ~= rule.close
    or state.stack[#state.stack] ~= open
    or lex.escaped(ctx.line, opening - 1)
  then
    return nil
  end
  -- Interpolation's structural braces belong to their language rule. Ordinary
  -- brackets inside the expression can still opt in independently.
  local sub = ctx.substitution
  if sub and ctx.row == sub.body_row and opening == sub.body_col then
    return nil
  end
  if key == " " then
    return { action = "pair", reason = "empty_pair_space", open = " ", close = " " }
  elseif key == "<BS>" then
    return {
      action = rule.delete and "delete" or "pass",
      reason = rule.delete and "empty_pair_padding" or "action_disabled",
      open = " ",
      close = " ",
    }
  elseif key == "<CR>" then
    return {
      action = rule.newline and "newline" or "pass",
      reason = rule.newline and "empty_pair_padding" or "action_disabled",
      open = open,
      close = rule.close,
      trim_space = true,
    }
  end
end

return M
