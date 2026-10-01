local M = { owned = {}, conflicts = {} }

local function keycode(key)
  return vim.api.nvim_replace_termcodes(key, true, true, true)
end

local function global_mapping(lhs)
  for _, mapping in ipairs(vim.api.nvim_get_keymap("i")) do
    if keycode(mapping.lhs) == keycode(lhs) then
      return mapping
    end
  end
end

function M.detach()
  for _, owned in ipairs(M.owned) do
    local current = global_mapping(owned.lhs)
    if current and current.rhs == owned.rhs then
      vim.keymap.del("i", owned.lhs)
    end
    local inner = global_mapping(owned.plug)
    if inner and inner.callback == owned.callback then
      vim.keymap.del("i", owned.plug)
    end
  end
  M.owned, M.conflicts = {}, {}
end

function M.attach(config, handler)
  if not config.mappings.enabled then
    return
  end
  local keys = {}
  local function register(rules)
    for open, rule in pairs(rules) do
      if rule ~= false then
        keys[open], keys[rule.close] = true, true
      end
    end
  end
  register(config.pairs)
  local function register_multi(rules)
    for open, rule in pairs(rules) do
      if rule ~= false then
        keys[open:sub(-1)], keys[rule.close:sub(-1)] = true, true
      end
    end
  end
  register_multi(config.multi_pairs)
  for ft in pairs(config.filetypes) do
    register(require("pairs.config").resolve(config, ft))
    register_multi(require("pairs.config").resolve_multi(config, ft))
  end
  if config.mappings.bs then
    keys["<BS>"] = true
  end
  if config.mappings.cr then
    keys["<CR>"] = true
  end
  for _, lhs in ipairs(vim.tbl_keys(keys)) do
    local bytes = { lhs:byte(1, #lhs) }
    local plug = "<Plug>(pairs.nvim-" .. table.concat(bytes, "-") .. ")"
    if global_mapping(lhs) or global_mapping(plug) then
      M.conflicts[#M.conflicts + 1] = lhs
    else
      local callback = function()
        return handler(lhs)
      end
      vim.keymap.set("i", plug, callback, {
        expr = true,
        replace_keycodes = false,
        silent = true,
        desc = "pairs.nvim deferred " .. lhs,
      })
      -- Expr mappings may be evaluated before preceding typed text is applied.
      -- Ignore flushes that text before the private expression is evaluated.
      local rhs = "<Ignore>" .. plug
      vim.keymap.set("i", lhs, rhs, { silent = true, desc = "pairs.nvim " .. lhs })
      M.owned[#M.owned + 1] = { lhs = lhs, plug = plug, rhs = rhs, callback = callback }
    end
  end
  table.sort(M.conflicts)
end

function M.render(result)
  if result.action == "pair" then
    return result.open .. result.close .. string.rep(keycode("<C-g>U<Left>"), #result.close)
  elseif result.action == "skip" then
    return string.rep(keycode("<C-g>U<Right>"), result.move or #result.close)
  elseif result.action == "delete" then
    return string.rep(keycode("<BS>"), #result.open) .. string.rep(keycode("<Del>"), #result.close)
  elseif result.action == "newline" then
    return require("pairs.newline").keys(result.indent_offset)
  end
end

M.keycode = keycode
return M
