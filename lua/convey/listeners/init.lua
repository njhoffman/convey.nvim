local config = require("convey.config")

local M = {}

local listener_modules = {}

--- Resolve a listener name to its module, caching the result.
--- @param name string Listener name (e.g., "changes", "jumps")
--- @return table listener Module conforming to ConveyListener interface
M.get = function(name)
  if not listener_modules[name] then
    local ok, mod = pcall(require, "convey.listeners." .. name)
    if not ok then
      config.log().error("[convey] Unknown listener: " .. name)
      return nil
    end
    listener_modules[name] = mod
  end
  return listener_modules[name]
end

--- Initialize listeners by name, calling their init() if present.
--- @param names string[] List of listener names
--- @param augroup number Autocommand group ID
M.init = function(names, augroup)
  local log = config.log()
  for _, name in ipairs(names) do
    local listener = M.get(name)
    if listener and type(listener.init) == "function" then
      log.trace("[convey] initializing listener: " .. name)
      listener.init(augroup)
    end
  end
end

--- Destroy listeners by name, calling their destroy() if present.
--- @param names string[]
M.destroy = function(names)
  local log = config.log()
  for _, name in ipairs(names) do
    local listener = M.get(name)
    if listener and type(listener.destroy) == "function" then
      log.trace("[convey] destroying listener: " .. name)
      listener.destroy()
    end
  end
end

--- Get the prefix icon for a listener.
--- @param name string Listener name
--- @return string|nil prefix
M.get_prefix = function(name)
  local listener = M.get(name)
  if not listener then
    return nil
  end
  return listener.prefix
end

--- Get positions from a listener.
--- @param name string Listener name
--- @param bufnr number Buffer number
--- @return table[] positions ConveyPosition[]
M.get_positions = function(name, bufnr)
  local listener = M.get(name)
  if not listener then
    return {}
  end
  return listener.get_positions(bufnr) or {}
end

return M
