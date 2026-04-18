# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Convey is a Neovim submodule for traversing time-based position lists from multiple sources. It uses a provider/listener architecture where providers aggregate positions from one or more listeners and expose next/prev navigation via keymaps and commands.

## Architecture

```
init.lua                 -- setup(), command/keymap registration
config.lua               -- default config, merge, logger
state.lua                -- per-provider state, view tracking (notify/inline), augroup
utils.lua                -- process_list, deduplicate, build_highlight_table, align_text, format_pos, has_ranges, is_multi_buffer, bufname_for_pos
providers.lua            -- provider registry: merge/sort/dedup, next/prev, get_status, refresh
movements.lua            -- on-demand position calculation from motions or treesitter queries
views/
  init.lua               -- view dispatcher (iterates registered view modules)
  notify.lua             -- notify popup (position list with truncation, highlights)
  inline.lua             -- inline virtual text after EOL (provider, index, keymap arrows)
  status.lua             -- ConveyStatus floating window (interactive expand/collapse)
listeners/
  init.lua               -- listener registry, lifecycle management
  changes.lua            -- vim.fn.getchangelist() snapshot
  jumps.lua              -- vim.fn.getjumplist() snapshot
  selections.lua         -- ModeChanged autocommand, extmark persistence, hash dedup
  yanks.lua              -- TextYankPost (operator=="y")
  pastes.lua             -- p/P keymap overrides (TextYankPost does not fire for put)
  writes.lua             -- BufWritePost cursor position
```

### Key design decisions

- **Full navigation ownership**: Convey owns cursor movement via `setpos()`, not delegating to native Vim motions
- **Global keymaps**: Provider keymaps work across all buffers (not buffer-local like histories)
- **No polling**: Positions fetched fresh on each navigation action (no timer like histories)
- **Multiple listeners per provider**: Unlike histories (1:1), convey merges positions from multiple listeners sorted by timestamp
- **Movement providers**: Providers can have a `movements` config instead of (or alongside) listeners. Movements calculate positions on demand from buffer structure rather than tracking events. Two modes: native Vim motions (`motions = { next = "]]", prev = "[[" }`) and treesitter queries (`queries = { "@block.outer" }`)
- **Configurable logger**: `config.logger` with error/warn/info/debug/trace levels

### Listener interface

```lua
--- @class ConveyListener
--- @field name string
--- @field prefix string                 -- icon shown in multi-listener providers
--- @field init fun(augroup: number)     -- setup autocommands
--- @field destroy fun()                 -- teardown
--- @field get_positions fun(bufnr: number): ConveyPosition[]
```

Default prefixes: pastes ``, yanks ``, selections `󰒅`, jumps `󰿅`, changes ``, writes ``.
When a provider has multiple listeners, the prefix icon is shown after the index number in both the notify and status views to identify which listener produced each position.

### Position format

```lua
--- @class ConveyPosition
--- @field lnum number        -- 1-indexed line
--- @field col number         -- 0-indexed column
--- @field end_lnum number|nil -- 1-indexed end line (range providers only)
--- @field end_col number|nil  -- 0-indexed end column (range providers only)
--- @field bufnr number
--- @field timestamp number   -- os.time() or index-based for snapshots
--- @field source string      -- listener name
--- @field curr boolean|nil   -- true if this is the current position
```

Range fields (`end_lnum`, `end_col`) are emitted by the `yanks`, `pastes`, and `selections` listeners. When any position in a provider's list has both end fields, views automatically display coordinates as `lnum:col - end_lnum:end_col` (detected via `utils.has_ranges()`).

## Commands

- `:ConveyNext <provider>` -- navigate to next (older) position
- `:ConveyPrev <provider>` -- navigate to previous (newer) position
- `:ConveyExit <provider>` -- deactivate provider, close views
- `:ConveyStatus` -- interactive status popup with expand/collapse

## Development

### Testing

```bash
./scripts/run_tests.sh                # all tests
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/unit/convey_spec.lua"   # single file
```

### Formatting and Linting

```bash
stylua lua/convey/       # Note: do not use goto/::label:: (stylua rejects it)
luacheck lua/convey/
```

## Configuration

```lua
require("convey").setup({
  max_marks = 50,
  on_navigate = nil,      -- callback(finish_fn) substituting default vim.schedule navigation completion
  logger = { ... },       -- custom logger with error/warn/info/debug/trace
  views = {
    notify = { enabled = true, lines_before = 8, lines_after = 3 },
    inline = { enabled = true, fg = "#ffffff" },
  },
  providers = {
    changes = { enabled = true, unique = true, listeners = { "changes" }, keymaps = { ["g;"] = "next", ["g,"] = "prev", ["<Esc>"] = "exit", ["<C-c>"] = "exit", ["<C-[>"] = "exit" }, views = { notify = { enabled = true } } },
    jumps   = { enabled = true, unique = true, listeners = { "jumps" },   keymaps = { ["<C-o>"] = "next", ["<C-i>"] = "prev", ["<Esc>"] = "exit", ["<C-c>"] = "exit", ["<C-[>"] = "exit" }, views = { notify = { enabled = true } } },
    visual  = { enabled = true, unique = true, on_navigate = nil, listeners = { "pastes", "yanks", "selections" }, keymaps = { ["gv"] = "next", ["gV"] = "prev", ["<Esc>"] = "exit", ["<C-c>"] = "exit", ["<C-[>"] = "exit" }, views = { notify = { enabled = true } } },
    saves     = { enabled = true, unique = false, listeners = { "writes" }, views = { notify = { enabled = true } } },
    paragraph = { enabled = true, unique = true, listeners = {}, movements = { motions = { next = "]]", prev = "[[" } }, keymaps = { ["[["] = "prev", ["]]"] = "next", ["<Esc>"] = "exit", ["<C-c>"] = "exit", ["<C-[>"] = "exit" } },
    block     = { enabled = true, unique = true, listeners = {}, movements = { queries = { "@block.outer", "@conditional.outer", "@loop.outer" } }, keymaps = {} },
  },
})
```

