local state = {
  -- Per-provider state, keyed by provider name
  -- Each entry: { positions = {}, index = 0 }
  providers = {},
  -- Shared notification tracking (one notification at a time across all providers)
  notify_id = nil,
  notify_wid = nil,
  -- Inline view tracking
  inline_ns = vim.api.nvim_create_namespace("convey_inline"),
  inline_extmark_id = nil,
  inline_bufnr = nil,
  -- The provider name currently being displayed in the view
  active_provider = nil,
  -- Shared augroup for all convey autocommands
  augroup = vim.api.nvim_create_augroup("Convey", { clear = true }),
}

state.get_provider = function(name)
  if not state.providers[name] then
    state.providers[name] = { positions = {}, index = 0 }
  end
  return state.providers[name]
end

state.reset_provider = function(name)
  state.providers[name] = { positions = {}, index = 0 }
end

state.has_active_view = function()
  return state.notify_id ~= nil or state.inline_extmark_id ~= nil
end

return state
