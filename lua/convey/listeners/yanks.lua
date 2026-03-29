local M = {}

M.name = "yanks"
M.prefix = ""

local stored = {}
local autocmd_id = nil

M.init = function(augroup)
  autocmd_id = vim.api.nvim_create_autocmd("TextYankPost", {
    group = augroup,
    desc = "Convey: track yank positions",
    callback = function(ev)
      local event = vim.v.event
      if event.operator ~= "y" then
        return
      end

      local bufnr = ev.buf
      local from = vim.fn.getpos("'[")
      local to = vim.fn.getpos("']")

      table.insert(stored, {
        bufnr = bufnr,
        lnum = from[2],
        col = from[3] - 1,
        end_lnum = to[2],
        end_col = to[3] - 1,
        time = os.time(),
      })
      require("convey.config")
        .log()
        .trace("[convey] yanks: tracked yank at " .. from[2] .. ":" .. from[3])
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
        end_lnum = item.end_lnum,
        end_col = item.end_col,
        bufnr = item.bufnr,
        timestamp = item.time,
        source = "yanks",
      })
    end
  end

  return positions
end

return M
