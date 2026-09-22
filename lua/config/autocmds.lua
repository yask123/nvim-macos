-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

-- Disable autoformat for markdown files
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown" },
  callback = function()
    vim.b.autoformat = false
  end,
})

-- Rulers sit one column past each formatter's line length (ruff 88, prettier
-- 80, stylua 120); nothing hard-wraps while you type.
local rulers = {
  python = "89",
  lua = "121",
  javascript = "81",
  javascriptreact = "81",
  typescript = "81",
  typescriptreact = "81",
}
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("DojoRulers", { clear = true }),
  callback = function(ev)
    vim.opt_local.colorcolumn = rulers[ev.match] or ""
  end,
})
