-- =============================================================================
-- Learning Mode: UI Simplification
-- =============================================================================
-- Strips away IDE-heavy features to create a focused Python learning environment.
-- Keeps: treesitter, completion, auto-save, terminal
-- Simplifies: bufferline, lualine, noice, gitsigns
-- Disables: zen-mode, twilight (caused window management conflicts)

return {
  -- Hide the buffer tab bar (single-file focus for learning)
  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        always_show_bufferline = false,
      },
      -- no italics anywhere, including the active tab
      highlights = (function()
        local groups = {}
        for _, name in ipairs({
          "buffer_selected",
          "numbers_selected",
          "diagnostic_selected",
          "hint_selected",
          "hint_diagnostic_selected",
          "info_selected",
          "info_diagnostic_selected",
          "warning_selected",
          "warning_diagnostic_selected",
          "error_selected",
          "error_diagnostic_selected",
          "pick_selected",
          "pick_visible",
          "pick",
          "duplicate_selected",
          "duplicate_visible",
          "duplicate",
          "buffer_visible",
          "numbers_visible",
        }) do
          groups[name] = { italic = false }
        end
        return groups
      end)(),
    },
  },

  -- Minimal status line: mode + filename + position. The mode pill matters
  -- most while learning: it always says whether keys type text or give commands.
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.component_separators = { left = "", right = "" }
      opts.options.section_separators = { left = "", right = "" }

      opts.sections = {
        lualine_a = {
          { "mode", padding = { left = 1, right = 1 } },
        },
        lualine_b = {},
        lualine_c = {
          {
            "filename",
            path = 0,
            symbols = { modified = " *", readonly = " ", unnamed = "[scratch]" },
          },
        },
        lualine_x = {
          { "diagnostics", symbols = { error = "E:", warn = "W:" } },
        },
        lualine_y = {
          { "progress", padding = { left = 1, right = 1 } },
        },
        lualine_z = {
          { "location", padding = { left = 0, right = 1 } },
        },
      }

      opts.inactive_sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_c = { { "filename", path = 0 } },
        lualine_x = {},
        lualine_y = {},
        lualine_z = {},
      }
    end,
  },

  -- Disable gitsigns for learning (no git gutter noise)
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      signs = {
        add = { text = "" },
        change = { text = "" },
        delete = { text = "" },
        topdelete = { text = "" },
        changedelete = { text = "" },
      },
      signcolumn = false,
    },
  },

  -- Simplify noice (less popup animation, cleaner command line)
  {
    "folke/noice.nvim",
    opts = {
      presets = {
        bottom_search = true,
        command_palette = false,
        long_message_to_split = true,
        lsp_doc_border = true,
      },
      routes = {
        { filter = { event = "msg_show", kind = "", find = "written" }, opts = { skip = true } },
        { filter = { event = "msg_show", kind = "search_count" }, opts = { skip = true } },
      },
    },
  },

  -- Disable zen-mode (conflicts with terminal/floating windows)
  {
    "folke/zen-mode.nvim",
    enabled = false,
  },

  -- Disable twilight (paired with zen-mode)
  {
    "folke/twilight.nvim",
    enabled = false,
  },
}
