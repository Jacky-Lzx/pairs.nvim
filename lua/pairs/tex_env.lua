-- Environment declarations are metadata; they never parse or edit a buffer.
local M = { defaults = {}, protected = {} }

for _, name in ipairs({
  "document",
  "center",
  "flushleft",
  "flushright",
  "quote",
  "quotation",
  "itemize",
  "enumerate",
  "description",
  "figure",
  "figure*",
  "table",
  "table*",
  "minipage",
}) do
  M.defaults[name] = "text"
end
for _, name in ipairs({
  "math",
  "displaymath",
  "displaymath*",
  "equation",
  "equation*",
  "multline",
  "multline*",
  "eqnarray",
  "eqnarray*",
  "align",
  "align*",
  "aligned",
  "aligned*",
  "array",
  "array*",
  "split",
  "split*",
  "alignat",
  "alignat*",
  "alignedat",
  "alignedat*",
  "gather",
  "gather*",
  "gathered",
  "gathered*",
  "flalign",
  "flalign*",
}) do
  M.defaults[name], M.protected[name] = "math", "math"
end
for _, name in ipairs({
  "comment",
  "verbatim",
  "lstlisting",
  "minted",
  "asy",
  "asydef",
  "pycode",
  "luacode",
  "luacode*",
  "sagesilent",
  "sageblock",
}) do
  M.defaults[name], M.protected[name] = "literal", "literal"
end

function M.validate(environments)
  assert(type(environments) == "table", "pairs: tex_environments must be a table")
  for name, mode in pairs(environments) do
    assert(
      type(name) == "string" and #name <= 62 and name:match("^[%w_.:%*%-]+$"),
      "pairs: invalid TeX environment name (1-62 ASCII name characters required)"
    )
    assert(
      mode == false or mode == "text" or mode == "math" or mode == "literal",
      "pairs: TeX environment mode must be text, math, literal or false"
    )
    local protected = M.protected[name]
    assert(
      not protected or mode == protected or mode == "literal",
      "pairs: cannot weaken built-in TeX environment protection: " .. name
    )
  end
end

return M
