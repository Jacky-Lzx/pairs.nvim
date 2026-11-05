-- Parsing never runs in mappings or redraw callbacks. The provider only reads
-- the cache and emits ephemeral marks for visible lines. While scanning, a
-- bounded snapshot of previously drawn brackets follows byte edits.
local M = {}
local api, uv = vim.api, vim.uv
local scan = require("pairs.rainbow_scan")
local ns = api.nvim_create_namespace("pairs.rainbow")
local config, options, group
local states, attached = {}, {}
local generation = 0
local has_drawn = false
local palette = {
  PairsRainbowRed = "#e06c75",
  PairsRainbowYellow = "#e5c07b",
  PairsRainbowBlue = "#61afef",
  PairsRainbowOrange = "#d19a66",
  PairsRainbowGreen = "#98c379",
  PairsRainbowViolet = "#c678dd",
  PairsRainbowCyan = "#56b6c2",
}

function M.validate(opts)
  assert(type(opts) == "table", "pairs: rainbow must be a table")
  assert(type(opts.enabled) == "boolean", "pairs: rainbow.enabled must be boolean")
  for _, key in ipairs({
    "debounce_ms",
    "budget_ms",
    "max_lines",
    "max_bytes",
    "max_line_bytes",
    "max_depth",
    "max_brackets",
    "max_visible_brackets",
    "priority",
  }) do
    local value = opts[key]
    assert(
      type(value) == "number"
        and value == value
        and value < math.huge
        and value >= (key == "debounce_ms" and 0 or 1)
        and value % 1 == 0,
      "pairs: rainbow."
        .. key
        .. " must be a finite "
        .. (key == "debounce_ms" and "nonnegative" or "positive")
        .. " integer"
    )
  end
  assert(opts.priority <= 65535, "pairs: rainbow.priority must be at most 65535")
  assert(
    type(opts.highlights) == "table" and vim.islist(opts.highlights) and #opts.highlights > 0,
    "pairs: rainbow.highlights must be a nonempty list"
  )
  for _, name in ipairs(opts.highlights) do
    assert(
      type(name) == "string" and name:match("^[%w_@.]+$"),
      "pairs: invalid rainbow highlight name"
    )
  end
end

local function colors()
  for name, color in pairs(palette) do
    api.nvim_set_hl(0, name, { fg = color, default = true })
  end
end

local function allowed(buf)
  if not options or not options.enabled or not api.nvim_buf_is_loaded(buf) then
    return false
  end
  local ft = vim.bo[buf].filetype
  return vim.bo[buf].buftype == ""
    and vim.b[buf].pairs_rainbow ~= false
    and not vim.tbl_contains(config.disabled_filetypes, ft)
    and (config.filetypes[ft] or {}).enabled ~= false
end

local function visible(buf)
  return #vim.fn.win_findbuf(buf) > 0
end

local function cancel(state)
  state.ticket = (state.ticket or 0) + 1
  if state.timer then
    state.timer:stop()
    if not state.timer:is_closing() then
      state.timer:close()
    end
    state.timer = nil
  end
end

local function redraw(buf, first, last)
  api.nvim__redraw({
    buf = buf,
    range = first and { first, last } or nil,
    valid = first ~= nil,
    flush = false,
  })
end

local function block(state, reason)
  state.reason, state.cache, state.next, state.brackets = reason, {}, 0, 0
  state.edits, state.tail, state.reset = {}, 0, false
  state.windows = {}
  state.pending = false
end

local function reset(state)
  state.cache, state.edits, state.next, state.tail, state.brackets = {}, {}, 0, 0, 0
  state.reuse, state.reset = false, false
end

