-- Bounded, parser-independent discovery. All offsets are zero-based bytes;
-- regions are half-open so they translate directly to nvim_buf_set_text().
local M = {}

local function region(first, last, left, right, trim, text)
  local inner_first, inner_last = first + left, last - right
  if trim then
    while inner_first < inner_last and text:sub(inner_first + 1, inner_first + 1):match("%s") do
      inner_first = inner_first + 1
    end
    while inner_last > inner_first and text:sub(inner_last, inner_last):match("%s") do
      inner_last = inner_last - 1
    end
  end
  return { first = first, last = last, inner_first = inner_first, inner_last = inner_last }
end

local function literal(text, left, right, trim, masked)
  local source = masked or text
  local result, stack, i, slashes = {}, {}, 1, 0
  while i <= #text do
    local step = 1
    if source:sub(i, i + #right - 1) == right and #stack > 0 and slashes % 2 == 0 then
      local first = table.remove(stack)
      result[#result + 1] = region(first - 1, i + #right - 1, #left, #right, trim, text)
      step = #right
    elseif source:sub(i, i + #left - 1) == left and slashes % 2 == 0 then
      stack[#stack + 1] = i
      step = #left
    end
    for j = i, i + step - 1 do
      slashes = source:byte(j) == 92 and slashes + 1 or 0
    end
    i = i + step
    if #result > 10000 or #stack > 256 then
      return nil
    end
  end
  return result
end

-- Tags are tokenized before matching, including quoted attributes and nested
-- tags with the same name. Declarations, comments and self-closing tags do
-- not own surrounding regions.
local function tags(text)
  local result, stack, i = {}, {}, 1
  local void = {
    area = true,
    base = true,
    br = true,
    col = true,
    embed = true,
    hr = true,
    img = true,
    input = true,
    link = true,
    meta = true,
    param = true,
    source = true,
    track = true,
    wbr = true,
  }
  while i <= #text do
    local start = text:find("<", i, true)
    if not start then
      break
    end
    if text:sub(start, start + 3) == "<!--" then
      local stop = text:find("-->", start + 4, true)
      if not stop then
        break
      end
      i = stop + 3
    else
      local quote, stop
      for j = start + 1, #text do
        local char = text:sub(j, j)
        if quote then
          if char == quote then
            quote = nil
          end
        elseif char == '"' or char == "'" then
          quote = char
        elseif char == ">" then
          stop = j
          break
        end
      end
      if not stop then
        break
      end
      local token = text:sub(start, stop)
      local closing, name = token:match("^<(/?)([%a_][%w_:%.%-]*)[%s/>]")
      if name then
        if closing == "/" then
          local top = stack[#stack]
          if top and top.name == name and token:match("^</[^%s>]+%s*>$") then
            table.remove(stack)
            result[#result + 1] = region(top.first - 1, stop, top.length, #token, false, text)
          else
            -- Never infer a complete outer tag across mismatched markup.
            stack = {}
          end
        elseif not token:match("/%s*>$") and not void[name:lower()] then
          stack[#stack + 1] = { first = start, length = #token, name = name }
        end
      end
      i = stop + 1
    end
    if #result > 10000 or #stack > 256 then
      return nil
    end
  end
  return result
end

function M.candidates(text, spec, masked)
  if spec.kind == "tag" then
    return tags(text)
  end
  local result, limited = {}, false
  local function append(items)
    if not items then
      limited = true
      return
    end
    for _, item in ipairs(items) do
      result[#result + 1] = item
    end
  end
  if spec.kind == "bracket" then
    for _, pair in ipairs({ { "(", ")" }, { "[", "]" }, { "{", "}" } }) do
      append(literal(text, pair[1], pair[2], false, masked))
    end
  elseif spec.kind == "quote" then
    for _, quote in ipairs({ '"', "'", "`" }) do
      append(literal(text, quote, quote, false))
    end
  elseif spec.kind == "function" then
    local calls = literal(text, "(", ")", false, masked)
    if not calls then
      return nil
    end
    for _, item in ipairs(calls) do
      local start = item.first
      while start > 0 and text:sub(start, start):match("[%w_%.]") do
        start = start - 1
      end
      local name = text:sub(start + 1, item.first)
      name = name:match("^[%a_][%w_%.]*$")
      if name then
        item.first = item.first - #name
        result[#result + 1] = item
      end
    end
  else
    append(literal(text, spec.left, spec.right, spec.trim, masked))
  end
  if limited or #result > 10000 then
    return nil
  end
  return result
end

function M.select(candidates, cursor, method, count)
  local covering, before, after = {}, {}, {}
  if not candidates then
    return nil
  end
  for _, item in ipairs(candidates) do
    if item.first <= cursor and cursor < item.last then
      covering[#covering + 1] = item
    elseif item.last <= cursor then
      before[#before + 1] = item
    else
      after[#after + 1] = item
    end
  end
  table.sort(covering, function(a, b)
    if a.last - a.first == b.last - b.first then
      return a.first > b.first
    end
    return a.last - a.first < b.last - b.first
  end)
  table.sort(before, function(a, b)
    if a.last == b.last then
      return a.first > b.first
    end
    return a.last > b.last
  end)
  table.sort(after, function(a, b)
    if a.first == b.first then
      return a.last < b.last
    end
    return a.first < b.first
  end)
  local nearby = {}
  for _, items in ipairs({ before, after }) do
    for _, item in ipairs(items) do
      nearby[#nearby + 1] = item
    end
  end
  table.sort(nearby, function(a, b)
    local da = math.min(math.abs(cursor - a.first), math.abs(cursor - a.last + 1))
    local db = math.min(math.abs(cursor - b.first), math.abs(cursor - b.last + 1))
    if da == db then
      return a.first < b.first
    end
    return da < db
  end)
  local chosen = covering
  if method == "next" then
    chosen = after
  elseif method == "prev" then
    chosen = before
  elseif method == "nearest" then
    chosen = #covering > 0 and covering or nearby
  elseif #covering == 0 then
    chosen = ({ cover_or_next = after, cover_or_prev = before, cover_or_nearest = nearby })[method]
      or covering
  end
  return chosen[count or 1]
end

function M.find(text, spec, cursor, method, count)
  return M.select(M.candidates(text, spec), cursor, method, count)
end

return M
