local M = {}

--- Generate a hash string from a position's lnum and col.
--- @param pos table Position with lnum and col fields
--- @return string hash
--- @return number hash_n Numeric component for change detection
local get_position_hash = function(pos)
  return tostring(pos.lnum) .. ":" .. tostring(pos.col), pos.lnum + pos.col
end

--- Deduplicate positions by lnum+col, keeping the first occurrence (most recent).
--- @param positions table[] List of ConveyPosition
--- @return table[] deduplicated
M.deduplicate = function(positions)
  local seen = {}
  local result = {}
  for _, pos in ipairs(positions) do
    local hash = get_position_hash(pos)
    if not seen[hash] then
      seen[hash] = true
      table.insert(result, pos)
    end
  end
  return result
end

--- Process a raw list into a display-ready format.
--- Reverses the list (most recent first), optionally deduplicates,
--- marks the current position, and assigns display indices.
--- @param list table[] Raw position list
--- @param pos_idx number Current position index in the original list (0-based)
--- @param unique boolean Whether to deduplicate
--- @return table[] processed List with .idx and .curr fields added
--- @return number new_idx Current position index in the processed list (1-based)
--- @return number hash_id Hash for change detection
M.process_list = function(list, pos_idx, unique)
  local new_list = {}
  local hashes = {}
  local hash_id = pos_idx
  local new_idx = 0
  for i, item in ipairs(vim.fn.reverse(list)) do
    local hash, hash_n = get_position_hash(item)
    hash_id = hash_id + i + hash_n
    item.idx = i
    if not unique or not vim.list_contains(hashes, hash) then
      if i == (#list - pos_idx) then
        new_idx = #new_list + 1
        hash_id = hash_id + i
        item.curr = true
      end
      table.insert(new_list, item)
      table.insert(hashes, hash)
    end
  end
  return new_list, new_idx, hash_id
end

--- Align text within a given width.
--- @param text string Text to align
--- @param width number Target width
--- @param align_type string|nil "left", "center", or "right" (default: "left")
--- @return string aligned Padded text
--- @return table pos { offset, length } of the original text within the padded string
M.align_text = function(text, width, align_type)
  local left, right = 0, 0
  local len = vim.fn.strwidth(text)
  if align_type == "right" then
    left = width - len
  elseif align_type == "center" then
    left = math.floor((width - len) / 2)
    right = math.ceil((width - len) / 2)
  else
    right = width - len
  end
  return string.rep(" ", left) .. text .. string.rep(" ", right), { left, len }
end

--- Format a position as a coordinate string.
--- If the position has end fields, formats as "lnum:col - end_lnum:end_col".
--- Otherwise formats as "lnum:col".
--- @param pos table ConveyPosition
--- @return string
M.format_pos = function(pos)
  local start = pos.lnum .. ":" .. pos.col
  if pos.end_lnum and pos.end_col then
    local end_col_str = pos.end_col == vim.v.maxcol and "EOL" or tostring(pos.end_col)
    return start .. " - " .. pos.end_lnum .. ":" .. end_col_str
  end
  return start
end

--- Check if any position in the list has range fields (end_lnum and end_col).
--- @param positions table[] ConveyPosition[]
--- @return boolean
M.has_ranges = function(positions)
  for _, pos in ipairs(positions) do
    if pos.end_lnum and pos.end_col then
      return true
    end
  end
  return false
end

--- Check if positions span more than one buffer.
--- @param positions table[] ConveyPosition[]
--- @return boolean
M.is_multi_buffer = function(positions)
  if #positions <= 1 then
    return false
  end
  local first_bufnr = positions[1].bufnr
  for i = 2, #positions do
    if positions[i].bufnr ~= first_bufnr then
      return true
    end
  end
  return false
end

--- Get a truncated tail filename for a position's buffer.
--- @param pos table ConveyPosition
--- @param max_len number|nil Maximum length (default 15)
--- @return string
M.bufname_for_pos = function(pos, max_len)
  max_len = max_len or 15
  if not pos.bufnr or not vim.api.nvim_buf_is_valid(pos.bufnr) then
    return ""
  end
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(pos.bufnr), ":t")
  if name == "" then
    return "[" .. pos.bufnr .. "]"
  end
  if #name > max_len then
    name = name:sub(1, max_len - 1) .. "~"
  end
  return name
end

--- Build a formatted table with aligned columns and highlight information.
--- @param rows table[] Array of rows, each row is array of { text, hl_group }
--- @param opts table|nil { headers: string[], align: string[], padding: number }
--- @return string[] lines Formatted lines for display
--- @return table[] highlights Array of { hl_group, line_idx, col_start, col_end }
M.build_highlight_table = function(rows, opts)
  opts = opts or {}
  opts.padding = opts.padding or 2
  if opts.headers then
    local header_row = {}
    for _, header in ipairs(opts.headers) do
      table.insert(header_row, { header, "Title" })
    end
    table.insert(rows, 1, header_row)
  end

  local colwidths = {}
  for _, row in ipairs(rows) do
    for i, item in ipairs(row) do
      local width = colwidths[i] or 0
      colwidths[i] = math.max(width, vim.fn.strwidth(item[1] or ""))
    end
  end

  local lines, highlights = {}, {}
  for _, row in ipairs(rows) do
    local line = ""
    for i, item in ipairs(row) do
      local text, pos =
        M.align_text(item[1], colwidths[i] + opts.padding, opts.align and opts.align[i])
      local start = #line + pos[1]
      local finish = start + pos[2]
      table.insert(highlights, { item[2], #lines, start, finish })
      line = line .. text
    end
    table.insert(lines, line)
  end
  return lines, highlights
end

return M
