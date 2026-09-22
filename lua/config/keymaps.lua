-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- =============================================================================
-- Run & Output
-- =============================================================================

local runner = require("config.runner")
vim.keymap.set("n", "<leader>rr", runner.run, { silent = true, desc = "Run current file" })
vim.keymap.set("n", "<leader>rc", runner.run, { silent = true, desc = "Run (fresh output)" })
vim.keymap.set("n", "<leader>rq", runner.close, { silent = true, desc = "Close output panel" })

-- =============================================================================
-- General Terminal (replaces toggleterm with Snacks.terminal)
-- =============================================================================
-- Ctrl+\ opens a floating terminal

vim.keymap.set({ "n", "t", "i" }, [[<C-\>]], function()
  Snacks.terminal(nil, {
    win = {
      style = "float",
      width = 0.8,
      height = 0.8,
    },
  })
end, { noremap = true, silent = true, desc = "Toggle terminal" })

-- =============================================================================
-- Python REPL
-- =============================================================================

vim.keymap.set("n", "<leader>ri", function()
  Snacks.terminal("python3", {
    win = {
      style = "float",
      width = 0.8,
      height = 0.8,
    },
  })
end, { noremap = true, silent = true, desc = "Open Python REPL" })

-- =============================================================================
-- Core Keymaps (preserved from original)
-- =============================================================================

vim.api.nvim_set_keymap("n", "<leader>w", ":w<CR>", { noremap = true, silent = true })

-- Close current buffer with Ctrl+W (VSCode-style, overrides window commands)
vim.keymap.set("n", "<C-w>", function()
  local has_bufremove, bufremove = pcall(require, "mini.bufremove")
  if has_bufremove then
    bufremove.delete(0, false)
  else
    vim.cmd("bdelete")
  end
end, { noremap = true, silent = true, desc = "Close buffer" })

-- Navigate buffers (terminal-friendly alternatives)
vim.keymap.set("n", "<S-Tab>", ":bprevious<CR>", { noremap = true, silent = true, desc = "Previous buffer" })
vim.keymap.set("n", "<Tab>", ":bnext<CR>", { noremap = true, silent = true, desc = "Next buffer" })

-- Close all other buffers (keep only current one)
vim.keymap.set("n", "<leader>bo", function()
  local current_buf = vim.api.nvim_get_current_buf()
  local has_bufremove, bufremove = pcall(require, "mini.bufremove")

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= current_buf and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
      if has_bufremove then
        bufremove.delete(buf, false)
      else
        vim.api.nvim_buf_delete(buf, { force = false })
      end
    end
  end
end, { noremap = true, silent = true, desc = "Close all other buffers" })

-- macOS text keys: Ctrl-A / Ctrl-E jump to line start / end (as in every Mac
-- text field and VS Code). Ghostty also sends these for ⌘← / ⌘→.
-- Select all is ⌘A.
vim.keymap.set("n", "<C-a>", "^", { desc = "Line start" })
vim.keymap.set("i", "<C-a>", "<C-o>^", { desc = "Line start" })
vim.keymap.set("i", "<C-e>", "<End>", { desc = "Line end" })

-- Disable macro recording (q key) - prevent accidental triggers
vim.keymap.set("n", "q", "<Nop>", { noremap = true, silent = true, desc = "Disabled (macro recording)" })

-- Pick and save a colour theme (previews as you move through the list)
vim.keymap.set("n", "<leader>uC", function()
  require("dojo.theme").pick()
end, { desc = "Pick & save colorscheme" })

-- Dojo: Cmd-key layer, cheatsheet, palette, projects (lua/dojo)
require("dojo").setup()
