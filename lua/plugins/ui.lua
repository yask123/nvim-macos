-- The editor chrome, kept quiet: plain tabs, a one-line status bar that sits
-- in the editor's own background, no gutter noise, no progress chatter.

-- "python" → "Python", "typescriptreact" → "TypeScript React", …
local languages = {
  c = "C",
  cpp = "C++",
  cs = "C#",
  css = "CSS",
  html = "HTML",
  javascript = "JavaScript",
  javascriptreact = "JavaScript React",
  json = "JSON",
  jsonc = "JSON",
  lua = "Lua",
  markdown = "Markdown",
  sh = "Shell",
  zsh = "Shell",
  sql = "SQL",
  toml = "TOML",
  typescript = "TypeScript",
  typescriptreact = "TypeScript React",
  yaml = "YAML",
}

-- Status details only for real files (not the tree, welcome screen or a terminal).
local function is_file()
  return vim.bo.buftype == ""
end

local function language()
  local ft = vim.bo.filetype
  if ft == "" or not is_file() then
    return ""
  end
  return languages[ft] or (ft:sub(1, 1):upper() .. ft:sub(2))
end

-- Only say the mode when it isn't Normal: the cursor shape already tells you.
local function mode()
  local name = require("lualine.utils.mode").get_mode()
  return name == "NORMAL" and "" or name:sub(1, 1) .. name:sub(2):lower()
end

-- Every lualine section in the editor's own colours: no pills, no bars.
local function theme()
  local function get(group, attr)
    local value = vim.api.nvim_get_hl(0, { name = group, link = false })[attr]
    return value and ("#%06x"):format(value) or nil
  end
  local bg = get("Normal", "bg")
  local quiet = { fg = get("Comment", "fg"), bg = bg }
  local section = { a = quiet, b = quiet, c = quiet, x = quiet, y = quiet, z = quiet }
  return {
    normal = section,
    insert = section,
    visual = section,
    replace = section,
    command = section,
    terminal = section,
    inactive = section,
  }
end

return {
  -- Tabs: file names only. No close buttons, badges or coloured icons.
  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        always_show_bufferline = false,
        diagnostics = false,
        show_buffer_close_icons = false,
        show_close_icon = false,
        color_icons = false,
        modified_icon = "●",
        separator_style = { "", "" },
        indicator = { style = "none" },
        tab_size = 14,
      },
      -- One surface with the editor: no darker strip, no italics. The open
      -- file is bright, the others quiet.
      highlights = (function()
        local bg = { attribute = "bg", highlight = "Normal" }
        local quiet = { attribute = "fg", highlight = "Comment" }
        local groups = {
          fill = { bg = bg },
          background = { bg = bg, fg = quiet },
          buffer_visible = { bg = bg, fg = quiet, italic = false },
          buffer_selected = { bg = bg, bold = true, italic = false },
          modified = { bg = bg, fg = quiet },
          modified_visible = { bg = bg, fg = quiet },
          modified_selected = { bg = bg },
          separator = { bg = bg, fg = bg },
          separator_visible = { bg = bg, fg = bg },
          separator_selected = { bg = bg, fg = bg },
          indicator_visible = { bg = bg, fg = bg },
          indicator_selected = { bg = bg, fg = bg },
          duplicate = { bg = bg, fg = quiet, italic = false },
          duplicate_visible = { bg = bg, fg = quiet, italic = false },
          duplicate_selected = { bg = bg, italic = false },
          offset_separator = { bg = bg, fg = bg },
          tab = { bg = bg, fg = quiet },
          tab_selected = { bg = bg },
          tab_separator = { bg = bg, fg = bg },
          tab_separator_selected = { bg = bg, fg = bg },
          tab_close = { bg = bg },
          close_button = { bg = bg },
          close_button_visible = { bg = bg },
          close_button_selected = { bg = bg },
        }
        for _, name in ipairs({ "numbers_selected", "numbers_visible", "pick", "pick_visible", "pick_selected" }) do
          groups[name] = { bg = bg, italic = false }
        end
        return groups
      end)(),
    },
  },

  -- Status bar, Sublime-style: file on the left; problems, position,
  -- language and branch on the right. The mode shows only outside Normal.
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.theme = theme()
      opts.options.component_separators = { left = "", right = "" }
      opts.options.section_separators = { left = "", right = "" }

      local accent = function()
        local fg = vim.api.nvim_get_hl(0, { name = "Function", link = false }).fg
        return { fg = fg and ("#%06x"):format(fg) or nil }
      end
      opts.sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_c = {
          { mode, cond = is_file, color = accent, padding = { left = 1, right = 1 } },
          {
            "filename",
            path = 1,
            cond = is_file,
            symbols = { modified = " ●", readonly = " (read only)", unnamed = "Untitled", newfile = "" },
          },
        },
        lualine_x = {
          {
            "diagnostics",
            sections = { "error", "warn" },
            symbols = { error = "● ", warn = "● " },
          },
          {
            function()
              return ("Ln %d, Col %d"):format(vim.fn.line("."), vim.fn.virtcol("."))
            end,
            cond = is_file,
          },
          { language },
          { "branch", icon = "", cond = is_file },
        },
        lualine_y = {},
        lualine_z = {},
      }
      opts.inactive_sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_c = { { "filename", path = 1, cond = is_file } },
        lualine_x = {},
        lualine_y = {},
        lualine_z = {},
      }
      opts.extensions = {}
    end,
    config = function(_, opts)
      require("lualine").setup(opts)
      -- Rebuild the colours whenever the theme changes.
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("DojoStatusline", { clear = true }),
        callback = function()
          vim.schedule(function()
            opts.options.theme = theme()
            require("lualine").setup(opts)
          end)
        end,
      })
    end,
  },

  -- No git marks in the gutter; lazygit (⌃⇧G) shows changes when you ask.
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

  -- Messages: search at the bottom like a normal editor, no "written" or
  -- "3/12" chatter, no language-server progress spinners.
  {
    "folke/noice.nvim",
    opts = {
      lsp = { progress = { enabled = false } },
      presets = {
        bottom_search = true,
        command_palette = false,
        long_message_to_split = true,
        lsp_doc_border = false,
      },
      routes = {
        { filter = { event = "msg_show", kind = "", find = "written" }, opts = { skip = true } },
        { filter = { event = "msg_show", kind = "search_count" }, opts = { skip = true } },
      },
    },
  },

  -- Plain notifications: one line of text, no icon or title bar.
  {
    "folke/snacks.nvim",
    opts = { notifier = { style = "minimal" } },
  },

  -- Leader-key hints appear only if you pause, not on every keystroke.
  {
    "folke/which-key.nvim",
    opts = { delay = 400 },
  },

  -- Disabled: zen-mode and twilight (Snacks.zen covers it).
  { "folke/zen-mode.nvim", enabled = false },
  { "folke/twilight.nvim", enabled = false },
}
