local config = require("convey.config")
local state = require("convey.state")
local listeners = require("convey.listeners")
local views = require("convey.views")
local utils = require("convey.utils")

local M = {}

local navigating = false
local dismiss_augroup = vim.api.nvim_create_augroup("ConveyDismiss", { clear = true })

--- Set up autocommands that dismiss the notify view on the next non-navigation action.
--- Provider keymaps trigger navigate() which sets the navigating flag, so their
--- CursorMoved events are ignored. Any other cursor movement, mode change, or
--- command-line entry dismisses the view.
local function setup_dismiss_autocmds()
  vim.api.nvim_clear_autocmds({ group = dismiss_augroup })

  if not state.has_active_view() then
    return
  end

  vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "CmdlineEnter" }, {
    group = dismiss_augroup,
    callback = function()
      if navigating then
        return
      end
      if state.has_active_view() then
        views.close()
        state.active_provider = nil
      end
      vim.api.nvim_clear_autocmds({ group = dismiss_augroup })
    end,
  })
end

local function finish_navigate()
  setup_dismiss_autocmds()
  navigating = false
end

--- Fetch, merge, and process positions from all listeners for a provider.
--- @param provider_name string
--- @param provider_config table
--- @return table[] positions Processed position list (most recent first)
--- @return number curr_idx Current position index (1-based), 0 if none
local function refresh_positions(provider_name, provider_config, bufnr)
  local log = config.log()
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local all = {}

  for _, listener_name in ipairs(provider_config.listeners) do
    local positions = listeners.get_positions(listener_name, bufnr)
    log.trace(
      "[convey] "
        .. provider_name
        .. ": "
        .. listener_name
        .. " returned "
        .. #positions
        .. " positions"
    )
    vim.list_extend(all, positions)
  end

  -- Collect movement positions if configured
  if provider_config.movements then
    local movements = require("convey.movements")
    local move_positions = movements.get_positions(bufnr, provider_config.movements)
    vim.list_extend(all, move_positions)
  end

  -- Sort by timestamp descending (most recent first)
  table.sort(all, function(a, b)
    return a.timestamp > b.timestamp
  end)

  -- Deduplicate if unique
  if provider_config.unique then
    all = utils.deduplicate(all)
  end

  -- Truncate to max_marks
  local max_marks = config.get().max_marks
  if #all > max_marks then
    local truncated = {}
    for i = 1, max_marks do
      truncated[i] = all[i]
    end
    all = truncated
  end

  -- Find current position (marked by listener)
  local curr_idx = 0
  for i, pos in ipairs(all) do
    if pos.curr then
      curr_idx = i
      break
    end
  end

  -- Store in state
  local pstate = state.get_provider(provider_name)
  pstate.positions = all
  if curr_idx > 0 then
    pstate.index = curr_idx
  end

  return all, pstate.index
end

--- Navigate to a position and update the view.
--- @param provider_name string
--- @param direction number 1 for next (older), -1 for prev (newer)
local function navigate(provider_name, direction)
  local log = config.log()
  local provider_config = config.get_provider(provider_name)
  if not provider_config then
    log.error("[convey] Unknown provider: " .. provider_name)
    return
  end

  navigating = true

  local positions, _ = refresh_positions(provider_name, provider_config)
  if #positions == 0 then
    log.debug("[convey] " .. provider_name .. ": no positions found")
    views.show(provider_name, {}, 0, provider_config)
    local on_navigate = config.get().on_navigate
    if on_navigate then
      on_navigate(finish_navigate)
    else
      vim.schedule(finish_navigate)
    end
    return
  end

  local pstate = state.get_provider(provider_name)
  local new_idx = pstate.index + direction

  -- Clamp to bounds
  if new_idx < 1 then
    new_idx = 1
  elseif new_idx > #positions then
    new_idx = #positions
  end

  pstate.index = new_idx
  log.debug("[convey] " .. provider_name .. ": navigate to index " .. new_idx .. "/" .. #positions)

  -- Clear curr flag on all, set on new current
  for _, pos in ipairs(positions) do
    pos.curr = false
  end
  positions[new_idx].curr = true

  -- Jump to position
  local pos = positions[new_idx]
  if pos.bufnr and vim.api.nvim_buf_is_valid(pos.bufnr) then
    if pos.bufnr ~= vim.api.nvim_get_current_buf() then
      vim.api.nvim_set_current_buf(pos.bufnr)
    end
    vim.fn.setpos(".", { pos.bufnr, pos.lnum, pos.col + 1, 0 })
  end

  -- Provider-level post-navigation callback
  if type(provider_config.on_navigate) == "function" then
    provider_config.on_navigate(pos)
  end

  -- Track active provider and show view
  state.active_provider = provider_name
  views.show(provider_name, positions, new_idx, provider_config)

  -- Dismiss the notify view on the next non-navigation action
  local on_navigate = config.get().on_navigate
  if on_navigate then
    on_navigate(finish_navigate)
  else
    vim.schedule(finish_navigate)
  end
end

--- Navigate to the next (older) position in a provider.
--- @param provider_name string
M.next = function(provider_name)
  navigate(provider_name, 1)
end

--- Navigate to the previous (newer) position in a provider.
--- @param provider_name string
M.prev = function(provider_name)
  navigate(provider_name, -1)
end

--- Refresh the view for the currently active provider (e.g., on buffer change).
M.refresh = function()
  local provider_name = state.active_provider
  if not provider_name then
    return
  end
  -- Only refresh if a view is currently visible
  if not state.has_active_view() then
    return
  end
  local provider_config = config.get_provider(provider_name)
  if not provider_config then
    return
  end

  local positions, _ = refresh_positions(provider_name, provider_config)
  local pstate = state.get_provider(provider_name)
  views.show(provider_name, positions, pstate.index, provider_config)
end

--- Initialize all configured providers' listeners.
M.init = function()
  local log = config.log()
  local cfg = config.get()
  for name, provider_config in pairs(cfg.providers) do
    if provider_config.enabled ~= false then
      log.debug("[convey] initializing provider: " .. name)
      listeners.init(provider_config.listeners, state.augroup)
    else
      log.debug("[convey] skipping disabled provider: " .. name)
    end
  end

  -- Refresh view when switching buffers
  vim.api.nvim_create_autocmd("BufEnter", {
    group = state.augroup,
    callback = function()
      vim.schedule(M.refresh)
    end,
  })
end

--- Get the current status of a provider without side effects.
--- @param provider_name string
--- @return table|nil status { positions, index, config } or nil if unknown
M.get_status = function(provider_name, bufnr)
  local provider_config = config.get_provider(provider_name)
  if not provider_config then
    return nil
  end

  if not provider_config.enabled then
    return { positions = {}, index = 0, config = provider_config }
  end

  local positions, _ = refresh_positions(provider_name, provider_config, bufnr)
  local pstate = state.get_provider(provider_name)
  return { positions = positions, index = pstate.index, config = provider_config }
end

--- Destroy all configured providers' listeners.
M.destroy = function()
  local cfg = config.get()
  for _, provider_config in pairs(cfg.providers) do
    listeners.destroy(provider_config.listeners)
  end
end

return M
