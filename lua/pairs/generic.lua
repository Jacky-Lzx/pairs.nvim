-- Opt-in literal multi-character pairs. Specialized language families retain
-- their existing ownership and parser requirements.
local M = {}
local special = {
  ['"""'] = true,
  ["'''"] = true,
  ["${"] = true,
  ["```"] = true,
  ["~~~"] = true,
  ["$$"] = true,
  ["\\("] = true,
  ["\\["] = true,
}

function M.is_generic(open)
  return not special[open]
end

function M.prepare(rules)
  local ordered, keys = {}, {}
  for open, rule in pairs(rules) do
    if rule ~= false and M.is_generic(open) then
      ordered[#ordered + 1] = { open = open, rule = rule }
      keys[open:sub(-1)] = true
      for char in rule.close:gmatch(".") do
        keys[char] = true
      end
      keys["<BS>"], keys["<CR>"] = true, true
      if rule.space then
        keys[" "], keys["<Space>"] = true, true
      end
    end
  end
  table.sort(ordered, function(a, b)
    if #a.open == #b.open then
      return a.open < b.open
    end
    return #a.open > #b.open
  end)
  return { rules = ordered, keys = keys }
end

local function origin(ctx, offset)
  local window = ctx.generic_window
  local row, col, line
  for i = #window.starts, 1, -1 do
    if offset >= window.starts[i] then
      row, col, line = window.first_row + i - 1, offset - window.starts[i], window.lines[i]
      break
    end
  end
  if ctx.syntax == "comment" then
    if ctx.comment_start_row == row and ctx.comment_start_col == col then
      return "code"
    end
    return "comment"
  end
  if ctx.literal_string then
    return "string"
  end
  local source = row == ctx.row and (ctx.lex_line or line) or line
  local state = require("pairs.lex").scan(source, col, {
    max_scan_bytes = ctx.lex.max_scan_bytes,
    line_comments = ctx.lex.line_comments,
    quotes = ctx.lex.quotes,
    rust = ctx.lex.rust,
    openers = {},
    closers = {},
  })
  if state.uncertain then
    return nil
  end
  return state.comment and "comment" or state.quote and "string" or "code"
end

local function permitted(ctx, rule, action, offset)
  local context = origin(ctx, offset)
  local allowed = false
  for _, name in ipairs(rule.contexts) do
    allowed = allowed or context == name
  end
  if not allowed then
    return false
  end
  if rule.condition then
    local ok, value = pcall(rule.condition, ctx, action)
    return ok and value == true
  end
  return true
end

local function decision(action, reason, open, close, extra)
  local result = { action = action, reason = reason, open = open, close = close }
  for key, value in pairs(extra or {}) do
    result[key] = value
  end
  return result
end

function M.decide(ctx, key)
  local meta, window = ctx.generic_rules, ctx.generic_window
  if not meta or #meta.rules == 0 or not meta.keys[key] then
    return nil
  end
  if not window or ctx.syntax == "unknown" then
    return decision("pass", ctx.syntax == "unknown" and "syntax_pending" or "scan_limit")
  end
  local text, col = window.text, window.col
  local matching = text
  if ctx.syntax == "code" and ctx.lex_line then
    matching = text:sub(1, window.starts[#window.starts]) .. ctx.lex_line
  end
  local scan, lex = require("pairs.surround_scan"), require("pairs.lex")
  -- Markdown's parser can distinguish a fence line from inline strikeout.
  -- The third tilde upgrades an adjacent empty ~~ pair to a fence opener,
  -- instead of swallowing it as the first character of the generated closer.
  local fence_rule = ctx.multi_rules["~~~"]
  if
    key == "~"
    and ctx.filetype == "markdown"
    and fence_rule
    and fence_rule ~= false
    and fence_rule.open
    and ctx.fence
    and ctx.fence.supported
    and ctx.fence.open_row == ctx.row
    and not ctx.fence.close_row
    and ctx.line:sub(ctx.col - 1, ctx.col) == "~~"
    and ctx.line:sub(ctx.col + 1) == "~~"
  then
    for _, entry in ipairs(meta.rules) do
      if entry.open == "~~" and entry.rule.close == "~~" and entry.rule.open then
        return decision("pair", "generic_fence_upgrade", "~", "", { delete_after = 2 })
      end
    end
  end
  -- Prove a complete pair before skipping any byte of its closing delimiter.
  for _, entry in ipairs(meta.rules) do
    local open, rule = entry.open, entry.rule
    local close = rule.close
    local candidates = scan.candidates(text, { left = open, right = close }, matching)
    if not candidates then
      return decision("pass", "scan_limit")
    end
    local pair = scan.select(candidates, col, "cover", 1)
    if
      pair
      and col >= pair.inner_last
      and col < pair.last
      and text:sub(col + 1, col + 1) == key
    then
      if rule.skip and permitted(ctx, rule, "skip", pair.first) then
        return decision("skip", "generic_closer", open, close, { move = 1 })
      end
      return decision("pass", "generic_skip_disabled")
    end
    local width = key == " " and 0 or 1
    local padded = rule.space
      and (key == " " or key == "<BS>" or key == "<CR>")
      and text:sub(col - width - #open + 1, col - width) == open
      and text:sub(col + width + 1, col + width + #close) == close
      and (width == 0 or text:sub(col, col + 1) == "  ")
    local empty = text:sub(col - #open + 1, col) == open
      and text:sub(col + 1, col + #close) == close
    local first = col - #open - (padded and width or 0)
    if
      (empty or padded)
      and first >= 0
      and not lex.escaped(text, first)
      and (key == "<BS>" or key == "<CR>" or (padded and key == " "))
    then
      local action = key == "<BS>" and "delete" or key == "<CR>" and "newline" or "space"
      if not (rule[action] and permitted(ctx, rule, action, first)) then
        return decision("pass", "generic_action_disabled")
      end
      if action == "space" then
        return decision("pair", "empty_generic_space", " ", " ")
      end
      if padded and action == "delete" then
        return decision("delete", "empty_generic_padding", " ", " ")
      end
      return decision(
        action,
        "empty_generic_pair",
        open,
        close,
        { trim_space = padded or nil, clear_comment_leaders = action == "newline" or nil }
      )
    end
  end
  for _, entry in ipairs(meta.rules) do
    local open, rule = entry.open, entry.rule
    local prefix = open:sub(1, -2)
    local first = col - #prefix
    if key == open:sub(-1) and first >= 0 and text:sub(first + 1, col) == prefix then
      local completed = scan.candidates(text, { left = open, right = rule.close }) or {}
      for _, pair in ipairs(completed) do
        if pair.last <= col and first >= pair.inner_last and first < pair.last then
          return decision("pass", "generic_completed_closer")
        end
      end
      if lex.escaped(text, first) or not rule.open or not permitted(ctx, rule, "open", first) then
        return decision("pass", "generic_open_disabled")
      end
      local next = lex.next(ctx.line, ctx.col)
      if text:sub(col + 1, col + #rule.close) == rule.close then
        return decision("pair", "generic_existing_closer", key, "")
      end
      -- Standard auto-pairs may already have completed the typed prefix,
      -- e.g. '[' -> '[]' before the second '[' completes a '[[' rule.
      local native = ""
      for char in prefix:gmatch(".") do
        local pair = ctx.rules[char]
        if not pair or pair == false or pair.close == char then
          native = ""
          break
        end
        native = pair.close .. native
      end
      if
        native ~= ""
        and #native < #rule.close
        and rule.close:sub(-#native) == native
        and text:sub(col + 1, col + #native) == native
      then
        return decision(
          "pair",
          "generic_partial_closer",
          key,
          rule.close:sub(1, #rule.close - #native)
        )
      end
      if
        not lex.next_allows_pair(next, ctx.rules)
        and not (ctx.lex.quotes[next] and origin(ctx, first) == "string")
      then
        return decision("pass", "generic_neighbor")
      end
      return decision("pair", "generic_open", key, rule.close)
    end
  end
end

return M
