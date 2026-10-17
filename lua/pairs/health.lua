local M = {}

function M.check()
  vim.health.start("pairs.nvim")
  if vim.fn.has("nvim-0.11") == 1 then
    vim.health.ok("Neovim 0.11 or newer")
  else
    vim.health.error("Neovim 0.11 or newer is required")
  end
  local status = require("pairs").status()
  if not status.initialized then
    vim.health.warn(
      "Not initialized; call require('pairs').setup() (or enter Insert mode if lazy-loaded)"
    )
    return
  end
  vim.health.ok("Initialized; " .. status.mappings .. " Insert-mode mappings registered")
  if not status.enabled then
    vim.health.info("Pairing is globally disabled")
  end
  if #status.conflicts > 0 then
    vim.health.warn("Existing mappings preserved: " .. table.concat(status.conflicts, ", "), {
      "Disable the previous pairs plugin or compose expr() with the existing mapping owner",
    })
  else
    vim.health.ok("No global mapping conflicts during setup")
  end
  if status.surround.mappings > 0 then
    vim.health.info("Surround mappings installed; see :help pairs-surround")
    if #status.surround.conflicts > 0 then
      vim.health.warn(
        "Existing surround mappings preserved: " .. table.concat(status.surround.conflicts, ", "),
        {
          "Disable mini.surround before enabling the same keys in pairs.nvim, or use custom mappings",
        }
      )
    end
  end
  vim.health.info("Enter expansion is configurable; Tab is not mapped. See :help pairs-enter")
end

return M
