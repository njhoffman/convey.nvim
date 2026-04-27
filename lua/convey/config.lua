local M = {}

M.version = "0.3.0"

local default_logger = {
  error = function(msg)
    return vim.notify(msg, vim.log.levels.ERROR)
  end,
  warn = function(msg)
    return vim.notify(msg, vim.log.levels.WARN)
  end,
  info = function(msg)
    return vim.notify(msg, vim.log.levels.INFO)
  end,
  debug = function(msg)
    return vim.notify(msg, vim.log.levels.DEBUG)
  end,
  trace = function(msg)
    return vim.notify(msg, vim.log.levels.TRACE)
  end,
}

local exit_maps = {
  ["<Esc>"] = "exit",
  ["<C-c>"] = "exit",
  ["<C-[>"] = "exit",
}

local defaults = {
  max_marks = 50,
  on_navigate = nil,
  views = {
    notify = {
      enabled = true,
      lines_before = 8,
      lines_after = 3,
      hl = {
        icon = "Special",
        number = "Number",
        text = "Comment",
      },
    },
    inline = {
      enabled = true,
      fg = "#00ffff",
      bg = nil,
      align = "eol",
      padding = 2,
      delay = 100,
      template = {
        { "{provider} ", "ConveyInline" },
        { "[{curr}/{total}] ", "ConveyInline" },
        { "{prev_key}\u{2191} ", "ConveyInline" },
        { "{next_key}\u{2193}", "ConveyInline" },
      },
    },
  },
  logger = default_logger,
  providers = {
    changes = {
      enabled = true,
      unique = true,
      cycle = false,
      listeners = { "changes" },
      keymaps = {
        global = {
          ["g;"] = "next",
          ["g,"] = "prev",
        },
        provider = vim.tbl_extend("force", exit_maps, {
          ["g;"] = "next",
          ["g,"] = "prev",
        }),
      },
      views = {
        notify = { enabled = true },
        inline = { enabled = true },
      },
    },
    jumps = {
      enabled = true,
      unique = true,
      cycle = false,
      listeners = { "jumps" },
      keymaps = {
        global = {
          ["<C-o>"] = "next",
          ["<C-i>"] = "prev",
        },
        provider = vim.tbl_extend("force", exit_maps, {
          ["<C-o>"] = "next",
          ["<C-i>"] = "prev",
        }),
      },
      views = {
        notify = { enabled = true },
        inline = { enabled = true },
      },
    },
    visual = {
      enabled = true,
      unique = true,
      cycle = false,
      on_navigate = function(pos)
        if pos.end_lnum and pos.end_col then
          vim.fn.setpos("'<", { pos.bufnr, pos.lnum, pos.col + 1, 0 })
          vim.fn.setpos("'>", { pos.bufnr, pos.end_lnum, pos.end_col, 0 })
          vim.cmd("normal! gv")
        end
      end,
      listeners = { "pastes", "yanks", "selections" },
      keymaps = {
        global = {
          ["gv"] = "next",
          ["gV"] = "prev",
        },
        provider = vim.tbl_extend("force", exit_maps, {
          ["gv"] = "next",
          ["gV"] = "prev",
        }),
      },
      views = {
        notify = { enabled = true },
        inline = { enabled = true },
      },
    },
    saves = {
      enabled = true,
      unique = false,
      cycle = false,
      listeners = { "writes" },
      keymaps = {
        provider = exit_maps,
      },
      views = {
        notify = { enabled = true },
        inline = { enabled = true },
      },
    },
    paragraph = {
      enabled = true,
      unique = true,
      cycle = false,
      listeners = {},
      movements = {
        motions = { next = "]]", prev = "[[" },
      },
      keymaps = {
        global = {
          ["[["] = "prev",
          ["]]"] = "next",
        },
        provider = vim.tbl_extend("force", exit_maps, {
          ["[["] = "prev",
          ["]]"] = "next",
        }),
      },
      views = {
        notify = { enabled = true },
        inline = { enabled = true },
      },
    },
    block = {
      enabled = true,
      unique = true,
      cycle = false,
      listeners = {},
      movements = {
        queries = { "@block.outer", "@conditional.outer", "@loop.outer" },
      },
      keymaps = {
        provider = exit_maps,
      },
      views = {
        notify = { enabled = true },
        inline = { enabled = true },
      },
    },
  },
}

M.values = vim.deepcopy(defaults)

local listener_to_providers = nil

local build_inverse_map = function()
  listener_to_providers = {}
  for provider_name, p in pairs(M.values.providers) do
    if p.listeners then
      for _, l in ipairs(p.listeners) do
        listener_to_providers[l] = listener_to_providers[l] or {}
        table.insert(listener_to_providers[l], provider_name)
      end
    end
  end
end

M.setup = function(opts)
  M.values = vim.tbl_deep_extend("force", defaults, opts or {})
  listener_to_providers = nil
end

M.get = function()
  return M.values
end

M.get_provider = function(name)
  return M.values.providers[name]
end

M.get_view = function(view_name)
  return M.values.views[view_name]
end

M.log = function()
  return M.values.logger
end

--- Return the list of provider names that include the given listener.
--- Cached on first call after setup.
--- @param listener_name string
--- @return string[]
M.get_providers_for_listener = function(listener_name)
  if not listener_to_providers then
    build_inverse_map()
  end
  return listener_to_providers[listener_name] or {}
end

return M
