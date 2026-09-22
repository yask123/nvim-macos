-- Dojo plugin specs: welcome screen, reading comfort, learning helpers, sound.

local header = [[
╺━━━━━━━━━━━━━━━╸
 ━━┳━━━━━━━━━┳━━
   ┃         ┃
   ┃         ┃

d o j o]]

-- A different Vim lesson on the dashboard every day.
local function tip_of_the_day()
  local lessons = {}
  for _, group in ipairs(require("dojo.keys")) do
    for _, section in ipairs(group.sections) do
      for _, item in ipairs(section.items) do
        if item.vim and item.vim ~= "" and not item.hidden then
          table.insert(lessons, item)
        end
      end
    end
  end
  local lesson = lessons[(tonumber(os.date("%j")) % #lessons) + 1]
  return {
    align = "center",
    padding = 1,
    text = {
      { "  today  ", hl = "SnacksDashboardDesc" },
      { " " .. lesson.vim .. " ", hl = "DojoVim" },
      { "  " .. lesson.desc, hl = "SnacksDashboardFooter" },
    },
  }
end

return {
  -- Welcome screen, pickers, explorer, scroll.
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      local project = function(fn)
        return function()
          require("dojo.project")[fn]()
        end
      end
      opts.scroll = { enabled = vim.g.neovide == nil } -- Neovide animates scrolling itself
      opts.image = { enabled = vim.g.neovide == nil } -- kitty graphics: Ghostty yes, Neovide no
      opts.styles = vim.tbl_deep_extend("force", opts.styles or {}, { zen = { width = 100 } })
      opts.picker = opts.picker or {}
      opts.picker.sources = vim.tbl_deep_extend("force", opts.picker.sources or {}, {
        projects = { dev = require("dojo.project").dev_dirs },
        -- A quiet file tree: no title or search line until you start searching.
        -- Press / in the tree to search; the line hides again when you leave it.
        explorer = {
          layout = { hidden = { "input" }, auto_hide = { "input" }, layout = { width = 32, min_width = 28 } },
        },
      })
      opts.dashboard = {
        width = 60,
        preset = {
          header = header,
          keys = {
            { icon = "\u{f07c} ", key = "o", desc = "Open Folder…", action = project("choose_folder") },
            { icon = "\u{f401} ", key = "p", desc = "Recent Projects", action = project("recent") },
            { icon = "\u{f002} ", key = "f", desc = "Find File", action = ":lua require('dojo.actions').find_file()" },
            { icon = "\u{f0c5} ", key = "r", desc = "Recent Files", action = ":lua Snacks.picker.recent()" },
            { icon = "\u{f082e} ", key = "n", desc = "New Note", action = ":Obsidian new" },
            { icon = "\u{f073} ", key = "d", desc = "Today's Note", action = ":Obsidian today" },
            { icon = "\u{f030c} ", key = "?", desc = "Keyboard Shortcuts", action = ":Dojo" },
            { icon = "\u{f0474} ", key = "l", desc = "Learn & Practise", action = ":DojoLearn" },
            { icon = "\u{e348} ", key = "s", desc = "Restore Session", section = "session" },
            { icon = "\u{f423} ", key = "c", desc = "Settings", action = ":lua require('dojo.actions').settings()" },
            { icon = "\u{f426} ", key = "q", desc = "Quit", action = ":qa" },
          },
        },
        sections = {
          { section = "header", padding = 2 },
          { section = "keys", gap = 1, padding = 2 },
          { icon = "\u{f401} ", title = "Recent Projects", section = "projects", indent = 2, padding = 2, limit = 5 },
          tip_of_the_day,
          { section = "startup" },
        },
      }
    end,
  },

  -- Completion that feels like VS Code: Tab or Enter accepts, docs pop up.
  {
    "saghen/blink.cmp",
    opts = {
      enabled = function()
        return vim.bo.buftype ~= "prompt" and vim.b.completion ~= false and vim.bo.filetype ~= "typr"
      end,
      keymap = { preset = "super-tab", ["<CR>"] = { "accept", "fallback" } },
      completion = {
        menu = { scrollbar = false },
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
        ghost_text = { enabled = true },
      },
      signature = { enabled = true },
    },
  },

  -- One signature popup (blink's), not two.
  {
    "folke/noice.nvim",
    opts = { lsp = { signature = { enabled = false } } },
  },

  -- Markdown: keep marksman + rendering, skip the lint noise while writing.
  {
    "mfussenegger/nvim-lint",
    opts = { linters_by_ft = { markdown = {} } },
  },

  -- Claude Code: also add files from the snacks explorer.
  {
    "coder/claudecode.nvim",
    keys = {
      {
        "<leader>as",
        "<cmd>ClaudeCodeTreeAdd<cr>",
        desc = "Add file",
        ft = { "NvimTree", "neo-tree", "oil", "minifiles", "netrw", "snacks_picker_list" },
      },
    },
  },

  ---------------------------------------------------------------------------
  -- Learning helpers
  ---------------------------------------------------------------------------

  -- Motion hints: shows where w, b, e, ^, $, % would jump (Space u P).
  {
    "tris203/precognition.nvim",
    event = "VeryLazy",
    opts = { startVisible = false, showBlankVirtLine = false, disabled_fts = { "snacks_dashboard" } },
  },

  -- Gentle coaching: a hint when there's a better motion than jjjj.
  {
    "m4xshen/hardtime.nvim",
    cmd = "Hardtime",
    dependencies = { "MunifTanjim/nui.nvim" },
    opts = {
      enabled = false, -- off by default; Space u H turns the coaching on
      restriction_mode = "hint",
      disable_mouse = false,
      max_count = 4,
      disabled_keys = { ["<Up>"] = false, ["<Down>"] = false, ["<Left>"] = false, ["<Right>"] = false },
      disabled_filetypes = {
        snacks_dashboard = true,
        snacks_picker_input = true,
        snacks_picker_list = true,
        typr = true,
      },
    },
  },

  -- Show the keys you press on screen (great for learning and screencasts).
  {
    "NStefan002/screenkey.nvim",
    cmd = "Screenkey",
    version = "*",
    opts = { group_mappings = true, show_leader = true },
  },

  -- Practice: a Vim motions game and a typing trainer.
  { "ThePrimeagen/vim-be-good", cmd = "VimBeGood" },
  { "nvzone/typr", dependencies = { "nvzone/volt" }, cmd = { "Typr", "TyprStats" }, opts = {} },

  ---------------------------------------------------------------------------
  -- Game-style sound effects: a tiny Swift daemon (sfx/nvsfx.swift) fed over
  -- a pipe. Builds itself on first use (swiftc + python3, ~3 s, async).
  -- Only runs with a UI attached; NVIM_SFX=0 or SSH turns it off.
  ---------------------------------------------------------------------------
  {
    dir = vim.fn.stdpath("config") .. "/sfx",
    name = "sfx",
    lazy = false,
    cond = function()
      return #vim.api.nvim_list_uis() > 0
    end,
    -- Subtle by default: a soft keyboard "thock" while typing and a quiet
    -- bell on save and run. The retro cues (mode blips, yank/undo, start
    -- jingle) still exist in the pack; enable them here if you want them.
    opts = {
      volume = 0.3,
      idle_suspend = 20,
      buffer_frames = 256,
      events = {
        typing = true,
        enter = true,
        backspace = true,
        save = true,
        run = true,
        mode = false,
        visual = false,
        start = false,
        quit = false,
        yank = false,
        paste = false,
        undo = false,
      },
    },
    config = function(_, opts)
      require("sfx").setup(opts)
      Snacks.toggle
        .new({
          id = "sfx",
          name = "Sound Effects",
          get = function()
            return require("sfx").opts.enabled
          end,
          set = function(enabled)
            require("sfx").set_enabled(enabled)
          end,
        })
        :map("<leader>uM")
    end,
  },
}
