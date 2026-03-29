local M = {}

--- Discover positions by executing a Vim motion repeatedly from the top of the buffer.
--- @param bufnr number
--- @param motions table { next = string, prev = string }
--- @return table[] Raw positions (unsorted, no timestamp/curr)
M.from_motions = function(bufnr, motions)
  local saved_view = vim.fn.winsaveview()
  local positions = {}
  local seen = {}

  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local max_iterations = vim.api.nvim_buf_line_count(bufnr)
  for _ = 1, max_iterations do
    local before = vim.api.nvim_win_get_cursor(0)
    vim.cmd("normal! " .. motions.next)
    local after = vim.api.nvim_win_get_cursor(0)

    if after[1] == before[1] and after[2] == before[2] then
      break
    end

    local key = after[1] .. ":" .. after[2]
    if seen[key] then
      break
    end
    seen[key] = true

    table.insert(positions, {
      lnum = after[1],
      col = after[2],
      bufnr = bufnr,
      source = "movements",
    })
  end

  vim.fn.winrestview(saved_view)
  return positions
end

--- Discover positions from treesitter textobject queries.
--- @param bufnr number
--- @param queries string[] e.g. { "@block.outer", "@conditional.outer" }
--- @return table[] Raw positions (unsorted, no timestamp/curr)
M.from_queries = function(bufnr, queries)
  local positions = {}

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return {}
  end

  local lang = parser:lang()
  local ts_query = vim.treesitter.query.get(lang, "textobjects")
  if not ts_query then
    return {}
  end

  local trees = parser:parse()
  if not trees or #trees == 0 then
    return {}
  end

  local root = trees[1]:root()
  local seen = {}

  for id, node in ts_query:iter_captures(root, bufnr) do
    local capture_name = ts_query.captures[id]
    for _, query_name in ipairs(queries) do
      local pattern = query_name:gsub("^@", "")
      if capture_name == pattern or capture_name:match("^" .. vim.pesc(pattern) .. "%.") then
        local start_row, start_col = node:range()
        local key = start_row .. ":" .. start_col
        if not seen[key] then
          seen[key] = true
          table.insert(positions, {
            lnum = start_row + 1,
            col = start_col,
            bufnr = bufnr,
            source = "movements",
          })
        end
      end
    end
  end

  return positions
end

--- Compute positions from movements config, sorted by buffer position.
--- Timestamps are assigned so descending sort preserves ascending lnum order.
--- @param bufnr number
--- @param movements_config table { motions = {...} } or { queries = {...} }
--- @return table[] ConveyPosition[]
M.get_positions = function(bufnr, movements_config)
  local positions
  if movements_config.motions then
    positions = M.from_motions(bufnr, movements_config.motions)
  elseif movements_config.queries then
    positions = M.from_queries(bufnr, movements_config.queries)
  else
    return {}
  end

  table.sort(positions, function(a, b)
    if a.lnum == b.lnum then
      return a.col < b.col
    end
    return a.lnum < b.lnum
  end)

  local total = #positions
  for i, pos in ipairs(positions) do
    pos.timestamp = total - i + 1
  end

  local cursor_lnum = vim.fn.winsaveview().lnum
  for i = #positions, 1, -1 do
    if positions[i].lnum <= cursor_lnum then
      positions[i].curr = true
      break
    end
  end

  return positions
end

return M
