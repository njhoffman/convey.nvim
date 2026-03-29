local config = require("convey.config")
local providers = require("convey.providers")
local utils = require("convey.utils")
local listeners = require("convey.listeners")

local ns = vim.api.nvim_create_namespace("convey_status")

-- Provider display order (stable iteration)
local provider_order = { "changes", "jumps", "visual", "saves" }

local popup = {
  bufnr = nil,
  winnr = nil,
  source_bufnr = nil,
  expanded = {},
  expanded_gaps = {},
  expanded_config = {},
  line_map = {},
}

--- Get text preview for a position.
--- @param pos table ConveyPosition
--- @return string
local function get_text_preview(pos, max_len)
  max_len = max_len or 40
  if not pos.bufnr or not vim.api.nvim_buf_is_valid(pos.bufnr) then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(pos.bufnr, pos.lnum - 1, pos.lnum, false)
  if not lines[1] then
    return ""
  end
  local text = vim.trim(lines[1])
  if #text > max_len then
    text = text:sub(1, max_len) .. "..."
  end
  return text
end

--- Format a config table as a summary string.
--- @param cfg table Provider config
--- @return string
local function format_config_summary(cfg)
  local parts = {}
  table.insert(parts, "unique = " .. tostring(cfg.unique))
  table.insert(parts, "listeners = { " .. table.concat(
    vim.tbl_map(function(l)
      return '"' .. l .. '"'
    end, cfg.listeners),
    ", "
  ) .. " }")
  if cfg.keymaps then
    local keyparts = {}
    for k, v in pairs(cfg.keymaps) do
      table.insert(keyparts, '["' .. k .. '"] = "' .. v .. '"')
    end
    table.insert(parts, "keymaps = { " .. table.concat(keyparts, ", ") .. " }")
  end
  return table.concat(parts, ", ")
end

--- Format a config table as expanded multi-line output.
--- @param cfg table Provider config
--- @return string[] lines
local function format_config_expanded(cfg)
  local inspected = vim.inspect(cfg)
  local result = {}
  for line in inspected:gmatch("[^\n]+") do
    table.insert(result, "      " .. line)
  end
  return result
end

--- Format a single item line.
--- @param pos table ConveyPosition
--- @param i number Item index
--- @param idx number Current index
--- @param status table { config }
--- @param multi_buf boolean Whether positions span multiple buffers
--- @return string
local function format_item_line(pos, i, idx, status, multi_buf)
  local marker = (i == idx) and "  > " or "    "
  local text = get_text_preview(pos, 50)
  local coord = utils.format_pos(pos)
  local show_prefix = status.config and status.config.listeners and #status.config.listeners > 1
  local prefix = ""
  if show_prefix then
    prefix = " " .. (listeners.get_prefix(pos.source) or "")
  end
  local buf_label = ""
  if multi_buf then
    buf_label = " " .. utils.bufname_for_pos(pos)
  end
  return marker .. string.format("%-4d", i) .. prefix .. buf_label .. " " .. coord .. "  " .. text
end

--- Build expanded items display for a provider.
--- Shows first item, gap, items around current (3 total), gap, last item.
--- Gaps can be expanded to show all items in the range.
--- @param provider_name string
--- @param status table { positions, index, config }
--- @return string[] lines
--- @return table[] line_actions { { action, ... } } parallel to lines
local function build_expanded_items(provider_name, status)
  local positions = status.positions
  local idx = status.index
  local total = #positions
  local result_lines = {}
  local result_actions = {}
  local gap_state = popup.expanded_gaps[provider_name] or {}
  local multi_buf = utils.is_multi_buffer(positions)

  if total == 0 then
    table.insert(result_lines, "    (no items)")
    table.insert(result_actions, { action = "none", provider = provider_name })
    return result_lines, result_actions
  end

  -- Determine which indices are always shown: first, around current, last
  local show = {}
  show[1] = true
  show[total] = true
  for i = math.max(1, idx - 1), math.min(total, idx + 1) do
    show[i] = true
  end

  local last_shown = 0
  for i = 1, total do
    if show[i] then
      -- Handle gap before this item
      if last_shown > 0 and i - last_shown > 1 then
        local gap_start = last_shown + 1
        local gap_end = i - 1
        local gap_key = gap_start .. "-" .. gap_end
        if gap_state[gap_key] then
          -- Gap is expanded: show all items in range
          for j = gap_start, gap_end do
            table.insert(result_lines, format_item_line(positions[j], j, idx, status, multi_buf))
            table.insert(result_actions, {
              action = "collapse_gap",
              provider = provider_name,
              gap_key = gap_key,
            })
          end
        else
          -- Gap is collapsed: show summary
          table.insert(result_lines, "    ... (items " .. gap_start .. " - " .. gap_end .. ")")
          table.insert(result_actions, {
            action = "expand_gap",
            provider = provider_name,
            gap_key = gap_key,
          })
        end
      end
      -- Show the always-visible item
      table.insert(result_lines, format_item_line(positions[i], i, idx, status, multi_buf))
      table.insert(result_actions, { action = "toggle_provider", provider = provider_name })
      last_shown = i
    end
  end

  return result_lines, result_actions
