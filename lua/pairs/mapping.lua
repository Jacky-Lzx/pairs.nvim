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
    if current and current.callback == owned.callback then
      vim.keymap.del("i", owned.lhs)
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
  for ft in pairs(config.filetypes) do
    register(require("pairs.config").resolve(config, ft))
  end
  if config.mappings.bs then
    keys["<BS>"] = true
  end
  for _, lhs in ipairs(vim.tbl_keys(keys)) do
    if global_mapping(lhs) then
      M.conflicts[#M.conflicts + 1] = lhs
    else
      local callback = function()
        return handler(lhs)
      end
      vim.keymap.set("i", lhs, callback, {
        expr = true,
        replace_keycodes = false,
        silent = true,
        desc = "pairs.nvim " .. lhs,
      })
      M.owned[#M.owned + 1] = { lhs = lhs, callback = callback }
    end
  end
  table.sort(M.conflicts)
end

function M.render(result)
  if result.action == "pair" then
    return result.open .. result.close .. keycode("<C-g>U<Left>")
  elseif result.action == "skip" then
    return keycode("<C-g>U<Right>")
  elseif result.action == "delete" then
    return keycode("<BS><Del>")
  end
end

M.keycode = keycode
return M
