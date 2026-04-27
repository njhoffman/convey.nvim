local M = {}

M.name = "selections"
M.prefix = "󰒅"

local ns = vim.api.nvim_create_namespace("convey_selections")
local stored = {}
local last_hash = nil
local autocmd_id = nil

local get_hash = function(pos)
  return vim.fn.sha256(vim.fn.json_encode(pos))
end

local get_select_pos = function(_buf)
  local get_pos_with_len = function(mark)
    local pos = vim.fn.getpos(mark)
    local lines = vim.api.nvim_buf_get_lines(pos[1], pos[2] - 1, pos[2], false)
    local line_length = lines[1] and #lines[1] or 0
    table.insert(pos, line_length)
    return pos
  end
  local from = get_pos_with_len("'<")
  local to = get_pos_with_len("'>")
  return { from = from, to = to }, get_hash({ from, to })
end

local create_mark = function(pos, bufnr)
  local end_line = vim.api.nvim_buf_get_lines(bufnr, pos.to[2] - 1, pos.to[2], false)
  local end_line_length = end_line[1] and #end_line[1] or 0
  local end_col = pos.to[3] == vim.v.maxcol and end_line_length or pos.to[3]

  local ok, mark = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, pos.from[2] - 1, pos.from[3], {
    end_row = pos.to[2] - 1,
    end_col = end_col,
  })
  if ok then
    return mark
  end
  return nil
end

M.init = function(augroup)
  autocmd_id = vim.api.nvim_create_autocmd("ModeChanged", {
    group = augroup,
    pattern = "*:*",
    desc = "Convey: track visual selections",
    callback = function(ev)
      local from = unpack(vim.split(ev.match, ":"))
      if not vim.tbl_contains({ "v", "V", "\22" }, from) then
        return
      end

      local bufnr = ev.buf
      local pos, hash = get_select_pos(bufnr)

      -- Skip duplicates and zero-length selections
      if hash == last_hash then
        return
      end
      if vim.fn.join(pos.from, " ") == vim.fn.join(pos.to, " ") then
        return
      end

      local mark = create_mark(pos, bufnr)
      if not mark then
        return
      end

      table.insert(stored, {
        bufnr = bufnr,
        mark = mark,
        lnum = pos.from[2],
        col = pos.from[3],
        time = os.time(),
      })
      last_hash = hash
      require("convey.log").tracked(M.name, "selection", {
        bufnr = bufnr,
        lnum = pos.from[2],
        col = pos.from[3],
        end_lnum = pos.to[2],
        end_col = pos.to[3],
      })
    end,
  })
end

M.destroy = function()
  if autocmd_id then
    pcall(vim.api.nvim_del_autocmd, autocmd_id)
    autocmd_id = nil
  end
  stored = {}
  last_hash = nil
  require("convey.log").reset()
end

--- @param bufnr number
--- @return table[]
M.get_positions = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local positions = {}

  for _, item in ipairs(stored) do
    if item.bufnr == bufnr and vim.api.nvim_buf_is_valid(item.bufnr) then
      -- Read current position from extmark (survives edits)
      local ok, mark =
        pcall(vim.api.nvim_buf_get_extmark_by_id, item.bufnr, ns, item.mark, { details = true })
      local lnum = (ok and mark and #mark > 0) and (mark[1] + 1) or item.lnum
      local col = (ok and mark and #mark > 0) and mark[2] or item.col
      local details = (ok and mark and mark[3]) or {}
      local end_lnum = details.end_row and (details.end_row + 1) or nil
      local end_col = details.end_col or nil

      table.insert(positions, {
        lnum = lnum,
        col = col,
        end_lnum = end_lnum,
        end_col = end_col,
        bufnr = item.bufnr,
        timestamp = item.time,
        source = "selections",
      })
    end
  end

  return positions
end

return M
