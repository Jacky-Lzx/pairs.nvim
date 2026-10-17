-- Extract math boundaries from the current outer LaTeX tree.
local lex = require("pairs.lex")
local nodes = require("pairs.tex_node")
local M = {}
local literal = {
  verbatim_environment = true,
  listing_environment = true,
  minted_environment = true,
  asy_environment = true,
  asydef_environment = true,
  pycode_environment = true,
  luacode_environment = true,
  sagesilent_environment = true,
  sageblock_environment = true,
  source_code = true,
  text_mode = true,
}
local math_nodes = {
  inline_formula = true,
  displayed_equation = true,
  math_environment = true,
  math_delimiter = true,
}
local priority = { text = 0, unknown = 1, math = 2, literal = 3 }

local function restrict(current, mode)
  return priority[mode] > priority[current] and mode or current
end

local function short_text(node, buf)
  if not node then
    return nil
  end
  local sr, sc, er, ec = node:range()
  if sr ~= er or ec - sc > 64 then
    return nil
  end
  return vim.treesitter.get_node_text(node, buf)
end

local function environment_name(begin, buf)
  local text = begin and short_text(nodes.field(begin, "name"), buf)
  return text and text:match("^%{([%w_.:%*%-]+)%}$") or nil
end

local function environment_mode(begin, buf, environments)
  local name = environment_name(begin, buf)
  return name and environments[name] or "unknown"
end

