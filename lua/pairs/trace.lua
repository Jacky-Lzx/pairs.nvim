-- Opt-in diagnostics. No reads, copies, timers or writes occur on the disabled path.
local M = { active = false }
local capacity, text_limit = 100, 4096
local ring, size, slot, sequence, dropped, last_error = {}, 0, 1, 0, 0, nil

local function bounded(text, limit)
  if #text <= limit then
    return text, false
  end
  local finish = limit
  -- Do not split a UTF-8 codepoint before encoding the result as JSON.
  while finish > 0 and text:byte(finish + 1) >= 128 and text:byte(finish + 1) < 192 do
    finish = finish - 1
  end
  return text:sub(1, finish), true
end

local function local_line(line, col)
  local first = #line > text_limit
      and math.max(0, math.min(col - math.floor(text_limit / 2), #line - text_limit))
    or 0
  while first > 0 and line:byte(first + 1) >= 128 and line:byte(first + 1) < 192 do
    first = first + 1
  end
  local text = bounded(line:sub(first + 1, first + text_limit + 4), text_limit)
  return {
    line = text,
    start_col = first,
    total_bytes = #line,
    truncated_left = first > 0,
    truncated_right = first + #text < #line,
  }
end

local function rules_copy(rules, single)
  local copy = {}
  for open, rule in pairs(rules or {}) do
    if rule == false then
      copy[open] = false
    else
      -- Copy only the validated policy, never arbitrary user rule metadata.
      copy[open] = {
        close = rule.close,
        open = rule.open,
        skip = rule.skip,
        delete = rule.delete,
        newline = rule.newline,
      }
      if single then
        copy[open].space = rule.space
        copy[open].skip_space = rule.skip_space
        copy[open].wrap = rule.wrap
      end
    end
  end
  return copy
end

function M.start()
  M.active, last_error = true, nil
end

function M.stop()
  M.active = false
end

function M.clear()
  ring, size, slot, sequence, dropped, last_error = {}, 0, 1, 0, 0, nil
end

function M.status()
  return {
    active = M.active,
    count = size,
    capacity = capacity,
    dropped = dropped,
    error = last_error,
  }
end

function M.entries()
  local entries = {}
  local first = size == capacity and slot or 1
  for i = 0, size - 1 do
    entries[#entries + 1] = vim.deepcopy(ring[(first + i - 1) % capacity + 1])
  end
  return entries
end

-- Internal hook runs after capture/decision and before the returned keys edit text.
function M.record(key, result, ctx, config)
  if not M.active then
    return
  end
  local cursor = ctx and { ctx.row, ctx.col } or vim.api.nvim_win_get_cursor(0)
  if not ctx then
    cursor[1] = cursor[1] - 1
  end
  local line = ctx and ctx.line or vim.api.nvim_get_current_line()
  local ft = ctx and ctx.filetype or vim.bo.filetype
  local captured_ft, clipped_ft = bounded(ft, 128)
  local input = local_line(line, cursor[2])
  local decision, shortened = {}, false
  for _, name in ipairs({
    "action",
    "reason",
    "open",
    "close",
    "move",
    "indent_offset",
    "insert_close",
    "remove_close",
    "prefix",
    "error",
    "trim_space",
  }) do
    local value = result[name]
    if type(value) == "string" then
      local clipped
      value, clipped = bounded(value, 1024)
      shortened = shortened or clipped
    end
    decision[name] = value
  end
  decision.truncated = shortened
  local source = not ctx
      and (result.reason == "not_initialized" and "uninitialized" or "capture_error")
    or not ctx.enabled and "disabled"
    or not config.treesitter and "lexer"
    or ctx.syntax and "treesitter"
    or "lexer_fallback"
  local limitations = {}
  if clipped_ft then
    limitations[#limitations + 1] = "Filetype was clipped; setup options for it are omitted."
  end
  if input.truncated_left or input.truncated_right then
    limitations[#limitations + 1] = "Current line was clipped; original byte cursor is retained."
  end
  if config and config.treesitter then
    limitations[#limitations + 1] =
      "Surrounding lines, parser trees and parse scheduling are not captured."
  end
  if not ctx then
    limitations[#limitations + 1] = result.reason == "not_initialized"
        and "Plugin is not initialized; effective rules are unavailable."
      or "Context capture failed; effective rules are unavailable."
  elseif not ctx.enabled then
    limitations[#limitations + 1] =
      "Runtime disable/mode/paste/macro state must be recreated separately."
  end
  if config and type(config.enabled) == "function" then
    limitations[#limitations + 1] =
      "The enabled callback is not serialized; only its observed effect is captured."
  end
  sequence = sequence + 1
  local entry = {
    id = sequence,
    key = bounded(key, 128),
    buffer = ctx and ctx.buf or vim.api.nvim_get_current_buf(),
    cursor = { row = cursor[1], col = cursor[2] }, -- zero-based row and byte column
    mode = vim.fn.mode(),
    filetype = captured_ft,
    input = input,
    decision = decision, -- observed behavior, not a regression's expected behavior
    syntax = {
      source = source,
      classification = ctx and ctx.syntax or "unavailable",
      reason = ctx and ctx.syntax_reason or nil,
      literal_string = ctx and ctx.literal_string or false,
      string_quote = ctx and ctx.string_quote or nil,
      string_close = ctx and ctx.string_close or nil,
    },
    limitations = limitations,
  }
  if ctx and not clipped_ft then
    entry.options = {
      enabled = ctx.enabled,
      treesitter = config.treesitter,
      max_scan_bytes = config.max_scan_bytes,
      filetypes = {
        [ft] = { pairs = rules_copy(ctx.rules, true), multi_pairs = rules_copy(ctx.multi_rules) },
      },
    }
  end
  ring[slot] = entry
  slot = slot % capacity + 1
  if size < capacity then
    size = size + 1
  else
    dropped = dropped + 1
  end
end

function M.fail(err)
  M.active = false
  last_error = bounded(tostring(err), 1024)
end

function M.export(path, overwrite)
  assert(type(path) == "string" and path ~= "", "pairs: export requires a file path")
  assert(overwrite == nil or type(overwrite) == "boolean", "pairs: overwrite must be boolean")
  local data = {
    schema = 1,
    plugin = "pairs.nvim",
    neovim = vim.version(),
    cursor_convention = "zero-based row and byte column, before the key is applied",
    limits = { records = capacity, line_bytes = text_limit },
    status = M.status(),
    records = M.entries(),
    note = "Observed decisions are not expected assertions. Confirm intended behavior before adding regression cases.",
    reproduction_scope = "Local input and delimiter policy only; surrounding lines, language declarations, indentation callbacks, parser trees, completion/snippets and mapping ownership are not serialized.",
  }
  local json = vim.json.encode(data) .. "\n"
  local fd, err = vim.uv.fs_open(path, overwrite and "w" or "wx", 384)
  assert(fd, "pairs: cannot export trace: " .. tostring(err))
  local ok, write_error = pcall(function()
    local offset = 0
    while offset < #json do
      local written, failure = vim.uv.fs_write(fd, json:sub(offset + 1), offset)
      assert(written and written > 0, "pairs: cannot write trace: " .. tostring(failure))
      offset = offset + written
    end
  end)
  local closed, close_error = vim.uv.fs_close(fd)
  if not ok or not closed then
    if not overwrite then
      vim.uv.fs_unlink(path)
    end
    error(not ok and write_error or "pairs: cannot close trace: " .. tostring(close_error))
  end
  return path
end

function M.show()
  local status = M.status()
  local lines = {
    "pairs.nvim trace: " .. (status.active and "recording" or "stopped"),
    string.format("%d/%d records; %d older records discarded", size, capacity, dropped),
    "Positions below are 1-based rows and byte columns. JSON positions are 0-based.",
  }
  if last_error then
    lines[#lines + 1] = "Trace error: " .. vim.json.encode(last_error)
  end
  for _, entry in ipairs(M.entries()) do
    local col = entry.cursor.col - entry.input.start_col
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format(
      "#%d buffer=%d ft=%s %d:%d key=%s -> %s (%s)",
      entry.id,
      entry.buffer,
      vim.json.encode(entry.filetype),
      entry.cursor.row + 1,
      entry.cursor.col + 1,
      vim.json.encode(entry.key),
      entry.decision.action,
      entry.decision.reason
    )
    lines[#lines + 1] = "  "
      .. vim.json.encode(entry.input.line:sub(1, col))
      .. " | "
      .. vim.json.encode(entry.input.line:sub(col + 1))
    lines[#lines + 1] = "  syntax: "
      .. entry.syntax.source
      .. "/"
      .. entry.syntax.classification
      .. (entry.syntax.reason and " (" .. entry.syntax.reason .. ")" or "")
    if entry.input.truncated_left or entry.input.truncated_right then
      lines[#lines + 1] = "  line clipped; first byte column: " .. (entry.input.start_col + 1)
    end
    if entry.decision.error then
      lines[#lines + 1] = "  error: " .. vim.json.encode(entry.decision.error)
    end
    for _, limitation in ipairs(entry.limitations) do
      lines[#lines + 1] = "  " .. limitation
    end
  end
  vim.cmd("botright new")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "nofile", "wipe", false
  vim.bo[buf].filetype = "pairs-trace"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  return buf
end

function M.command(args, bang)
  local action = args[1]
  if action == "export" then
    assert(#args == 2, "pairs: usage: PairsTrace[!] export {file}")
    M.export(args[2], bang)
    vim.notify("Trace exported to " .. args[2], vim.log.levels.INFO, { title = "pairs.nvim" })
    return
  end
  assert(#args == 1 and not bang, "pairs: use ! only with PairsTrace export {file}")
  if action == "start" then
    M.start()
  elseif action == "stop" then
    M.stop()
  elseif action == "clear" then
    M.clear()
  elseif action == "show" then
    return M.show()
  else
    error("pairs: expected start, stop, show, clear, or export {file}")
  end
end

function M.complete(lead, line, pos)
  local prefix = line:sub(1, pos)
  if prefix:match("PairsTrace!?%s+export%s") then
    return vim.fn.getcompletion(lead, "file")
  end
  if prefix:match("PairsTrace!?%s+%S+%s") then
    return {}
  end
  local matches = {}
  for _, action in ipairs({ "start", "stop", "show", "clear", "export" }) do
    if action:sub(1, #lead) == lead then
      matches[#matches + 1] = action
    end
  end
  return matches
end

return M