end

--- Build all lines and highlights for the status popup.
--- @return string[] lines
--- @return table[] highlights { { group, line, col_start, col_end } }
local function build_lines()
  local bufnr = popup.source_bufnr or vim.api.nvim_get_current_buf()
  local bufname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
  if bufname == "" then
    bufname = "[No Name]"
  end

  local lines = {}
  local highlights = {}
  local line_map = {}

  -- Header
  local header = "  Buffer: [" .. bufnr .. "] " .. bufname
  table.insert(lines, header)
  table.insert(highlights, { "Title", 0, 0, #header })
  table.insert(lines, "")

  -- Providers
  local cfg = config.get()
  for _, name in ipairs(provider_order) do
    local provider_config = cfg.providers[name]
    if provider_config then
      local line_idx = #lines
      local enabled = provider_config.enabled ~= false
      local icon = enabled and "●" or "○"
      local icon_hl = enabled and "Special" or "Comment"

      if not enabled then
        local line = "  " .. icon .. " " .. name .. "    -- disabled --"
        table.insert(lines, line)
        table.insert(highlights, { icon_hl, line_idx, 2, 2 + #icon })
        table.insert(highlights, { "Function", line_idx, 2 + #icon + 1, 2 + #icon + 1 + #name })
        table.insert(highlights, { "Comment", line_idx, 2 + #icon + 1 + #name, #line })
        line_map[line_idx] = { provider = name, action = "none" }
      else
        local status = providers.get_status(name, bufnr)
        local positions = status and status.positions or {}
        local idx = status and status.index or 0
        local total = #positions

        local summary
        if total == 0 then
          summary = "  " .. icon .. " " .. string.format("%-10s", name) .. " [0/0]"
        else
          local pos = positions[math.max(1, math.min(idx, total))]
          local text = get_text_preview(pos, 35)
          local coord = utils.format_pos(pos)
          summary = "  "
            .. icon
            .. " "
            .. string.format("%-10s", name)
            .. " ["
            .. idx
            .. "/"
            .. total
            .. "]"
            .. "  "
            .. coord
            .. "  "
            .. text
        end

        table.insert(lines, summary)
        -- Icon highlight
        table.insert(highlights, { icon_hl, line_idx, 2, 2 + #icon })
        -- Name highlight
        local name_start = 2 + #icon + 1
        table.insert(highlights, { "Function", line_idx, name_start, name_start + #name })
        -- Find bracket position for number highlight
        local bracket_start = summary:find("%[")
        if bracket_start then
          local bracket_end = summary:find("%]")
          if bracket_end then
            table.insert(highlights, { "Number", line_idx, bracket_start - 1, bracket_end })
          end
        end
        -- Text preview highlight (everything after the second double-space after brackets)
        if total > 0 then
          local pos = positions[math.max(1, math.min(idx, total))]
          local coord = utils.format_pos(pos)
          local coord_start = summary:find(coord, bracket_start or 1, true)
          if coord_start then
            table.insert(
              highlights,
              { "Number", line_idx, coord_start - 1, coord_start - 1 + #coord }
            )
            local text_start = coord_start + #coord + 1
            if text_start < #summary then
              table.insert(highlights, { "String", line_idx, text_start, #summary })
            end
          end
        end
        line_map[line_idx] = { provider = name, action = "toggle_provider" }

        -- Expanded content
        if popup.expanded[name] then
          -- Config line(s)
          if popup.expanded_config[name] then
            local cfg_lines = format_config_expanded(provider_config)
            for _, cl in ipairs(cfg_lines) do
              table.insert(lines, cl)
              local ci = #lines - 1
              table.insert(highlights, { "Comment", ci, 0, #cl })
              line_map[ci] = { provider = name, action = "toggle_config" }
            end
          else
            local cfg_line = "    " .. format_config_summary(provider_config)
            table.insert(lines, cfg_line)
            table.insert(highlights, { "Comment", #lines - 1, 0, #cfg_line })
            line_map[#lines - 1] = { provider = name, action = "toggle_config" }
          end

          -- Items
          local item_lines, item_actions = build_expanded_items(name, status)
          for li, item_line in ipairs(item_lines) do
            table.insert(lines, item_line)
            local il = #lines - 1
            line_map[il] = item_actions[li]
            if item_line:match("^    %.%.%.") then
              table.insert(highlights, { "NonText", il, 0, #item_line })
            elseif item_line:match("^  > ") then
              table.insert(highlights, { "CursorLine", il, 0, #item_line })
            end
          end
        end
      end
    end
  end

  table.insert(lines, "")
  popup.line_map = line_map
  return lines, highlights
end

--- Apply highlights to the popup buffer.
--- @param bufnr number
--- @param highlights table[]
local function apply_highlights(bufnr, highlights)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, hl[1], hl[2], hl[3], hl[4])
  end
end

--- Render content into the popup buffer.
local function render()
  if not popup.bufnr or not vim.api.nvim_buf_is_valid(popup.bufnr) then
    return
  end

  local lines, highlights = build_lines()

  vim.bo[popup.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
  vim.bo[popup.bufnr].modifiable = false

  apply_highlights(popup.bufnr, highlights)

  -- Resize window height to fit content (capped)
  if popup.winnr and vim.api.nvim_win_is_valid(popup.winnr) then
    local max_height = math.floor(vim.o.lines * 0.8)
    local height = math.min(#lines, max_height)
    vim.api.nvim_win_set_height(popup.winnr, height)
  end
end

--- Handle action for the line under the cursor.
local function toggle_expand()
  if not popup.bufnr or not vim.api.nvim_buf_is_valid(popup.bufnr) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(popup.winnr)
  local line_idx = cursor[1] - 1 -- 0-based
  local entry = popup.line_map[line_idx]
  if not entry or entry.action == "none" then
    return
  end

  local provider_name = entry.provider
  local act = entry.action

  if act == "toggle_provider" then
    local provider_config = config.get_provider(provider_name)
    if not provider_config or provider_config.enabled == false then
      return
    end
    popup.expanded[provider_name] = not popup.expanded[provider_name]
    if not popup.expanded[provider_name] then
      popup.expanded_gaps[provider_name] = nil
      popup.expanded_config[provider_name] = nil
    end
  elseif act == "toggle_config" then
    popup.expanded_config[provider_name] = not popup.expanded_config[provider_name]
  elseif act == "expand_gap" then
    if not popup.expanded_gaps[provider_name] then
      popup.expanded_gaps[provider_name] = {}
    end
    popup.expanded_gaps[provider_name][entry.gap_key] = true
  elseif act == "collapse_gap" then
    if popup.expanded_gaps[provider_name] then
      popup.expanded_gaps[provider_name][entry.gap_key] = nil
    end
  end

  render()

  -- Try to keep cursor near where it was
  local line_count = vim.api.nvim_buf_line_count(popup.bufnr)
  if cursor[1] > line_count then
    vim.api.nvim_win_set_cursor(popup.winnr, { line_count, 0 })
  end
end

--- Close the status popup.
local function close()
  if popup.winnr and vim.api.nvim_win_is_valid(popup.winnr) then
    vim.api.nvim_win_close(popup.winnr, true)
  end
  popup.winnr = nil
  popup.bufnr = nil
  popup.source_bufnr = nil
  popup.line_map = {}
end

local M = {}

--- Open the ConveyStatus popup.
M.open = function()
  -- Close existing popup if open
  if popup.winnr and vim.api.nvim_win_is_valid(popup.winnr) then
    close()
    return
  end

  popup.source_bufnr = vim.api.nvim_get_current_buf()
  popup.expanded = {}
  popup.expanded_gaps = {}
  popup.expanded_config = {}
  popup.line_map = {}

  -- Build initial content to determine size
  local lines, highlights = build_lines()

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false

  -- Calculate centered position
  local width = math.floor(vim.o.columns * 0.6)
  local max_height = math.floor(vim.o.lines * 0.8)
  local height = math.min(#lines, max_height)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Open window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " ConveyStatus ",
    title_pos = "center",
  })

  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  popup.bufnr = buf
  popup.winnr = win

  -- Set content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  apply_highlights(buf, highlights)

  -- Keymaps
  local map = require("mapper").map
  local keymap_opts = { buffer = buf, nowait = true }
  map("n", "q", close, keymap_opts)
  map("n", "<Esc>", close, keymap_opts)
  map("n", "<CR>", toggle_expand, keymap_opts)
  map("n", "<LeftMouse>", function()
    -- Let the click position the cursor first, then toggle
    vim.schedule(toggle_expand)
  end, keymap_opts)

  -- Cleanup on window close
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      popup.winnr = nil
      popup.bufnr = nil
      popup.source_bufnr = nil
      popup.line_map = {}
    end,
  })
end

M.close = close

return M
