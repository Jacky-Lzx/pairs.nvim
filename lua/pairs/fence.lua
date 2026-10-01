-- Decisions use Markdown's outer block tree, never text-only fence guesses.
local M = {}

function M.decide(ctx, key)
  if ctx.filetype ~= "markdown" then
    return nil
  end
  local rule = ctx.multi_rules and ctx.multi_rules["```"]
  local fence = ctx.fence
  if not rule or rule == false or not fence or not fence.supported then
    return nil
  end
  if
    key == "`"
    and rule.skip
    and ctx.row == fence.close_row
    and ctx.col >= fence.close_col
    and ctx.col < fence.close_end
  then
    return { action = "skip", reason = "fence_closer", open = "```", close = "`", move = 1 }
  end
  if key == "<CR>" and ctx.row == fence.open_row and ctx.col == #ctx.line then
    if not rule.open or not rule.newline then
      return { action = "pass", reason = "fence_opening_disabled" }
    end
    if fence.close_row then
      return { action = "pass", reason = "fence_existing_closer" }
    end
    if fence.has_content then
      return { action = "pass", reason = "fence_existing_content" }
    end
    return {
      action = "newline",
      reason = "fence_opening",
      open = "```",
      close = "```",
      insert_close = true,
      indent_offset = 0,
    }
  end
end

return M
