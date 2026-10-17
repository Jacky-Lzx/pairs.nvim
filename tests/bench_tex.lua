-- Prepared-tree decisions and the first time slice after a real edit are
-- measured separately. Fixture parsing and settling are outside the timers.
return function(h)
  local opts = {
    treesitter = true,
    tex_environments = { proof = "text" },
    multi_pairs = { ["$$"] = {}, ["\\("] = {}, ["\\["] = {} },
  }
  local function ready()
    vim.treesitter.get_parser(0, "latex"):parse(true)
  end
  local function decision(case)
    case.ft, case.opts, case.prepare = "tex", case.opts or opts, case.prepare or ready
    h.decision(case)
  end
  decision({ name = "tex-bracket-ready", key = "(", action = "pair" })
  decision({ name = "tex-inline-ready", line = "word \\", col = 6, key = "(", action = "pair" })
  decision({
    name = "tex-proof-ready",
    lines = { "\\begin{proof}", "word \\", "\\end{proof}" },
    row = 2,
    col = 6,
    key = "(",
    action = "pair",
  })
  decision({
    name = "tex-url-ready",
    line = "\\url{https://example.com/}",
    col = 24,
    key = "(",
    action = "pass",
  })
  decision({
    name = "tex-argument-2k",
    line = "\\textbf{" .. string.rep("x", 2000) .. "}",
    col = 2008,
    key = "(",
    action = "pair",
  })
  decision({
    name = "tex-raw-spans-300",
    line = "\\textbf{" .. string.rep("\\url{x}", 300) .. " }",
    col = 2109,
    key = "(",
    action = "pass",
  })
  local sizes = {}
  for _, count in ipairs({ 1000, math.min(10000, h.large_lines), h.large_lines }) do
    if not sizes[count] then
      sizes[count] = true
      local lines = { "\\begin{document}" }
      for _ = 1, count do
        lines[#lines + 1] = "Text with $x$ and \\textbf{value}."
      end
      lines[#lines + 1] = "\\end{document}"
      local middle = math.floor(count / 2)
      lines[middle] = "word \\"
      decision({
        name = "tex-ready-" .. count,
        lines = lines,
        row = middle,
        col = 6,
        key = "(",
        action = "pair",
      })
      local unfinished = vim.list_slice(lines, 1, #lines - 1)
      decision({
        name = "tex-unfinished-" .. count,
        lines = unfinished,
        row = middle,
        col = 6,
        key = "(",
        action = "pass",
      })
      local parser, range
      decision({
        name = "tex-after-edit-" .. count,
        lines = lines,
        row = middle,
        col = 6,
        key = "(",
        actions = { pair = true, pass = true },
        samples = math.min(h.samples, 30),
        prepare = function()
          parser = vim.treesitter.get_parser(0, "latex")
          parser:parse(true)
        end,
        before = function(i)
          local line = i % 2 == 0 and "word \\" or "word  \\"
          vim.api.nvim_buf_set_lines(0, middle - 1, middle, false, { line })
          vim.api.nvim_win_set_cursor(0, { middle, #line })
          range = { middle - 1, #line - 1, middle - 1, #line - 1 }
        end,
        after = function()
          assert(
            vim.wait(2000, function()
              return parser:is_valid(false, range)
            end, 1),
            "LaTeX parser did not settle in the requested range"
          )
        end,
      })
    end
  end
end
