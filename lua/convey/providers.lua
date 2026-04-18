local config = require("convey.config")
local state = require("convey.state")
local listeners = require("convey.listeners")
local views = require("convey.views")
local utils = require("convey.utils")

local M = {}

local navigating = false
local dismiss_augroup = vim.api.nvim_create_augroup("ConveyDismiss", { clear = true })

-- Saved snapshots of mappings overridden by apply_provider_keymaps, keyed by provider name.
local saved_keymaps = {}

local function action_fn(provider_name, action)
  if action == "exit" then
    return function()
      M.exit(provider_name)
    end
  elseif action == "next" then
    return function()
      M.next(provider_name)
    end
  elseif action == "prev" then
    return function()
      M.prev(provider_name)
    end
  end
end

local function apply_provider_keymaps(provider_name, provider_config)
  local maps = (provider_config.keymaps or {}).provider
  if not maps or vim.tbl_isempty(maps) then
    return
  end
  -- Two-pass: snapshot all current mappings BEFORE installing any. Some keys
  -- alias at the terminal level (e.g. <Esc> == <C-[>); interleaving save and
  -- install would make the second save capture our own mapping.
  local saved = {}
  for key, _ in pairs(maps) do
    saved[key] = vim.fn.maparg(key, "n", false, true)
  end
  for key, action in pairs(maps) do
    local fn = action_fn(provider_name, action)
    if fn then
      vim.keymap.set("n", key, fn, {
        desc = "Convey " .. action .. " " .. provider_name,
      })
    end
  end
  saved_keymaps[provider_name] = saved
end

local function restore_provider_keymaps(provider_name)
  local saved = saved_keymaps[provider_name]
  if not saved then
    return
  end
  for key, prev in pairs(saved) do
    if prev and not vim.tbl_isempty(prev) then
      vim.fn.mapset("n", false, prev)
    else
      pcall(vim.keymap.del, "n", key)
    end
  end
  saved_keymaps[provider_name] = nil
end

--- Set up autocommands that dismiss views and deactivate the provider on the next
--- non-navigation action. Provider keymaps trigger navigate() which sets the
--- navigating flag, so their CursorMoved events are ignored. Any other cursor
--- movement, mode change, or command-line entry dismisses the view and restores
--- the provider's saved keymaps. Runs whenever a provider is active, regardless
--- of view visibility — the activation lifecycle is keyed on state.active_provider.
local function setup_dismiss_autocmds()
  vim.api.nvim_clear_autocmds({ group = dismiss_augroup })

  if not state.active_provider then
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
      end
      if state.active_provider then
        restore_provider_keymaps(state.active_provider)
        state.active_provider = nil
      end
      vim.api.nvim_clear_autocmds({ group = dismiss_augroup })
    end,
  })
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

  local pre_dedup_count = #all

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

  if provider_config.unique then
    log.debug(
      "[convey] "
        .. provider_name
        .. " returned "
        .. #all
        .. " unique positions out of "
        .. pre_dedup_count
    )
  else
    log.debug("[convey] " .. provider_name .. " returned " .. #all .. " positions")
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
  local show_provider_name = provider_name
  local show_positions, show_idx

  if #positions == 0 then
    log.debug("[convey] " .. provider_name .. ": no positions found")
    show_positions = {}
    show_idx = 0
  else
    local pstate = state.get_provider(provider_name)
    local new_idx = pstate.index + direction

    if provider_config.cycle then
      if new_idx < 1 then
        new_idx = #positions
      elseif new_idx > #positions then
        new_idx = 1
      end
    else
      if new_idx < 1 then
        new_idx = 1
      elseif new_idx > #positions then
        new_idx = #positions
      end
    end

    pstate.index = new_idx
    log.debug(
      "[convey] " .. provider_name .. ": navigate to index " .. new_idx .. "/" .. #positions
    )

    -- Clear curr flag on all, set on new current
    for _, pos in ipairs(positions) do
      pos.curr = false
    end
    positions[new_idx].curr = true

    -- Jump to position without adding to the jump list
    local pos = positions[new_idx]
    if pos.bufnr and vim.api.nvim_buf_is_valid(pos.bufnr) then
      if pos.bufnr ~= vim.api.nvim_get_current_buf() then
        vim.cmd("keepjumps buffer " .. pos.bufnr)
      end
      vim.fn.setpos(".", { pos.bufnr, pos.lnum, pos.col + 1, 0 })
    end

    -- Transition activation state. If a different provider was previously active,
    -- restore its keymaps before installing this one's.
    if state.active_provider and state.active_provider ~= provider_name then
      restore_provider_keymaps(state.active_provider)
    end
    if state.active_provider ~= provider_name then
      apply_provider_keymaps(provider_name, provider_config)
    end
    state.active_provider = provider_name
    show_positions = positions
    show_idx = new_idx
  end

  -- When the global on_navigate is configured, defer view rendering and the
  -- provider's on_navigate until the callback fires (e.g., after scroll animation
  -- completes). Otherwise run the provider callback immediately, then show.
  local top_on_navigate = config.get().on_navigate
  local provider_on_navigate = type(provider_config.on_navigate) == "function"
      and provider_config.on_navigate
    or nil

  local function run_provider_on_navigate()
    if provider_on_navigate and #show_positions > 0 then
      provider_on_navigate(show_positions[show_idx])
    end
  end

  if top_on_navigate then
    top_on_navigate(function()
      run_provider_on_navigate()
      views.show(show_provider_name, show_positions, show_idx, provider_config)
      setup_dismiss_autocmds()
      navigating = false
    end)
  else
    run_provider_on_navigate()
    views.show(show_provider_name, show_positions, show_idx, provider_config)
    vim.schedule(function()
      setup_dismiss_autocmds()
      navigating = false
    end)
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

--- Explicitly deactivate a provider: close views, restore saved keymaps, clear active state.
--- @param provider_name string
M.exit = function(provider_name)
  if state.active_provider == provider_name then
    vim.api.nvim_clear_autocmds({ group = dismiss_augroup })
    if state.has_active_view() then
      views.close()
    end
    restore_provider_keymaps(provider_name)
    state.active_provider = nil
    navigating = false
  end
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
