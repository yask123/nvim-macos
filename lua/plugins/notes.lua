return {
  -- Render Markdown: headings, checkboxes, callouts and tables drawn in place.
  -- The raw text reappears on the cursor line (anti-conceal) so editing stays easy.
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      preset = "obsidian",
      checkbox = { enabled = true }, -- LazyVim's markdown extra turns these off
      completions = { lsp = { enabled = true } },
      code = {
        sign = false,
        width = "block",
        right_pad = 1,
      },
      heading = {
        sign = false,
        width = "block",
        icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
      },
    },
  },

  -- Obsidian-style notes in ~/notes (maintained community fork).
  -- Completion comes from its built-in LSP, so no blink source is needed.
  {
    "obsidian-nvim/obsidian.nvim",
    version = "*",
    ft = "markdown",
    cmd = "Obsidian",
    init = function()
      vim.api.nvim_create_user_command("Notes", function()
        local actions = {
          { label = "Find note", cmd = "Obsidian quick_switch" },
          { label = "Search notes (grep)", cmd = "Obsidian search" },
          { label = "Daily note (today)", cmd = "Obsidian today" },
          { label = "New note", cmd = "Obsidian new" },
          { label = "Insert template", cmd = "Obsidian template" },
          { label = "Show links", cmd = "Obsidian links" },
          { label = "Show backlinks", cmd = "Obsidian backlinks" },
        }
        vim.ui.select(actions, {
          prompt = "Notes",
          format_item = function(item)
            return item.label
          end,
        }, function(choice)
          if choice then
            vim.cmd(choice.cmd)
          end
        end)
      end, { desc = "Notes menu (Obsidian)" })
    end,
    keys = {
      { "<leader>nn", "<cmd>Obsidian new<cr>", desc = "New Note" },
      { "<leader>ns", "<cmd>Obsidian search<cr>", desc = "Search Notes (Grep)" },
      { "<leader>nf", "<cmd>Obsidian quick_switch<cr>", desc = "Find Note (File)" },
      { "<leader>nd", "<cmd>Obsidian today<cr>", desc = "Daily Note" },
      { "<leader>nt", "<cmd>Obsidian template<cr>", desc = "Insert Template" },
      { "<leader>nl", "<cmd>Obsidian links<cr>", desc = "Show Links" },
      { "<leader>nb", "<cmd>Obsidian backlinks<cr>", desc = "Show Backlinks" },
      { "<leader>nH", "<cmd>Notes<cr>", desc = "Notes Home" },
    },
    opts = {
      legacy_commands = false,
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
        min_chars = 2,
      },
      picker = { name = "snacks.picker" },
      ui = { enable = false }, -- render-markdown draws the notes
      callbacks = {
        enter_note = function()
          vim.keymap.set(
            "n",
            "<leader>ch",
            "<cmd>Obsidian toggle_checkbox<cr>",
            { buffer = true, desc = "Toggle checkbox" }
          )
        end,
      },
    },
  },
}
