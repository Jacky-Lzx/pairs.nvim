local M = {}

-- A fresh snapshot for one synchronous install/teardown operation. Never retain
-- it across operations: users and other plugins can replace mappings at any time.
function M.snapshot(mode)
  local result = {}
  for _, mapping in ipairs(vim.api.nvim_get_keymap(mode)) do
    local lhs = vim.api.nvim_replace_termcodes(mapping.lhs, true, true, true)
    result[lhs] = mapping
  end
  return result
end

return M
