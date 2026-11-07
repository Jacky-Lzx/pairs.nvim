local M = {}

function M.check()
  vim.health.start("pairs.nvim")
  if vim.fn.has("nvim-0.11") == 0 then
    vim.health.error("Neovim 0.11+ is required", { "Upgrade Neovim" })
    return
  end
  local issues = {}
  local function problem(level, message, advice)
    issues[#issues + 1] = { level = level, message = message, advice = advice }
  end
  local plugin = package.loaded.pairs
  local status = plugin and plugin.status()
  if not status or not status.initialized then
    vim.health.info("Not initialized; pairing checks deferred until activation.")
    return
  end
  if not status.enabled then
    vim.health.info("Pairing is disabled; mapping checks skipped. Details: :PairsInfo")
    return
  end
  local conflicts = vim.list_extend(vim.deepcopy(status.conflicts), status.surround.conflicts or {})
  if #conflicts > 0 then
    table.sort(conflicts)
    problem(
      "warn",
      "Mappings owned elsewhere: "
        .. table.concat(conflicts, ", ")
        .. "; pairing actions on these keys are unavailable.",
      { "Compose the mappings with their current owner or configure different keys" }
    )
  end

  table.sort(issues, function(a, b)
    if a.level ~= b.level then
      return a.level == "error"
    end
    return a.message < b.message
  end)
  for _, issue in ipairs(issues) do
    vim.health[issue.level](issue.message, issue.advice)
  end
  if #issues == 0 then
    vim.health.ok("Pairing handlers and configured mappings are available.")
  end
  vim.health.info("Details: :PairsInfo")
end

return M
