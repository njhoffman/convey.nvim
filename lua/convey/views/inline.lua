local config = require("convey.config")
local listeners = require("convey.listeners")
local state = require("convey.state")
local utils = require("convey.utils")

local M = {}

local DEFAULT_HL = "ConveyInline"

-- Token incremented on every load/close. Deferred renders compare against it
-- and abort if a newer load or a close has superseded them.
local pending_token = 0

local find_keymap = function(keymaps, action)
  if not keymaps then
    return nil
  end
  -- Nested {global, provider} form: prefer provider, then global
  if keymaps.provider or keymaps.global then
    for _, src in ipairs({ keymaps.provider, keymaps.global }) do
      if type(src) == "table" then
        for key, act in pairs(src) do
          if act == action then
            return key
          end
        end
      end
    end
    return nil
  end
  -- Flat form
  for key, act in pairs(keymaps) do
    if act == action then
      return key
    end
  end
  return nil
end

local make_context = function(provider_name, positions, curr_idx, provider_config)
  local curr_pos = positions[curr_idx] or {}
  local source = curr_pos.source or ""
  local prefix = ""
  if source ~= "" then
    prefix = listeners.get_prefix(source) or ""
  end
  return {
    provider = provider_name,
    curr = tostring(curr_idx),
    total = tostring(#positions),
    prev_key = find_keymap(provider_config.keymaps, "prev") or "?",
    next_key = find_keymap(provider_config.keymaps, "next") or "?",
    source = source,
    prefix = prefix,
    bufname = utils.bufname_for_pos(curr_pos),
  }
end

local substitute = function(text, ctx)
  return (
    text:gsub("{([%w_]+)}", function(key)
      local v = ctx[key]
      if v == nil then
        return "{" .. key .. "}"
      end
      return v
    end)
  )
end

local render_chunks = function(template, ctx)
  local chunks = {}
  for _, segment in ipairs(template or {}) do
    local text = substitute(segment[1] or "", ctx)
    if text ~= "" then
      table.insert(chunks, { text, segment[2] or DEFAULT_HL })
    end
  end
  return chunks
end

local chunks_width = function(chunks)
  local w = 0
  for _, c in ipairs(chunks) do
    w = w + vim.fn.strdisplaywidth(c[1])
  end
  return w
end

local resolve_inline_settings = function(provider_config)
  local global = config.get_view("inline") or {}
  local local_ = (provider_config.views and provider_config.views.inline) or {}
  local pick = function(key, default)
    if local_[key] ~= nil then
      return local_[key]
    end
    if global[key] ~= nil then
      return global[key]
    end
    return default
  end
  return {
    fg = pick("fg", "#ffffff"),
    bg = pick("bg", nil),
    template = pick("template", {}),
    align = pick("align", "eol"),
    padding = pick("padding", 0),
    delay = pick("delay", 100),
  }
end

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

  local settings = resolve_inline_settings(provider_config)

  local hl_opts = { fg = settings.fg }
  if settings.bg ~= nil then
    hl_opts.bg = settings.bg
  end
  vim.api.nvim_set_hl(0, DEFAULT_HL, hl_opts)

  local ctx = make_context(provider_name, positions, curr_idx, provider_config)
  local chunks = render_chunks(settings.template, ctx)
  if #chunks == 0 then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local padding = settings.padding or 0
  local pad_str = padding > 0 and string.rep(" ", padding) or ""

  local extmark_opts = { virt_text = chunks, hl_mode = "combine" }

  if settings.align == "right_align" then
    if pad_str ~= "" then
      table.insert(chunks, { pad_str, DEFAULT_HL })
    end
    extmark_opts.virt_text = chunks
    extmark_opts.virt_text_pos = "right_align"
  elseif settings.align == "textwidth" then
    local tw = vim.bo[bufnr].textwidth
    local fits = false
    if tw > 0 then
      local text_w = chunks_width(chunks)
      local target_col = tw - text_w - padding
      local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
      local line_w = vim.fn.strdisplaywidth(line)
      if target_col > 0 and target_col >= line_w then
        extmark_opts.virt_text = chunks
        extmark_opts.virt_text_win_col = target_col
        fits = true
      end
    end
    if not fits then
      -- Overlap or no textwidth: fall back to eol with leading padding
      if pad_str ~= "" then
        table.insert(chunks, 1, { pad_str, DEFAULT_HL })
      end
      extmark_opts.virt_text = chunks
      extmark_opts.virt_text_pos = "eol"
    end
  else
    -- "eol" (default)
    if pad_str ~= "" then
      table.insert(chunks, 1, { pad_str, DEFAULT_HL })
    end
    extmark_opts.virt_text = chunks
    extmark_opts.virt_text_pos = "eol"
  end

  pending_token = pending_token + 1
  local my_token = pending_token

  local place = function()
    if my_token ~= pending_token then
      return
    end
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    state.inline_extmark_id =
      vim.api.nvim_buf_set_extmark(bufnr, state.inline_ns, row, 0, extmark_opts)
    state.inline_bufnr = bufnr
  end

  local delay = settings.delay or 0
  if delay > 0 then
    vim.defer_fn(place, delay)
  else
    place()
  end
end

M.close = function()
  pending_token = pending_token + 1
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
