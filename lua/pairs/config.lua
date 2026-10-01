local M = {}

M.defaults = {
  enabled = true,
  mappings = { enabled = true, bs = true, cr = true },
  max_scan_bytes = 4096,
  treesitter = false,
  disabled_filetypes = { "TelescopePrompt", "snacks_picker_input" },
  multi_pairs = {},
  pairs = {
    ["("] = { close = ")", open = true, skip = true, delete = true, newline = true },
    ["["] = { close = "]", open = true, skip = true, delete = true, newline = true },
    ["{"] = { close = "}", open = true, skip = true, delete = true, newline = true },
    ['"'] = { close = '"', open = true, skip = true, delete = true, newline = false },
    ["'"] = { close = "'", open = true, skip = true, delete = true, newline = false },
  },
  filetypes = {
    text = { pairs = { ["'"] = { open = false } } },
    markdown = { pairs = { ["'"] = { open = false } } },
    rust = { pairs = { ["'"] = { open = false } } },
  },
}

local function validate_pairs(rules)
  assert(type(rules) == "table", "pairs: pairs must be a table")
  local closers = {}
  for open, rule in pairs(rules) do
    assert(
      type(open) == "string" and #open == 1 and open:byte() >= 32 and open:byte() < 127,
      "pairs: opening delimiters must be single printable ASCII characters"
    )
    if rule ~= false then
      assert(type(rule) == "table", "pairs: a rule must be a table or false")
      assert(
        type(rule.close) == "string"
          and #rule.close == 1
          and rule.close:byte() >= 32
          and rule.close:byte() < 127,
        "pairs: closing delimiters must be single printable ASCII characters"
      )
      for _, key in ipairs({ "open", "skip", "delete", "newline" }) do
        if rule[key] == nil then
          rule[key] = key ~= "newline" or open ~= rule.close
        end
        assert(type(rule[key]) == "boolean", "pairs: rule." .. key .. " must be boolean")
      end
      assert(not closers[rule.close], "pairs: closing delimiters must be unique")
      closers[rule.close] = open
    end
  end
  for open, rule in pairs(rules) do
    if rule ~= false and open ~= rule.close then
      assert(not closers[open], "pairs: a delimiter cannot close one pair and open another")
    end
  end
end

local function validate_multi(rules)
  assert(type(rules) == "table", "pairs: multi_pairs must be a table")
  for open, rule in pairs(rules) do
    assert(
      open == '"""' or open == "'''" or open == "${" or open == "```" or open == "~~~",
      "pairs: unsupported multi-character delimiter"
    )
    if rule ~= false then
      local fence = open == "```" or open == "~~~"
      if type(rule) == "table" and rule.close == nil then
        rule.close = open == "${" and "}" or open
      end
      assert(
        type(rule) == "table" and rule.close == (open == "${" and "}" or open),
        "pairs: multi-character closer does not match its rule"
      )
      for _, key in ipairs({ "open", "skip", "delete", "newline" }) do
        if rule[key] == nil then
          rule[key] = not fence or key ~= "delete"
        end
        assert(type(rule[key]) == "boolean", "pairs: multi rule." .. key .. " must be boolean")
      end
      assert(not fence or not rule.delete, "pairs: Markdown fence deletion is not supported")
    end
  end
end

local function merge_rules(base, overrides)
  local rules = vim.tbl_deep_extend("force", vim.deepcopy(base), overrides or {})
  for open, rule in pairs(overrides or {}) do
    -- A partial policy cannot recreate a delimiter disabled by a previous
    -- layer. Re-enabling it requires an explicit complete rule with a closer.
    if base[open] == false and type(rule) == "table" and rule.close == nil then
      rules[open] = false
    end
  end
  return rules
end

function M.build(opts)
  assert(opts == nil or type(opts) == "table", "pairs: setup expects a table")
  local config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), vim.deepcopy(opts or {}))
  if opts and opts.disabled_filetypes then
    config.disabled_filetypes = vim.deepcopy(opts.disabled_filetypes)
  end
  assert(
    type(config.enabled) == "boolean" or type(config.enabled) == "function",
    "pairs: enabled must be boolean or function"
  )
  assert(
    type(config.max_scan_bytes) == "number"
      and config.max_scan_bytes >= 1
      and config.max_scan_bytes % 1 == 0,
    "pairs: max_scan_bytes must be a positive integer"
  )
  assert(type(config.treesitter) == "boolean", "pairs: treesitter must be boolean")
  assert(type(config.mappings) == "table", "pairs: mappings must be a table")
  for _, key in ipairs({ "enabled", "bs", "cr" }) do
    assert(type(config.mappings[key]) == "boolean", "pairs: mappings." .. key .. " must be boolean")
  end
  assert(type(config.disabled_filetypes) == "table", "pairs: disabled_filetypes must be a list")
  for _, ft in ipairs(config.disabled_filetypes) do
    assert(type(ft) == "string", "pairs: disabled_filetypes entries must be strings")
  end
  validate_pairs(config.pairs)
  validate_multi(config.multi_pairs)
  assert(type(config.filetypes) == "table", "pairs: filetypes must be a table")
  for ft, overrides in pairs(config.filetypes) do
    assert(type(ft) == "string" and type(overrides) == "table", "pairs: invalid filetype override")
    local rules = merge_rules(config.pairs, overrides.pairs)
    validate_pairs(rules)
    validate_multi(
      vim.tbl_deep_extend("force", vim.deepcopy(config.multi_pairs), overrides.multi_pairs or {})
    )
    if overrides.enabled ~= nil then
      assert(type(overrides.enabled) == "boolean", "pairs: filetype enabled must be boolean")
    end
  end
  return config
end

function M.resolve(config, ft, buffer)
  local rules = merge_rules(merge_rules(config.pairs, (config.filetypes[ft] or {}).pairs), buffer)
  validate_pairs(rules)
  return rules
end

function M.resolve_multi(config, ft, buffer)
  local rules = vim.tbl_deep_extend(
    "force",
    vim.deepcopy(config.multi_pairs),
    (config.filetypes[ft] or {}).multi_pairs or {},
    buffer or {}
  )
  validate_multi(rules)
  return rules
end

return M
