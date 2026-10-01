local M = {}

function M.decide(ctx, key)
  if ctx.filetype ~= "tex" and ctx.filetype ~= "plaintex" then
    return nil
  end
  local rule = ctx.multi_rules and ctx.multi_rules["$$"]
  if not rule or rule == false then
    return nil
  end
  local adjacent = ctx.line:sub(ctx.col - 1, ctx.col) == "$$"
    and ctx.line:sub(ctx.col + 1, ctx.col + 2) == "$$"
  if key ~= "$" and not ((key == "<BS>" or key == "<CR>") and adjacent) then
    return nil
  end
  local syntax = ctx.tex
  if not syntax then
    return {
      action = "pass",
      reason = ctx.syntax == "unknown" and "syntax_pending" or "tex_context_missing",
    }
  end
  if syntax.blocked then
    return { action = "pass", reason = "tex_literal" }
  end
  local pair = syntax.pair
  if pair then
    if
      key == "$"
      and rule.skip
      and ctx.row == pair.close_row
      and ctx.col >= pair.close_col
      and ctx.col < pair.close_col + 2
    then
      return { action = "skip", reason = "display_closer", open = "$$", close = "$", move = 1 }
    end
    local empty = adjacent
      and pair.open_row == ctx.row
      and pair.close_row == ctx.row
      and pair.open_col + 2 == ctx.col
      and pair.close_col == ctx.col
    if empty and key == "<BS>" and rule.delete then
      return { action = "delete", reason = "empty_display", open = "$$", close = "$$" }
    end
    if empty and key == "<CR>" and rule.newline then
      return {
        action = "newline",
        reason = "empty_display",
        open = "$$",
        close = "$$",
        indent_offset = 0,
      }
    end
  end
  if
    key == "$"
    and rule.open
    and syntax.upgrade
    and ctx.line:sub(1, ctx.col):match("^[ \t]*%$$")
    and ctx.line:sub(ctx.col + 1):match("^[ \t]*$")
  then
    return { action = "pair", reason = "display_opening", open = "$", close = "$$" }
  end
  return { action = "pass", reason = "not_display_boundary" }
end

return M
