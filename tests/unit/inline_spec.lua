describe("convey.views.inline templating", function()
  local inline_view
  local state
  local cfg

  local silent_logger = function()
    return {
      error = function() end,
      warn = function() end,
      info = function() end,
      debug = function() end,
      trace = function() end,
    }
  end

  local reset = function(extra)
    for key, _ in pairs(package.loaded) do
      if key:match("^convey") then
        package.loaded[key] = nil
      end
    end
    cfg = require("convey.config")
    local base = {
      logger = silent_logger(),
      views = { inline = { delay = 0 } },
    }
    local opts = vim.tbl_deep_extend("force", base, extra or {})
    cfg.setup(opts)
    inline_view = require("convey.views.inline")
    state = require("convey.state")
  end

  local get_virt_text = function(bufnr)
    local mark = vim.api.nvim_buf_get_extmark_by_id(
      bufnr,
      state.inline_ns,
      state.inline_extmark_id,
      { details = true }
    )
    return mark[3]
  end

  local make_buf = function(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or { "test line" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    return bufnr
  end

  before_each(function()
    reset()
  end)

  after_each(function()
    if inline_view then
      inline_view.close()
    end
  end)

  describe("token substitution", function()
    it("substitutes core tokens (provider, curr, total, prev_key, next_key)", function()
      reset({ views = { inline = { padding = 0 } } })
      local bufnr = make_buf()
      local positions = {
        { lnum = 1, col = 0, bufnr = bufnr, source = "changes" },
        { lnum = 2, col = 0, bufnr = bufnr, source = "changes" },
      }
      inline_view.load("changes", positions, 1, {
        keymaps = { ["g;"] = "next", ["g,"] = "prev" },
      })
      local vt = get_virt_text(bufnr)
      local text = ""
      for _, c in ipairs(vt.virt_text) do
        text = text .. c[1]
      end
      assert.is_truthy(text:find("changes", 1, true))
      assert.is_truthy(text:find("[1/2]", 1, true))
      assert.is_truthy(text:find("g,", 1, true))
      assert.is_truthy(text:find("g;", 1, true))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("substitutes {source} from current position", function()
      reset({
        views = {
          inline = { padding = 0, template = { { "{source}", "ConveyInline" } } },
        },
      })
      local bufnr = make_buf()
      local positions = {
        { lnum = 1, col = 0, bufnr = bufnr, source = "yanks" },
      }
      inline_view.load("visual", positions, 1, { keymaps = {} })
      local vt = get_virt_text(bufnr)
      assert.are.equal("yanks", vt.virt_text[1][1])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("substitutes {prefix} from listener registry", function()
      reset({
        views = {
          inline = { padding = 0, template = { { "{prefix}", "ConveyInline" } } },
        },
      })
      local listeners = require("convey.listeners")
      local expected_prefix = listeners.get_prefix("yanks")
      assert.is_truthy(expected_prefix and #expected_prefix > 0)

      local bufnr = make_buf()
      local positions = {
        { lnum = 1, col = 0, bufnr = bufnr, source = "yanks" },
      }
      inline_view.load("visual", positions, 1, { keymaps = {} })
      local vt = get_virt_text(bufnr)
      assert.are.equal(expected_prefix, vt.virt_text[1][1])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("substitutes {bufname} via utils.bufname_for_pos", function()
      reset({
        views = {
          inline = { padding = 0, template = { { "{bufname}", "ConveyInline" } } },
        },
      })
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "/tmp/example.txt")
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "x" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "yanks" } }
      inline_view.load("p", positions, 1, { keymaps = {} })
      local vt = get_virt_text(bufnr)
      assert.are.equal("example.txt", vt.virt_text[1][1])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("leaves unknown tokens as literal {token}", function()
      reset({
        views = {
          inline = { padding = 0, template = { { "{unknown}", "ConveyInline" } } },
        },
      })
      local bufnr = make_buf()
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "yanks" } }
      inline_view.load("p", positions, 1, { keymaps = {} })
      local vt = get_virt_text(bufnr)
      assert.are.equal("{unknown}", vt.virt_text[1][1])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("reads keymaps from nested {global,provider} structure", function()
      reset({ views = { inline = { padding = 0 } } })
      local bufnr = make_buf()
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "x" } }
      inline_view.load("p", positions, 1, {
        keymaps = {
          global = { ["<C-o>"] = "next", ["<C-i>"] = "prev" },
          provider = { ["<C-o>"] = "next", ["<C-i>"] = "prev", ["<Esc>"] = "exit" },
        },
      })
      local vt = get_virt_text(bufnr)
      local text = ""
      for _, c in ipairs(vt.virt_text) do
        text = text .. c[1]
      end
      assert.is_truthy(text:find("<C-o>", 1, true))
      assert.is_truthy(text:find("<C-i>", 1, true))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("per-segment highlights", function()
    it("preserves user-supplied highlight groups per chunk", function()
      reset({
        views = {
          inline = {
            padding = 0,
            template = {
              { "{provider}", "Number" },
              { " ", "ConveyInline" },
              { "{curr}", "Constant" },
            },
          },
        },
      })
      local bufnr = make_buf()
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "x" } }
      inline_view.load("p", positions, 1, { keymaps = {} })
      local vt = get_virt_text(bufnr)
      assert.are.equal("Number", vt.virt_text[1][2])
      assert.are.equal("ConveyInline", vt.virt_text[2][2])
      assert.are.equal("Constant", vt.virt_text[3][2])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("alignment modes", function()
    it("eol with padding prepends spaces", function()
      reset({
        views = {
          inline = {
            template = { { "X", "ConveyInline" } },
            align = "eol",
            padding = 3,
          },
        },
      })
      local bufnr = make_buf()
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "x" } }
      inline_view.load("p", positions, 1, { keymaps = {} })
      local vt = get_virt_text(bufnr)
      assert.are.equal("eol", vt.virt_text_pos)
      assert.are.equal("   ", vt.virt_text[1][1])
      assert.are.equal("X", vt.virt_text[2][1])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("right_align uses virt_text_pos=right_align with trailing padding", function()
      reset({
        views = {
          inline = {
            template = { { "X", "ConveyInline" } },
            align = "right_align",
            padding = 4,
          },
        },
      })
      local bufnr = make_buf()
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "x" } }
      inline_view.load("p", positions, 1, { keymaps = {} })
      local vt = get_virt_text(bufnr)
      assert.are.equal("right_align", vt.virt_text_pos)
      assert.are.equal("X", vt.virt_text[1][1])
      assert.are.equal("    ", vt.virt_text[2][1])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("textwidth places virt_text_win_col at tw - width - padding", function()
      reset({
        views = {
          inline = {
            template = { { "ABCDE", "ConveyInline" } },
            align = "textwidth",
            padding = 2,
          },
        },
      })
      local bufnr = make_buf({ "short" })
      vim.bo[bufnr].textwidth = 80
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "x" } }
      inline_view.load("p", positions, 1, { keymaps = {} })
      local vt = get_virt_text(bufnr)
      assert.are.equal(73, vt.virt_text_win_col)
      assert.are.equal("ABCDE", vt.virt_text[1][1])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("textwidth falls back to eol when buffer line would overlap", function()
      reset({
        views = {
          inline = {
            template = { { "ABCDE", "ConveyInline" } },
            align = "textwidth",
            padding = 2,
          },
        },
      })
      local long_line = string.rep("x", 78)
      local bufnr = make_buf({ long_line })
      vim.bo[bufnr].textwidth = 80
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "x" } }
      inline_view.load("p", positions, 1, { keymaps = {} })
      local vt = get_virt_text(bufnr)
      assert.are.equal("eol", vt.virt_text_pos)
      assert.is_nil(vt.virt_text_win_col)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("textwidth falls back to eol when textwidth is 0", function()
      reset({
        views = {
          inline = {
            template = { { "X", "ConveyInline" } },
            align = "textwidth",
            padding = 0,
          },
        },
      })
      local bufnr = make_buf()
      vim.bo[bufnr].textwidth = 0
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "x" } }
      inline_view.load("p", positions, 1, { keymaps = {} })
      local vt = get_virt_text(bufnr)
      assert.are.equal("eol", vt.virt_text_pos)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("background blending", function()
    it("uses hl_mode=combine so cursorline and other line highlights show through", function()
      reset({ views = { inline = { padding = 0 } } })
      local bufnr = make_buf()
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "x" } }
      inline_view.load("p", positions, 1, { keymaps = {} })
      local vt = get_virt_text(bufnr)
      assert.are.equal("combine", vt.hl_mode)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not set bg on ConveyInline when not configured (transparent)", function()
      reset({ views = { inline = { padding = 0, fg = "#abcdef" } } })
      local bufnr = make_buf()
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "x" } }
      inline_view.load("p", positions, 1, { keymaps = {} })
      local hl = vim.api.nvim_get_hl(0, { name = "ConveyInline" })
      assert.is_nil(hl.bg)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("sets bg on ConveyInline when configured", function()
      reset({ views = { inline = { padding = 0, fg = "#abcdef", bg = "#112233" } } })
      local bufnr = make_buf()
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "x" } }
      inline_view.load("p", positions, 1, { keymaps = {} })
      local hl = vim.api.nvim_get_hl(0, { name = "ConveyInline" })
      assert.is_not_nil(hl.bg)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("delay option", function()
    it("delay=0 places extmark synchronously", function()
      reset({ views = { inline = { padding = 0, delay = 0 } } })
      local bufnr = make_buf()
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "x" } }
      inline_view.load("p", positions, 1, { keymaps = {} })
      assert.is_not_nil(state.inline_extmark_id)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("delay>0 defers extmark placement", function()
      reset({ views = { inline = { padding = 0, delay = 50 } } })
      local bufnr = make_buf()
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "x" } }
      inline_view.load("p", positions, 1, { keymaps = {} })
      -- Immediately after load, extmark should not yet be placed
      assert.is_nil(state.inline_extmark_id)
      -- Wait for the deferred call
      vim.wait(200, function()
        return state.inline_extmark_id ~= nil
      end)
      assert.is_not_nil(state.inline_extmark_id)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("a second load before the delay supersedes the first", function()
      reset({ views = { inline = { padding = 0, delay = 30 } } })
      local bufnr = make_buf()
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "first" } }
      inline_view.load("p1", positions, 1, { keymaps = {} })
      -- Immediately replace with a second load
      local positions2 = { { lnum = 1, col = 0, bufnr = bufnr, source = "second" } }
      inline_view.load("p2", positions2, 1, { keymaps = {} })

      vim.wait(200, function()
        return state.inline_extmark_id ~= nil
      end)
      assert.is_not_nil(state.inline_extmark_id)
      local vt = get_virt_text(bufnr)
      local text = ""
      for _, c in ipairs(vt.virt_text) do
        text = text .. c[1]
      end
      assert.is_truthy(text:find("p2", 1, true))
      assert.is_falsy(text:find("p1", 1, true))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("close() before the delay cancels the pending render", function()
      reset({ views = { inline = { padding = 0, delay = 50 } } })
      local bufnr = make_buf()
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "x" } }
      inline_view.load("p", positions, 1, { keymaps = {} })
      inline_view.close()
      vim.wait(200, function()
        return false
      end)
      assert.is_nil(state.inline_extmark_id)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("provider-level override at render", function()
    it("provider align overrides global align in the rendered extmark", function()
      reset({
        views = {
          inline = {
            padding = 0,
            delay = 0,
            align = "eol",
            template = { { "X", "ConveyInline" } },
          },
        },
      })
      local bufnr = make_buf()
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "x" } }
      inline_view.load("p", positions, 1, {
        keymaps = {},
        views = { inline = { align = "right_align" } },
      })
      local vt = get_virt_text(bufnr)
      assert.are.equal("right_align", vt.virt_text_pos)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("provider template overrides global template", function()
      reset({
        views = {
          inline = {
            padding = 0,
            delay = 0,
            template = { { "GLOBAL", "ConveyInline" } },
          },
        },
      })
      local bufnr = make_buf()
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "x" } }
      inline_view.load("p", positions, 1, {
        keymaps = {},
        views = { inline = { template = { { "PROVIDER", "ConveyInline" } } } },
      })
      local vt = get_virt_text(bufnr)
      assert.are.equal("PROVIDER", vt.virt_text[1][1])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("provider padding overrides global padding", function()
      reset({
        views = {
          inline = {
            delay = 0,
            padding = 2,
            template = { { "X", "ConveyInline" } },
          },
        },
      })
      local bufnr = make_buf()
      local positions = { { lnum = 1, col = 0, bufnr = bufnr, source = "x" } }
      inline_view.load("p", positions, 1, {
        keymaps = {},
        views = { inline = { padding = 5 } },
      })
      local vt = get_virt_text(bufnr)
      -- 5-space padding chunk, then "X"
      assert.are.equal("     ", vt.virt_text[1][1])
      assert.are.equal("X", vt.virt_text[2][1])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("default config", function()
    it("default template preserves the original output shape", function()
      local view = cfg.get_view("inline")
      assert.are.equal("eol", view.align)
      assert.are.equal(2, view.padding)
      assert.is_table(view.template)
      assert.is_truthy(#view.template > 0)
      assert.is_truthy(view.template[1][1]:find("{provider}", 1, true))
    end)

    it("provider-level inline overrides global settings", function()
      cfg.setup({
        providers = {
          changes = {
            views = { inline = { align = "right_align", padding = 5 } },
          },
        },
      })
      local p = cfg.get_provider("changes")
      assert.are.equal("right_align", p.views.inline.align)
      assert.are.equal(5, p.views.inline.padding)
    end)
  end)
end)