local function recovery_prefix(parent, leaf, buf, environments, row, col, argument)
  -- Recovery can flatten scopes or put a raw body's end command inside math.
  -- Inspect bounded syntax children, never fetch or scan the whole body text.
  local stack, visited = {}, 0
  local function mode()
    local result = "text"
    for _, scope in ipairs(stack) do
      result = restrict(result, scope.mode)
    end
    return result
  end
  local function ending(child)
    local name = environment_name(child, buf)
    local active = stack[#stack]
    if active and active.mode == "literal" then
      if name == active.name then
        stack[#stack] = nil
      end
      return true -- Other environment-looking text is raw code.
    end
    if not name or not active or name ~= active.name then
      return false
    end
    stack[#stack] = nil
    return true
  end
  local visit
  visit = function(child)
    local sr, sc, er, ec = child:range()
    if sr > row or (sr == row and sc >= col) then
      return true
    end
    if
      argument
      and argument.proven
      and (sr > argument.start_row or (sr == argument.start_row and sc >= argument.start_col))
    then
      return true -- This prefix is a validated command argument, not a lost scope.
    end
    visited = visited + 1
    if visited > 256 then
      return false
    end
    local kind = child:type()
    local raw = mode() == "literal"
    if kind == "begin" then
      if not raw then
        local name = environment_name(child, buf)
        if not name then
          return false
        end
        stack[#stack + 1] = { name = name, mode = environments[name] or "unknown" }
      end
      return true
    elseif kind == "end" then
      return ending(child)
    elseif kind == "generic_command" then
      local command = short_text(nodes.field(child, "command"), buf)
      if command == "\\begin" or command == "\\end" then
        local name = short_text(nodes.field(child, "arg"), buf)
        name = name and name:match("^%{([%w_.:%*%-]+)%}$")
        if command == "\\end" then
          local active = stack[#stack]
          if raw then
            if active and name == active.name then
              stack[#stack] = nil
            end
            return true
          end
          if not active or not name or name ~= active.name then
            return false
          end
          stack[#stack] = nil
        elseif not raw then
          if not name then
            return false
          end
          stack[#stack + 1] = { name = name, mode = environments[name] or "unknown" }
        end
        return true
      end
      return raw or (command ~= nil and not child:has_error())
    end
    if not raw and kind:match("_environment$") and not child:has_error() then
      local begin, finish = nodes.environment(child)
      if finish and environment_name(begin, buf) == environment_name(finish, buf) then
        return true -- A complete sibling is no longer an active scope.
      end
    elseif not raw and kind ~= "ERROR" then
      return child:named() and not child:has_error()
    end
    -- Inside declared raw code, descend only containers that can hide commands.
    -- Leaf text and punctuation need no interpretation.
    for nested in child:iter_children() do
      local nr, nc = nested:range()
      if nr > row or (nr == row and nc >= col) then
        break
      end
      if not visit(nested) then
        return false
      end
    end
    return true
  end
  for child in parent:iter_children() do
    local sr, sc, er, ec = child:range()
    local at_target = leaf and child:id() == leaf:id()
    local is_end = child:type() == "end"
      or (
        child:type() == "generic_command"
        and short_text(nodes.field(child, "command"), buf) == "\\end"
      )
    local finished_end = is_end and (er < row or (er == row and ec <= col))
    if (at_target and not finished_end) or sr > row or (sr == row and sc >= col) then
      if at_target and mode() == "literal" then
        return visit(child), mode() -- Its prefix may contain the raw scope's end.
      end
      return true, mode()
    end
    if not visit(child) then
      return false, mode()
    end
  end
  return true, mode()
end

local function inline_literal(text, col)
  -- The grammar parses \verb as a generic command. Mask its delimiter span,
  -- including an unfinished span, rather than trusting dollar nodes inside it.
  local from = 1
  while from <= #text do
    local first, last = text:find("\\verb%*?", from)
    if not first then
      break
    end
    local delimiter = text:sub(last + 1, last + 1)
    if not lex.escaped(text, first - 1) and delimiter ~= "" and not delimiter:match("[%a%s]") then
      local finish = text:find(delimiter, last + 2, true)
      if col >= last + 1 and (not finish or col < finish) then
        return true
      end
    end
    from = last + 1
  end
  -- Other inline code commands have package-specific option/delimiter syntax.
  -- Conservatively preserve input on their remaining line.
  for _, command in ipairs({ "\\lstinline", "\\mintinline" }) do
    local start = text:find(command, 1, true)
    if start and not lex.escaped(text, start - 1) and col >= start + #command then
      return true
    end
  end
  return false
end

function M.capture(root, row, col, text, buf, environments, custom_literal)
  environments = environments or require("pairs.tex_env").defaults
  if custom_literal == nil then
    custom_literal = false
    for name, mode in pairs(environments) do
      if mode == "literal" and require("pairs.tex_env").protected[name] ~= "literal" then
        custom_literal = true
        break
      end
    end
  end
  local result = { upgrade = false }
  if inline_literal(text, col) then
    return { blocked = true }
  end
  local argument = require("pairs.tex_args").capture(root, row, col, text, buf)
  local left = math.max(col - 1, 0)
  local leaf = root:descendant_for_range(row, left, row, left)
  local parent = leaf:parent()
  local sr, sc, er, ec = leaf:range()
  -- A pending control symbol may consume the following space/punctuation in
  -- the grammar. Only the typed prefix must be exactly one backslash.
  result.slash_open = leaf:type() == "command_name"
    and sr == row
    and sc == col - 1
    and text:sub(col, col) == "\\"
    and not lex.escaped(text, col - 1)
  local candidate = leaf:type() == "$"
    and not leaf:missing()
    and sr == row
    and er == row
    and sc == col - 1
    and ec == col
  if candidate and parent then
    if parent:type() == "inline_formula" then
      result.upgrade = parent:child(0):id() == leaf:id()
        and parent:child(parent:child_count() - 1):missing()
    end
  end
  local node, formula, branch, region, uncertain = leaf, nil, nil, "text", false
  local outer_literal, visited = false, 0
  while node do
    visited = visited + 1
    if visited > 256 then
      return { blocked = true, uncertain = true, region = "unknown" }
    end
    local kind = node:type()
    local br, bc, nr, nc = node:range()
    local inside = row < nr
      or (row == nr and col < nc)
      or (kind == "line_comment" and row == nr and col == nc)
    if inside and (literal[kind] or kind:find("comment", 1, true)) then
      local recovered_comment = kind:find("comment", 1, true)
        and require("pairs.tex_args").raw_comment(argument, br, bc)
      if not recovered_comment then
        region = "literal"
      end
      local raw_content = argument
        and argument.mode == "literal"
        and argument.proven
        and (br > argument.start_row or (br == argument.start_row and bc >= argument.start_col))
      outer_literal = outer_literal or (not raw_content and not recovered_comment)
    end
    if
      kind == "ERROR"
      or (custom_literal and (kind == "source_file" or kind == "generic_environment"))
    then
      local safe, mode = recovery_prefix(node, branch, buf, environments, row, col, argument)
      region = restrict(region, mode)
      outer_literal = outer_literal or mode == "literal"
      if not safe then
        region = restrict(region, "unknown")
        result.slash_open = false
        uncertain = custom_literal
      end
      if kind == "ERROR" then
        if candidate and parent and node:id() == parent:id() then
          result.upgrade = safe and mode == "text"
        else
          result.upgrade = false
        end
      end
    end
    if kind:match("_environment$") then
      local begin, ending = nodes.environment(node)
      local er, ec
      if ending then
        er, ec = ending:end_()
      end
      local after_end = ending and (er < row or (er == row and ec <= col))
      if not after_end then
        if ending and environment_name(begin, buf) ~= environment_name(ending, buf) then
          region = restrict(region, "unknown")
        else
          local mode = environment_mode(begin, buf, environments)
          region = restrict(region, mode)
          outer_literal = outer_literal or mode == "literal"
        end
      end
    end
    if math_nodes[kind] then
      result.slash_open = false
      if not parent or node:id() ~= parent:id() then
        result.upgrade = false
      end
      if (kind == "displayed_equation" or kind == "inline_formula") and not formula then
        formula = node
        local open, close = node:child(0), node:child(node:child_count() - 1)
        local expected = ({ ["$$"] = "$$", ["\\("] = "\\)", ["\\["] = "\\]" })[open:type()]
        if expected and close:type() == expected and not close:missing() then
          local br, bc = open:range()
          local cr, cc = close:range()
          result.pair = {
            open = open:type(),
            close = close:type(),
            open_row = br,
            open_col = bc,
            close_row = cr,
            close_col = cc,
          }
        end
      elseif formula then
        region = restrict(region, "math") -- No nested formula inside another math zone.
      end
    end
    branch = node
    node = node:parent()
  end
  if argument then
    result.lex_line = argument.lex_line
    result.raw_comment = not outer_literal and not argument.comment and argument.lex_line ~= nil
    if argument.active and not outer_literal and not uncertain and not argument.unsafe then
      result.argument = argument
    end
    region = restrict(region, argument.mode or "unknown")
    uncertain = uncertain or argument.unsafe
  end
  if region ~= "text" then
    return {
      blocked = true,
      literal = region == "literal",
      uncertain = uncertain,
      region = region,
      argument = result.argument,
      lex_line = result.lex_line,
      raw_comment = result.raw_comment,
    }
  end
  return result
end

return M
