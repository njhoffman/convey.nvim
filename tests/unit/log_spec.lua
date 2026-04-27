describe("convey.log", function()
  local log
  local config
  local utils
  local captured

  local capture_logger = function()
    captured = { trace = {}, warn = {}, info = {}, error = {}, debug = {} }
    config.setup({
      logger = {
        trace = function(msg)
          table.insert(captured.trace, msg)
        end,
        warn = function(msg)
          table.insert(captured.warn, msg)
        end,
        info = function(msg)
          table.insert(captured.info, msg)
        end,
        error = function(msg)
          table.insert(captured.error, msg)
        end,
        debug = function(msg)
          table.insert(captured.debug, msg)
        end,
      },
    })
  end

  before_each(function()
    package.loaded["convey.log"] = nil
    package.loaded["convey.config"] = nil
    package.loaded["convey.utils"] = nil
    config = require("convey.config")
    utils = require("convey.utils")
    log = require("convey.log")
    capture_logger()
    log.reset()
  end)

  it("formats a single-position write log line under the correct provider", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    log.tracked("writes", "write", { bufnr = bufnr, lnum = 1, col = 7 })
    assert.are.equal(1, #captured.trace)
    assert.is_truthy(captured.trace[1]:match("^%[convey%] saves: tracked write at 1:7"))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("uses comma-joined provider names for multi-provider listeners (architectural)", function()
    config.setup({
      providers = {
        extra = {
          enabled = true,
          unique = false,
          listeners = { "writes" },
        },
      },
      logger = {
        trace = function(msg)
          table.insert(captured.trace, msg)
        end,
        warn = function(msg)
          table.insert(captured.warn, msg)
        end,
      },
    })
    captured.trace = {}
    log.reset()
    local bufnr = vim.api.nvim_create_buf(false, true)
    log.tracked("writes", "write", { bufnr = bufnr, lnum = 2, col = 3 })
    -- Both "saves" and "extra" claim "writes"; comma-joined order is provider-table iteration order
    assert.is_truthy(captured.trace[1]:match("^%[convey%] [%w,]+: tracked write at 2:3"))
    local label = captured.trace[1]:match("^%[convey%] ([%w,]+): tracked")
    assert.is_truthy(label:match("saves") and label:match("extra"))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("falls back to listener name and warns once when no provider claims it", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    log.tracked("orphan_listener", "event", { bufnr = bufnr, lnum = 1, col = 1 })
    log.tracked("orphan_listener", "event", { bufnr = bufnr, lnum = 2, col = 1 })
    assert.is_truthy(captured.trace[1]:match("^%[convey%] orphan_listener: tracked event"))
    assert.are.equal(1, #captured.warn)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("emits range size with both line and char counts for char-wise ranges", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "abc", "defgh", "ij" })
    log.tracked("yanks", "yank", {
      bufnr = bufnr,
      lnum = 1,
      col = 1,
      end_lnum = 3,
      end_col = 2,
    })
    -- 3L total, chars: "abc" (3) + \n + "defgh" (5) + \n + "ij" (2) = 12
    assert.is_truthy(captured.trace[1]:match("%(3L 12c%)"))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("omits char count for linewise V-mode (end_col == vim.v.maxcol)", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
    log.tracked("selections", "selection", {
      bufnr = bufnr,
      lnum = 1,
      col = 1,
      end_lnum = 3,
      end_col = vim.v.maxcol,
    })
    assert.is_truthy(captured.trace[1]:match("%(3L%)"))
    assert.is_falsy(captured.trace[1]:match("%(3L %d+c%)"))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("omits range block when range is zero-width", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "abc" })
    log.tracked("pastes", "paste", {
      bufnr = bufnr,
      lnum = 1,
      col = 1,
      end_lnum = 1,
      end_col = 1,
    })
    assert.is_falsy(captured.trace[1]:match("%([^)]+%)"))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("includes path on first call, omits on repeat, includes again after change", function()
    local home = vim.fn.expand("$HOME")
    -- Buffer A: real-name buffer with path under HOME
    local path_a = home .. "/__convey_test_a.txt"
    vim.cmd("edit " .. vim.fn.fnameescape(path_a))
    local buf_a = vim.api.nvim_get_current_buf()

    log.tracked("writes", "write", { bufnr = buf_a, lnum = 1, col = 1 })
    assert.is_truthy(captured.trace[1]:find("'~/__convey_test_a.txt'", 1, true))

    -- Same buffer/path again -> path omitted
    log.tracked("writes", "write", { bufnr = buf_a, lnum = 2, col = 1 })
    assert.is_falsy(captured.trace[2]:find("__convey_test_a.txt", 1, true))

    -- Different buffer -> path included again
    local path_b = home .. "/__convey_test_b.txt"
    vim.cmd("edit " .. vim.fn.fnameescape(path_b))
    local buf_b = vim.api.nvim_get_current_buf()
    log.tracked("writes", "write", { bufnr = buf_b, lnum = 1, col = 1 })
    assert.is_truthy(captured.trace[3]:find("'~/__convey_test_b.txt'", 1, true))

    pcall(vim.api.nvim_buf_delete, buf_a, { force = true })
    pcall(vim.api.nvim_buf_delete, buf_b, { force = true })
  end)

  it("substitutes ~/.config/nvim with ./", function()
    local nvim_cfg = vim.fn.expand("$HOME") .. "/.config/nvim"
    local path = nvim_cfg .. "/__convey_test_settings.lua"
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local bufnr = vim.api.nvim_get_current_buf()
    log.tracked("writes", "write", { bufnr = bufnr, lnum = 1, col = 1 })
    assert.is_truthy(captured.trace[1]:find("'./__convey_test_settings.lua'", 1, true))
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end)

  it("renders no path block for unnamed buffers", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    log.tracked("writes", "write", { bufnr = bufnr, lnum = 1, col = 1 })
    assert.is_falsy(captured.trace[1]:match("'.*'"))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("reset() clears last_path so next log re-emits the path", function()
    local home = vim.fn.expand("$HOME")
    local path = home .. "/__convey_test_reset.txt"
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local bufnr = vim.api.nvim_get_current_buf()

    log.tracked("writes", "write", { bufnr = bufnr, lnum = 1, col = 1 })
    log.tracked("writes", "write", { bufnr = bufnr, lnum = 2, col = 1 })
    assert.is_truthy(captured.trace[1]:find("__convey_test_reset.txt", 1, true))
    assert.is_falsy(captured.trace[2]:find("__convey_test_reset.txt", 1, true))

    log.reset()
    log.tracked("writes", "write", { bufnr = bufnr, lnum = 3, col = 1 })
    assert.is_truthy(captured.trace[3]:find("__convey_test_reset.txt", 1, true))

    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end)
end)

describe("convey.utils.format_buf_path", function()
  local utils

  before_each(function()
    package.loaded["convey.utils"] = nil
    utils = require("convey.utils")
  end)

  it("substitutes nvim-config prefix before HOME prefix", function()
    local home = vim.fn.expand("$HOME")
    local nvim_cfg = home .. "/.config/nvim"
    local path = nvim_cfg .. "/lua/settings.lua"
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local bufnr = vim.api.nvim_get_current_buf()
    assert.are.equal("./lua/settings.lua", utils.format_buf_path(bufnr, home, nvim_cfg))
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end)

  it("substitutes HOME prefix when path is not under nvim-config", function()
    local home = vim.fn.expand("$HOME")
    local nvim_cfg = home .. "/.config/nvim"
    local path = home .. "/.gitconfig"
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local bufnr = vim.api.nvim_get_current_buf()
    assert.are.equal("~/.gitconfig", utils.format_buf_path(bufnr, home, nvim_cfg))
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end)

  it("does not replace HOME-like substring mid-path", function()
    local home = "/home/nicholas"
    local nvim_cfg = home .. "/.config/nvim"
    -- A buffer with name "/tmp/home/nicholas/foo" should not be touched
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/tmp/home/nicholas/foo")
    assert.are.equal("/tmp/home/nicholas/foo", utils.format_buf_path(bufnr, home, nvim_cfg))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("returns empty string for unnamed buffers", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    assert.are.equal("", utils.format_buf_path(bufnr, "/home/x", "/home/x/.config/nvim"))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe("convey.utils.range_size", function()
  local utils

  before_each(function()
    package.loaded["convey.utils"] = nil
    utils = require("convey.utils")
  end)

  it("returns nil for missing end coords", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local n_lines, n_chars = utils.range_size(bufnr, 1, 1, nil, nil)
    assert.is_nil(n_lines)
    assert.is_nil(n_chars)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("returns nil for zero-width range", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local n_lines, n_chars = utils.range_size(bufnr, 1, 1, 1, 1)
    assert.is_nil(n_lines)
    assert.is_nil(n_chars)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("returns line count and nil chars for linewise V-mode", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
    local n_lines, n_chars = utils.range_size(bufnr, 1, 1, 3, vim.v.maxcol)
    assert.are.equal(3, n_lines)
    assert.is_nil(n_chars)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("counts characters for single-line range", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello" })
    local n_lines, n_chars = utils.range_size(bufnr, 1, 1, 1, 5)
    assert.are.equal(1, n_lines)
    assert.are.equal(5, n_chars)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("counts characters across multiple lines including newlines", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "abc", "defgh", "ij" })
    local n_lines, n_chars = utils.range_size(bufnr, 1, 1, 3, 2)
    assert.are.equal(3, n_lines)
    -- "abc" (3) + \n + "defgh" (5) + \n + "ij" (2) = 12
    assert.are.equal(12, n_chars)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("uses display characters (multibyte-correct)", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    -- Single emoji character; bytes > strchars
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "★★" })
    local _, n_chars = utils.range_size(bufnr, 1, 1, 1, vim.fn.strlen("★★"))
    assert.are.equal(2, n_chars)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
