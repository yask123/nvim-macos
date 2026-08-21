-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- =============================================================================
-- Python Learning: Run & Output
-- =============================================================================
-- The core learning loop: write code → run → see output → iterate

local runner = require("config.runner")
vim.keymap.set("n", "<leader>rr", runner.run, { silent = true, desc = "Run current file" })
vim.keymap.set("n", "<leader>rc", runner.run, { silent = true, desc = "Run (fresh output)" })
vim.keymap.set("n", "<leader>rq", runner.close, { silent = true, desc = "Close output panel" })

-- =============================================================================
-- Learning Tutor: understand the selection or current file without editing it
-- =============================================================================

local tutor = require("config.tutor")
tutor.setup()
vim.keymap.set("n", "<leader>ta", tutor.ask_file, { silent = true, desc = "Ask Tutor about file" })
vim.keymap.set("x", "<leader>ta", tutor.ask_selection, { silent = true, desc = "Ask Tutor about selection" })
vim.keymap.set("n", "<leader>tt", tutor.toggle, { silent = true, desc = "Toggle Tutor sidebar" })

-- =============================================================================
-- General Terminal (replaces toggleterm with Snacks.terminal)
-- =============================================================================
-- Ctrl+\ opens a floating terminal — works perfectly with zen-mode

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
-- Python Learning: Interactive REPL
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
-- Learning Mode Toggle (no zen-mode, just native options)
-- =============================================================================

vim.keymap.set("n", "<leader>zl", function()
  -- Toggle between focused (no chrome) and normal (full chrome) view
  if vim.o.laststatus == 0 then
    -- Restore normal view
    vim.o.laststatus = 3
    vim.o.showtabline = 2
    vim.wo.signcolumn = "yes"
    vim.notify("Normal mode", vim.log.levels.INFO)
  else
    -- Enter focused view
    vim.o.laststatus = 0
    vim.o.showtabline = 0
    vim.wo.signcolumn = "no"
    vim.notify("Focus mode", vim.log.levels.INFO)
  end
end, { noremap = true, silent = true, desc = "Toggle Focus Mode" })

-- =============================================================================
-- Core Keymaps (preserved from original)
-- =============================================================================

-- Claude Code integration is handled by claudecode.nvim plugin
-- Keymaps: <leader>ac (toggle), <leader>as (send selection), <leader>ab (add file)

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

-- Select all text
vim.keymap.set({ "n", "i" }, "<C-a>", "<Esc>ggVG", { desc = "Select All" })

-- Disable macro recording (q key) - prevent accidental triggers
vim.keymap.set("n", "q", "<Nop>", { noremap = true, silent = true, desc = "Disabled (macro recording)" })

-- Claude Code: Send visual selection
vim.keymap.set("v", "<leader>as", ":ClaudeCodeSend<CR>", { noremap = true, silent = true, desc = "Send to Claude" })

-- Pick and save colorscheme permanently
vim.keymap.set("n", "<leader>uC", function()
  vim.ui.select(vim.fn.getcompletion("", "color"), { prompt = "Select colorscheme:" }, function(choice)
    if choice then
      vim.cmd.colorscheme(choice)
      require("config.theme").save(choice)
      vim.notify("Colorscheme saved: " .. choice, vim.log.levels.INFO)
    end
  end)
end, { desc = "Pick & save colorscheme" })
