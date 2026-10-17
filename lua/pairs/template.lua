-- Parser-proven template boundaries; no state or direct buffer edits.
local lex = require("pairs.lex")
local M = {}
local filetypes = {
  javascript = true,
  javascriptreact = true,
  typescript = true,
  typescriptreact = true,
}

local function result(action, reason, open, close)
  return { action = action, reason = reason, open = open, close = close }
end

function M.decide(ctx, key)
  if not filetypes[ctx.filetype] then
    return nil
  end
  local tick = ctx.rules["`"]
  local interpolation = ctx.multi_rules and ctx.multi_rules["${"]
  if ctx.template then
    if tick and tick ~= false and tick.close == "`" then
      local closing = ctx.row == ctx.template_close_row and ctx.col == ctx.template_close_col
      if key == "`" and tick.skip and closing then
        return result("skip", "template_closer", "`", "`")
      end
      if
        key == "<BS>"
        and tick.delete
        and closing
        and ctx.row == ctx.template_start_row
        and ctx.col == ctx.template_open_col + 1
      then
        return result("delete", "empty_template", "`", "`")
      end
    end
    if
      key == "{"
      and interpolation
      and interpolation ~= false
      and interpolation.open
      and lex.previous(ctx.line, ctx.col) == "$"
      and not lex.escaped(ctx.line, ctx.col - 1)
    then
      local next_char = lex.next(ctx.line, ctx.col)
      if next_char == "}" then
        return result("pair", "interpolation_existing_closer", "{", "")
      end
      if next_char == "`" or lex.next_allows_pair(next_char, ctx.rules) then
        -- The dollar is already typed; render only the brace pair.
        return result("pair", "template_interpolation", "{", "}")
      end
    end
    return nil
  end
  if ctx.syntax ~= "code" then
    return nil
  end
  local sub = ctx.substitution
  if interpolation and interpolation ~= false and sub then
    if interpolation.space then
      local padding = require("pairs.padding").multi(ctx, key, interpolation, {
        open = "${",
        close = "}",
        open_row = sub.body_row,
        open_col = sub.body_col - 2,
        close_row = sub.close_row,
        close_col = sub.close_col,
      })
      if padding then
        return padding
      end
    end
    local closing = ctx.row == sub.close_row and ctx.col == sub.close_col
    if key == "}" and interpolation.skip and closing then
      return result("skip", "interpolation_closer", "${", "}")
    end
    local empty = closing and ctx.row == sub.body_row and ctx.col == sub.body_col
    if empty and key == "<BS>" then
      return result(interpolation.delete and "delete" or "pass", "empty_interpolation", "${", "}")
    end
    if empty and key == "<CR>" then
      return result(interpolation.newline and "newline" or "pass", "empty_interpolation", "${", "}")
    end
  end
  if key == "`" and tick and tick ~= false and tick.close == "`" and tick.open then
    local state = lex.scan(ctx.lex_line or ctx.line, ctx.col, ctx.lex)
    local previous = lex.previous(ctx.line, ctx.col)
    if
      not state.uncertain
      and not state.comment
      and not state.quote
      and not ctx.lex.quotes[previous]
      and not lex.escaped(ctx.line, ctx.col)
      and lex.next_allows_pair(lex.next(ctx.line, ctx.col), ctx.rules)
    then
      -- Identifiers/calls before a template may be its tag. Unlike ordinary
      -- quotes, template opening is valid next to those code expressions.
      return result("pair", "opening_template", "`", "`")
    end
  end
end

return M
