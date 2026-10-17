local M = {}
-- Only setup-owned metadata is shared. Buffer overrides are never cached.
local prepared = setmetatable({}, { __mode = "k" })

local function prepare_tex(environments)
  local custom_literal = false
  for name, mode in pairs(environments) do
    if mode == "literal" and require("pairs.tex_env").protected[name] ~= "literal" then
      custom_literal = true
      break
    end
  end
  return { environments = environments, custom_literal = custom_literal }
end

local function prepare(rules, multi_rules)
  local openers, closers, quotes = {}, {}, { ['"'] = true, ["'"] = true }
  local has_space = false
  for open, rule in pairs(rules) do
    has_space = has_space or (rule ~= false and rule.space)
    if rule ~= false and open ~= rule.close then
      openers[open], closers[rule.close] = rule.close, open
    elseif rule ~= false then
      quotes[open] = true
    end
  end
  local tick_quotes = vim.tbl_extend("force", quotes, { ["`"] = true })
  return {
    rules = rules,
    multi_rules = multi_rules,
    openers = openers,
    closers = closers,
    quotes = quotes,
    tick_quotes = tick_quotes,
    has_space = has_space,
  }
end

M.defaults = {
  enabled = true,
  mappings = { enabled = true, bs = true, cr = true, space = true, fast_wrap = false },
  max_scan_bytes = 4096,
  treesitter = false,
  surround = require("pairs.surround").defaults,
  rainbow = {
    enabled = true,
    debounce_ms = 20,
    budget_ms = 2,
    max_lines = 100000,
    max_bytes = 2 * 1024 * 1024,
    max_line_bytes = 10000,
    max_depth = 256,
    max_brackets = 100000,
    max_visible_brackets = 2000,
    priority = 110,
    highlights = {
      "PairsRainbowRed",
      "PairsRainbowYellow",
      "PairsRainbowBlue",
      "PairsRainbowOrange",
      "PairsRainbowGreen",
      "PairsRainbowViolet",
      "PairsRainbowCyan",
    },
  },
  disabled_filetypes = { "TelescopePrompt", "snacks_picker_input" },
  multi_pairs = {},
  tex_environments = vim.deepcopy(require("pairs.tex_env").defaults),
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
      for _, key in ipairs({ "open", "skip", "delete", "newline", "space", "skip_space", "wrap" }) do
        if rule[key] == nil then
          if key == "wrap" then
            rule[key] = ({ ["("] = ")", ["["] = "]", ["{"] = "}" })[open] == rule.close
          else
            rule[key] = key ~= "space"
              and key ~= "skip_space"
              and (key ~= "newline" or open ~= rule.close)
          end
        end
        assert(type(rule[key]) == "boolean", "pairs: rule." .. key .. " must be boolean")
      end
      assert(
        not rule.space or ({ ["("] = ")", ["["] = "]", ["{"] = "}" })[open] == rule.close,
        "pairs: space padding supports (), [] and {} only"
      )
      assert(
        not rule.skip_space or ({ ["("] = ")", ["["] = "]", ["{"] = "}" })[open] == rule.close,
        "pairs: skip_space supports (), [] and {} only"
      )
      assert(
        not rule.wrap or ({ ["("] = ")", ["["] = "]", ["{"] = "}" })[open] == rule.close,
        "pairs: wrap supports (), [] and {} only"
      )
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
      open == '"""'
        or open == "'''"
        or open == "${"
        or open == "```"
        or open == "~~~"
        or open == "$$"
        or open == "\\("
        or open == "\\[",
      "pairs: unsupported multi-character delimiter"
    )
    if rule ~= false then
      local fence = open == "```" or open == "~~~"
      local close = ({ ["${"] = "}", ["\\("] = "\\)", ["\\["] = "\\]" })[open] or open
      if type(rule) == "table" and rule.close == nil then
        rule.close = close
      end
      assert(
        type(rule) == "table" and rule.close == close,
        "pairs: multi-character closer does not match its rule"
      )
      for _, key in ipairs({ "open", "skip", "delete", "newline", "space" }) do
        if rule[key] == nil then
          rule[key] = key ~= "space"
            and not (fence and key == "delete")
            and not (open == "\\(" and key == "newline")
        end
        assert(type(rule[key]) == "boolean", "pairs: multi rule." .. key .. " must be boolean")
      end
      assert(not fence or not rule.delete, "pairs: Markdown fence deletion is not supported")
      assert(not fence or not rule.space, "pairs: Markdown fence space padding is not supported")
    end
  end
end

