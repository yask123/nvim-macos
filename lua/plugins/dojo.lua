-- Dojo plugin specs: welcome screen, completion, typing sounds.

-- The welcome screen: a quiet wordmark, a few actions, your recent projects.
local header = "d o j o"

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
      -- The terminal panel is labelled plainly, not "1: term://~/project//4242".
      opts.terminal = vim.tbl_deep_extend("force", opts.terminal or {}, {
        win = { wo = { winbar = "%#Comment#  Terminal" } },
      })
      opts.picker = opts.picker or {}
      -- One Esc closes a picker, as in any Mac app (not "leave typing, then close").
      opts.picker.win = vim.tbl_deep_extend("force", opts.picker.win or {}, {
        input = { keys = { ["<Esc>"] = { "cancel", mode = { "n", "i" } } } },
      })
      opts.picker.sources = vim.tbl_deep_extend("force", opts.picker.sources or {}, {
        projects = { dev = require("dojo.project").dev_dirs },
        -- A quiet file tree: no title or search line until you start searching.
        -- Press / in the tree to search; the line hides again when you leave it.
        explorer = {
          layout = { hidden = { "input" }, auto_hide = { "input" }, layout = { width = 32, min_width = 28 } },
        },
      })
      opts.dashboard = {
        width = 44,
        preset = {
          header = header,
          keys = {
            { key = "o", desc = "Open Folder…", action = project("choose_folder") },
            { key = "f", desc = "Find File", action = ":lua require('dojo.actions').find_file()" },
            { key = "r", desc = "Recent Files", action = ":lua Snacks.picker.recent()" },
            { key = "s", desc = "Restore Session", section = "session" },
            { key = "?", desc = "Keyboard Shortcuts", action = ":Dojo" },
            { key = ",", desc = "Settings", action = ":lua require('dojo.actions').settings()" },
            { key = "q", desc = "Quit", action = ":qa" },
          },
        },
        sections = {
          { section = "header", padding = 3 },
          { section = "keys", gap = 0, padding = 3 },
          { title = "Recent Projects", section = "projects", padding = 1, limit = 5 },
        },
      }
    end,
  },

  -- Completion that feels like VS Code: Tab or Enter accepts, docs pop up.
  {
    "saghen/blink.cmp",
    opts = {
      enabled = function()
        return vim.bo.buftype ~= "prompt" and vim.b.completion ~= false
      end,
      keymap = { preset = "super-tab", ["<CR>"] = { "accept", "fallback" } },
      completion = {
        menu = { scrollbar = false },
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
      },
      signature = { enabled = true },
    },
  },
  -- Suggestions from the language server, file paths and words in the file.
  -- No snippet packs (they fuzzy-match everything: "Ani" → assertNotIn) and
  -- no grey preview text. A function, so it replaces LazyVim's lists.
  {
    "saghen/blink.cmp",
    opts = function(_, opts)
      opts.sources.default = { "lsp", "path", "buffer" }
      opts.completion.ghost_text = { enabled = false }
    end,
  },

  -- One signature popup (blink's), not two.
  {
    "folke/noice.nvim",
    opts = { lsp = { signature = { enabled = false } } },
  },

  ---------------------------------------------------------------------------
  -- Typing sounds: a tiny Swift daemon (sfx/nvsfx.swift) fed over a pipe.
  -- Builds itself on first use (swiftc + python3, ~3 s, async).
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
