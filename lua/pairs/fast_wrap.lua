-- A conservative, bounded same-line target. Rendering uses only native keys.
local lex = require("pairs.lex")
local M = {}

function M.decide(ctx, state)
  if state.quote or ctx.syntax == "string" then
    return { action = "pass", reason = "string" }
  end
  local open = ctx.line:sub(ctx.col, ctx.col)
  local rule = ctx.rules[open]
  if not rule or rule == false or not rule.wrap then
    return { action = "pass", reason = "wrap_disabled" }
  end
  if state.stack[#state.stack] ~= open or lex.escaped(ctx.line, ctx.col - 1) then
    return { action = "pass", reason = "not_wrap_boundary" }
  end
  local sub = ctx.substitution
  if sub and ctx.row == sub.body_row and ctx.col == sub.body_col then
    return { action = "pass", reason = "interpolation_boundary" }
  end
  -- Count the complete prefix plus forward target against the existing budget.
  -- One lookahead byte proves the identifier ends without scanning the suffix.
  local remove_close = ctx.line:sub(ctx.col + 1, ctx.col + 1) == rule.close
  local offset = remove_close and 1 or 0
  local target =
    ctx.line:sub(ctx.col + offset + 1, ctx.lex.max_scan_bytes + 1):match("^[A-Za-z_][A-Za-z0-9_]*")
  if not target then
    return { action = "pass", reason = "no_identifier" }
  end
  local last = ctx.col + offset + #target
  if last > ctx.lex.max_scan_bytes then
    return { action = "pass", reason = "scan_limit" }
  end
  local after = ctx.line:sub(last + 1, last + 1)
  if after ~= "" and not after:match("^[%s,;%)%]%}]$") then
    return { action = "pass", reason = "complex_target" }
  end
  return {
    action = "wrap",
    reason = remove_close and "identifier_wrap"
      or after == rule.close and "identifier_wrap_existing_closer"
      or "identifier_wrap_missing_closer",
    open = open,
    close = rule.close,
    move = #target,
    remove_close = remove_close,
    insert_close = remove_close or after ~= rule.close,
  }
end

return M
