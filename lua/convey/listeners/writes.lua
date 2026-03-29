local M = {}

M.name = "writes"
M.prefix = ""

local stored = {}
local autocmd_id = nil

M.init = function(augroup)
  autocmd_id = vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    desc = "Convey: track cursor position on file write",
    callback = function(ev)
      local bufnr = ev.buf
      local pos = vim.api.nvim_win_get_cursor(0)

      table.insert(stored, {
        bufnr = bufnr,
        lnum = pos[1],
        col = pos[2],
        time = os.time(),
      })
      require("convey.config")
        .log()
        .trace("[convey] writes: tracked write at " .. pos[1] .. ":" .. pos[2])
    end,
  })
end

M.destroy = function()
  if autocmd_id then
    pcall(vim.api.nvim_del_autocmd, autocmd_id)
    autocmd_id = nil
  end
  stored = {}
end

--- @param bufnr number
--- @return table[]
M.get_positions = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local positions = {}

  for _, item in ipairs(stored) do
    if item.bufnr == bufnr then
      table.insert(positions, {
        lnum = item.lnum,
        col = item.col,
        bufnr = item.bufnr,
        timestamp = item.time,
        source = "writes",
      })
    end
  end

  return positions
end

return M
