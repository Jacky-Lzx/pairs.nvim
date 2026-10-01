-- Multi-character policy is independent of mappings and owns no buffer state.
-- The first rule family is Python triple quotes, proven by parser boundaries.
local lex = require("pairs.lex")
local M = {}
local prefixes = {
  [""] = true,
  r = true,
  u = true,
  b = true,
  f = true,
  br = true,
  rb = true,
  fr = true,
  rf = true,
}

local function result(action, reason, open, close, extra)
  local value = { action = action, reason = reason, open = open, close = close }
  for key, item in pairs(extra or {}) do
    value[key] = item
  end
  return value
end

function M.decide(ctx, key)
  if ctx.filetype ~= "python" or not ctx.multi_rules then
    return nil
  end
  local delimiter = ctx.literal_delimiter
  local rule = delimiter and ctx.multi_rules[delimiter]
  if ctx.syntax == "string" and rule and rule ~= false then
    local closing = ctx.literal_close_col
    local at_close = closing ~= nil and ctx.row == ctx.literal_close_row
    if
      key == delimiter:sub(-1)
      and rule.skip
      and at_close
      and ctx.col >= closing
      and ctx.col < closing + #delimiter
    then
      return result("skip", "triple_closer", delimiter, delimiter, { move = 1 })
    end
    local empty = at_close
      and ctx.row == ctx.literal_start_row
      and ctx.col == closing
      and ctx.col == ctx.literal_open_col + #delimiter
    if empty and key == "<BS>" and rule.delete then
      return result("delete", "empty_triple", delimiter, delimiter)
    end
    if empty and key == "<CR>" and rule.newline then
      return result("newline", "empty_triple", delimiter, delimiter, { indent_offset = 0 })
    end
    return nil
  end

  -- Upgrade only a complete empty short string, never an arbitrary quote run.
  local previous = ctx.previous_string
  if ctx.syntax ~= "code" or not previous or not previous.string_empty then
    return nil
  end
  if previous.empty_quote ~= key then
    return nil
  end
  delimiter = string.rep(key, 3)
  rule = ctx.multi_rules[delimiter]
  if not rule or rule == false or not rule.open then
    return nil
  end
  if not prefixes[previous.string_prefix:lower()] then
    return nil
  end
  local state = lex.scan(ctx.lex_line or ctx.line, ctx.col, ctx.lex)
  if state.uncertain or state.comment or state.quote then
    return nil
  end
  local neighbor = lex.previous(ctx.line, previous.string_start)
  if lex.word(neighbor) or neighbor == key or lex.escaped(ctx.line, previous.string_start) then
    return nil
  end
  if not lex.next_allows_pair(lex.next(ctx.line, ctx.col), ctx.rules) then
    return nil
  end
  return result("pair", "triple_upgrade", key, delimiter)
end

return M
