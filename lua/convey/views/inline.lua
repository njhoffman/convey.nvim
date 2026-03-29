local config = require("convey.config")
local state = require("convey.state")

local M = {}

--- Show inline virtual text for the current navigation position.
--- @param provider_name string
--- @param positions table[]
--- @param curr_idx number
--- @param provider_config table
M.load = function(provider_name, positions, curr_idx, provider_config)
  M.close()

  if #positions == 0 or curr_idx < 1 then
    return
  end

  -- Look up prev/next keymaps
  local next_key, prev_key
  for key, action in pairs(provider_config.keymaps or {}) do
    if action == "next" then
      next_key = key
    elseif action == "prev" then
      prev_key = key
    end
  end

  local text = string.format(
    "%s [%d/%d] %s\u{2191} %s\u{2193}",
    provider_name,
    curr_idx,
    #positions,
    prev_key or "?",
    next_key or "?"
  )

  -- Set up highlight with transparent background
  local view_config = config.get_view("inline") or {}
  local provider_inline = provider_config.views and provider_config.views.inline or {}
  local fg = provider_inline.fg or view_config.fg or "#ffffff"
  vim.api.nvim_set_hl(0, "ConveyInline", { fg = fg, bg = "NONE" })

  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1

  state.inline_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, state.inline_ns, row, 0, {
    virt_text = { { "  " .. text, "ConveyInline" } },
    virt_text_pos = "eol",
  })
  state.inline_bufnr = bufnr
end

M.close = function()
  if
    state.inline_extmark_id
    and state.inline_bufnr
    and vim.api.nvim_buf_is_valid(state.inline_bufnr)
  then
    pcall(
      vim.api.nvim_buf_del_extmark,
      state.inline_bufnr,
      state.inline_ns,
      state.inline_extmark_id
    )
  end
  state.inline_extmark_id = nil
  state.inline_bufnr = nil
end

return M
