-- Explicit inspection does not configure or start the plugin.
require("pairs.user_command").create("PairsInfo", function()
  vim.notify(
    vim.inspect({
      pairing = require("pairs").status(),
      rainbow = require("pairs.rainbow").status(
        vim.bo.filetype == "checkhealth" and vim.fn.bufnr("#") > 0 and vim.fn.bufnr("#") or nil
      ),
    }),
    vim.log.levels.INFO,
    { title = "pairs.nvim", filetype = "lua" }
  )
end, { desc = "Inspect configuration and current runtime state" })
