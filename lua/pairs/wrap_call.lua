-- Structural proof for one same-line call, within the caller's bounded window.
-- Complex literal syntaxes are rejected rather than interpreted as plain quotes.
local M = {}
local opens = { ["("] = ")", ["["] = "]", ["{"] = "}" }
local closes = { [")"] = true, ["]"] = true, ["}"] = true }
local javascript = {
  javascript = true,
  javascriptreact = true,
  typescript = true,
  typescriptreact = true,
}
local shell = { sh = true, bash = true, zsh = true }

local function unsafe_quote(text, at, ft)
  local quote = text:sub(at, at)
  if text:sub(at, at + 2) == string.rep(quote, 3) then
    return true
  end
  local prev = text:sub(at - 1, at - 1)
  local first = at - 1
  while first > 0 and text:sub(first, first):match("[A-Za-z]") do
    first = first - 1
  end
  local prefix = text:sub(first + 1, at - 1)
  return prev == "#"
    or (ft == "python" and prefix:lower():find("[fr]") ~= nil)
    or (ft == "rust" and prefix:sub(-1) == "r")
    or (ft == "cpp" and prefix:sub(-1) == "R")
    or (ft == "cs" and (prev == "@" or prev == "$"))
end

function M.finish(text, start, opts, ft)
  local stack, quote, backslashes = {}, nil, 0
  for at = start, #text do
    local char = text:sub(at, at)
    local escaped = backslashes % 2 == 1
    if quote then
      -- Interpolated strings may contain nested quotes; they need a language
      -- parser rather than the ordinary quote/escape proof used here.
      if
        (shell[ft] and quote == '"' and char == "$" and not escaped)
        or (ft == "ruby" and quote == '"' and char == "#" and not escaped and text:sub(
          at + 1,
          at + 1
        ) == "{")
        or (ft == "swift" and char == "(" and escaped)
      then
        return nil, "unsupported_call_literal"
      end
      if char == quote and (not escaped or (shell[ft] and quote == "'")) then
        quote = nil
      end
    else
      for _, marker in ipairs(opts.line_comments) do
        if text:sub(at, at + #marker - 1) == marker then
          return nil, "call_comment"
        end
      end
      if text:sub(at, at + 1) == "/*" then
        return nil, "call_comment"
      end
      if
        char == "`"
        or char == "\\"
        or ((javascript[ft] or ft == "ruby" or ft == "swift") and char == "/")
        or (ft == "ruby" and char == "%")
        or (ft == "lua" and char == "[" and text:find("^%[=*%[", at))
        or (opts.quotes[char] and char ~= '"' and char ~= "'")
      then
        return nil, "unsupported_call_literal"
      end
      if char == '"' or char == "'" then
        if unsafe_quote(text, at, ft) then
          return nil, "unsupported_call_literal"
        end
        quote = char
      elseif opens[char] then
        stack[#stack + 1] = opens[char]
      elseif closes[char] then
        if stack[#stack] ~= char then
          return nil, "mismatched_call"
        end
        stack[#stack] = nil
        if #stack == 0 then
          return at
        end
      end
    end
    backslashes = char == "\\" and backslashes + 1 or 0
  end
  return nil, "incomplete_call"
end

return M
