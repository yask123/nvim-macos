return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        vim.cmd.colorscheme(require("config.theme").get())
      end,
    },
  },

  -- Popular, eye-friendly themes (dark + light variants)

  -- Catppuccin (Mocha/Macchiato/Frappe + Latte)
  -- Tuned for Python learning: clear syntax distinction, readable comments
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      -- Latte for daytime, Mocha for evening (switch with <leader>uC)
      flavour = "latte",
      background = {
        light = "latte",
        dark = "mocha",
      },
      -- Subtle transparent feel
      transparent_background = false,
      -- Better distinction between code elements
      styles = {
        comments = { "italic" }, -- Italic comments: visually secondary but readable
        conditionals = { "bold" }, -- Bold if/else/for: structural clarity
        functions = { "bold" }, -- Bold function names: easy to spot
        keywords = { "bold" }, -- Bold keywords: Python's def, class, return stand out
        strings = {}, -- Normal strings
        variables = {}, -- Normal variables
      },
      integrations = {
        cmp = true,
        gitsigns = true,
        treesitter = true,
        which_key = true,
        noice = true,
        notify = true,
        zen_mode = true,
        -- Better diagnostics underlines
        native_lsp = {
          enabled = true,
          underlines = {
            errors = { "undercurl" },
            hints = { "undercurl" },
            warnings = { "undercurl" },
            information = { "undercurl" },
          },
        },
      },
      -- Custom overrides for better learning readability
      custom_highlights = function(colors)
        return {
          -- Make the color column very subtle (not distracting)
          ColorColumn = { bg = colors.mantle },
          -- Slightly more visible cursor line
          CursorLine = { bg = colors.mantle },
          -- Cleaner line numbers
          LineNr = { fg = colors.surface1 },
          CursorLineNr = { fg = colors.blue, style = { "bold" } },
        }
      end,
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
    end,
  },

  -- Kanagawa (wave/dragon/lotus)
  {
    "rebelot/kanagawa.nvim",
    lazy = false,
    priority = 1000,
    opts = {},
    config = function(_, opts)
      require("kanagawa").setup(opts)
    end,
  },

  -- Rose Pine (rose-pine, rose-pine-moon, rose-pine-dawn)
  {
    "rose-pine/neovim",
    name = "rose-pine",
    lazy = false,
    priority = 1000,
    opts = {},
    config = function(_, opts)
      require("rose-pine").setup(opts)
    end,
  },

  -- GitHub theme (great light variants like github_light)
  {
    "projekt0n/github-nvim-theme",
    lazy = false,
    priority = 1000,
    opts = {},
    config = function(_, opts)
      require("github-theme").setup(opts)
    end,
  },

  -- Nightfox family (nightfox/dayfox/dawnfox/duskfox/etc.)
  {
    "EdenEast/nightfox.nvim",
    lazy = false,
    priority = 1000,
    opts = {},
    config = function(_, opts)
      require("nightfox").setup(opts)
    end,
  },
}
