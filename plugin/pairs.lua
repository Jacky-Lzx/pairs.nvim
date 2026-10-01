if vim.g.loaded_pairs_nvim then
  return
end
vim.g.loaded_pairs_nvim = true

vim.api.nvim_create_user_command("PairsToggle", function()
  require("pairs").toggle()
end, { desc = "Toggle pairs.nvim" })

vim.api.nvim_create_user_command("PairsInspect", function(args)
  local result = require("pairs").explain(args.args, { assume_insert = true })
  vim.notify(vim.inspect(result), vim.log.levels.INFO, { title = "pairs.nvim" })
end, {
  nargs = 1,
  desc = "Explain insertion before the cursor without editing text",
  complete = function()
    return { '"', "'", "(", ")", "[", "]", "{", "}", "<BS>" }
  end,
})
