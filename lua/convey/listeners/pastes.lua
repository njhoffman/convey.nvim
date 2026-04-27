local M = {}

M.name = "pastes"
M.prefix = ""

local stored = {}
local mapped_keys = {}

local function record_paste()
  local bufnr = vim.api.nvim_get_current_buf()
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
  require("convey.log").tracked(M.name, "paste", {
    bufnr = bufnr,
    lnum = from[2],
    col = from[3],
    end_lnum = to[2],
    end_col = to[3],
  })
end

-- TextYankPost does not fire for paste/put operations (only yank/delete/change).
-- Track pastes by overriding p/P keymaps and recording '[/'] marks after execution.
M.init = function(_augroup)
  local paste_keys = { "p", "P" }
  for _, key in ipairs(paste_keys) do
    for _, mode in ipairs({ "n", "x" }) do
      vim.keymap.set(mode, key, function()
        local count = vim.v.count
        local reg = vim.v.register
        local prefix = (reg ~= '"' and ('"' .. reg) or "") .. (count > 0 and tostring(count) or "")
        local cmd = prefix .. key
        local keys = vim.api.nvim_replace_termcodes(cmd, true, false, true)
        vim.api.nvim_feedkeys(keys, "nx", false)
        record_paste()
      end, { desc = "Convey: track paste position (" .. key .. ")" })
      table.insert(mapped_keys, { mode = mode, key = key })
    end
  end
end

M.destroy = function()
  for _, mapping in ipairs(mapped_keys) do
    pcall(vim.keymap.del, mapping.mode, mapping.key)
  end
  mapped_keys = {}
  stored = {}
  require("convey.log").reset()
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
        source = "pastes",
      })
    end
  end

  return positions
end

return M
