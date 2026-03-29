-- Minimal init file for testing
vim.opt.rtp:prepend(".")

-- Add plenary.nvim
local plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.rtp:append(plenary_path)
  vim.cmd("runtime! plugin/plenary.vim")
end

-- Set up basic test environment
vim.o.swapfile = false
vim.o.backup = false
vim.o.writebackup = false
vim.o.undofile = false
