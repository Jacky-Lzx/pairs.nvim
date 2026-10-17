local M = {}
M.defaults = {
  enabled = false,
  mappings = {
    add = "sa",
    delete = "sd",
    replace = "sr",
    find = "sf",
    find_left = "sF",
    highlight = "sh",
    update_n_lines = "sn",
    suffix_last = "l",
    suffix_next = "n",
  },
  n_lines = 20,
  search_method = "cover",
  highlight_duration = 500,
  respect_selection_type = false,
  max_scan_bytes = 1024 * 1024,
  custom_surroundings = {},
}
local methods =
  { "cover", "cover_or_next", "cover_or_prev", "cover_or_nearest", "next", "prev", "nearest" }
local config, global_enabled, pending, replay, previous_operator, visual_state
local owned, conflicts = {}, {}
local namespace = vim.api.nvim_create_namespace("pairs.surround")
local highlight_generation = {}
local operator_name = "v:lua.require'pairs.surround'.operator"

function M.validate(opts)
  assert(type(opts) == "table", "pairs: surround must be a table")
  assert(type(opts.enabled) == "boolean", "pairs: surround.enabled must be boolean")
  assert(
    type(opts.respect_selection_type) == "boolean",
    "pairs: surround.respect_selection_type must be boolean"
  )
  for _, key in ipairs({ "n_lines", "highlight_duration", "max_scan_bytes" }) do
    assert(
      type(opts[key]) == "number"
        and opts[key] % 1 == 0
        and opts[key] >= (key == "max_scan_bytes" and 1 or 0),
      "pairs: surround." .. key .. " must be a nonnegative integer (scan budget must be positive)"
    )
  end
  assert(vim.tbl_contains(methods, opts.search_method), "pairs: invalid surround.search_method")
  assert(type(opts.mappings) == "table", "pairs: surround.mappings must be a table")
  local seen = {}
  for _, key in ipairs({
    "add",
    "delete",
    "replace",
    "find",
    "find_left",
    "highlight",
    "update_n_lines",
    "suffix_last",
    "suffix_next",
  }) do
    local lhs = opts.mappings[key]
    assert(
      type(lhs) == "string",
      "pairs: surround.mappings." .. key .. " must be a string; use '' to disable"
    )
    if lhs ~= "" and key ~= "suffix_last" and key ~= "suffix_next" then
      assert(not seen[lhs], "pairs: duplicate surround mapping " .. lhs)
      seen[lhs] = true
    end
  end
  for _, action in ipairs({ "delete", "replace", "find", "find_left", "highlight" }) do
    for _, suffix in ipairs({ opts.mappings.suffix_last, opts.mappings.suffix_next }) do
      if opts.mappings[action] ~= "" and suffix ~= "" then
        local lhs = opts.mappings[action] .. suffix
        assert(not seen[lhs], "pairs: duplicate surround mapping " .. lhs)
        seen[lhs] = true
      end
    end
  end
  assert(
    type(opts.custom_surroundings) == "table",
    "pairs: surround.custom_surroundings must be a table"
  )
  for id, spec in pairs(opts.custom_surroundings) do
    assert(
      type(id) == "string" and vim.fn.strchars(id) == 1,
      "pairs: surround identifiers must be one character"
    )
    assert(
      spec == false or type(spec) == "table",
      "pairs: custom surrounding must be a table or false"
    )
    if spec ~= false then
      for _, part in ipairs({ "input", "output" }) do
        local value = spec[part]
        assert(
          value == nil
            or type(value) == "function"
            or (
              type(value) == "table"
              and type(value.left) == "string"
              and type(value.right) == "string"
              and (part == "output" or (#value.left > 0 and #value.right > 0))
            ),
          "pairs: custom surrounding " .. part .. " must be { left, right } strings or a function"
        )
      end
    end
  end
end

local function options()
  if not config then
    return nil
  end
  local ft = vim.bo.filetype
  local opts = vim.tbl_deep_extend(
    "force",
    vim.deepcopy(config.surround),
    (config.filetypes[ft] or {}).surround or {},
    vim.b.pairs_surround_config or {}
  )
  M.validate(opts)
  if
    not opts.enabled
    or not global_enabled()
    or vim.b.pairs_enabled == false
    or vim.b.pairs_surround_enabled == false
    or vim.bo.buftype ~= ""
    or not vim.bo.modifiable
    or vim.tbl_contains(config.disabled_filetypes, ft)
    or (config.filetypes[ft] or {}).enabled == false
    or config.enabled == false
    or (type(config.enabled) == "function" and not config.enabled(0))
  then
    return nil
  end
  return opts
end

local function character()
  local ok, value = pcall(vim.fn.getcharstr)
  if not ok or value == "\027" or value == "\003" or vim.fn.strchars(value) ~= 1 then
    return nil
  end
  return value
end

local function prompt(label)
  local ok, value =
    pcall(vim.fn.input, { prompt = "Surround " .. label .. ": ", cancelreturn = "\027" })
  if not ok or value == "\027" then
    return nil
  end
  return value
end

local brackets = {
  ["("] = ")",
  [")"] = "(",
  ["["] = "]",
  ["]"] = "[",
  ["{"] = "}",
  ["}"] = "{",
  ["<"] = ">",
  [">"] = "<",
}
local opening = { ["("] = true, ["["] = true, ["{"] = true, ["<"] = true }

local function specification(id, part, opts)
  local custom = opts.custom_surroundings[id]
  if custom == false then
    return nil
  end
  if custom then
    local value = custom[part]
    if type(value) == "function" then
      value = value()
    end
    if value == nil then
      return nil
    end
    assert(
      type(value) == "table" and type(value.left) == "string" and type(value.right) == "string",
      "pairs: surround callback must return { left, right } or nil"
    )
    assert(
      part == "output" or (#value.left > 0 and #value.right > 0),
      "pairs: empty surround search delimiter"
    )
    return vim.deepcopy(value)
  end
  if brackets[id] then
    local left, right = opening[id] and id or brackets[id], opening[id] and brackets[id] or id
    if part == "output" and opening[id] then
      return { left = left .. " ", right = " " .. right }
    end
    return { left = left, right = right, trim = opening[id] == true }
  end
  if id == "b" then
    return part == "input" and { kind = "bracket" } or { left = "(", right = ")" }
  end
  if id == "q" then
    return part == "input" and { kind = "quote" } or { left = '"', right = '"' }
  end
  if id == "t" then
    if part == "input" then
      return { kind = "tag" }
    end
    local tag = prompt("tag")
    if not tag then
      return nil
    end
    local name = tag:match("^([%a_][%w_:%.%-]*)")
    if not name or tag:find("[<>\r\n]") then
      return nil
    end
    return { left = "<" .. tag .. ">", right = "</" .. name .. ">" }
  end
  if id == "f" then
    if part == "input" then
      return { kind = "function" }
    end
    local name = prompt("function")
    if not name or not name:match("^[%a_][%w_%.]*$") then
      return nil
    end
    return { left = name .. "(", right = ")" }
  end
  if id == "?" then
    local left = prompt("left")
    if not left then
      return nil
    end
    local right = prompt("right")
    if not right or (part == "input" and (#left == 0 or #right == 0)) then
      return nil
    end
    return { left = left, right = right }
  end
  return { left = id, right = id }
end

local function read_spec(part, opts)
  local id = character()
  return id and specification(id, part, opts)
end

local function char_end(line, col)
  col = math.min(#line, math.max(0, col))
  -- Operator marks may point to the last byte of a character; Visual marks
  -- point to its first byte. Normalize both before computing an exclusive end.
  if col == #line then
    return col
  end
  return vim.fn.byteidx(line, vim.fn.charidx(line, col) + 1)
end

local function byte_position(window, offset)
  for i = #window.starts, 1, -1 do
    if offset >= window.starts[i] then
      return { window.first_row + i - 1, offset - window.starts[i] }
    end
  end
  return { window.first_row, 0 }
end

local function window(opts)
  local pos = vim.api.nvim_win_get_cursor(0)
  local first = math.max(0, pos[1] - 1 - opts.n_lines)
  local last = math.min(vim.api.nvim_buf_line_count(0), pos[1] + opts.n_lines)
  local bytes = vim.api.nvim_buf_get_offset(0, last) - vim.api.nvim_buf_get_offset(0, first)
  if bytes > opts.max_scan_bytes then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(0, first, last, false)
  local starts, size = {}, 0
  for i, line in ipairs(lines) do
    starts[i], size = size, size + #line + 1
  end
  return {
    text = table.concat(lines, "\n"),
    starts = starts,
    first_row = first,
    cursor = starts[pos[1] - first] + pos[2],
  }
end

local function find(spec, opts, method, count)
  local context = window(opts)
  if not context then
    return nil
  end
  local region = require("pairs.surround_scan").find(
    context.text,
    spec,
    context.cursor,
    method or opts.search_method,
    count
  )
  if not region then
    return nil
  end
  return region, context
end

local function edit(edits, cursor)
  -- Every range and prompt is resolved before the first mutation. Apply in
  -- reverse document order; join only this operation's subsequent changes.
  table.sort(edits, function(a, b)
    if a.first[1] == b.first[1] then
      return a.first[2] > b.first[2]
    end
    return a.first[1] > b.first[1]
  end)
  for i, item in ipairs(edits) do
    if i > 1 then
      vim.cmd("undojoin")
    end
    vim.api.nvim_buf_set_text(
      0,
      item.first[1],
      item.first[2],
      item.last[1],
      item.last[2],
      vim.split(item.text, "\n", { plain = true })
    )
  end
  if cursor then
    local lines = vim.api.nvim_buf_line_count(0)
    local row = math.min(cursor[1], lines - 1)
    local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
    vim.api.nvim_win_set_cursor(0, { row + 1, math.min(cursor[2], #line) })
  end
end

local function selected(kind, visual)
  local a, b =
    vim.api.nvim_buf_get_mark(0, visual and "<" or "["),
    vim.api.nvim_buf_get_mark(0, visual and ">" or "]")
  if a[1] > b[1] or (a[1] == b[1] and a[2] > b[2]) then
    a, b = b, a
  end
  local lines = vim.api.nvim_buf_get_lines(0, a[1] - 1, b[1], false)
  a, b = { a[1] - 1, a[2] }, { b[1] - 1, b[2] }
  if kind == "line" then
    a[2] = #(lines[1]:match("^%s*") or "")
    b[2] = math.max(0, #(lines[#lines]:gsub("%s*$", "")))
  else
    a[2] = math.min(a[2], #lines[1])
    b[2] = visual and vim.o.selection == "exclusive" and math.min(b[2], #lines[#lines])
      or char_end(lines[#lines], b[2])
  end
  if a[1] == b[1] then
    b[2] = math.max(a[2], b[2])
  end
  return a, b, lines
end

local function add(kind, state, opts, visual)
  local first, last, lines = selected(kind, visual)
  local output = state.output or read_spec("output", opts)
  if not output then
    return false
  end
  state.output = output
  if (#output.left + #output.right) * state.count > opts.max_scan_bytes then
    return false
  end
  local left, right = output.left:rep(state.count), output.right:rep(state.count)
  if opts.respect_selection_type and kind == "line" then
    local indent = lines[1]:match("^%s*") or ""
    local width = vim.bo.shiftwidth > 0 and vim.bo.shiftwidth or vim.bo.tabstop
    local extra = vim.bo.expandtab and string.rep(" ", width) or "\t"
    local body = {}
    for _, line in ipairs(lines) do
      body[#body + 1] = line == "" and "" or extra .. line
    end
    local replacement = indent
      .. left
      .. "\n"
      .. table.concat(body, "\n")
      .. "\n"
      .. indent
      .. right
    edit(
      { { first = { first[1], 0 }, last = { last[1], #lines[#lines] }, text = replacement } },
      { first[1] + 1, #extra + #indent }
    )
  elseif opts.respect_selection_type and kind == "block" then
    local a = state.block_columns and state.block_columns[1]
      or vim.fn.virtcol(visual and "'<" or "'[")
    local b = state.block_columns and state.block_columns[2]
      or vim.fn.virtcol(visual and "'>" or "']")
    local lo, hi = math.min(a, b), math.max(a, b)
    if visual and vim.o.selection == "exclusive" then
      hi = hi - 1
    end
    local edits = {}
    for i, line in ipairs(lines) do
      local row = first[1] + i - 1
      local start = lo > vim.fn.strdisplaywidth(line) and #line
        or math.max(0, vim.fn.virtcol2col(0, row + 1, lo) - 1)
      local stop = hi > vim.fn.strdisplaywidth(line) and #line
        or char_end(line, math.max(0, vim.fn.virtcol2col(0, row + 1, hi) - 1))
      edits[#edits + 1] = {
        first = { row, start },
        last = { row, stop },
        text = left .. line:sub(start + 1, stop) .. right,
      }
    end
    edit(edits, { first[1], edits[1].first[2] + #left })
  else
    -- A single replacement also handles empty ranges without ordering two
    -- insertions at the same byte position.
    local body = vim.api.nvim_buf_get_text(0, first[1], first[2], last[1], last[2], {})
    edit(
      { { first = first, last = last, text = left .. table.concat(body, "\n") .. right } },
      { first[1], first[2] + #left }
    )
  end
  return true
end

local function change(state, opts)
  local input = state.input or read_spec("input", opts)
  if not input then
    return false
  end
  local region, context = find(input, opts, state.method, state.count)
  if not region then
    return false
  end
  local output = state.action == "delete" and { left = "", right = "" }
    or state.output
    or read_spec("output", opts)
  if not output then
    return false
  end
  state.input, state.output = input, output
  local first = byte_position(context, region.first)
  local last = byte_position(context, region.last)
  local left_end, right_start =
    byte_position(context, region.inner_first), byte_position(context, region.inner_last)
  -- Remove otherwise blank delimiter lines and restore one indent level.
  local left_line = vim.api.nvim_buf_get_lines(0, first[1], first[1] + 1, false)[1]
  local right_line = vim.api.nvim_buf_get_lines(0, last[1], last[1] + 1, false)[1]
  if
    state.action == "delete"
    and first[1] < last[1]
    and left_end[1] == first[1]
    and right_start[1] == last[1]
    and left_line:sub(1, first[2]):match("^%s*$")
    and left_line:sub(left_end[2] + 1):match("^%s*$")
    and right_line:sub(1, right_start[2]):match("^%s*$")
    and right_line:sub(last[2] + 1):match("^%s*$")
  then
    local body = vim.api.nvim_buf_get_lines(0, first[1] + 1, last[1], false)
    local width = vim.bo.shiftwidth > 0 and vim.bo.shiftwidth or vim.bo.tabstop
    for i, line in ipairs(body) do
      body[i] = line:sub(1, 1) == "\t" and line:sub(2)
        or line:gsub("^" .. string.rep(" ", width), "", 1)
    end
    edit({
      {
        first = { first[1], 0 },
        last = { last[1], #right_line },
        text = table.concat(body, "\n"),
      },
    }, { first[1], #(body[1] and body[1]:match("^%s*") or "") })
    return true
  end
  edit({
    { first = first, last = byte_position(context, region.inner_first), text = output.left },
    {
      first = byte_position(context, region.inner_last),
      last = byte_position(context, region.last),
      text = output.right,
    },
  }, { first[1], first[2] + #output.left })
  return true
end

function M.operator(kind)
  local opts = options()
  local state = pending or replay
  if not opts or not state then
    return
  end
  local fresh = pending ~= nil
  pending = nil
  local ok = state.action == "add" and add(kind, state, opts, false)
    or state.action ~= "add" and change(state, opts)
  if ok then
    replay = state
  elseif fresh then
    replay = nil
  end
end

function M.start(action, method)
  if not options() then
    return "<Esc>"
  end
  pending = { action = action, method = method, count = vim.v.count1 }
  if vim.o.operatorfunc ~= operator_name then
    previous_operator = vim.o.operatorfunc
  end
  vim.o.operatorfunc = operator_name
  -- The command boundary consumes the prefix count. For add it controls
  -- wrapper repetition, while a count after sa belongs to the user's motion.
  return "<Cmd>redraw<CR>g@" .. (action == "add" and "" or " ")
end

function M.prepare_visual()
  visual_state = { action = "add", count = vim.v.count1, mode = vim.fn.mode() }
  if visual_state.mode == "\022" then
    visual_state.block_columns =
      { vim.fn.virtcol("v"), math.max(vim.fn.virtcol("."), vim.fn.getcurpos()[5]) }
  end
  return "<Esc><Cmd>lua require('pairs.surround').visual()<CR>"
end

function M.visual()
  local opts = options()
  if not opts then
    return
  end
  local state = visual_state or { action = "add", count = vim.v.count1, mode = vim.fn.visualmode() }
  visual_state = nil
  local kind = ({ v = "char", V = "line", ["\022"] = "block" })[state.mode] or "char"
  add(kind, state, opts, true)
end

function M.action(action, method, count)
  local opts = options()
  if not opts then
    return
  end
  if action == "update_n_lines" then
    local value = prompt("search range")
    local number = value and value:match("^%d+$") and tonumber(value)
    if number and number < math.huge then
      local override = vim.b.pairs_surround_config or {}
      override.n_lines = number
      vim.b.pairs_surround_config = override
    end
    return
  end
  local spec = read_spec("input", opts)
  if not spec then
    return
  end
  local region, context = find(spec, opts, method, count or vim.v.count1)
  if not region then
    return
  end
  if action == "highlight" then
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    highlight_generation[buf] = (highlight_generation[buf] or 0) + 1
    local generation = highlight_generation[buf]
    for _, range in ipairs({
      { region.first, region.inner_first },
      { region.inner_last, region.last },
    }) do
      local first, last = byte_position(context, range[1]), byte_position(context, range[2])
      vim.api.nvim_buf_set_extmark(
        buf,
        namespace,
        first[1],
        first[2],
        { end_row = last[1], end_col = last[2], hl_group = "PairsSurround", priority = 200 }
      )
    end
    vim.defer_fn(function()
      if generation == highlight_generation[buf] and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
      end
    end, opts.highlight_duration)
  else
    local positions = {
      region.first,
      math.max(region.first, region.inner_first - 1),
      region.inner_last,
      region.last - 1,
    }
    for i, offset in ipairs(positions) do
      while
        offset > 0
        and (context.text:byte(offset + 1) or 0) >= 128
        and (context.text:byte(offset + 1) or 0) < 192
      do
        offset = offset - 1
      end
      positions[i] = offset
    end
    table.sort(positions)
    local chosen = action == "find_left" and positions[#positions] or positions[1]
    if action == "find_left" then
      for i = #positions, 1, -1 do
        if positions[i] < context.cursor then
          chosen = positions[i]
          break
        end
      end
    else
      for _, pos in ipairs(positions) do
        if pos > context.cursor then
          chosen = pos
          break
        end
      end
    end
    local pos = byte_position(context, chosen)
    vim.api.nvim_win_set_cursor(0, { pos[1] + 1, pos[2] })
    vim.cmd("normal! zv")
  end
end

local function install(mode, lhs, callback, expr, label)
  if lhs == "" then
    return false
  end
  local canonical = vim.api.nvim_replace_termcodes(lhs, true, true, true)
  for _, mapping in ipairs(vim.api.nvim_get_keymap(mode)) do
    if vim.api.nvim_replace_termcodes(mapping.lhs, true, true, true) == canonical then
      conflicts[#conflicts + 1] = mode .. ":" .. lhs
      return false
    end
  end
  vim.keymap.set(
    mode,
    lhs,
    callback,
    { expr = expr, silent = true, desc = "pairs.nvim surround " .. label }
  )
  owned[#owned + 1] = { mode = mode, lhs = lhs, callback = callback }
  return true
end

function M.setup(candidate, enabled)
  config, global_enabled = candidate, enabled
  vim.api.nvim_set_hl(0, "PairsSurround", { default = true, link = "IncSearch" })
  local active = config.surround.enabled
  for _, overrides in pairs(config.filetypes) do
    active = active or (overrides.surround or {}).enabled
  end
  if not active or not config.mappings.enabled then
    return
  end
  local maps = config.surround.mappings
  for _, action in ipairs({
    "add",
    "delete",
    "replace",
    "find",
    "find_left",
    "highlight",
    "update_n_lines",
  }) do
    local operator = action == "add" or action == "delete" or action == "replace"
    local function register(lhs, method)
      local plug = "<Plug>(pairs-surround-" .. action .. (method and "-" .. method or "") .. ")"
      local ok = install("n", plug, operator and function()
        return M.start(action, method)
      end or function()
        M.action(action, method)
      end, operator, action)
      if ok then
        install("n", lhs, plug, false, action)
      end
      if action == "find" or action == "find_left" then
        for _, mode in ipairs({ "x", "o" }) do
          local command = "<Cmd>lua require('pairs.surround').action('"
            .. action
            .. "',"
            .. (method and "'" .. method .. "'" or "nil")
            .. ","
          if
            install(mode, plug, function()
              return command .. vim.v.count1 .. ")<CR>"
            end, true, action)
          then
            install(mode, lhs, plug, false, action)
          end
        end
      end
    end
    register(maps[action])
    if action == "add" then
      local plug = "<Plug>(pairs-surround-add)"
      if install("x", plug, M.prepare_visual, true, action) then
        install("x", maps.add, plug, false, action)
      end
    elseif action ~= "update_n_lines" and maps[action] ~= "" then
      if maps.suffix_last ~= "" then
        register(maps[action] .. maps.suffix_last, "prev")
      end
      if maps.suffix_next ~= "" then
        register(maps[action] .. maps.suffix_next, "next")
      end
    end
  end
end

function M.teardown()
  for _, item in ipairs(owned) do
    for _, mapping in ipairs(vim.api.nvim_get_keymap(item.mode)) do
      if
        vim.api.nvim_replace_termcodes(mapping.lhs, true, true, true)
          == vim.api.nvim_replace_termcodes(item.lhs, true, true, true)
        and (
          mapping.callback == item.callback
          or (
            type(item.callback) == "string"
            and mapping.rhs
            and vim.api.nvim_replace_termcodes(mapping.rhs, true, true, true)
              == vim.api.nvim_replace_termcodes(item.callback, true, true, true)
          )
        )
      then
        vim.keymap.del(item.mode, item.lhs)
      end
    end
  end
  if vim.o.operatorfunc == operator_name then
    vim.o.operatorfunc = previous_operator or ""
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    end
  end
  for buf, generation in pairs(highlight_generation) do
    highlight_generation[buf] = generation + 1
  end
  config, global_enabled, pending, replay, previous_operator = nil, nil, nil, nil, nil
  visual_state = nil
  owned, conflicts = {}, {}
end

function M.status()
  return {
    enabled = config ~= nil and config.surround.enabled,
    mappings = #owned,
    conflicts = vim.deepcopy(conflicts),
  }
end

return M
