local M = {}

M.name = "changes"
M.prefix = ""

--- No-op for snapshot listener (reads from vim on demand).
M.init = function(_augroup) end

M.destroy = function() end

--- Get change positions for the given buffer.
--- @param bufnr number Buffer number
--- @return table[] positions ConveyPosition[]
M.get_positions = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local changelist = vim.fn.getchangelist(bufnr)
  if not changelist or #changelist == 0 then
    return {}
  end

  local list = changelist[1] or {}
  local curr_idx = changelist[2] or 0
  local positions = {}

  for i, item in ipairs(list) do
    table.insert(positions, {
      lnum = item.lnum,
      col = item.col,
      bufnr = bufnr,
      timestamp = i,
      source = "changes",
      curr = (i == curr_idx + 1),
    })
  end

  return positions
end

return M
