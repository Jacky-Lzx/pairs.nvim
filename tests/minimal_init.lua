vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.swapfile = false
vim.o.shadafile = "NONE"
vim.o.backspace = "indent,eol,start"
vim.o.expandtab = true
vim.o.shiftwidth = 2
vim.o.tabstop = 4
vim.o.showmode = false
vim.o.report = 9999

-- Optional pinned parser fixtures, including LaTeX, Python, Rust and JS/TS.
if vim.env.PAIRS_TEST_PARSER_ROOT then
  vim.opt.runtimepath:append(vim.env.PAIRS_TEST_PARSER_ROOT)
end
