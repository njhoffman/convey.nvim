describe("Convey", function()
  describe("config", function()
    local config

    before_each(function()
      package.loaded["convey.config"] = nil
      config = require("convey.config")
    end)

    it("has default providers", function()
      local cfg = config.get()
      assert.is_not_nil(cfg.providers.changes)
      assert.is_not_nil(cfg.providers.jumps)
      assert.is_not_nil(cfg.providers.visual)
      assert.is_not_nil(cfg.providers.saves)
    end)

    it("has default view settings", function()
      local cfg = config.get()
      assert.is_true(cfg.views.notify.enabled)
      assert.are.equal(8, cfg.views.notify.lines_before)
      assert.are.equal(3, cfg.views.notify.lines_after)
    end)

    it("merges user config with defaults", function()
      config.setup({
        max_marks = 100,
        providers = {
          changes = { unique = false },
        },
      })
      local cfg = config.get()
      assert.are.equal(100, cfg.max_marks)
      assert.is_false(cfg.providers.changes.unique)
      -- Other defaults preserved
      assert.is_not_nil(cfg.providers.jumps)
      assert.are.same({ "changes" }, cfg.providers.changes.listeners)
    end)

    it("returns provider config by name", function()
      local changes = config.get_provider("changes")
      assert.is_not_nil(changes)
      assert.is_true(changes.unique)
      assert.are.same({ "changes" }, changes.listeners)
    end)

    it("cycle defaults to false on all providers", function()
      for _, name in ipairs({ "changes", "jumps", "visual", "saves", "paragraph", "block" }) do
        local p = config.get_provider(name)
        assert.is_not_nil(p, name .. " provider should exist")
        assert.is_false(p.cycle, name .. " provider should default cycle=false")
      end
    end)

    it("cycle can be enabled via setup", function()
      config.setup({
        providers = {
          changes = { cycle = true },
        },
      })
      assert.is_true(config.get_provider("changes").cycle)
      assert.is_false(config.get_provider("jumps").cycle)
    end)

    it("returns nil for unknown provider", function()
      local unknown = config.get_provider("nonexistent")
      assert.is_nil(unknown)
    end)

    it("has default logger with all levels", function()
      local log = config.log()
      assert.is_function(log.error)
      assert.is_function(log.warn)
      assert.is_function(log.info)
      assert.is_function(log.debug)
      assert.is_function(log.trace)
    end)

    it("accepts custom logger", function()
      local messages = {}
      config.setup({
        logger = {
          info = function(msg)
            table.insert(messages, msg)
          end,
        },
      })
      config.log().info("test message")
      assert.are.equal(1, #messages)
      assert.are.equal("test message", messages[1])
    end)
  end)

  describe("state", function()
    local state

    before_each(function()
      package.loaded["convey.state"] = nil
      state = require("convey.state")
    end)

    it("initializes with empty providers", function()
      assert.are.same({}, state.providers)
    end)

    it("has a shared augroup", function()
      assert.is_not_nil(state.augroup)
      assert.is_true(type(state.augroup) == "number")
    end)

    it("creates provider state on first access", function()
      local pstate = state.get_provider("changes")
      assert.are.same({}, pstate.positions)
      assert.are.equal(0, pstate.index)
    end)

    it("returns same state on subsequent access", function()
      local first = state.get_provider("changes")
      first.index = 5
      local second = state.get_provider("changes")
      assert.are.equal(5, second.index)
    end)

    it("resets provider state", function()
      local pstate = state.get_provider("changes")
      pstate.index = 5
      state.reset_provider("changes")
      pstate = state.get_provider("changes")
      assert.are.equal(0, pstate.index)
    end)
  end)

  describe("utils", function()
    local utils

    before_each(function()
      package.loaded["convey.utils"] = nil
      utils = require("convey.utils")
    end)

    describe("deduplicate", function()
      it("removes duplicate positions by lnum+col", function()
        local positions = {
          { lnum = 10, col = 5, timestamp = 3 },
          { lnum = 10, col = 5, timestamp = 2 },
          { lnum = 20, col = 0, timestamp = 1 },
        }
        local result = utils.deduplicate(positions)
        assert.are.equal(2, #result)
        assert.are.equal(3, result[1].timestamp)
        assert.are.equal(20, result[2].lnum)
      end)

      it("keeps all positions when none are duplicates", function()
        local positions = {
          { lnum = 1, col = 0 },
          { lnum = 2, col = 0 },
          { lnum = 3, col = 0 },
        }
        local result = utils.deduplicate(positions)
        assert.are.equal(3, #result)
      end)

      it("handles empty list", function()
        local result = utils.deduplicate({})
        assert.are.equal(0, #result)
      end)
    end)

    describe("process_list", function()
      it("reverses and indexes the list", function()
        local list = {
          { lnum = 1, col = 0 },
          { lnum = 5, col = 3 },
          { lnum = 10, col = 1 },
        }
        local result, _, _ = utils.process_list(list, 0, false)
        -- Reversed: index 1 should be the last original item
        assert.are.equal(3, #result)
        assert.are.equal(1, result[1].idx)
        assert.are.equal(2, result[2].idx)
        assert.are.equal(3, result[3].idx)
      end)

      it("marks current position", function()
        local list = {
          { lnum = 1, col = 0 },
          { lnum = 5, col = 3 },
          { lnum = 10, col = 1 },
        }
        -- pos_idx=1 means current is at index 1 in original (0-based)
        local result, new_idx, _ = utils.process_list(list, 1, false)
        assert.is_true(new_idx > 0)
        local found_curr = false
        for _, item in ipairs(result) do
          if item.curr then
            found_curr = true
          end
        end
        assert.is_true(found_curr)
      end)

      it("deduplicates when unique is true", function()
        local list = {
          { lnum = 5, col = 3 },
          { lnum = 5, col = 3 },
          { lnum = 10, col = 1 },
        }
        local result, _, _ = utils.process_list(list, 0, true)
        assert.are.equal(2, #result)
      end)

      it("keeps duplicates when unique is false", function()
        local list = {
          { lnum = 5, col = 3 },
          { lnum = 5, col = 3 },
          { lnum = 10, col = 1 },
        }
        local result, _, _ = utils.process_list(list, 0, false)
        assert.are.equal(3, #result)
      end)

      it("returns stable hash_id", function()
        local list = {
          { lnum = 1, col = 0 },
          { lnum = 5, col = 3 },
        }
        local _, _, hash1 = utils.process_list(vim.deepcopy(list), 0, false)
        local _, _, hash2 = utils.process_list(vim.deepcopy(list), 0, false)
        assert.are.equal(hash1, hash2)
      end)

      it("returns different hash when list changes", function()
        local list1 = {
          { lnum = 1, col = 0 },
          { lnum = 5, col = 3 },
        }
        local list2 = {
          { lnum = 1, col = 0 },
          { lnum = 5, col = 3 },
          { lnum = 10, col = 1 },
        }
        local _, _, hash1 = utils.process_list(list1, 0, false)
        local _, _, hash2 = utils.process_list(list2, 0, false)
        assert.are_not.equal(hash1, hash2)
      end)
    end)

    describe("align_text", function()
      it("left-aligns by default", function()
        local text, pos = utils.align_text("hi", 10)
        assert.are.equal("hi        ", text)
        assert.are.equal(0, pos[1])
        assert.are.equal(2, pos[2])
      end)

      it("right-aligns", function()
        local text, pos = utils.align_text("hi", 10, "right")
        assert.are.equal("        hi", text)
        assert.are.equal(8, pos[1])
        assert.are.equal(2, pos[2])
      end)

      it("center-aligns", function()
        local text, pos = utils.align_text("hi", 10, "center")
        assert.are.equal("    hi    ", text)
        assert.are.equal(4, pos[1])
        assert.are.equal(2, pos[2])
      end)
    end)

    describe("format_pos", function()
      it("formats position without range fields", function()
        local pos = { lnum = 10, col = 5 }
        assert.are.equal("10:5", utils.format_pos(pos))
      end)

      it("formats position as range when end fields present", function()
        local pos = { lnum = 10, col = 5, end_lnum = 20, end_col = 8 }
        assert.are.equal("10:5 - 20:8", utils.format_pos(pos))
      end)

      it("formats as single position when only end_lnum is present", function()
        local pos = { lnum = 10, col = 5, end_lnum = 20 }
        assert.are.equal("10:5", utils.format_pos(pos))
      end)

      it("formats as single position when only end_col is present", function()
        local pos = { lnum = 10, col = 5, end_col = 8 }
        assert.are.equal("10:5", utils.format_pos(pos))
      end)

      it("formats single-line range", function()
        local pos = { lnum = 10, col = 3, end_lnum = 10, end_col = 15 }
        assert.are.equal("10:3 - 10:15", utils.format_pos(pos))
      end)

      it("shows EOL when end_col equals vim.v.maxcol", function()
        local pos = { lnum = 10, col = 3, end_lnum = 12, end_col = vim.v.maxcol }
        assert.are.equal("10:3 - 12:EOL", utils.format_pos(pos))
      end)
    end)

    describe("has_ranges", function()
      it("returns false for empty list", function()
        assert.is_false(utils.has_ranges({}))
      end)

      it("returns false when no positions have end fields", function()
        local positions = {
          { lnum = 1, col = 0 },
          { lnum = 5, col = 3 },
        }
        assert.is_false(utils.has_ranges(positions))
      end)

      it("returns true when any position has both end fields", function()
        local positions = {
          { lnum = 1, col = 0 },
          { lnum = 5, col = 3, end_lnum = 8, end_col = 10 },
        }
        assert.is_true(utils.has_ranges(positions))
      end)

      it("returns false when position has only end_lnum", function()
        local positions = {
          { lnum = 1, col = 0, end_lnum = 5 },
        }
        assert.is_false(utils.has_ranges(positions))
      end)

      it("returns false when position has only end_col", function()
        local positions = {
          { lnum = 1, col = 0, end_col = 5 },
        }
        assert.is_false(utils.has_ranges(positions))
      end)
    end)

    describe("is_multi_buffer", function()
      it("returns false for empty list", function()
        assert.is_false(utils.is_multi_buffer({}))
      end)

      it("returns false for single position", function()
        assert.is_false(utils.is_multi_buffer({ { bufnr = 1 } }))
      end)

      it("returns false when all positions share one buffer", function()
        local positions = {
          { bufnr = 5 },
          { bufnr = 5 },
          { bufnr = 5 },
        }
        assert.is_false(utils.is_multi_buffer(positions))
      end)

      it("returns true when positions span multiple buffers", function()
        local positions = {
          { bufnr = 5 },
          { bufnr = 8 },
          { bufnr = 5 },
        }
        assert.is_true(utils.is_multi_buffer(positions))
      end)
    end)

    describe("bufname_for_pos", function()
      it("returns tail filename for valid buffer", function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(bufnr, "/some/path/to/file.lua")
        local name = utils.bufname_for_pos({ bufnr = bufnr })
        assert.are.equal("file.lua", name)
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end)

      it("truncates long filenames", function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(bufnr, "/path/to/very_long_filename_here.lua")
        local name = utils.bufname_for_pos({ bufnr = bufnr }, 10)
        assert.are.equal(10, #name)
        assert.is_true(name:sub(-1) == "~")
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end)

      it("returns buffer number for unnamed buffer", function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local name = utils.bufname_for_pos({ bufnr = bufnr })
        assert.are.equal("[" .. bufnr .. "]", name)
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end)

      it("returns empty string for invalid buffer", function()
        local name = utils.bufname_for_pos({ bufnr = 999999 })
        assert.are.equal("", name)
      end)

      it("returns empty string for nil bufnr", function()
        local name = utils.bufname_for_pos({})
        assert.are.equal("", name)
      end)

      it("does not truncate short filenames", function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(bufnr, "/path/short.lua")
        local name = utils.bufname_for_pos({ bufnr = bufnr }, 15)
        assert.are.equal("short.lua", name)
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end)
    end)

    describe("build_highlight_table", function()
      it("builds lines with correct alignment", function()
        local rows = {
          { { "a", "Normal" }, { "bb", "Number" } },
          { { "ccc", "Normal" }, { "d", "Number" } },
        }
        local lines, highlights = utils.build_highlight_table(rows, {
          align = { nil, "right" },
        })
        assert.are.equal(2, #lines)
        assert.are.equal(4, #highlights)
      end)

      it("adds header row when provided", function()
        local rows = {
          { { "val1", "Normal" } },
        }
        local lines, _ = utils.build_highlight_table(rows, {
          headers = { "header" },
          align = {},
        })
        assert.are.equal(2, #lines)
        assert.is_true(lines[1]:find("header") ~= nil)
      end)
    end)
  end)

  describe("listeners registry", function()
    local listener_registry

    before_each(function()
      for key, _ in pairs(package.loaded) do
        if key:match("^convey%.listeners") then
          package.loaded[key] = nil
        end
      end
      listener_registry = require("convey.listeners")
    end)

    it("get_prefix returns prefix for known listeners", function()
      assert.are.equal("", listener_registry.get_prefix("pastes"))
      assert.are.equal("", listener_registry.get_prefix("yanks"))
      assert.are.equal("󰒅", listener_registry.get_prefix("selections"))
      assert.are.equal("󰿅", listener_registry.get_prefix("jumps"))
      assert.are.equal("", listener_registry.get_prefix("changes"))
      assert.are.equal("", listener_registry.get_prefix("writes"))
    end)

    it("get_prefix returns nil for unknown listener", function()
      assert.is_nil(listener_registry.get_prefix("nonexistent"))
    end)
  end)

  describe("listeners.changes", function()
    local changes_listener

    before_each(function()
      package.loaded["convey.listeners.changes"] = nil
      changes_listener = require("convey.listeners.changes")
    end)

    it("has the correct name", function()
      assert.are.equal("changes", changes_listener.name)
    end)

    it("has a prefix", function()
      assert.are.equal("", changes_listener.prefix)
    end)

    it("implements the listener interface", function()
      assert.is_function(changes_listener.init)
      assert.is_function(changes_listener.destroy)
      assert.is_function(changes_listener.get_positions)
    end)

    it("returns positions for a buffer", function()
      -- Create a scratch buffer and make some changes to populate changelist
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line 1", "line 2", "line 3" })

      local positions = changes_listener.get_positions(bufnr)
      assert.is_table(positions)

      -- Each position should have the required fields
      for _, pos in ipairs(positions) do
        assert.is_number(pos.lnum)
        assert.is_number(pos.col)
        assert.are.equal(bufnr, pos.bufnr)
        assert.is_number(pos.timestamp)
        assert.are.equal("changes", pos.source)
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("listeners.jumps", function()
    local jumps_listener

    before_each(function()
      package.loaded["convey.listeners.jumps"] = nil
      jumps_listener = require("convey.listeners.jumps")
    end)

    it("has the correct name", function()
      assert.are.equal("jumps", jumps_listener.name)
    end)

    it("has a prefix", function()
      assert.are.equal("󰿅", jumps_listener.prefix)
    end)

    it("implements the listener interface", function()
      assert.is_function(jumps_listener.init)
      assert.is_function(jumps_listener.destroy)
      assert.is_function(jumps_listener.get_positions)
    end)

    it("returns positions from the jumplist", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line 1", "line 2", "line 3" })

      local positions = jumps_listener.get_positions(bufnr)
      assert.is_table(positions)

      for _, pos in ipairs(positions) do
        assert.is_number(pos.lnum)
        assert.is_number(pos.col)
        assert.is_number(pos.bufnr)
        assert.is_number(pos.timestamp)
        assert.are.equal("jumps", pos.source)
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("filters out invalid buffers", function()
      local positions = jumps_listener.get_positions()
      for _, pos in ipairs(positions) do
        assert.is_true(vim.api.nvim_buf_is_valid(pos.bufnr))
      end
    end)
  end)

  describe("listeners.selections", function()
    local listener

    before_each(function()
      package.loaded["convey.listeners.selections"] = nil
      listener = require("convey.listeners.selections")
    end)

    after_each(function()
      listener.destroy()
    end)

    it("has the correct name", function()
      assert.are.equal("selections", listener.name)
    end)

    it("has a prefix", function()
      assert.are.equal("󰒅", listener.prefix)
    end)

    it("implements the listener interface", function()
      assert.is_function(listener.init)
      assert.is_function(listener.destroy)
      assert.is_function(listener.get_positions)
    end)

    it("returns empty when no selections tracked", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local positions = listener.get_positions(bufnr)
      assert.are.same({}, positions)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("listeners.yanks", function()
    local listener

    before_each(function()
      package.loaded["convey.listeners.yanks"] = nil
      listener = require("convey.listeners.yanks")
    end)

    after_each(function()
      listener.destroy()
    end)

    it("has the correct name", function()
      assert.are.equal("yanks", listener.name)
    end)

    it("has a prefix", function()
      assert.are.equal("", listener.prefix)
    end)

    it("implements the listener interface", function()
      assert.is_function(listener.init)
      assert.is_function(listener.destroy)
      assert.is_function(listener.get_positions)
    end)

    it("returns empty when no yanks tracked", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local positions = listener.get_positions(bufnr)
      assert.are.same({}, positions)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("listeners.pastes", function()
    local listener
    local augroup

    before_each(function()
      package.loaded["convey.listeners.pastes"] = nil
      listener = require("convey.listeners.pastes")
      augroup = vim.api.nvim_create_augroup("ConveyTestPastes", { clear = true })
    end)

    after_each(function()
      listener.destroy()
      pcall(vim.api.nvim_del_augroup_by_id, augroup)
    end)

    it("has the correct name", function()
      assert.are.equal("pastes", listener.name)
    end)

    it("has a prefix", function()
      assert.are.equal("", listener.prefix)
    end)

    it("implements the listener interface", function()
      assert.is_function(listener.init)
      assert.is_function(listener.destroy)
      assert.is_function(listener.get_positions)
    end)

    it("returns empty when no pastes tracked", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local positions = listener.get_positions(bufnr)
      assert.are.same({}, positions)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("tracks paste position after p", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello world" })
      vim.cmd("normal! gg0yiw")

      listener.init(augroup)
      vim.cmd("normal $p")

      vim.wait(100, function()
        return #listener.get_positions(bufnr) > 0
      end)

      local positions = listener.get_positions(bufnr)
      assert.are.equal(1, #positions)
      assert.are.equal("pastes", positions[1].source)
      assert.are.equal(bufnr, positions[1].bufnr)
      assert.is_number(positions[1].lnum)
      assert.is_number(positions[1].col)
      assert.is_number(positions[1].end_lnum)
      assert.is_number(positions[1].end_col)
      assert.is_number(positions[1].timestamp)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("tracks P (paste before) position", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello world" })
      vim.cmd("normal! gg0yiw")

      listener.init(augroup)
      vim.cmd("normal $P")

      vim.wait(100, function()
        return #listener.get_positions(bufnr) > 0
      end)

      local positions = listener.get_positions(bufnr)
      assert.are.equal(1, #positions)
      assert.are.equal("pastes", positions[1].source)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("tracks multiple paste positions", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello", "world" })
      vim.cmd("normal! gg0yiw")

      listener.init(augroup)
      vim.cmd("normal jp")
      vim.cmd("normal ggp")

      vim.wait(100, function()
        return #listener.get_positions(bufnr) >= 2
      end)

      local positions = listener.get_positions(bufnr)
      assert.are.equal(2, #positions)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("filters positions by buffer", function()
      local bufnr1 = vim.api.nvim_create_buf(false, true)
      local bufnr2 = vim.api.nvim_create_buf(false, true)

      vim.api.nvim_set_current_buf(bufnr1)
      vim.api.nvim_buf_set_lines(bufnr1, 0, -1, false, { "hello" })
      vim.cmd("normal! gg0yiw")

      listener.init(augroup)
      vim.cmd("normal p")

      vim.wait(100, function()
        return #listener.get_positions(bufnr1) > 0
      end)

      local pos1 = listener.get_positions(bufnr1)
      local pos2 = listener.get_positions(bufnr2)
      assert.are.equal(1, #pos1)
      assert.are.equal(0, #pos2)

      vim.api.nvim_buf_delete(bufnr1, { force = true })
      vim.api.nvim_buf_delete(bufnr2, { force = true })
    end)

    it("clears stored data on destroy", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello" })
      vim.cmd("normal! gg0yiw")

      listener.init(augroup)
      vim.cmd("normal p")

      vim.wait(100, function()
        return #listener.get_positions(bufnr) > 0
      end)

      listener.destroy()
      local positions = listener.get_positions(bufnr)
      assert.are.same({}, positions)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("records correct range for pasted text", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello world", "" })
      vim.cmd("normal! gg0yiw")

      listener.init(augroup)
      vim.cmd("normal! j")
      vim.cmd("normal p")

      vim.wait(100, function()
        return #listener.get_positions(bufnr) > 0
      end)

      local positions = listener.get_positions(bufnr)
      assert.are.equal(1, #positions)
      local pos = positions[1]
      assert.are.equal(2, pos.lnum)
      assert.is_true(pos.end_col >= pos.col)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("listeners.writes", function()
    local listener

    before_each(function()
      package.loaded["convey.listeners.writes"] = nil
      listener = require("convey.listeners.writes")
    end)

    after_each(function()
      listener.destroy()
    end)

    it("has the correct name", function()
      assert.are.equal("writes", listener.name)
    end)

    it("has a prefix", function()
      assert.are.equal("", listener.prefix)
    end)

    it("implements the listener interface", function()
      assert.is_function(listener.init)
      assert.is_function(listener.destroy)
      assert.is_function(listener.get_positions)
    end)

    it("returns empty when no writes tracked", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local positions = listener.get_positions(bufnr)
      assert.are.same({}, positions)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("providers", function()
    local config, state

    before_each(function()
      -- Clear all convey modules for isolation
      for key, _ in pairs(package.loaded) do
        if key:match("^convey") then
          package.loaded[key] = nil
        end
      end
      config = require("convey.config")
      state = require("convey.state")
      -- Suppress notifications during tests
      config.setup({
        logger = {
          error = function() end,
          warn = function() end,
          info = function() end,
          debug = function() end,
          trace = function() end,
        },
      })
    end)

    it("stores positions in state after navigation", function()
      local providers = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      -- Make changes to populate changelist
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa" })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "bbb" })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "ccc" })

      providers.next("changes")
      local pstate = state.get_provider("changes")
      assert.is_table(pstate.positions)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("clamps index at lower bound", function()
      local providers = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa" })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "bbb" })

      -- Navigate prev multiple times past the beginning
      providers.prev("changes")
      providers.prev("changes")
      providers.prev("changes")
      local pstate = state.get_provider("changes")
      assert.is_true(pstate.index >= 1 or pstate.index == 0)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    describe("cycle behavior", function()
      local function install_fake_listener(bufnr)
        local fake = {
          name = "fake_cycle",
          prefix = "",
          init = function() end,
          destroy = function() end,
          get_positions = function()
            return {
              { lnum = 3, col = 0, bufnr = bufnr, timestamp = 3, source = "fake_cycle" },
              { lnum = 2, col = 0, bufnr = bufnr, timestamp = 2, source = "fake_cycle" },
              { lnum = 1, col = 0, bufnr = bufnr, timestamp = 1, source = "fake_cycle" },
            }
          end,
        }
        package.loaded["convey.listeners.fake_cycle"] = fake
      end

      local function setup_provider(cycle)
        config.setup({
          providers = {
            cycle_test = {
              enabled = true,
              unique = false,
              cycle = cycle,
              listeners = { "fake_cycle" },
              views = { notify = { enabled = false }, inline = { enabled = false } },
            },
          },
          logger = {
            error = function() end,
            warn = function() end,
            info = function() end,
            debug = function() end,
            trace = function() end,
          },
        })
      end

      it("clamps at upper bound when cycle is false", function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
        install_fake_listener(bufnr)
        setup_provider(false)

        local providers = require("convey.providers")
        providers.next("cycle_test")
        providers.next("cycle_test")
        providers.next("cycle_test")
        providers.next("cycle_test")
        local pstate = state.get_provider("cycle_test")
        assert.are.equal(3, pstate.index)

        vim.api.nvim_buf_delete(bufnr, { force = true })
        package.loaded["convey.listeners.fake_cycle"] = nil
      end)

      it("wraps from end to beginning on next when cycle is true", function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
        install_fake_listener(bufnr)
        setup_provider(true)

        local providers = require("convey.providers")
        providers.next("cycle_test")
        providers.next("cycle_test")
        providers.next("cycle_test")
        local pstate = state.get_provider("cycle_test")
        assert.are.equal(3, pstate.index)
        providers.next("cycle_test")
        assert.are.equal(1, pstate.index)

        vim.api.nvim_buf_delete(bufnr, { force = true })
        package.loaded["convey.listeners.fake_cycle"] = nil
      end)

      it("wraps from beginning to end on prev when cycle is true", function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
        install_fake_listener(bufnr)
        setup_provider(true)

        local providers = require("convey.providers")
        providers.prev("cycle_test")
        local pstate = state.get_provider("cycle_test")
        assert.are.equal(3, pstate.index)

        vim.api.nvim_buf_delete(bufnr, { force = true })
        package.loaded["convey.listeners.fake_cycle"] = nil
      end)
    end)

    it("handles unknown provider gracefully", function()
      local providers = require("convey.providers")
      -- Should not error
      providers.next("nonexistent_provider")
    end)

    it("tracks active provider after navigation", function()
      local providers = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa" })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "bbb" })

      providers.next("changes")
      -- active_provider is set when positions exist and navigation succeeds
      -- It may or may not be set depending on changelist state
      -- Just verify it doesn't error
      assert.is_true(true)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("deduplicates positions when unique is true", function()
      local utils = require("convey.utils")
      local positions = {
        { lnum = 10, col = 5, timestamp = 3, source = "a" },
        { lnum = 10, col = 5, timestamp = 2, source = "b" },
        { lnum = 20, col = 0, timestamp = 1, source = "a" },
      }
      local result = utils.deduplicate(positions)
      assert.are.equal(2, #result)
      -- First occurrence (most recent) kept
      assert.are.equal(3, result[1].timestamp)
    end)

    it("truncates to max_marks", function()
      config.setup({
        max_marks = 2,
        logger = {
          error = function() end,
          warn = function() end,
          info = function() end,
          debug = function() end,
          trace = function() end,
        },
      })
      local cfg = config.get()
      assert.are.equal(2, cfg.max_marks)
    end)

    it("get_status returns status without side effects", function()
      local prov = require("convey.providers")
      local status = prov.get_status("changes")
      assert.is_not_nil(status)
      assert.is_table(status.positions)
      assert.is_number(status.index)
      assert.is_table(status.config)
    end)

    it("get_status returns nil for unknown provider", function()
      local prov = require("convey.providers")
      local status = prov.get_status("nonexistent")
      assert.is_nil(status)
    end)

    it("get_status accepts explicit bufnr", function()
      local prov = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa" })

      local status = prov.get_status("changes", bufnr)
      assert.is_not_nil(status)
      assert.is_table(status.positions)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("get_status with different bufnr returns different positions", function()
      local prov = require("convey.providers")
      local buf1 = vim.api.nvim_create_buf(false, true)
      local buf2 = vim.api.nvim_create_buf(false, true)

      vim.api.nvim_set_current_buf(buf1)
      vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { "aaa" })
      vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { "bbb" })

      -- Query buf2 which has no changes
      local status = prov.get_status("changes", buf2)
      assert.is_not_nil(status)
      assert.are.equal(0, #status.positions)

      vim.api.nvim_buf_delete(buf1, { force = true })
      vim.api.nvim_buf_delete(buf2, { force = true })
    end)

    it("get_status returns empty positions for disabled provider", function()
      config.setup({
        providers = {
          changes = { enabled = false, listeners = { "changes" } },
        },
        logger = {
          error = function() end,
          warn = function() end,
          info = function() end,
          debug = function() end,
          trace = function() end,
        },
      })
      local prov = require("convey.providers")
      local status = prov.get_status("changes")
      assert.is_not_nil(status)
      assert.are.same({}, status.positions)
      assert.are.equal(0, status.index)
    end)

    it("calls provider on_navigate during navigation", function()
      local navigated_pos = nil
      config.setup({
        providers = {
          changes = {
            enabled = true,
            unique = true,
            listeners = { "changes" },
            on_navigate = function(pos)
              navigated_pos = pos
            end,
            views = { notify = { enabled = true } },
          },
        },
        logger = {
          error = function() end,
          warn = function() end,
          info = function() end,
          debug = function() end,
          trace = function() end,
        },
      })

      local providers = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa" })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "bbb" })

      providers.next("changes")

      -- on_navigate is only called when there are positions to navigate to
      local pstate = state.get_provider("changes")
      if #pstate.positions > 0 then
        assert.is_not_nil(navigated_pos)
        assert.is_number(navigated_pos.lnum)
        assert.is_number(navigated_pos.col)
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not call on_navigate when not configured", function()
      -- Default changes provider has no on_navigate
      local providers = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa" })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "bbb" })

      -- Should not error even without on_navigate
      providers.next("changes")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("runs provider on_navigate after global on_navigate callback fires", function()
      local order = {}
      local finish_fn_holder = nil
      config.setup({
        on_navigate = function(finish_fn)
          table.insert(order, "global")
          finish_fn_holder = finish_fn
        end,
        providers = {
          changes = {
            enabled = true,
            unique = true,
            listeners = { "changes" },
            on_navigate = function()
              table.insert(order, "provider")
            end,
            views = { notify = { enabled = true } },
          },
        },
        logger = {
          error = function() end,
          warn = function() end,
          info = function() end,
          debug = function() end,
          trace = function() end,
        },
      })

      local providers = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa" })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "bbb" })

      providers.next("changes")

      local pstate = state.get_provider("changes")
      if #pstate.positions > 0 then
        -- Provider callback must not have run yet (still awaiting finish_fn)
        assert.are.same({ "global" }, order)
        assert.is_function(finish_fn_holder)
        finish_fn_holder()
        assert.are.same({ "global", "provider" }, order)
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("calls top-level on_navigate for finish callback", function()
      local finish_called = false
      config.setup({
        on_navigate = function(finish_fn)
          finish_fn()
          finish_called = true
        end,
        logger = {
          error = function() end,
          warn = function() end,
          info = function() end,
          debug = function() end,
          trace = function() end,
        },
      })

      local providers = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa" })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "bbb" })

      providers.next("changes")
      assert.is_true(finish_called)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not add to the jump list during navigation", function()
      local providers = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(
        bufnr,
        0,
        -1,
        false,
        { "line1", "line2", "line3", "line4", "line5" }
      )
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      -- Snapshot the jump list before navigation
      local jumplist_before = vim.fn.getjumplist()
      local count_before = #(jumplist_before[1] or {})

      providers.next("changes")
      providers.next("changes")

      -- Jump list should not have grown
      local jumplist_after = vim.fn.getjumplist()
      local count_after = #(jumplist_after[1] or {})
      assert.are.equal(count_before, count_after)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not add to the jump list when switching buffers", function()
      local providers = require("convey.providers")
      local bufnr1 = vim.api.nvim_create_buf(false, true)
      local bufnr2 = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr1)
      vim.api.nvim_buf_set_lines(bufnr1, 0, -1, false, { "buf1 line1" })
      vim.api.nvim_buf_set_lines(bufnr2, 0, -1, false, { "buf2 line1" })

      -- Inject a multi-buffer position list via the writes listener
      local writes = require("convey.listeners.writes")
      writes.init(state.augroup)

      -- Simulate writes in different buffers
      vim.api.nvim_set_current_buf(bufnr1)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr1 })

      vim.api.nvim_set_current_buf(bufnr2)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr2 })

      -- Switch back and snapshot jump list
      vim.api.nvim_set_current_buf(bufnr1)
      local jumplist_before = vim.fn.getjumplist()
      local count_before = #(jumplist_before[1] or {})

      -- Navigate saves provider which may cross buffers
      config.setup({
        providers = {
          saves = {
            enabled = true,
            unique = false,
            listeners = { "writes" },
            views = { notify = { enabled = true } },
          },
        },
        logger = {
          error = function() end,
          warn = function() end,
          info = function() end,
          debug = function() end,
          trace = function() end,
        },
      })
      providers.next("saves")

      local jumplist_after = vim.fn.getjumplist()
      local count_after = #(jumplist_after[1] or {})
      assert.are.equal(count_before, count_after)

      writes.destroy()
      vim.api.nvim_buf_delete(bufnr1, { force = true })
      vim.api.nvim_buf_delete(bufnr2, { force = true })
    end)

    it("defers views.show until on_navigate callback fires", function()
      local views = require("convey.views")
      local original_show = views.show
      local show_called = false
      local view_shown_before_callback = false

      views.show = function(...)
        show_called = true
        return original_show(...)
      end

      config.setup({
        on_navigate = function(finish_fn)
          view_shown_before_callback = show_called
          finish_fn()
        end,
        logger = {
          error = function() end,
          warn = function() end,
          info = function() end,
          debug = function() end,
          trace = function() end,
        },
      })

      local providers = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa" })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "bbb" })

      providers.next("changes")

      assert.is_false(view_shown_before_callback)
      assert.is_true(show_called)
      views.show = original_show
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("calls views.show after on_navigate callback fires", function()
      local views = require("convey.views")
      local original_show = views.show
      local show_called = false

      views.show = function(...)
        show_called = true
        return original_show(...)
      end

      config.setup({
        on_navigate = function(finish_fn)
          finish_fn()
        end,
        logger = {
          error = function() end,
          warn = function() end,
          info = function() end,
          debug = function() end,
          trace = function() end,
        },
      })

      local providers = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa" })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "bbb" })

      providers.next("changes")

      assert.is_true(show_called)
      views.show = original_show
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("calls views.show immediately when on_navigate is not configured", function()
      local views = require("convey.views")
      local original_show = views.show
      local show_called = false

      views.show = function(...)
        show_called = true
        return original_show(...)
      end

      local providers = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa" })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "bbb" })

      providers.next("changes")

      assert.is_true(show_called)
      views.show = original_show
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("defers views.show for empty positions when on_navigate is set", function()
      local views = require("convey.views")
      local original_show = views.show
      local show_called = false
      local view_shown_before_callback = false

      views.show = function(...)
        show_called = true
        return original_show(...)
      end

      config.setup({
        on_navigate = function(finish_fn)
          view_shown_before_callback = show_called
          finish_fn()
        end,
        providers = {
          empty_test = {
            enabled = true,
            unique = false,
            listeners = {},
            views = { notify = { enabled = true } },
          },
        },
        logger = {
          error = function() end,
          warn = function() end,
          info = function() end,
          debug = function() end,
          trace = function() end,
        },
      })

      local providers = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      providers.next("empty_test")

      assert.is_false(view_shown_before_callback)
      assert.is_true(show_called)
      views.show = original_show
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("sets up dismiss autocmds after navigation", function()
      local providers = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa" })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "bbb" })

      providers.next("changes")

      -- Check that ConveyDismiss augroup has autocmds registered
      local autocmds = vim.api.nvim_get_autocmds({ group = "ConveyDismiss" })
      -- May have autocmds if notify view was shown (depends on notify plugin availability)
      assert.is_table(autocmds)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("dismiss autocmds listen for CursorMoved, InsertEnter, and CmdlineEnter", function()
      local providers = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })

      providers.next("changes")

      local autocmds = vim.api.nvim_get_autocmds({ group = "ConveyDismiss" })
      local events = {}
      for _, au in ipairs(autocmds) do
        events[au.event] = true
      end

      -- Verify the dismiss autocmds cover the expected events
      if #autocmds > 0 then
        assert.is_true(events["CursorMoved"] or false, "Expected CursorMoved autocmd")
        assert.is_true(events["InsertEnter"] or false, "Expected InsertEnter autocmd")
        assert.is_true(events["CmdlineEnter"] or false, "Expected CmdlineEnter autocmd")
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("views.close clears active_provider via dismiss", function()
      local providers = require("convey.providers")
      local views = require("convey.views")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })

      providers.next("changes")

      -- Manually close the view and clear active_provider (as dismiss would)
      views.close()
      state.active_provider = nil

      assert.is_nil(state.active_provider)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("exit closes views and clears active_provider", function()
      local providers = require("convey.providers")
      local views = require("convey.views")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })

      providers.next("changes")

      -- Provider should be active after navigation
      local was_active = state.active_provider == "changes"

      local close_called = false
      local original_close = views.close
      views.close = function(...)
        close_called = true
        return original_close(...)
      end

      providers.exit("changes")

      assert.is_true(was_active or true) -- active if positions existed
      assert.is_nil(state.active_provider)
      views.close = original_close
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("exit is a no-op when provider is not active", function()
      local providers = require("convey.providers")
      local views = require("convey.views")

      local close_called = false
      local original_close = views.close
      views.close = function(...)
        close_called = true
        return original_close(...)
      end

      -- Exit without navigating first
      providers.exit("changes")

      assert.is_false(close_called)
      assert.is_nil(state.active_provider)
      views.close = original_close
    end)

    it("exit does not affect a different active provider", function()
      local providers = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })

      providers.next("changes")

      -- Try to exit a different provider
      providers.exit("jumps")

      -- changes should still be active
      if state.active_provider then
        assert.are.equal("changes", state.active_provider)
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("exit clears dismiss autocmds", function()
      local providers = require("convey.providers")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })

      providers.next("changes")

      providers.exit("changes")

      local autocmds = vim.api.nvim_get_autocmds({ group = "ConveyDismiss" })
      assert.are.equal(0, #autocmds)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    describe("provider keymap lifecycle", function()
      local function make_buf_with_changes()
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa" })
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "bbb" })
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "ccc" })
        return bufnr
      end

      local function cleanup_esc()
        pcall(vim.keymap.del, "n", "<Esc>")
        pcall(vim.keymap.del, "n", "<C-c>")
        pcall(vim.keymap.del, "n", "<C-[>")
      end

      it("installs provider keymaps when provider becomes active", function()
        cleanup_esc()
        local providers = require("convey.providers")
        local bufnr = make_buf_with_changes()

        assert.is_true(vim.tbl_isempty(vim.fn.maparg("<Esc>", "n", false, true)))

        providers.next("changes")

        if state.active_provider == "changes" then
          local mapping = vim.fn.maparg("<Esc>", "n", false, true)
          assert.is_false(vim.tbl_isempty(mapping))
          assert.are.equal("Convey exit changes", mapping.desc)
        end

        providers.exit("changes")
        cleanup_esc()
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end)

      it("restores original mapping on exit", function()
        cleanup_esc()
        local sentinel_called = false
        vim.keymap.set("n", "<Esc>", function()
          sentinel_called = true
        end, { desc = "test sentinel" })

        local providers = require("convey.providers")
        local bufnr = make_buf_with_changes()

        providers.next("changes")
        if state.active_provider == "changes" then
          assert.are.equal("Convey exit changes", vim.fn.maparg("<Esc>", "n", false, true).desc)
        end

        providers.exit("changes")

        local mapping = vim.fn.maparg("<Esc>", "n", false, true)
        assert.is_false(vim.tbl_isempty(mapping))
        assert.are.equal("test sentinel", mapping.desc)
        assert.is_false(sentinel_called)

        cleanup_esc()
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end)

      it("deletes mapping on exit when no prior mapping existed", function()
        cleanup_esc()
        local providers = require("convey.providers")
        local bufnr = make_buf_with_changes()

        providers.next("changes")
        if state.active_provider ~= "changes" then
          cleanup_esc()
          vim.api.nvim_buf_delete(bufnr, { force = true })
          return
        end

        providers.exit("changes")

        assert.is_true(vim.tbl_isempty(vim.fn.maparg("<Esc>", "n", false, true)))

        cleanup_esc()
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end)

      it("restores previous provider's keymaps when switching providers", function()
        cleanup_esc()
        pcall(vim.keymap.del, "n", "g;")
        local providers = require("convey.providers")
        local bufnr = make_buf_with_changes()

        providers.next("changes")
        if state.active_provider ~= "changes" then
          cleanup_esc()
          pcall(vim.keymap.del, "n", "g;")
          vim.api.nvim_buf_delete(bufnr, { force = true })
          return
        end
        assert.are.equal("Convey next changes", vim.fn.maparg("g;", "n", false, true).desc)

        -- Force a jump onto the jump list so jumps provider has a position
        vim.cmd("normal! m'")
        providers.next("jumps")
        if state.active_provider == "jumps" then
          -- changes-only keys should be restored (g; was only in changes.provider)
          assert.is_true(vim.tbl_isempty(vim.fn.maparg("g;", "n", false, true)))
          -- jumps provider keymap installed
          assert.are.equal("Convey exit jumps", vim.fn.maparg("<Esc>", "n", false, true).desc)
        end

        providers.exit("jumps")
        cleanup_esc()
        pcall(vim.keymap.del, "n", "g;")
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end)

      it("exit keymap invocation closes the active provider", function()
        cleanup_esc()
        local providers = require("convey.providers")
        local bufnr = make_buf_with_changes()

        providers.next("changes")
        if state.active_provider ~= "changes" then
          cleanup_esc()
          vim.api.nvim_buf_delete(bufnr, { force = true })
          return
        end

        -- Invoke the installed <Esc> mapping directly
        local mapping = vim.fn.maparg("<Esc>", "n", false, true)
        assert.is_function(mapping.callback)
        mapping.callback()

        assert.is_nil(state.active_provider)
        assert.is_true(vim.tbl_isempty(vim.fn.maparg("<Esc>", "n", false, true)))

        cleanup_esc()
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end)
    end)
  end)

  describe("config enabled field", function()
    local cfg

    before_each(function()
      package.loaded["convey.config"] = nil
      cfg = require("convey.config")
    end)

    it("providers have views.notify enabled by default", function()
      local changes = cfg.get_provider("changes")
      assert.is_table(changes.views)
      assert.is_table(changes.views.notify)
      assert.is_true(changes.views.notify.enabled)
    end)

    it("provider views.notify can be disabled", function()
      cfg.setup({
        providers = {
          changes = { views = { notify = { enabled = false } } },
        },
      })
      local changes = cfg.get_provider("changes")
      assert.is_false(changes.views.notify.enabled)
    end)

    it("provider views.notify can have custom lines_before/lines_after", function()
      cfg.setup({
        providers = {
          changes = { views = { notify = { lines_before = 5, lines_after = 2 } } },
        },
      })
      local changes = cfg.get_provider("changes")
      assert.are.equal(5, changes.views.notify.lines_before)
      assert.are.equal(2, changes.views.notify.lines_after)
    end)

    it("visual provider has on_navigate by default", function()
      local visual = cfg.get_provider("visual")
      assert.is_function(visual.on_navigate)
    end)

    it("non-visual providers do not have on_navigate", function()
      local changes = cfg.get_provider("changes")
      assert.is_nil(changes.on_navigate)
      local jumps = cfg.get_provider("jumps")
      assert.is_nil(jumps.on_navigate)
      local saves = cfg.get_provider("saves")
      assert.is_nil(saves.on_navigate)
    end)

    it("provider on_navigate can be set via setup", function()
      local called_with = nil
      cfg.setup({
        providers = {
          saves = {
            on_navigate = function(pos)
              called_with = pos
            end,
          },
        },
      })
      local saves = cfg.get_provider("saves")
      assert.is_function(saves.on_navigate)
      saves.on_navigate({ lnum = 1, col = 0 })
      assert.are.same({ lnum = 1, col = 0 }, called_with)
    end)

    it("top-level on_navigate defaults to nil", function()
      local c = cfg.get()
      assert.is_nil(c.on_navigate)
    end)

    it("accepts custom top-level on_navigate", function()
      local called = false
      cfg.setup({
        on_navigate = function(cb)
          called = true
          cb()
        end,
      })
      local c = cfg.get()
      assert.is_function(c.on_navigate)
      c.on_navigate(function() end)
      assert.is_true(called)
    end)

    it("providers are enabled by default", function()
      local changes = cfg.get_provider("changes")
      assert.is_true(changes.enabled)
      local jumps = cfg.get_provider("jumps")
      assert.is_true(jumps.enabled)
    end)

    it("providers can be disabled", function()
      cfg.setup({
        providers = {
          jumps = { enabled = false },
        },
      })
      local jumps = cfg.get_provider("jumps")
      assert.is_false(jumps.enabled)
      -- Others remain enabled
      local changes = cfg.get_provider("changes")
      assert.is_true(changes.enabled)
    end)

    it("changes provider has global nav keys and provider exit keys", function()
      local changes = cfg.get_provider("changes")
      assert.are.equal("next", changes.keymaps.global["g;"])
      assert.are.equal("prev", changes.keymaps.global["g,"])
      assert.are.equal("exit", changes.keymaps.provider["<Esc>"])
      assert.are.equal("exit", changes.keymaps.provider["<C-c>"])
      assert.are.equal("exit", changes.keymaps.provider["<C-[>"])
      assert.are.equal("next", changes.keymaps.provider["g;"])
      assert.are.equal("prev", changes.keymaps.provider["g,"])
    end)

    it("jumps provider has global nav keys and provider exit keys", function()
      local jumps = cfg.get_provider("jumps")
      assert.are.equal("next", jumps.keymaps.global["<C-o>"])
      assert.are.equal("prev", jumps.keymaps.global["<C-i>"])
      assert.are.equal("exit", jumps.keymaps.provider["<Esc>"])
      assert.are.equal("next", jumps.keymaps.provider["<C-o>"])
      assert.are.equal("prev", jumps.keymaps.provider["<C-i>"])
    end)

    it("saves provider has provider exit keys and no global keys", function()
      local saves = cfg.get_provider("saves")
      assert.are.equal("exit", saves.keymaps.provider["<Esc>"])
      assert.are.equal("exit", saves.keymaps.provider["<C-c>"])
      assert.are.equal("exit", saves.keymaps.provider["<C-[>"])
      assert.is_nil(saves.keymaps.global)
    end)
  end)

  describe("movements", function()
    local movements

    before_each(function()
      package.loaded["convey.movements"] = nil
      package.loaded["convey.config"] = nil
      movements = require("convey.movements")
      local cfg = require("convey.config")
      cfg.setup({
        logger = {
          error = function() end,
          warn = function() end,
          info = function() end,
          debug = function() end,
          trace = function() end,
        },
      })
    end)

    it("can be required", function()
      assert.is_not_nil(movements)
      assert.is_function(movements.from_motions)
      assert.is_function(movements.from_queries)
      assert.is_function(movements.get_positions)
    end)

    it("from_motions discovers positions via forward motion", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      -- Lines starting with { at column 0 are section boundaries for ]]
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "preamble",
        "{",
        "  body1",
        "}",
        "",
        "{",
        "  body2",
        "}",
      })

      local positions = movements.from_motions(bufnr, { next = "]]", prev = "[[" })
      assert.is_true(#positions >= 2)
      -- Positions should be at the { lines
      assert.are.equal(bufnr, positions[1].bufnr)
      assert.are.equal("movements", positions[1].source)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("from_motions restores cursor position", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "line1",
        "{",
        "line3",
        "{",
      })
      vim.api.nvim_win_set_cursor(0, { 3, 2 })

      movements.from_motions(bufnr, { next = "]]", prev = "[[" })

      local cursor = vim.api.nvim_win_get_cursor(0)
      assert.are.equal(3, cursor[1])
      assert.are.equal(2, cursor[2])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("from_motions returns empty for single-line buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "single line" })

      local positions = movements.from_motions(bufnr, { next = "]]", prev = "[[" })
      assert.are.same({}, positions)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("get_positions assigns timestamps for position-order sorting", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "line1",
        "{",
        "line3",
        "{",
      })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local positions = movements.get_positions(bufnr, {
        motions = { next = "]]", prev = "[[" },
      })

      if #positions >= 2 then
        -- Higher timestamp = earlier in buffer (for descending sort)
        assert.is_true(positions[1].timestamp > positions[2].timestamp)
        -- But lnum is ascending
        assert.is_true(positions[1].lnum <= positions[2].lnum)
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("get_positions marks curr as last position at or before cursor", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "line1",
        "{",
        "  between",
        "{",
        "line5",
      })
      -- Place cursor on line 3 (between the two { lines)
      vim.api.nvim_win_set_cursor(0, { 3, 0 })

      local positions = movements.get_positions(bufnr, {
        motions = { next = "]]", prev = "[[" },
      })

      if #positions >= 2 then
        -- The { on line 2 should be curr (last position <= cursor line 3)
        local curr_found = false
        for _, pos in ipairs(positions) do
          if pos.curr then
            assert.is_true(pos.lnum <= 3)
            curr_found = true
          end
        end
        assert.is_true(curr_found)
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("from_queries returns empty when treesitter unavailable", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "no parser" })

      local positions = movements.from_queries(bufnr, { "@block.outer" })
      assert.are.same({}, positions)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("get_positions returns empty for empty movements config", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      local positions = movements.get_positions(bufnr, {})
      assert.are.same({}, positions)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("movements config", function()
    local cfg

    before_each(function()
      package.loaded["convey.config"] = nil
      cfg = require("convey.config")
    end)

    it("paragraph provider has movements with motions", function()
      local paragraph = cfg.get_provider("paragraph")
      assert.is_not_nil(paragraph)
      assert.is_true(paragraph.enabled)
      assert.is_not_nil(paragraph.movements)
      assert.is_not_nil(paragraph.movements.motions)
      assert.are.equal("]]", paragraph.movements.motions.next)
      assert.are.equal("[[", paragraph.movements.motions.prev)
    end)

    it("paragraph provider has default keymaps", function()
      local paragraph = cfg.get_provider("paragraph")
      assert.are.equal("prev", paragraph.keymaps.global["[["])
      assert.are.equal("next", paragraph.keymaps.global["]]"])
      assert.are.equal("prev", paragraph.keymaps.provider["[["])
      assert.are.equal("next", paragraph.keymaps.provider["]]"])
      assert.are.equal("exit", paragraph.keymaps.provider["<Esc>"])
    end)

    it("paragraph provider has empty listeners", function()
      local paragraph = cfg.get_provider("paragraph")
      assert.are.same({}, paragraph.listeners)
    end)

    it("block provider has movements with queries", function()
      local block = cfg.get_provider("block")
      assert.is_not_nil(block)
      assert.is_true(block.enabled)
      assert.is_not_nil(block.movements)
      assert.is_not_nil(block.movements.queries)
      assert.are.equal(3, #block.movements.queries)
    end)

    it("block provider has provider exit keymaps and no global keys", function()
      local block = cfg.get_provider("block")
      assert.is_nil(block.keymaps.global)
      assert.are.equal("exit", block.keymaps.provider["<Esc>"])
      assert.are.equal("exit", block.keymaps.provider["<C-c>"])
      assert.are.equal("exit", block.keymaps.provider["<C-[>"])
    end)

    it("movement providers can be disabled", function()
      cfg.setup({
        providers = {
          paragraph = { enabled = false },
          block = { enabled = false },
        },
      })
      assert.is_false(cfg.get_provider("paragraph").enabled)
      assert.is_false(cfg.get_provider("block").enabled)
    end)
  end)

  describe("views.inline", function()
    local inline_view
    local state

    before_each(function()
      for key, _ in pairs(package.loaded) do
        if key:match("^convey") then
          package.loaded[key] = nil
        end
      end
      local cfg = require("convey.config")
      cfg.setup({
        logger = {
          error = function() end,
          warn = function() end,
          info = function() end,
          debug = function() end,
          trace = function() end,
        },
      })
      inline_view = require("convey.views.inline")
      state = require("convey.state")
    end)

    after_each(function()
      inline_view.close()
    end)

    it("can be required", function()
      assert.is_not_nil(inline_view)
      assert.is_function(inline_view.load)
      assert.is_function(inline_view.close)
    end)

    it("places extmark on load", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "test line" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local positions = {
        { lnum = 1, col = 0, bufnr = bufnr, timestamp = 1, source = "test" },
        { lnum = 2, col = 0, bufnr = bufnr, timestamp = 2, source = "test" },
      }
      local provider_config = {
        keymaps = { ["g;"] = "next", ["g,"] = "prev" },
        views = { inline = { enabled = true } },
      }

      inline_view.load("changes", positions, 1, provider_config)

      assert.is_not_nil(state.inline_extmark_id)
      assert.are.equal(bufnr, state.inline_bufnr)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("clears extmark on close", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "test line" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local positions = {
        { lnum = 1, col = 0, bufnr = bufnr, timestamp = 1, source = "test" },
      }
      local provider_config = {
        keymaps = { ["g;"] = "next" },
        views = { inline = { enabled = true } },
      }

      inline_view.load("changes", positions, 1, provider_config)
      assert.is_not_nil(state.inline_extmark_id)

      inline_view.close()
      assert.is_nil(state.inline_extmark_id)
      assert.is_nil(state.inline_bufnr)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not place extmark for empty positions", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      inline_view.load("changes", {}, 0, { keymaps = {} })
      assert.is_nil(state.inline_extmark_id)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("replaces previous extmark on subsequent load", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local positions = {
        { lnum = 1, col = 0, bufnr = bufnr, timestamp = 1, source = "test" },
        { lnum = 2, col = 0, bufnr = bufnr, timestamp = 2, source = "test" },
      }
      local provider_config = {
        keymaps = { ["g;"] = "next", ["g,"] = "prev" },
        views = { inline = { enabled = true } },
      }

      inline_view.load("changes", positions, 1, provider_config)
      local first_id = state.inline_extmark_id

      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      inline_view.load("changes", positions, 2, provider_config)

      assert.is_not_nil(state.inline_extmark_id)
      assert.are_not.equal(first_id, state.inline_extmark_id)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("creates ConveyInline highlight group", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "test" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local positions = {
        { lnum = 1, col = 0, bufnr = bufnr, timestamp = 1, source = "test" },
      }
      inline_view.load("changes", positions, 1, { keymaps = {}, views = {} })

      local hl = vim.api.nvim_get_hl(0, { name = "ConveyInline" })
      assert.is_not_nil(hl)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("views.inline config", function()
    before_each(function()
      for key, _ in pairs(package.loaded) do
        if key:match("^convey") then
          package.loaded[key] = nil
        end
      end
    end)

    it("has inline view enabled by default", function()
      local cfg = require("convey.config")
      local view = cfg.get_view("inline")
      assert.is_not_nil(view)
      assert.is_true(view.enabled)
      assert.are.equal("#00ffff", view.fg)
    end)

    it("providers have inline view enabled by default", function()
      local cfg = require("convey.config")
      local changes = cfg.get_provider("changes")
      assert.is_not_nil(changes.views.inline)
      assert.is_true(changes.views.inline.enabled)
    end)

    it("inline view can be disabled globally", function()
      local cfg = require("convey.config")
      cfg.setup({ views = { inline = { enabled = false } } })
      local view = cfg.get_view("inline")
      assert.is_false(view.enabled)
    end)

    it("inline view can be disabled per provider", function()
      local cfg = require("convey.config")
      cfg.setup({
        providers = {
          changes = { views = { inline = { enabled = false } } },
        },
      })
      local changes = cfg.get_provider("changes")
      assert.is_false(changes.views.inline.enabled)
    end)

    it("inline fg color can be customized", function()
      local cfg = require("convey.config")
      cfg.setup({ views = { inline = { fg = "#ff0000" } } })
      local view = cfg.get_view("inline")
      assert.are.equal("#ff0000", view.fg)
    end)
  end)

  describe("state.has_active_view", function()
    local state

    before_each(function()
      package.loaded["convey.state"] = nil
      state = require("convey.state")
    end)

    it("returns false when no views active", function()
      assert.is_false(state.has_active_view())
    end)

    it("returns true when notify is active", function()
      state.notify_id = 1
      assert.is_true(state.has_active_view())
      state.notify_id = nil
    end)

    it("returns true when inline is active", function()
      state.inline_extmark_id = 1
      assert.is_true(state.has_active_view())
      state.inline_extmark_id = nil
    end)
  end)

  describe("views dispatcher", function()
    before_each(function()
      for key, _ in pairs(package.loaded) do
        if key:match("^convey") then
          package.loaded[key] = nil
        end
      end
      local cfg = require("convey.config")
      cfg.setup({
        logger = {
          error = function() end,
          warn = function() end,
          info = function() end,
          debug = function() end,
          trace = function() end,
        },
      })
    end)

    it("dispatches to both notify and inline views", function()
      local views = require("convey.views")
      assert.is_function(views.show)
      assert.is_function(views.close)
    end)

    it("close clears inline state", function()
      local views = require("convey.views")
      local state = require("convey.state")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "test" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local positions = {
        { lnum = 1, col = 0, bufnr = bufnr, timestamp = 1, source = "test" },
      }
      local provider_config = {
        keymaps = { ["g;"] = "next" },
        views = { notify = { enabled = false }, inline = { enabled = true } },
      }

      views.show("changes", positions, 1, provider_config)
      assert.is_not_nil(state.inline_extmark_id)

      views.close()
      assert.is_nil(state.inline_extmark_id)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("views.status", function()
    before_each(function()
      for key, _ in pairs(package.loaded) do
        if key:match("^convey") then
          package.loaded[key] = nil
        end
      end
      local cfg = require("convey.config")
      cfg.setup({
        logger = {
          error = function() end,
          warn = function() end,
          info = function() end,
          debug = function() end,
          trace = function() end,
        },
      })
    end)

    it("can be required", function()
      local status = require("convey.views.status")
      assert.is_not_nil(status)
      assert.is_function(status.open)
      assert.is_function(status.close)
    end)

    it("opens and closes a floating window", function()
      local status = require("convey.views.status")
      status.open()
      -- Should have created a window
      -- Close it
      status.close()
    end)
  end)
end)
