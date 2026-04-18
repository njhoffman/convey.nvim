local config = require("convey.config")
local providers = require("convey.providers")

local M = {}

local register_commands = function()
  local provider_names = function()
    return vim.tbl_keys(config.get().providers)
  end

  vim.api.nvim_create_user_command("ConveyNext", function(ev)
    local name = ev.fargs[1]
    if not name then
      vim.notify("[convey] Usage: ConveyNext <provider>", vim.log.levels.WARN)
      return
    end
    providers.next(name)
  end, {
    nargs = 1,
    complete = function()
      return provider_names()
    end,
    desc = "Navigate to next position in a convey provider",
  })

  vim.api.nvim_create_user_command("ConveyPrev", function(ev)
    local name = ev.fargs[1]
    if not name then
      vim.notify("[convey] Usage: ConveyPrev <provider>", vim.log.levels.WARN)
      return
    end
    providers.prev(name)
  end, {
    nargs = 1,
    complete = function()
      return provider_names()
    end,
    desc = "Navigate to previous position in a convey provider",
  })

  vim.api.nvim_create_user_command("ConveyExit", function(ev)
    local name = ev.fargs[1]
    if not name then
      vim.notify("[convey] Usage: ConveyExit <provider>", vim.log.levels.WARN)
      return
    end
    providers.exit(name)
  end, {
    nargs = 1,
    complete = function()
      return provider_names()
    end,
    desc = "Deactivate a convey provider and close its views",
  })

  vim.api.nvim_create_user_command("ConveyStatus", function()
    require("convey.views.status").open()
  end, {
    desc = "Show convey provider status popup",
  })
end

local register_keymaps = function()
  local map = require("mapper").map
  local cfg = config.get()
  for provider_name, provider_config in pairs(cfg.providers) do
    local globals = (provider_config.keymaps or {}).global or {}
    for key, action in pairs(globals) do
      local fn = action == "next" and providers.next or providers.prev
      map("n", key, function()
        fn(provider_name)
      end, {
        desc = "Convey " .. action .. " " .. provider_name,
      })
    end
  end
end

M.setup = function(opts)
  config.setup(opts)
  config.log().info("[convey] setup complete")
  providers.init()
  register_commands()
  register_keymaps()
end

return M
