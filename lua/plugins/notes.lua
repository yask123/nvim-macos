return {
  -- Zen-mode and twilight disabled in plugins/learning.lua

  -- Render Markdown: Aesthetic rendering
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      code = {
        sign = false,
        width = "block",
        right_pad = 1,
      },
      heading = {
        sign = false,
        icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
      },
    },
    ft = { "markdown", "norg", "rmd", "org" },
    config = function(_, opts)
      require("render-markdown").setup(opts)
    end,
  },

  -- 4. Obsidian.nvim: Note management
  {
    "epwalsh/obsidian.nvim",
    version = "*",
    lazy = true,
    cmd = {
      "ObsidianNew",
      "ObsidianSearch",
      "ObsidianQuickSwitch",
      "ObsidianToday",
      "ObsidianTemplate",
      "ObsidianLinks",
      "ObsidianBacklinks",
      "ObsidianOpen",
    },
    ft = "markdown",
    dependencies = {
      "nvim-lua/plenary.nvim",
      -- "hrsh7th/nvim-cmp", -- Removed: User uses blink.cmp
    },
    init = function()
      vim.api.nvim_create_user_command("Notes", function()
        local actions = {
          { label = "Find note", cmd = "ObsidianQuickSwitch" },
          { label = "Search notes (grep)", cmd = "ObsidianSearch" },
          { label = "Daily note (today)", cmd = "ObsidianToday" },
          { label = "New note", cmd = "ObsidianNew" },
          { label = "Insert template", cmd = "ObsidianTemplate" },
          { label = "Show links", cmd = "ObsidianLinks" },
          { label = "Show backlinks", cmd = "ObsidianBacklinks" },
        }

        vim.ui.select(actions, {
          prompt = "Notes",
          format_item = function(item)
            return item.label
          end,
        }, function(choice)
          if not choice then
            return
          end
          vim.cmd(choice.cmd)
        end)
      end, { desc = "Notes menu (Obsidian)" })
    end,
    keys = {
      { "<leader>nn", "<cmd>ObsidianNew<cr>", desc = "New Note" },
      { "<leader>ns", "<cmd>ObsidianSearch<cr>", desc = "Search Notes (Grep)" },
      { "<leader>nf", "<cmd>ObsidianQuickSwitch<cr>", desc = "Find Note (File)" },
      { "<leader>nd", "<cmd>ObsidianToday<cr>", desc = "Daily Note" },
      { "<leader>nt", "<cmd>ObsidianTemplate<cr>", desc = "Insert Template" },
      { "<leader>nl", "<cmd>ObsidianLinks<cr>", desc = "Show Links" },
      { "<leader>nb", "<cmd>ObsidianBacklinks<cr>", desc = "Show Backlinks" },
      { "<leader>nH", "<cmd>Notes<cr>", desc = "Notes Home" },
    },
    opts = {
      workspaces = {
        {
          name = "notes",
          path = "~/notes",
        },
      },
      daily_notes = {
        folder = "dailies",
        date_format = "%Y-%m-%d",
        alias_format = "%B %-d, %Y",
      },
      completion = {
        nvim_cmp = false, -- Disabled to prevent crash with blink.cmp
        min_chars = 2,
      },
      mappings = {
        ["gf"] = {
          action = function()
            return require("obsidian").util.gf_passthrough()
          end,
          opts = { noremap = false, expr = true, buffer = true },
        },
        ["<leader>ch"] = {
          action = function()
            return require("obsidian").util.toggle_checkbox()
          end,
          opts = { buffer = true },
        },
      },
      ui = {
        enable = false,
      },
    },
  },

  -- 5. Blink Compatibility (for Obsidian completion)
  {
    "saghen/blink.compat",
    lazy = true,
    opts = {},
    version = "*",
  },

  -- 6. Configure Blink to use Obsidian source
  {
    "saghen/blink.cmp",
    dependencies = { "saghen/blink.compat" },
    opts = function(_, opts)
      -- Ensure sources table exists
      opts.sources = opts.sources or {}
      opts.sources.default = opts.sources.default or {}

      -- Add obsidian to the default sources list if not present
      if not vim.tbl_contains(opts.sources.default, "obsidian") then
        table.insert(opts.sources.default, "obsidian")
      end

      -- Define the obsidian provider
      opts.sources.providers = opts.sources.providers or {}
      opts.sources.providers.obsidian = {
        name = "obsidian",
        module = "blink.compat.source",
        score_offset = 100, -- Give it high priority in markdown
      }
    end,
  },
}
