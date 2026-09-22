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

  -- Multiple cursors, VS Code style:
  --   ⌘D / Ctrl-n  add the next match of the word (or selection)
  --   ⌘⇧L          add every match
  --   ⌘⌥↑ / ⌘⌥↓    add a cursor above / below
  --   Esc          clear the extra cursors
  -- Edit with normal Vim commands; every cursor follows along.
  {
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    event = "VeryLazy",
    config = function()
      local mc = require("multicursor-nvim")
      mc.setup()
      local set = vim.keymap.set
      -- ⌘D / ⌘⇧L are wired through the Dojo registry (lua/dojo/keys.lua).
      set({ "n", "x" }, "<C-n>", function()
        mc.matchAddCursor(1)
      end, { desc = "Add cursor at next match" })
      set({ "n", "x", "i" }, "<D-M-Up>", function()
        mc.lineAddCursor(-1)
      end, { desc = "Add cursor above" })
      set({ "n", "x", "i" }, "<D-M-Down>", function()
        mc.lineAddCursor(1)
      end, { desc = "Add cursor below" })
      set("n", "<C-LeftMouse>", mc.handleMouse, { desc = "Add cursor at click" })
      set("n", "<C-LeftDrag>", mc.handleMouseDrag)
      set("n", "<C-LeftRelease>", mc.handleMouseRelease)
      mc.addKeymapLayer(function(layer)
        layer("n", "<Esc>", function()
          if not mc.cursorsEnabled() then
            mc.enableCursors()
          else
            mc.clearCursors()
          end
        end)
      end)
    end,
  },

  -- Toggleterm disabled — conflicts with zen-mode window management.
  -- Using Snacks.terminal (LazyVim built-in) instead. See keymaps.lua for <C-\> mapping.
  {
    "akinsho/toggleterm.nvim",
    enabled = false,
  },

  -- Auto-save like VSCode/Zed. Background saves skip format-on-save (so code
  -- isn't reformatted a second after every pause); an explicit ⌘S / :w formats.
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
    init = function()
      local group = vim.api.nvim_create_augroup("DojoAutoSaveNoFormat", { clear = true })
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "AutoSaveWritePre",
        callback = function(ev)
          local buf = ev.data and ev.data.saved_buffer or vim.api.nvim_get_current_buf()
          vim.b[buf].dojo_autoformat = vim.b[buf].autoformat
          vim.b[buf].autoformat = false
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "AutoSaveWritePost",
        callback = function(ev)
          local buf = ev.data and ev.data.saved_buffer or vim.api.nvim_get_current_buf()
          vim.b[buf].autoformat = vim.b[buf].dojo_autoformat
          vim.b[buf].dojo_autoformat = nil
        end,
      })
    end,
  },
}
