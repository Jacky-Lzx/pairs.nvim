local lex = require("pairs.lex")
local M = {}

local function decision(action, reason, open, close)
  return { action = action, reason = reason, open = open, close = close }
end

local function next_allows_pair(char, rules)
  if char == "" or char:match("^%s$") or char == "," or char == ";" or char == ":" then
    return true
  end
  for open, rule in pairs(rules) do
    if rule ~= false and open ~= rule.close and char == rule.close then
      return true
    end
  end
  return false
end

local function quote_can_open(prev, quotes)
  return not lex.word(prev) and not quotes[prev] and prev ~= "`"
end

-- The engine consumes a snapshot; all Neovim interaction belongs to the adapter.
function M.decide(ctx, key)
  if not ctx.enabled then
    return decision("pass", ctx.disabled_reason or "disabled")
  end
  if ctx.syntax == "unknown" or ctx.literal_string then
    return decision("pass", ctx.literal_string and "literal_string" or "syntax_pending")
  end
  local state = lex.scan(ctx.line, ctx.col, ctx.lex)
  if state.uncertain then
    return decision("pass", state.reason)
  end
  if state.comment or ctx.syntax == "comment" then
    return decision("pass", "comment")
  end
  local prev, next_char = lex.previous(ctx.line, ctx.col), lex.next(ctx.line, ctx.col)

  if key == "<BS>" or key == "<CR>" then
    local rule = ctx.rules[prev]
    if not rule or rule == false or next_char ~= rule.close then
      return decision("pass", "not_empty_pair")
    end
    local before = lex.scan(ctx.line, ctx.col - #prev, ctx.lex)
    if
      before.uncertain
      or before.comment
      or before.quote
      or lex.escaped(ctx.line, ctx.col - #prev)
    then
      return decision("pass", "not_pair_boundary")
    end
    if ctx.syntax == "string" and prev ~= rule.close then
      return decision("pass", "string")
    end
    if
      prev == rule.close
      and not quote_can_open(lex.previous(ctx.line, ctx.col - #prev), ctx.lex.quotes)
    then
      return decision("pass", "not_quote_boundary")
    end
    if key == "<BS>" and rule.delete then
      return decision("delete", "empty_pair", prev, rule.close)
    end
    if key == "<CR>" and rule.newline and prev ~= rule.close then
      return decision("newline", "empty_pair", prev, rule.close)
    end
    return decision("pass", "action_disabled")
  end

  if lex.escaped(ctx.line, ctx.col) then
    return decision("pass", "escaped")
  end
  local rule = ctx.rules[key]
  if rule and rule ~= false and key == rule.close then
    if state.quote == key then
      if next_char == key and rule.skip then
        return decision("skip", "matching_quote", key, key)
      end
      return decision("pass", "closing_quote")
    end
    if state.quote or ctx.syntax == "string" then
      return decision("pass", "string")
    end
    if not rule.open then
      return decision("pass", "opening_disabled")
    end
    if not quote_can_open(prev, ctx.lex.quotes) then
      return decision("pass", "quote_neighbor")
    end
    if not next_allows_pair(next_char, ctx.rules) then
      return decision("pass", "next_character")
    end
    return decision("pair", "opening_quote", key, rule.close)
  end

  if state.quote or ctx.syntax == "string" then
    return decision("pass", "string")
  end
  if rule and rule ~= false then
    if rule.open and next_allows_pair(next_char, ctx.rules) then
      return decision("pair", "opening_bracket", key, rule.close)
    end
    return decision("pass", rule.open and "next_character" or "opening_disabled")
  end
  for open, candidate in pairs(ctx.rules) do
    if candidate ~= false and candidate.close == key and key ~= open then
      if candidate.skip and next_char == key and state.stack[#state.stack] == open then
        return decision("skip", "matching_bracket", open, key)
      end
      return decision("pass", "unmatched_bracket")
    end
  end
  return decision("pass", "unconfigured_key")
end

return M
