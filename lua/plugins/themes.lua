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

  -- Catppuccin: Mocha after dark, Latte by day — follows macOS automatically.
  -- Use `colorscheme catppuccin` (never a flavour name) so Neovide and the
  -- terminal can flip 'background' when the system appearance changes.
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "auto",
      no_italic = true,
      background = { light = "latte", dark = "mocha" },
      transparent_background = false,
      float = { transparent = false, solid = true }, -- borderless "card" floats (see winborder)
      dim_inactive = { enabled = true, shade = "dark", percentage = 0.12 },
      term_colors = true,
      -- No italics in code: comments are simply quieter in colour.
      styles = {
        comments = {},
        conditionals = {},
        keywords = {},
        functions = {},
        types = {},
        miscs = {}, -- catppuccin italicises some built-ins by default
      },
      lsp_styles = {
        underlines = {
          errors = { "undercurl" },
          hints = { "undercurl" },
          warnings = { "undercurl" },
          information = { "undercurl" },
        },
      },
      integrations = { noice = true, notify = true },
      -- Latte readability pass: same hues, darkened until accents reach ~4.5:1.
      color_overrides = {
        latte = {
          rosewater = "#a55848",
          flamingo = "#b05052",
          pink = "#b24297",
          maroon = "#cf2c41",
          peach = "#bd4804",
          yellow = "#9d6000",
          green = "#217f02",
          teal = "#097a80",
          sky = "#0275a4",
          sapphire = "#09798b",
          lavender = "#5363d6",
        },
      },
      highlight_overrides = {
        all = function(c)
          return {
            LineNr = { fg = c.overlay0 },
            CursorLineNr = { fg = c.lavender, style = { "bold" } },
            WinSeparator = { fg = c.surface0 },
            ColorColumn = { bg = c.mantle },
            -- Spelling: a soft dotted hint, not a red alarm; no capitalisation nags.
            SpellBad = { sp = c.overlay1, style = { "undercurl" } },
            SpellCap = {},
            SpellRare = {},
            SpellLocal = {},
            -- Quiet panel titles instead of coloured pills.
            FloatTitle = { fg = c.subtext0, bg = c.mantle },
            SnacksPickerTitle = { fg = c.subtext0, bg = c.mantle },
            SnacksPickerInputTitle = { fg = c.subtext0, bg = c.mantle },
            SnacksPickerListTitle = { fg = c.subtext0, bg = c.mantle },
            SnacksPickerPreviewTitle = { fg = c.subtext0, bg = c.mantle },
            SnacksPickerBoxTitle = { fg = c.subtext0, bg = c.mantle },
            SnacksDashboardHeader = { fg = c.lavender },
          }
        end,
        latte = function(c)
          return {
            Comment = { fg = c.subtext0 },
            LineNr = { fg = c.overlay1 },
          }
        end,
      },
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
    end,
  },

  -- Kanso: a zen, almost monochrome mood for long writing sessions.
  {
    "webhooked/kanso.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      background = { dark = "ink", light = "pearl" },
      foreground = { dark = "saturated", light = "saturated" },
      dimInactive = true,
      commentStyle = { italic = false },
      keywordStyle = { italic = false },
    },
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

  -- Rosé Pine: the Dojo default. Moon after dark, Dawn by day (follows macOS).
  -- No italics, dimmed inactive windows, and brighter keywords/strings where
  -- the stock palette is too faint to read comfortably.
  {
    "rose-pine/neovim",
    name = "rose-pine",
    lazy = false,
    priority = 1000,
    opts = {
      variant = "auto",
      dark_variant = "moon",
      dim_inactive_windows = true,
      extend_background_behind_borders = true,
      styles = { bold = true, italic = false, transparency = false },
      palette = {
        main = { pine = "#4f91ad" },
        moon = { pine = "#4b9bbc" },
        dawn = { gold = "#9d6306", rose = "#a95956", foam = "#3b7984" },
      },
      highlight_groups = {
        Comment = { fg = "subtle", italic = false },
        LineNr = { fg = "muted" },
        CursorLineNr = { fg = "rose", bold = true },
        FloatTitle = { fg = "subtle", bg = "surface", bold = false },
        SnacksPickerTitle = { fg = "subtle", bg = "surface" },
        SnacksPickerInputTitle = { fg = "subtle", bg = "surface" },
        SnacksPickerListTitle = { fg = "subtle", bg = "surface" },
        SnacksPickerPreviewTitle = { fg = "subtle", bg = "surface" },
        SnacksDashboardHeader = { fg = "iris" },
        SpellBad = { sp = "muted", undercurl = true },
        SpellCap = {},
        SpellRare = {},
        SpellLocal = {},
      },
    },
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
