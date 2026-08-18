-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Time to wait for a mapped sequence to complete (milliseconds)
-- 300 = fast but must type quickly, 500 = balanced, 1000 = relaxed
vim.opt.timeoutlen = 500

-- Use treesitter for better folding
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
-- Don't fold by default when opening files
vim.opt.foldenable = false

-- Python LSP Configuration
-- Use basedpyright (latest fork with more features) instead of pyright
vim.g.lazyvim_python_lsp = "basedpyright"
-- Use ruff for fast linting and formatting
vim.g.lazyvim_python_ruff = "ruff"

-- Disable inlay hints globally (no type annotations)
-- Note: This is handled in the LSP on_attach callback in python.lua

-- =============================================================================
-- Learning-Focused Settings
-- =============================================================================

-- Keep cursor vertically centered — always see context above and below
vim.opt.scrolloff = 12
vim.opt.sidescrolloff = 12

-- Wrap long lines at word boundaries (don't hide code off-screen)
vim.opt.wrap = true
vim.opt.linebreak = true

-- Always show where you are
vim.opt.cursorline = true

-- PEP 8 guide: 80-char column marker
vim.opt.textwidth = 80
vim.opt.colorcolumn = "80"

-- Absolute line numbers (simpler for learning — "error on line 15" is clear)
vim.opt.number = true
vim.opt.relativenumber = false

-- Smooth scrolling (if supported)
vim.opt.smoothscroll = true

-- Show matching brackets
vim.opt.showmatch = true
