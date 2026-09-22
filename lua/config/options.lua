-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Time to wait for a mapped sequence to complete (milliseconds)
-- 300 = fast but must type quickly, 500 = balanced, 1000 = relaxed
vim.opt.timeoutlen = 500

-- Use treesitter for better folding
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
-- Folds start open; big files open as an outline (lua/dojo/folds.lua)

-- Python LSP Configuration
-- Use basedpyright (latest fork with more features) instead of pyright
vim.g.lazyvim_python_lsp = "basedpyright"
-- Use ruff for fast linting and formatting
vim.g.lazyvim_python_ruff = "ruff"

-- Disable inlay hints globally (no type annotations)
-- Note: This is handled in the LSP on_attach callback in python.lua

-- =============================================================================
-- Reading comfort
-- =============================================================================

-- Keep cursor vertically centered — always see context above and below
vim.opt.scrolloff = 12
vim.opt.sidescrolloff = 12

-- Soft-wrap long lines at word boundaries (never hide code off-screen).
-- Continuation lines keep their indent, nudged in a little; no marker glyph.
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.breakindent = true
vim.opt.breakindentopt = "shift:2,min:40"
vim.opt.showbreak = ""

-- Always show where you are
vim.opt.cursorline = true

-- No hard wrapping while typing and no rulers: formatters own line length.
vim.opt.textwidth = 0
vim.opt.colorcolumn = ""

-- No UI animations (scroll, indent guides, zen, dim): everything is instant.
vim.g.snacks_animate = false

-- Borderless "card" floats (hover, completion docs, pickers).
vim.o.winborder = "solid"

-- Absolute line numbers ("error on line 15" is clear)
vim.opt.number = true
vim.opt.relativenumber = false

-- Smooth scrolling (if supported)
vim.opt.smoothscroll = true

-- Show matching brackets
vim.opt.showmatch = true

-- Neovide (the Dojo app): motion, padding, window chrome.
require("dojo.gui").setup()