local function merge_rules(base, overrides)
  local rules = vim.tbl_deep_extend("force", vim.deepcopy(base), overrides or {})
  for open, rule in pairs(overrides or {}) do
    -- Changing a standard closer must not make legacy custom rules inherit a
    -- newly introduced capability they cannot support. Explicit flags validate.
    if
      type(rule) == "table"
      and rule.close
      and rule.wrap == nil
      and ({ ["("] = ")", ["["] = "]", ["{"] = "}" })[open] ~= rule.close
    then
      rules[open].wrap = false
    end
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
  require("pairs.rainbow").validate(config.rainbow)
  require("pairs.surround").validate(config.surround)
  assert(type(config.mappings) == "table", "pairs: mappings must be a table")
  for _, key in ipairs({ "enabled", "bs", "cr", "space" }) do
    assert(type(config.mappings[key]) == "boolean", "pairs: mappings." .. key .. " must be boolean")
  end
  local wrap_key = config.mappings.fast_wrap
  assert(
    wrap_key == false or (type(wrap_key) == "string" and wrap_key:match("^<[^<>]+>$")),
    "pairs: mappings.fast_wrap must be false or a single non-text key such as <M-e>"
  )
  if wrap_key then
    local code = vim.api.nvim_replace_termcodes(wrap_key, true, true, true)
    local canonical = vim.fn.keytrans(code)
    assert(
      code ~= wrap_key
        and canonical:match("^<[^<>]+>$")
        and not vim.tbl_contains({
          "<BS>",
          "<C-H>",
          "<CR>",
          "<Tab>",
          "<Esc>",
          "<Ignore>",
          "<Plug>",
          "<Nop>",
          "<Cmd>",
          "<ScriptCmd>",
        }, canonical),
      "pairs: fast_wrap key must be recognized and cannot replace text, BS, CR, Tab or Esc"
    )
  end
  assert(type(config.disabled_filetypes) == "table", "pairs: disabled_filetypes must be a list")
  for _, ft in ipairs(config.disabled_filetypes) do
    assert(type(ft) == "string", "pairs: disabled_filetypes entries must be strings")
  end
  validate_pairs(config.pairs)
  validate_multi(config.multi_pairs)
  require("pairs.tex_env").validate(config.tex_environments)
  assert(type(config.filetypes) == "table", "pairs: filetypes must be a table")
  local metadata = { default = prepare(config.pairs, config.multi_pairs), filetypes = {} }
  metadata.default.tex = prepare_tex(config.tex_environments)
  for ft, overrides in pairs(config.filetypes) do
    assert(type(ft) == "string" and type(overrides) == "table", "pairs: invalid filetype override")
    if overrides.surround ~= nil then
      require("pairs.surround").validate(
        vim.tbl_deep_extend("force", vim.deepcopy(config.surround), overrides.surround)
      )
    end
    if overrides.tex_environments ~= nil then
      require("pairs.tex_env").validate(overrides.tex_environments)
    end
    local rules = merge_rules(config.pairs, overrides.pairs)
    validate_pairs(rules)
    local multi =
      vim.tbl_deep_extend("force", vim.deepcopy(config.multi_pairs), overrides.multi_pairs or {})
    validate_multi(multi)
    local environments = vim.tbl_deep_extend(
      "force",
      vim.deepcopy(config.tex_environments),
      overrides.tex_environments or {}
    )
    require("pairs.tex_env").validate(environments)
    if overrides.enabled ~= nil then
      assert(type(overrides.enabled) == "boolean", "pairs: filetype enabled must be boolean")
    end
    metadata.filetypes[ft] = prepare(rules, multi)
    metadata.filetypes[ft].tex = prepare_tex(environments)
  end
  prepared[config] = metadata
  return config
end

-- Internal capture path returns read-only setup metadata. Public resolve helpers
-- below retain independent tables; live buffer rules still merge and validate.
function M.capture(config, ft, buffer)
  local metadata = assert(prepared[config], "pairs: configuration was not built")
  local base = metadata.filetypes[ft] or metadata.default
  if not buffer then
    return base
  end
  local rules = merge_rules(base.rules, buffer)
  validate_pairs(rules)
  return prepare(rules, base.multi_rules)
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

function M.resolve_tex(config, ft, buffer)
  if buffer ~= nil then
    require("pairs.tex_env").validate(buffer)
  end
  local environments = vim.tbl_deep_extend(
    "force",
    vim.deepcopy(config.tex_environments),
    (config.filetypes[ft] or {}).tex_environments or {},
    buffer or {}
  )
  require("pairs.tex_env").validate(environments)
  return environments
end

function M.capture_tex(config, ft, buffer)
  if buffer ~= nil then
    return prepare_tex(M.resolve_tex(config, ft, buffer))
  end
  local metadata = assert(prepared[config], "pairs: configuration was not built")
  return (metadata.filetypes[ft] or metadata.default).tex
end

return M
