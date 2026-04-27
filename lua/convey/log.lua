local utils = require("convey.utils")

local M = {}

local home = vim.fn.expand("$HOME")
local nvim_cfg = home .. "/.config/nvim"

local last_path = nil
local warned_unmapped = {}

local format_coords = function(pos)
  local start = pos.lnum .. ":" .. pos.col
  if pos.end_lnum and pos.end_col then
    local end_col_str = pos.end_col == vim.v.maxcol and "EOL" or tostring(pos.end_col)
    return start .. " - " .. pos.end_lnum .. ":" .. end_col_str
  end
  return start
end

local format_range = function(pos)
  if not pos.end_lnum or not pos.end_col then
    return ""
  end
  local n_lines, n_chars = utils.range_size(pos.bufnr, pos.lnum, pos.col, pos.end_lnum, pos.end_col)
  if not n_lines then
    return ""
  end
  if not n_chars then
    return " (" .. n_lines .. "L)"
  end
  return " (" .. n_lines .. "L " .. n_chars .. "c)"
end

local resolve_provider_label = function(listener_name)
  local config = require("convey.config")
  local providers = config.get_providers_for_listener(listener_name)
  if #providers == 0 then
    if not warned_unmapped[listener_name] then
      warned_unmapped[listener_name] = true
      config
        .log()
        .warn("[convey] listener '" .. listener_name .. "' has no provider; logging under listener name")
    end
    return listener_name
  end
  return table.concat(providers, ",")
end

--- Emit a "tracked <event>" trace log line in the convey format.
--- pos uses getpos conventions: 1-indexed lnum and col (inclusive).
--- end_col may equal vim.v.maxcol for linewise V-mode.
--- @param listener_name string
--- @param event_word string e.g. "yank", "paste", "selection", "write"
--- @param pos table { bufnr, lnum, col, end_lnum?, end_col? }
M.tracked = function(listener_name, event_word, pos)
  local provider_label = resolve_provider_label(listener_name)
  local coords = format_coords(pos)
  local range = format_range(pos)

  local path_block = ""
  local path = utils.format_buf_path(pos.bufnr, home, nvim_cfg)
  if path ~= "" and path ~= last_path then
    path_block = " '" .. path .. "'"
    last_path = path
  end

  local msg = "[convey] "
    .. provider_label
    .. ": tracked "
    .. event_word
    .. " at "
    .. coords
    .. range
    .. path_block

  require("convey.config").log().trace(msg)
end

--- Reset cross-listener state. Call from listener destroy() to avoid stale path.
M.reset = function()
  last_path = nil
end

return M
