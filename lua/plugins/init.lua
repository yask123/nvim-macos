return {
  -- Disable flash.nvim completely (not using it, conflicts with surround)
  {
    "folke/flash.nvim",
    enabled = false,
  },

  -- Configure mini.surround with explicit keybindings
  {
    "nvim-mini/mini.surround",
    opts = {
      mappings = {
        add = "sa", -- Add surrounding in Normal and Visual modes
        delete = "sd", -- Delete surrounding
        find = "sf", -- Find surrounding (to the right)
        find_left = "sF", -- Find surrounding (to the left)
        highlight = "sh", -- Highlight surrounding
        replace = "sr", -- Replace surrounding
        update_n_lines = "sn", -- Update `n_lines`
      },
    },
  },

  -- Multi-cursor support (Sublime Text / VSCode style)
  -- Ctrl+n = select word, add next occurrence
  -- Ctrl+Down/Up = add cursor below/above
  -- n/N = get next/prev occurrence
  -- q = skip current and get next
  -- Q = remove current cursor
  {
    "mg979/vim-visual-multi",
    branch = "master",
    event = "VeryLazy",
    init = function()
      vim.g.VM_maps = {
        ["Find Under"] = "<C-n>", -- Select word, add next match
        ["Find Subword Under"] = "<C-n>", -- Same for subwords
        ["Select All"] = "\\A", -- Select all occurrences (backslash + A)
        ["Add Cursor Down"] = "<C-Down>", -- Add cursor below
        ["Add Cursor Up"] = "<C-Up>", -- Add cursor above
      }
      vim.g.VM_theme = "iceblue"
    end,
  },

  -- Add mini.comment for commenting functionality
  {
    "nvim-mini/mini.comment",
    event = "VeryLazy",
    opts = {
      options = {
        custom_commentstring = nil,
      },
    },
  },

  -- Toggleterm disabled — conflicts with zen-mode window management.
  -- Using Snacks.terminal (LazyVim built-in) instead. See keymaps.lua for <C-\> mapping.
  {
    "akinsho/toggleterm.nvim",
    enabled = false,
  },

  -- TypeScript support
  -- moved to config/lazy.lua

  -- Python support with basedpyright LSP
  -- moved to config/lazy.lua

  -- Auto-save like VSCode/Zed
  {
    "okuuva/auto-save.nvim",
    version = "^1.0.0",
    opts = {
      enabled = true,
      trigger_events = {
        immediate_save = {},
        defer_save = { "InsertLeave", "TextChanged" },
        cancel_deferred_save = { "InsertEnter" },
      },
      condition = function(buf)
        return vim.bo[buf].modifiable and vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= ""
      end,
      write_all_buffers = false,
      debounce_delay = 1000,
    },
  },
}
