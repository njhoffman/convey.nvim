local utils = require("convey.utils")
local state = require("convey.state")
local config = require("convey.config")
local listeners = require("convey.listeners")

local default_highlights = {
  icon = "Special",
  number = "Number",
  string = "String",
}

--- Truncate a position list to a window around the current index.
--- @param positions table[] Position list
--- @param curr_idx number Current position index (1-based)
--- @param opts table Provider config with notify.lines_before/lines_after
--- @return table[] truncated
local truncate_positions = function(positions, curr_idx, opts)
  local view_config = config.get_view("notify") or {}
  local provider_notify = opts.views and opts.views.notify or {}
  local lines_before = provider_notify.lines_before or view_config.lines_before or 8
  local lines_after = provider_notify.lines_after or view_config.lines_after or 3
  local start = curr_idx - lines_before + 1
  local finish = curr_idx + lines_after
  start = start > 0 and start or 1
  finish = finish < #positions and finish or #positions
  local result = {}
  for i = start, finish do
    table.insert(result, positions[i])
  end
  return result
end

--- Display positions in a notify window.
--- @param provider_name string Name of the provider (used in header)
--- @param positions table[] Position list (most recent first)
--- @param curr_idx number Current position index (1-based)
--- @param opts table Provider config
local notify_handler = function(provider_name, positions, curr_idx, opts)
  local log = config.log()
  local notify_ok, notify = pcall(require, "notify")
  if not notify_ok then
    log.warn("[convey] notify plugin not available")
    return
  end

  -- Empty state: show "No {provider} to show."
  if #positions == 0 or curr_idx < 1 then
    local notif = notify({ "No " .. provider_name .. " to show." }, 3, {
      timeout = 3000,
      title = provider_name,
      replace = state.notify_id,
      on_close = function()
        state.notify_id = nil
        state.notify_wid = nil
      end,
      on_open = function(wid)
        state.notify_wid = wid
      end,
    })
    state.notify_id = notif.id
    return
  end

  local truncated = truncate_positions(positions, curr_idx, opts)

  local hls = default_highlights
  local rows = {}
  local use_range = utils.has_ranges(positions)
  local show_prefix = opts.listeners and #opts.listeners > 1
  local multi_buf = utils.is_multi_buffer(positions)

  for _, pos in ipairs(truncated) do
    local line_text = ""
    if pos.bufnr and vim.api.nvim_buf_is_valid(pos.bufnr) then
      local lines = vim.api.nvim_buf_get_lines(pos.bufnr, pos.lnum - 1, pos.lnum, false)
      if lines[1] then
        line_text = vim.trim(lines[1]:sub(pos.col + 1, pos.col + 30))
      end
    end

    local row = {
      { pos.curr and ">" or " ", hls.icon },
    }
    if show_prefix then
      table.insert(row, { listeners.get_prefix(pos.source) or "", hls.icon })
    end
    if multi_buf then
      table.insert(row, { utils.bufname_for_pos(pos), "Directory" })
    end
    if use_range then
      table.insert(row, { utils.format_pos(pos), hls.number })
    else
      table.insert(row, { tostring(pos.lnum), hls.number })
      table.insert(row, { tostring(pos.col), hls.number })
    end
    table.insert(row, { line_text, hls.string })
    table.insert(rows, row)
  end

  local headers = { "" }
  local align = { "center" }
  if show_prefix then
    table.insert(headers, "")
    table.insert(align, "center")
  end
  if multi_buf then
    table.insert(headers, "buf")
    table.insert(align, "center")
  end
  if use_range then
    table.insert(headers, "pos")
    table.insert(align, "center")
  else
    table.insert(headers, "line")
    table.insert(align, "center")
    table.insert(headers, "col")
    table.insert(align, "center")
  end
  table.insert(headers, "text")
  table.insert(align, nil)

  local lines, highlights = utils.build_highlight_table(vim.fn.reverse(rows), {
    headers = headers,
    align = align,
  })

  local notif = notify(lines, 3, {
    timeout = false,
    title = provider_name,
    on_close = function()
      state.notify_id = nil
      state.notify_wid = nil
    end,
    on_open = function(wid)
      state.notify_wid = wid
    end,
    on_replace = function(wid)
      vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(wid) then
          local bufnr = vim.api.nvim_win_get_buf(wid)
          local total_lines = vim.api.nvim_buf_line_count(bufnr)
          local win_height = vim.api.nvim_win_get_height(wid)
          if total_lines > win_height then
            vim.api.nvim_win_set_cursor(wid, { total_lines, 0 })
          end
        end
      end, 200)
    end,
    replace = state.notify_id,
    highlights = { body = highlights },
  })
  state.notify_id = notif.id
end

local M = {}

--- Show the notify view for a provider.
--- @param provider_name string
--- @param positions table[]
--- @param curr_idx number
--- @param opts table Provider config
M.load = function(provider_name, positions, curr_idx, opts)
  curr_idx = curr_idx or 0
  if curr_idx >= 0 then
    notify_handler(provider_name, positions, curr_idx, opts)
  end
end

M.close = function()
  local notify_ok, notify = pcall(require, "notify")
  if notify_ok and type(state.notify_wid) == "number" then
    vim.api.nvim_win_close(state.notify_wid, true)
  end
end

return M