local function shift(state, edit)
  local first, old_end, new_end = unpack(edit)
  local delta, tail = new_end - old_end, state.tail
  if first >= tail then
    return
  end
  -- Huge replacements and edit bursts start a fresh background pass, keeping
  -- cache maintenance bounded even when a formatter replaces the whole file.
  if old_end - first > 512 or new_end - first > 512 then
    reset(state)
    return
  end
  for row = first + 1, math.min(old_end, tail) do
    local old = state.cache[row]
    state.brackets = state.brackets - (old and #old.marks / 2 or 0)
  end
  if old_end < tail then
    table.move(state.cache, old_end + 1, tail, new_end + 1)
  end
  local new_tail = math.max(first, tail + delta)
  for row = first + 1, math.min(new_end, new_tail) do
    state.cache[row] = nil
  end
  for row = new_tail + 1, tail do
    state.cache[row] = nil
  end
  state.tail = new_tail
end

local queue
local function step(buf, state)
  local started = uv.hrtime()
  local function measured()
    local elapsed = (uv.hrtime() - started) / 1e6
    state.work_ms = state.work_ms + elapsed
    state.max_slice_ms = math.max(state.max_slice_ms, elapsed)
    state.slices = state.slices + 1
  end
  if states[buf] ~= state or not allowed(buf) or not visible(buf) then
    state.pending = false
    return
  end
  local count = api.nvim_buf_line_count(buf)
  if count > options.max_lines then
    block(state, "line_count_limit")
  elseif api.nvim_buf_get_offset(buf, count) > options.max_bytes then
    block(state, "byte_limit")
  end
  if state.reason then
    redraw(buf)
    measured()
    return
  end
  local deadline = uv.hrtime() + options.budget_ms * 1e6
  if state.reset then
    reset(state)
  end
  while #state.edits > 0 do
    shift(state, table.remove(state.edits, 1))
    if uv.hrtime() >= deadline then
      measured()
      queue(buf, state, 1)
      return
    end
  end
  local start = state.next
  local redraw_end = start
  local stop = math.min(count, state.next + 128)
  local lines = api.nvim_buf_get_lines(buf, state.next, stop, false)
  for _, text in ipairs(lines) do
    local row, old = state.next, state.cache[state.next + 1]
    if #text > options.max_line_bytes then
      block(state, "line_length_limit")
      break
    end
    local before = row == 0 and scan.initial() or state.cache[row].after
    local entry, reason = scan.line(text, before, state.ft, options)
    if not entry then
      block(state, reason)
      break
    end
    state.brackets = state.brackets + #entry.marks / 2 - (old and #old.marks / 2 or 0)
    if state.brackets > options.max_brackets then
      block(state, "bracket_limit")
      break
    end
    state.cache[row + 1], state.next = entry, row + 1
    redraw_end = state.next
    state.scanned_lines = state.scanned_lines + 1
    -- Aligned unchanged lines retain their suffix once input state converges.
    if
      state.reuse
      and state.next >= state.dirty_end
      and old
      and scan.equal(entry.after, old.after)
    then
      state.next = count
      break
    end
    if uv.hrtime() >= deadline then
      break
    end
  end
  if state.next >= count then
    state.reuse = true
  end
  state.pending = not state.reason and state.next < count
  state.tail = math.max(state.tail, state.next)
  if not state.pending then
    state.dirty_end = 0
  end
  if state.reason then
    redraw(buf)
  elseif redraw_end > start then
    redraw(buf, start, redraw_end)
  end
  measured()
  if state.pending then
    queue(buf, state, 1)
  end
end

queue = function(buf, state, delay)
  cancel(state)
  state.pending = true
  local epoch = generation
  local ticket = state.ticket
  state.timer = vim.defer_fn(function()
    if generation == epoch and states[buf] == state and ticket == state.ticket then
      state.timer = nil
      step(buf, state)
    end
  end, delay)
end

-- Keep only brackets that survived the edit, with right gravity at insertions.
-- Byte coordinates also handle UTF-8, line splits and joins without lexing in
-- buffer callbacks. The work is bounded by the visible snapshot, not file size.
local function move_display(buf, first, col, old_rows, old_col, new_rows, new_col)
  local state = states[buf]
  if not state then
    return
  end
  local old_row, new_row = first + old_rows, first + new_rows
  old_col = old_col + (old_rows == 0 and col or 0)
  new_col = new_col + (new_rows == 0 and col or 0)
  for win, display in pairs(state.windows) do
    if not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= buf then
      state.windows[win] = nil
    else
      local rows, count = {}, 0
      for row, marks in vim.spairs(display.rows) do
        for i = 1, #marks, 2 do
          local target_row, target_col = row, marks[i]
          if row > old_row or (row == old_row and target_col >= old_col) then
            target_row = row + new_rows - old_rows
            if row == old_row then
              target_col = new_col + target_col - old_col
            end
          elseif row > first or (row == first and target_col >= col) then
            target_row = nil -- The bracket itself was deleted/replaced.
          end
          if target_row then
            local target = rows[target_row] or {}
            rows[target_row] = target
            target[#target + 1], target[#target + 2] = target_col, marks[i + 1]
            count = count + 1
          end
        end
      end
      display.rows, display.count = rows, count
    end
  end
end

local function invalidate(buf, first, old_end, new_end)
  local state = states[buf]
  if not state then
    return
  end
  if state.reason then
    state.reason, first, state.reuse = nil, 0, false
  end
  state.next = math.min(state.next, first)
  if old_end ~= new_end then
    local delta = new_end - old_end
    state.dirty_end = state.dirty_end > old_end and state.dirty_end + delta
      or math.min(state.dirty_end, first)
    if not state.reset then
      state.edits[#state.edits + 1] = { first, old_end, new_end }
      if #state.edits > 16 then
        state.edits, state.reset, state.next = {}, true, 0
      end
    end
  end
  -- A deletion can join two previously different lexical states. Always scan
  -- the first retained line after a splice before declaring convergence.
  state.dirty_end = math.max(state.dirty_end, new_end + (old_end ~= new_end and 1 or 0))
  queue(buf, state, options.debounce_ms)
end

local function attach(buf)
  if not allowed(buf) then
    local state = states[buf]
    if state then
      cancel(state)
      states[buf] = nil
    end
    return
  end
  local state = states[buf]
  local ft = vim.bo[buf].filetype
  if not state or state.ft ~= ft then
    if state then
      cancel(state)
    end
    state = {
      ft = ft,
      cache = {},
      windows = {},
      edits = {},
      next = 0,
      tail = 0,
      dirty_end = 0,
      reuse = false,
      brackets = 0,
      scanned_lines = 0,
      slices = 0,
      work_ms = 0,
      max_slice_ms = 0,
    }
    states[buf] = state
  end
  if not attached[buf] then
    attached[buf] = api.nvim_buf_attach(buf, false, {
      on_bytes = function(_, target, _, first, col, _, old_rows, old_col, _, new_rows, new_col)
        move_display(target, first, col, old_rows, old_col, new_rows, new_col)
      end,
      on_lines = function(_, target, _, first, old_end, new_end)
        invalidate(target, first, old_end, new_end)
      end,
      on_reload = function(_, target)
        local current = states[target]
        if current then
          cancel(current)
          states[target] = nil
        end
        vim.schedule(function()
          if options and api.nvim_buf_is_loaded(target) then
            attach(target)
          end
        end)
      end,
      on_detach = function(_, target)
        if states[target] then
          cancel(states[target])
        end
        states[target], attached[target] = nil, nil
      end,
    })
  end
  if not state.reason and state.next < api.nvim_buf_line_count(buf) then
    queue(buf, state, options.debounce_ms)
  end
end

function M.teardown()
  generation = generation + 1
  for _, state in pairs(states) do
    cancel(state)
  end
  states, config, options = {}, nil, nil
  if group then
    api.nvim_del_augroup_by_id(group)
    group = nil
  end
  api.nvim_set_decoration_provider(ns, {})
  if has_drawn then
    api.nvim__redraw({ valid = false })
    has_drawn = false
  end
end

function M.setup(candidate)
  M.teardown()
  config, options = candidate, candidate.rainbow
  if not options.enabled then
    return
  end
  colors()
  group = api.nvim_create_augroup("PairsRainbow", { clear = true })
  api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "FileType" }, {
    group = group,
    callback = function(args)
      attach(args.buf)
    end,
  })
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = colors })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      for _, state in pairs(states) do
        state.windows[tonumber(args.match)] = nil
      end
    end,
  })
  api.nvim_create_autocmd("BufHidden", {
    group = group,
    callback = function(args)
      local state = states[args.buf]
      if state then
        cancel(state)
        states[args.buf] = nil
      end
    end,
  })
  local drawn = 0
  api.nvim_set_decoration_provider(ns, {
    on_win = function(_, win, buf, top, bottom)
      drawn = 0
      local state = states[buf]
      if not state or not allowed(buf) then
        return false
      end
      local display = state.windows[win] or { rows = {}, count = 0 }
      state.windows[win] = display
      for row, marks in pairs(display.rows) do
        if row < top or row > bottom then
          display.rows[row] = nil
          display.count = display.count - #marks / 2
        end
      end
      return true
    end,
    -- on_line is used for compatibility with Neovim 0.11.
    on_line = function(_, win, buf, row)
      local state = states[buf]
      if not state then
        return
      end
      local display = state.windows[win]
      local entry = row < state.next and state.cache[row + 1] or nil
      local marks = entry and entry.marks or display.rows[row]
      if not marks then
        return
      end
      local snapshot
      if entry then
        display.count = display.count - #(display.rows[row] or {}) / 2
        snapshot = {}
        display.rows[row] = snapshot
      end
      local groups = options.highlights
      for i = 1, #marks, 2 do
        if drawn >= options.max_visible_brackets then
          break
        end
        drawn = drawn + 1
        has_drawn = true
        local col, depth = marks[i], marks[i + 1]
        if snapshot and display.count < options.max_visible_brackets then
          snapshot[#snapshot + 1], snapshot[#snapshot + 2] = col, depth
          display.count = display.count + 1
        end
        api.nvim_buf_set_extmark(buf, ns, row, col, {
          end_col = col + 1,
          hl_group = groups[(depth - 1) % #groups + 1],
          priority = options.priority,
          ephemeral = true,
          hl_mode = "combine",
        })
      end
    end,
  })
  for _, win in ipairs(api.nvim_list_wins()) do
    attach(api.nvim_win_get_buf(win))
  end
end

---Return bounded decorations for an immutable full document, without attaching
---buffers, scheduling work or changing the live rainbow cache. Rows/columns are
---zero-based bytes, suitable for projection into read-only previews.
function M.snapshot(lines, ft)
  if
    not options
    or not options.enabled
    or vim.tbl_contains(config.disabled_filetypes, ft)
    or (config.filetypes[ft] or {}).enabled == false
    or #lines > options.max_lines
  then
    return nil
  end
  local state, spans, bytes = scan.initial(), {}, 0
  for row, text in ipairs(lines) do
    bytes = bytes + #text + 1
    if bytes > options.max_bytes or #text > options.max_line_bytes then
      return nil
    end
    local entry = scan.line(text, state, ft, options)
    if not entry then
      return nil
    end
    state = entry.after
    for i = 1, #entry.marks, 2 do
      if #spans >= options.max_brackets then
        return nil
      end
      local col, depth = entry.marks[i], entry.marks[i + 1]
      spans[#spans + 1] = {
        row = row - 1,
        col = col,
        end_col = col + 1,
        hl_group = options.highlights[(depth - 1) % #options.highlights + 1],
        priority = options.priority,
      }
    end
  end
  return spans
end

function M.toggle(buf)
  buf = buf and buf ~= 0 and buf or api.nvim_get_current_buf()
  vim.b[buf].pairs_rainbow = vim.b[buf].pairs_rainbow == false
  if options then
    attach(buf)
    redraw(buf)
  end
  return vim.b[buf].pairs_rainbow
end

function M.status(buf)
  buf = buf and buf ~= 0 and buf or api.nvim_get_current_buf()
  local state = states[buf]
  return {
    enabled = not not allowed(buf),
    pending = state and state.pending or false,
    reason = state and state.reason or nil,
    valid_lines = state and state.next or 0,
    scanned_lines = state and state.scanned_lines or 0,
    slices = state and state.slices or 0,
    work_ms = state and state.work_ms or 0,
    max_slice_ms = state and state.max_slice_ms or 0,
    brackets = state and state.brackets or 0,
  }
end

return M
