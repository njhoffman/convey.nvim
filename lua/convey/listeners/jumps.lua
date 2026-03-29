local M = {}

M.name = "jumps"
M.prefix = "󰿅"

--- No-op for snapshot listener (reads from vim on demand).
M.init = function(_augroup) end

M.destroy = function() end

--- Get jump positions for the current window.
--- @param bufnr number Buffer number (used to filter jumps to current buffer)
--- @return table[] positions ConveyPosition[]
M.get_positions = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local jumplist = vim.fn.getjumplist()
  if not jumplist or #jumplist == 0 then
    return {}
  end

  local list = jumplist[1] or {}
  local curr_idx = jumplist[2] or 0
  local positions = {}

  for i, item in ipairs(list) do
    local jump_bufnr = item.bufnr or bufnr
    if vim.api.nvim_buf_is_valid(jump_bufnr) then
      table.insert(positions, {
        lnum = item.lnum,
        col = item.col,
        bufnr = jump_bufnr,
        timestamp = i,
        source = "jumps",
        curr = (i == curr_idx + 1),
      })
    end
  end

  return positions
end

return M
