-- Incremental lexical state, independent of pairing decisions and parsers.
-- All state is scalar so unchanged line boundaries converge in constant time.
local M = {}
local opens = { ["("] = ")", ["["] = "]", ["{"] = "}" }
local closes = { [")"] = "(", ["]"] = "[", ["}"] = "{" }
local hash =
  { python = true, sh = true, bash = true, zsh = true, ruby = true, yaml = true, toml = true }
local slash = {
  c = true,
  cpp = true,
  rust = true,
  swift = true,
  go = true,
  java = true,
  cs = true,
  javascript = true,
  javascriptreact = true,
  typescript = true,
  typescriptreact = true,
  jsonc = true,
  css = true,
  scss = true,
}
local templates =
  { javascript = true, javascriptreact = true, typescript = true, typescriptreact = true }
local prose = { text = true, markdown = true, tex = true, plaintex = true }
local lex = require("pairs.lex")

local function rust_char(text, pos)
  local first = lex.next(text, pos)
  if first == "\\" then
    local tail = text:sub(pos + 1, pos + 16)
    return tail:match("^\\[nrt0\\'\"]'") or tail:match("^\\x%x%x'") or tail:match("^\\u{%x+}'")
  end
  return first ~= "" and text:sub(pos + #first + 1, pos + #first + 1) == "'"
end

function M.initial()
  return { stack = "", mode = "", close = "", nesting = 0 }
end

function M.equal(a, b)
  return a.stack == b.stack and a.mode == b.mode and a.close == b.close and a.nesting == b.nesting
end

function M.line(text, previous, ft, limits)
  local state = {
    stack = previous.stack,
    mode = previous.mode,
    close = previous.close,
    nesting = previous.nesting,
  }
  local marks, i, n = {}, 1, #text
  local function push(char, col)
    if #state.stack >= limits.max_depth then
      return false
    end
    state.stack = state.stack .. char
    marks[#marks + 1] = col
    marks[#marks + 1] = #state.stack
    return true
  end
  local escaped = lex.escaped
  while i <= n do
    if state.mode == "block" then
      if ft == "rust" or ft == "swift" then
        -- One forward pass: searching independently for every future opener
        -- and closer would be quadratic in an unfinished nested comment.
        local pos = text:find("[*/]", i)
        if not pos then
          break
        end
        local token = text:sub(pos, pos + 1)
        if token == "/*" then
          state.nesting, i = state.nesting + 1, pos + 2
        elseif token == "*/" then
          state.nesting, i = state.nesting - 1, pos + 2
          if state.nesting == 0 then
            state.mode, state.close = "", ""
          end
        else
          i = pos + 1
        end
      else
        local finish = text:find(state.close, i, true)
        if not finish then
          break
        end
        i, state.mode, state.close, state.nesting = finish + #state.close, "", "", 0
      end
    elseif state.mode == "quote" or state.mode == "raw" or state.mode == "multi" then
      local finish = text:find(state.close, i, true)
      if not finish then
        break
      end
      if state.mode ~= "raw" and escaped(text, finish - 1) then
        i = finish + 1
      else
        i, state.mode, state.close = finish + #state.close, "", ""
      end
    elseif state.mode == "template" then
      local pos = text:find("[`$\\]", i)
      if not pos then
        break
      end
      local char = text:sub(pos, pos)
      if char == "\\" then
        i = pos + 2
      elseif char == "`" then
        i, state.mode = pos + 1, ""
      elseif text:sub(pos + 1, pos + 1) == "{" then
        if not push("t", pos) then
          return nil, "depth_limit"
        end
        i, state.mode = pos + 2, ""
      else
        i = pos + 1
      end
    else
      local pos = text:find("[%(%)%[%]{}\"'`/#%%\\%-]", i)
      if not pos then
        break
      end
      i = pos
      local char, next_two = text:sub(i, i), text:sub(i, i + 1)
      if char == "\\" then
        i = i + 2 -- Escaped delimiters (notably TeX) are literal.
      elseif (hash[ft] and char == "#") or ((ft == "tex" or ft == "plaintex") and char == "%") then
        break
      elseif ft == "lua" and (next_two == "--" or char == "[") then
        local start = next_two == "--" and i + 2 or i
        local equals = text:match("^%[(=*)%[", start)
        if equals then
          state.mode, state.close = "raw", "]" .. equals .. "]"
          i = start + #equals + 2
        elseif next_two == "--" then
          break
        else
          if not push(char, i - 1) then
            return nil, "depth_limit"
          end
          i = i + 1
        end
      elseif slash[ft] and next_two == "//" then
        break
      elseif slash[ft] and next_two == "/*" then
        state.mode, state.close, state.nesting, i = "block", "*/", 1, i + 2
      elseif char == "`" and templates[ft] then
        state.mode, i = "template", i + 1
      elseif char == "`" and (ft == "go" or ft == "sh" or ft == "bash" or ft == "zsh") then
        state.mode, state.close, i = "raw", "`", i + 1
      elseif (char == '"' or char == "'") and not prose[ft] then
        local lifetime = ft == "rust" and char == "'" and not rust_char(text, i)
        if lifetime then
          i = i + 1
        else
          local triple = ft == "python" and text:sub(i, i + 2) == string.rep(char, 3)
          local raw
          if ft == "rust" and char == '"' then
            local start = i - 1
            while text:byte(start) == 35 do
              start = start - 1
            end
            if text:sub(start, start) == "r" then
              raw = text:sub(start + 1, i - 1)
            end
          end
          state.mode = raw and "raw" or triple and "multi" or "quote"
          state.close = raw and ('"' .. raw) or triple and string.rep(char, 3) or char
          i = i + (triple and 3 or 1)
        end
      elseif opens[char] then
        if not push(char, i - 1) then
          return nil, "depth_limit"
        end
        i = i + 1
      elseif closes[char] then
        local top = state.stack:sub(-1)
        if top == closes[char] or (top == "t" and char == "}") then
          marks[#marks + 1], marks[#marks + 2] = i - 1, #state.stack
          state.stack = state.stack:sub(1, -2)
          if top == "t" then
            state.mode = "template"
          end
        end -- Unmatched/mismatched closers retain their normal syntax color.
        i = i + 1
      else
        i = i + 1
      end
    end
  end
  -- Ordinary unterminated quotes recover at the next line. Explicit multiline
  -- forms keep their state. A trailing escape continues an ordinary string.
  if state.mode == "quote" and not escaped(text, n) then
    state.mode, state.close = "", ""
  end
  return { after = state, marks = marks }
end

return M
