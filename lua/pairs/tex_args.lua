-- Command argument recovery uses current syntax anchors and a bounded prefix.
local M = {}
local profiles = {
  section = { option = "text", "text" },
  subsection = { option = "text", "text" },
  subsubsection = { option = "text", "text" },
  chapter = { option = "text", "text" },
  part = { option = "text", "text" },
  paragraph = { option = "text", "text" },
  subparagraph = { option = "text", "text" },
  textbf = { "text" },
  textit = { "text" },
  textrm = { "text" },
  textsf = { "text" },
  texttt = { "text" },
  textnormal = { "text" },
  emph = { "text" },
  underline = { "text" },
  url = { "literal" },
  nolinkurl = { "literal" },
  path = { "literal" },
  href = { option = "unknown", "literal", "text" },
}
for _, name in ipairs({
  "section",
  "subsection",
  "subsubsection",
  "chapter",
  "part",
  "paragraph",
  "subparagraph",
}) do
  profiles[name .. "*"] = profiles[name]
end
local priority = { text = 0, unknown = 1, literal = 2 }
local function before(ar, ac, br, bc)
  return ar < br or (ar == br and ac < bc)
end
local function command(node, buf)
  local token = node:field("command")[1]
  if token then
    local sr, sc, er, ec = token:range()
    if sr == er and ec - sc <= 64 then
      return vim.treesitter.get_node_text(token, buf):match("^\\([%a@]+%*?)$")
    end
  end
end
local function previous_child(node, row, col)
  local low, high = 0, node:child_count()
  while low < high do
    local mid = math.floor((low + high) / 2)
    local sr, sc = node:child(mid):range()
    if before(sr, sc, row, col) then
      low = mid + 1
    else
      high = mid
    end
  end
  return low > 0 and node:child(low - 1) or nil
end
local function anchor(root, row, col, buf)
  local node = root:descendant_for_range(row, math.max(col - 1, 0), row, math.max(col - 1, 0))
  if node:id() == root:id() then
    node = previous_child(root, row, col) or node
  end
  local branch, first
  while node do
    local kind = node:type()
    local sr, sc, er, ec = node:range()
    local unfinished = node:has_error() and not before(row, col, sr, sc)
    local inside = before(row, col, er, ec) or unfinished
    local previous = node:prev_named_sibling()
    if previous then
      local name = command(previous, buf)
      local _, _, pr = previous:range()
      if
        previous:type() == "ERROR"
        or (pr == row and profiles[name] and profiles[name][1] == "literal")
      then
        first = previous
      end
    end
    if kind == "ERROR" then
      first = node
      local previous = node:prev_named_sibling()
      if previous and profiles[command(previous, buf)] then
        first = previous -- A section header can detach its unfinished argument.
      end
    elseif command(node, buf) and (inside or (row == er and col == ec)) then
      if
        (branch and (branch:type():match("^curly_group") or branch:type():match("^brack_group")))
        or (unfinished and (kind == "generic_command" or kind == "hyperlink"))
      then
        first = node
      end
    end
    branch, node = node, node:parent()
  end
  return first
end
local function prefix(buf, first, row, col)
  local sr, sc = first:range()
  if row - sr > 31 or before(row, col, sr, sc) then
    return nil
  end
  local bytes = vim.api.nvim_buf_get_offset(buf, row)
    + col
    - vim.api.nvim_buf_get_offset(buf, sr)
    - sc
  if bytes > 4096 then
    return nil
  end
  return table.concat(vim.api.nvim_buf_get_text(buf, sr, sc, row, col, {}), "\n"), sr, sc
