if vim.g.loaded_pairs_nvim then
  return
end
vim.g.loaded_pairs_nvim = true

require("pairs.user_command").create("PairsRainbowToggle", function()
  require("pairs.rainbow").toggle()
end, { desc = "Toggle rainbow brackets in the current buffer" })

require("pairs.user_command").create("PairsToggle", function()
  require("pairs").toggle()
end, { desc = "Toggle pairs.nvim" })

require("pairs.user_command").create("PairsInspect", function(args)
  local result = require("pairs").explain(args.args, { assume_insert = true })
  vim.notify(vim.inspect(result), vim.log.levels.INFO, { title = "pairs.nvim", filetype = "lua" })
end, {
  nargs = 1,
  desc = "Explain insertion before the cursor without editing text",
  complete = function()
    return { '"', "'", "(", ")", "[", "]", "{", "}", "<BS>", "<CR>", "<Space>", "<FastWrap>" }
  end,
})

require("pairs.user_command").create("PairsTrace", function(args)
  local ok, err = pcall(require("pairs.trace").command, args.fargs, args.bang)
  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR, { title = "pairs.nvim", filetype = "text" })
  end
end, {
  nargs = "+",
  bang = true,
  desc = "Trace actual pairing decisions and export local reproduction data",
  complete = function(lead, line, pos)
    return require("pairs.trace").complete(lead, line, pos)
  end,
})
