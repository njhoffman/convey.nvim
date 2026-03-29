local config = require("convey.config")

local view_modules = {
  notify = require("convey.views.notify"),
  inline = require("convey.views.inline"),
}

local M = {}

--- Show all enabled views for a provider's positions.
--- @param provider_name string
--- @param positions table[]
--- @param curr_idx number
--- @param provider_config table
M.show = function(provider_name, positions, curr_idx, provider_config)
  local provider_views = provider_config.views or {}

  for view_name, view_mod in pairs(view_modules) do
    local global_config = config.get_view(view_name) or {}
    local provider_view_config = provider_views[view_name] or {}

    if global_config.enabled ~= false and provider_view_config.enabled ~= false then
      view_mod.load(provider_name, positions, curr_idx, provider_config)
    end
  end
end

M.close = function()
  for _, view_mod in pairs(view_modules) do
    view_mod.close()
  end
end

return M