end
local function scan(text)
  local stack, spans, pending, math, unsafe, comment = {}, {}, nil, nil, false, false
  local function mode()
    return stack[#stack] and stack[#stack].region or "text"
  end
  local i = 1
  while i <= #text do
    local char = text:sub(i, i)
    local raw = mode() == "literal"
    if char == "\\" then
      local name = not raw and text:match("^\\([%a@]+%*?)", i)
      if name then
        local token = text:match("^\\[%a@]+%*?", i)
        pending = { name = name, profile = profiles[name], index = 0 }
        if name == "begin" or name == "end" or name == "verb" then
          unsafe = true
        end
        i = i + #token
      else
        local symbol = text:sub(i + 1, i + 1)
        if not raw then
          if symbol == "(" or symbol == "[" then
            math = math and "unknown" or symbol
          elseif symbol == ")" or symbol == "]" then
            if math == (symbol == ")" and "(" or "[") then
              math = nil
            else
              unsafe = true
            end
          end
          pending = nil
        end
        i = i + (symbol == "" and 1 or 2)
      end
    elseif not raw and char == "%" then
      local newline = text:find("\n", i, true)
      comment = not newline
      i = (newline or #text) + 1
    elseif not raw and char == "$" then
      local token = text:sub(i, i + 1) == "$$" and "$$" or "$"
      if math == token then
        math = nil
      else
        math = math and "unknown" or token
      end
      pending, i = nil, i + #token
    elseif char == "{" or (not raw and char == "[") then
      local is_arg = pending and (char == "{" or (pending.profile and pending.profile.option))
      local inherited = mode()
      local group = { close = char == "{" and "}" or "]", mode = inherited, at = i }
      if is_arg then
        local option = char == "["
        pending.index = pending.index + (option and 0 or 1)
        group.mode = option and pending.profile.option
          or (pending.profile and pending.profile[pending.index] or "unknown")
        group.name, group.argument = pending.name, true
        group.resume = pending
      end
      group.region = priority[group.mode] > priority[inherited] and group.mode or inherited
      stack[#stack + 1], pending, i = group, nil, i + 1
    elseif char == "}" or (not raw and char == "]") then
      local group = stack[#stack]
      if not group or group.close ~= char then
        return { unsafe = true }
      end
      if group.argument and group.mode == "literal" then
        spans[#spans + 1] = { group.at, i }
      end
      stack[#stack], pending = nil, group.resume
      if pending and pending.profile and pending.index >= #pending.profile then
        pending = nil
      end
      i = i + 1
    else
      if not char:match("%s") then
        pending = nil
      end
      i = i + 1
    end
  end
  local argument
  for _, group in ipairs(stack) do
    if group.argument then
      argument = group
    end
  end
  if argument or #spans > 0 then
    local top = stack[#stack]
    return {
      mode = mode(),
      name = argument and argument.name,
      active = argument ~= nil,
      proven = not unsafe and not math,
      close = top and top.argument and top.close or nil,
      empty = top and top.argument and top.at == #text,
      spans = spans,
      comment = comment,
    }
  end
end
function M.capture(root, row, col, line, buf)
  local first = anchor(root, row, col, buf)
  if not first then
    return nil
  end
  local text, sr, sc = prefix(buf, first, row, col)
  if not text then
    return { mode = "unknown", unsafe = true }
  end
  local result = scan(text)
  if result then
    result.start_row, result.start_col = sr, sc
    result.close = result.close == line:sub(col + 1, col + 1) and result.close or nil
    local offset = #text - col
    local masked = line
    for _, span in ipairs(result.spans or {}) do
      local first_col, last_col = math.max(0, span[1] - offset), math.min(col, span[2] - offset - 1)
      if first_col < last_col then
        masked = masked:sub(1, first_col)
          .. string.rep(" ", last_col - first_col)
          .. masked:sub(last_col + 1)
      end
      local function position(index)
        local prefix = text:sub(1, index - 1)
        local _, count = prefix:gsub("\n", "")
        return sr + count, count == 0 and sc + #prefix or #(prefix:match("[^\n]*$") or "")
      end
      span.start_row, span.start_col = position(span[1] + 1)
      span.end_row, span.end_col = position(span[2])
    end
    result.lex_line = masked ~= line and masked or nil
  end
  return result
end
function M.raw_comment(argument, row, col)
  if not argument or argument.comment then
    return false
  end
  for _, span in ipairs(argument.spans or {}) do
    if
      not before(row, col, span.start_row, span.start_col)
      and before(row, col, span.end_row, span.end_col)
    then
      return true
    end
  end
  return false
end
return M
