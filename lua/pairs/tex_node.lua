-- TSNode:field() enumerates every child, even for an absent field. TeX
-- environments and command arguments can have thousands of direct children.
local M = {}

function M.field(node, name)
  -- Native field lookup is faster on small headers and creates no cursor
  -- iterator. Bound it by child count before using it on the input path.
  if node:child_count() <= 16 then
    return node:field(name)[1]
  end
  local visited = 0
  for child, field in node:iter_children() do
    visited = visited + 1
    if visited > 16 then
      return nil
    end
    if field == name then
      return child
    end
  end
end

function M.environment(node)
  local first, last = node:child(0), node:child(node:child_count() - 1)
  -- The LaTeX grammar places begin/end commands at the environment's edges.
  -- Recovery nodes may lack either edge; only inspect a bounded header then.
  return first and first:type() == "begin" and first or M.field(node, "begin"),
    last and last:type() == "end" and last or M.field(node, "end")
end

return M