### Provider options

- `enabled = false` disables a provider (skips listener init, shows as disabled in ConveyStatus)
- `cycle = true` wraps navigation: `next` past the last position jumps to the first, `prev` before the first jumps to the last. Default `false` (clamps at bounds).
- `on_navigate = function(pos)` (provider-level) called after cursor jump but before view show/dismiss setup. Receives the navigated `ConveyPosition`. Used by the visual provider to reselect the range via `setpos("'<")/setpos("'>")` + `normal! gv`.
- `on_navigate` (top-level) replaces the default `vim.schedule(finish)` navigation completion handler. Receives a single `finish_fn` callback that must be called to finalize navigation (show views, setup dismiss autocmds, clear navigating flag). Views are deferred until `finish_fn` is called, which prevents rendering during scroll animations.
- When both `on_navigate` callbacks are set, the top-level runs first; only after it invokes `finish_fn` does the provider-level `on_navigate(pos)` fire (followed by view show and dismiss setup). This lets the provider callback (e.g. visual reselect) land after scroll animations complete.
- `keymaps` supports three actions: `"next"`, `"prev"`, and `"exit"`. Exit keymaps (`<Esc>`, `<C-c>`, `<C-[>` by default) close all views and deactivate the provider. The provider remains inactive until the next `next`/`prev` keymap or command.

## Non-obvious patterns

These cross-module behaviors are easy to get wrong:

- **Navigating flag guard** (`providers.lua`): Module-level `navigating` boolean prevents dismiss autocmds from firing during navigation (since `setpos` triggers CursorMoved). Cleared after views are shown and dismiss autocmds are set up, either via `vim.schedule` or the custom `on_navigate` callback.
- **View dismiss via CursorMoved** (`providers.lua`): Views are dismissed by CursorMoved/InsertEnter/CmdlineEnter autocmds, not by detecting specific keys. The `exit` keymap action provides explicit dismissal via `providers.exit()`, which closes views, clears `active_provider`, and removes dismiss autocmds. Navigation does not add to the jump list (`keepjumps`).
- **Two listener categories**: Snapshot listeners (changes, jumps) have no-op init/destroy and fetch fresh data on each call via `vim.fn.getchangelist()`/`vim.fn.getjumplist()`. Event listeners (selections, yanks, pastes, writes) store to module-level tables via autocommands or keymaps.
- **Paste listener uses keymaps, not autocommands**: Unlike other event listeners, pastes overrides `p`/`P` keymaps because `TextYankPost` does not fire for put operations. The keymaps use `feedkeys` with `"nx"` (noremap + execute immediately) to run the built-in paste, then record `'[`/`']` marks.
- **Movement timestamp hack**: Positions from movements are sorted by lnum ascending, then assigned timestamps as `total - i + 1` so they survive the descending timestamp sort in `refresh_positions()` without losing position order. Curr is set to the last position at or before the cursor line.
- **Movement providers skip listeners**: A provider with `listeners = {}` and `movements = {...}` collects no listener positions. `listeners.init({})` is a no-op. Movement positions are collected separately in `refresh_positions()`.
- **Multi-view dispatch** (`views/init.lua`): The dispatcher iterates a `view_modules` table and checks both global and per-provider `enabled` flags for each view independently. Adding a new view requires: creating the module with `load()`/`close()`, adding it to `view_modules`, adding defaults to `config.lua`, and adding state tracking to `state.lua`. Dismiss logic uses `state.has_active_view()` which checks all view types.
- **Lazy listener caching** (`listeners/init.lua`): Once loaded via `pcall(require)`, listener modules are cached in `listener_modules`. Module-level state persists across providers sharing the same listener.
- **Timestamp semantics differ**: Event listeners use `os.time()`, snapshot listeners use list index as timestamp. Both sort correctly because positions are sorted by timestamp descending.
- **Selections use extmarks** while other event listeners store fixed positions. Extmarks survive buffer edits; fixed positions don't update.
- **Col indexing mismatch**: Positions use 0-indexed `col`, but `vim.fn.setpos()` needs 1-indexed. The visual provider's `on_navigate` adds 1 for this reason.

## Reference: lua/histories

The histories module is the predecessor. Key reused patterns:
- `histories/utils.lua`: `build_highlight_table`, `process_list`, `align_text`
- `histories/changes/view.lua`: notify view with truncation and replacement
- `histories/selects/track.lua`: ModeChanged listener with extmarks and hash dedup

## Later TODO (ignore for now)

- [ ] Add support for `:undo` and `:redo`
