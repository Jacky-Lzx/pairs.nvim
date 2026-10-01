-- A bounded, line-local lexer. It deliberately does not pretend to parse a language.
local M = {}

function M.next_allows_pair(char, rules)
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

function M.previous(text, col)
  if col == 0 then
    return ""
  end
  local start = col
  while start > 1 and text:byte(start) >= 128 and text:byte(start) < 192 do
    start = start - 1
  end
  return text:sub(start, col)
end

function M.next(text, col)
  local start = col + 1
  local byte = text:byte(start)
  if not byte then
    return ""
  end
  local length = byte < 128 and 1 or byte < 224 and 2 or byte < 240 and 3 or 4
  return text:sub(start, start + length - 1)
end

function M.word(char)
  -- Treat non-ASCII neighbors conservatively, including Chinese text.
  return char ~= "" and (char:match("^[%w_]$") ~= nil or char:byte() >= 128)
end

function M.escaped(text, col)
  local count = 0
  while col > 0 and text:sub(col, col) == "\\" do
    count = count + 1
    col = col - 1
  end
  return count % 2 == 1
end

local function rust_char(text, opening)
  local first = M.next(text, opening)
  if first == "\\" then
    local tail = text:sub(opening + 1, opening + 16)
    return tail:match("^\\[nrt0\\'\"]'") ~= nil
      or tail:match("^\\x%x%x'") ~= nil
      or tail:match("^\\u{%x+}'") ~= nil
  end
  return first ~= "" and text:sub(opening + #first + 1, opening + #first + 1) == "'"
end

function M.scan(text, col, opts, include_before)
  if col > opts.max_scan_bytes then
    return { uncertain = true, reason = "scan_limit" }
  end
  local quote, stack, before = nil, {}, nil
  local i, backslashes = 1, 0
  while i <= col do
    if include_before and i == col then
      -- Empty-pair actions only need the quote state before the final ASCII
      -- opener. Any earlier error/comment still aborts the complete scan below.
      before = { quote = quote }
    end
    local char = text:sub(i, i)
    local escaped = backslashes % 2 == 1
    if quote then
      if char == quote and not escaped then
        quote = nil
      end
    else
      for _, marker in ipairs(opts.line_comments) do
        if not escaped and i + #marker - 1 <= col and text:sub(i, i + #marker - 1) == marker then
          return { comment = true, stack = stack }
        end
      end
      if not escaped then
        if opts.quotes[char] then
          local apostrophe = char == "'" and M.word(M.previous(text, i - 1))
          -- Rust lifetime/label syntax is not a single-quoted string.
          local lifetime = char == "'" and opts.rust and not rust_char(text, i)
          if not apostrophe and not lifetime then
            quote = char
          end
        elseif opts.openers[char] then
          stack[#stack + 1] = char
        elseif opts.closers[char] then
          local open = stack[#stack]
          if open and opts.openers[open] == char then
            stack[#stack] = nil
          else
            -- A malformed prefix is insufficient evidence for skipping later closers.
            return { uncertain = true, reason = "unmatched_closer" }
          end
        end
      end
    end
    backslashes = char == "\\" and backslashes + 1 or 0
    i = i + 1
  end
  return { quote = quote, stack = stack, before = before }
end

return M
