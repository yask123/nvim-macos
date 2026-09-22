-- Dojo keymap registry: the single source of truth for the Cmd-key layer,
-- the ⌘⇧P command palette, and the ⌘K ⌘S cheatsheet.
--
-- Entry fields:
--   mac   macOS chord shown in the cheatsheet (⌘ ⇧ ⌥ ⌃)
--   keys  lhs list that get mapped (Neovide sends Cmd as <D-…>)
--   mode  modes for `run` (default { "n" })
--   run   action function; leaves insert/visual first when needed
--   map   per-mode rhs strings/functions instead of `run`
--   remap map with remap = true (for rhs that rely on other mappings)
--   vim   the Vim-native way to do the same thing
--   desc  what it does; tip = one extra sentence for the palette
--   hidden  mapped, but not listed (alternate spellings, the other half of a pair)
-- Entries without `keys` are display-only.

local A = require("dojo.actions")

local NIV = { "n", "i", "x" }
local NI = { "n", "i" }

-- One entry per line reads like a cheatsheet, so keep stylua away from it.
-- stylua: ignore
return {
  {
    name = "Essentials",
    sections = {
      {
        items = {
          { mac = "⌘P", keys = { "<D-p>" }, mode = NIV, run = A.find_file, desc = "Find file", vim = "Space Space", tip = "Fuzzy-find any file; recent files float to the top." },
          { mac = "⌘⇧P", keys = { "<D-P>", "<D-S-p>", "<F1>" }, mode = NIV, run = A.palette, desc = "Command palette", vim = "Space :", tip = "Every action, searchable, with its shortcut. F1 works too." },
          { mac = "⌘K ⌘S", keys = { "<D-k><D-s>", "<leader>?" }, run = A.cheatsheet, desc = "Keyboard shortcuts (this sheet)", vim = "Space ?" },
          { mac = "⌘O", keys = { "<D-o>" }, mode = NIV, run = A.open_folder, desc = "Open folder…", vim = ":cd path", tip = "Native macOS folder picker; restores that project's last session." },
          { mac = "⌘⌥O", keys = { "<D-M-o>", "<M-D-o>" }, mode = NIV, run = A.recent_projects, desc = "Recent projects", vim = "Space f p" },
          { mac = "⌘E", keys = { "<D-e>" }, mode = NIV, run = A.recent_files, desc = "Recent files", vim = "Space f r" },
          { mac = "⌘B", keys = { "<D-b>" }, mode = NIV, run = A.toggle_explorer, desc = "Show / hide the file tree", vim = "Space e" },
          { mac = "⌘J", keys = { "<C-`>", "<D-j>" }, mode = { "n", "i", "t" }, run = A.toggle_terminal, desc = "Show / hide the bottom panel (terminal, run output)", vim = "Ctrl-/" },
          { mac = "⌘R", keys = { "<D-r>", "<F5>" }, mode = NIV, run = A.run_file, desc = "Save & run this file", vim = "Space r r", tip = "Output opens below; type into it if the program asks for input. q or ⌘J closes it." },
          { mac = "⌘S", keys = { "<D-s>" }, mode = NIV, run = A.save, desc = "Save (asks for a name if new)", vim = ":w" },
          { mac = "⌘⌥S", keys = { "<D-M-s>", "<M-D-s>" }, mode = NIV, run = A.save_all, desc = "Save all", vim = ":wa" },
          { mac = "⌘W", keys = { "<D-w>" }, mode = NIV, run = A.close_file, desc = "Close file", vim = "Space b d" },
          { mac = "⌘⇧T", keys = { "<D-T>", "<D-S-t>" }, mode = NIV, run = A.reopen_closed, desc = "Reopen closed file", vim = "Space f r" },
          { vim = "Space f n", run = A.new_file, desc = "New file" },
          { mac = "⌘N", desc = "New window (another project side by side)", vim = "" },
          { mac = "⌘,", keys = { "<D-,>" }, mode = NIV, run = A.settings, desc = "Settings (config files)", vim = "Space f c" },
        },
      },
      {
        title = "Find",
        items = {
          { mac = "⌘F", keys = { "<D-f>" }, mode = NIV, run = A.find_in_file, desc = "Find in file (type, then ↩)", vim = "/text", tip = "This is Vim's / search. ⌘G / ⌘⇧G (or n / N) hop between matches." },
          { mac = "⌘G  ⌘⇧G", keys = { "<D-g>" }, map = { n = "n", i = "<C-o>n" }, desc = "Next / previous match", vim = "n · N" },
          { keys = { "<D-G>", "<D-S-g>" }, map = { n = "N", i = "<C-o>N" }, desc = "Previous match", hidden = true },
          { mac = "⌘⌥F", keys = { "<D-M-f>", "<M-D-f>" }, mode = NIV, run = A.replace_in_file, desc = "Replace in file", vim = ":%s/old/new/g", tip = "Prefills a :substitute for the word under the cursor. Add c at the end to confirm each." },
          { mac = "⌘⇧F", keys = { "<D-F>", "<D-S-f>" }, mode = NIV, run = A.find_in_project, desc = "Find in project", vim = "Space /" },
          { mac = "⌘⇧H", keys = { "<D-H>", "<D-S-h>" }, mode = NIV, run = A.replace_in_project, desc = "Replace in project", vim = "Space s r" },
        },
      },
    },
  },
  {
    name = "Code",
    sections = {
      {
        items = {
          { mac = "F12", keys = { "<F12>" }, mode = NI, run = A.definition, desc = "Go to definition (⌘-click too)", vim = "gd" },
          { keys = { "<D-LeftMouse>" }, map = { n = "<LeftMouse><cmd>lua require('dojo.actions').definition()<cr>", i = "<Esc><LeftMouse><cmd>lua require('dojo.actions').definition()<cr>" }, desc = "Go to definition (mouse)", hidden = true },
          { mac = "⇧F12", keys = { "<S-F12>" }, mode = NI, run = A.references, desc = "Find all references", vim = "gr" },
          { mac = "⌘F12", keys = { "<D-F12>" }, mode = NI, run = A.implementation, desc = "Go to implementation", vim = "gI" },
          { mac = "⌃-", keys = { "<C-->" }, map = { n = "<C-o>", i = "<Esc><C-o>" }, desc = "Back to where you were", vim = "Ctrl-o" },
          { mac = "⌘⇧O", keys = { "<D-O>", "<D-S-o>" }, mode = NIV, run = A.symbols, desc = "Go to symbol in file", vim = "Space s s" },
          { mac = "⌘T", keys = { "<D-t>" }, mode = NIV, run = A.workspace_symbols, desc = "Go to symbol in project", vim = "Space s S" },
          { mac = "⌃G", keys = { "<C-g>" }, mode = NI, run = A.goto_line, desc = "Go to line", vim = ":42 · 42G" },
          { mac = "⌘K ⌘I", keys = { "<D-k><D-i>" }, mode = NI, run = A.hover, desc = "Show docs for symbol", vim = "K" },
          { mac = "⌘.", keys = { "<D-.>" }, mode = NIV, run = A.code_action, desc = "Quick fix / code action", vim = "Space c a" },
          { mac = "F2", keys = { "<F2>" }, mode = NI, run = A.rename, desc = "Rename symbol everywhere", vim = "Space c r" },
          { mac = "⇧⌥F", keys = { "<M-F>", "<M-S-f>" }, mode = NIV, run = A.format, desc = "Format document", vim = "Space c f" },
          { mac = "F8  ⇧F8", keys = { "<F8>" }, mode = NI, run = A.next_problem, desc = "Next / previous problem", vim = "]d · [d" },
          { keys = { "<S-F8>" }, mode = NI, run = A.prev_problem, desc = "Previous problem", hidden = true },
          { mac = "⌘⇧M", keys = { "<D-M>", "<D-S-m>" }, mode = NI, run = A.problems, desc = "Problems panel", vim = "Space x x" },
          { mac = "⇥  ↩", desc = "Accept completion", vim = "Tab · Enter" },
        },
      },
      {
        title = "Run",
        items = {
          { mac = "⌘⇧R", keys = { "<D-R>", "<D-S-r>" }, mode = NI, run = A.close_output, desc = "Close run output", vim = "Space r q" },
          { mac = "⌃\\", desc = "Floating terminal", vim = "Ctrl-\\" },
          { mac = "Esc Esc", desc = "Leave terminal typing mode", vim = "Ctrl-\\ Ctrl-n" },
          { mac = "⌃⇧G", keys = { "<C-S-g>" }, mode = NI, run = A.lazygit, desc = "Source control (lazygit)", vim = "Space g g" },
        },
      },
    },
  },
  {
    name = "Edit",
    sections = {
      {
        items = {
          { mac = "⌘/", keys = { "<D-/>" }, map = { n = "gcc", x = "gc", i = "<C-o>gcc" }, remap = true, desc = "Toggle comment", vim = "gcc · gc" },
          { mac = "⌘D", keys = { "<D-d>" }, mode = { "n", "x" }, run = A.add_next_occurrence, desc = "Add next occurrence (multi-cursor)", vim = "Ctrl-n", tip = "Then edit with normal Vim keys; every cursor follows. Esc clears." },
          { mac = "⌘⇧L", keys = { "<D-L>", "<D-S-l>" }, mode = { "n", "x" }, run = A.select_all_occurrences, desc = "Select all occurrences", vim = ":%s/old/new/g" },
          { mac = "⌘⌥↑  ⌘⌥↓", desc = "Add a cursor above / below", vim = "" },
          { mac = "⌥↑  ⌥↓", keys = { "<M-Up>" }, map = { n = "<cmd>m .-2<cr>==", i = "<Esc><cmd>m .-2<cr>==gi", x = ":m '<-2<cr>gv=gv" }, desc = "Move line up / down", vim = "Alt-k · Alt-j" },
          { keys = { "<M-Down>" }, map = { n = "<cmd>m .+1<cr>==", i = "<Esc><cmd>m .+1<cr>==gi", x = ":m '>+1<cr>gv=gv" }, desc = "Move line down", hidden = true },
          { mac = "⇧⌥↓  ⇧⌥↑", keys = { "<M-S-Down>", "<S-M-Down>" }, map = { n = "<cmd>t.<cr>", i = "<cmd>t.<cr>", x = ":t'><cr>gv" }, desc = "Duplicate line down / up", vim = "yyp · yyP" },
          { keys = { "<M-S-Up>", "<S-M-Up>" }, map = { n = "<cmd>t-1<cr>", i = "<cmd>t-1<cr>", x = ":t'<-1<cr>gv" }, desc = "Duplicate line up", hidden = true },
          { mac = "⌘⇧K", keys = { "<D-K>", "<D-S-k>" }, map = { n = '"_dd', i = '<C-o>"_dd' }, desc = "Delete line", vim = "dd" },
          { mac = "⌘↩  ⌘⇧↩", keys = { "<D-CR>" }, map = { n = "o", i = "<C-o>o" }, desc = "New line below / above", vim = "o · O" },
          { keys = { "<D-S-CR>" }, map = { n = "O", i = "<C-o>O" }, desc = "New line above", hidden = true },
          { mac = "⌘]  ⌘[", keys = { "<D-]>" }, map = { n = ">>", i = "<C-t>", x = ">gv" }, desc = "Indent / outdent", vim = ">> · <<" },
          { keys = { "<D-[>" }, map = { n = "<<", i = "<C-d>", x = "<gv" }, desc = "Outdent", hidden = true },
        },
      },
      {
        title = "Clipboard & undo",
        items = {
          { mac = "⌘Z", keys = { "<D-z>" }, map = { n = "u", i = "<C-o>u", x = "<Esc>u" }, desc = "Undo", vim = "u" },
          { mac = "⌘⇧Z", keys = { "<D-Z>", "<D-S-z>" }, map = { n = "<C-r>", i = "<C-o><C-r>", x = "<Esc><C-r>" }, desc = "Redo", vim = "Ctrl-r" },
          { mac = "⌘C", keys = { "<D-c>" }, map = { x = '"+y', n = '"+yy', i = '<C-o>"+yy' }, desc = "Copy (line if nothing selected)", vim = "y · yy" },
          { mac = "⌘X", keys = { "<D-x>" }, map = { x = '"+d', n = '"+dd', i = '<C-o>"+dd' }, desc = "Cut (line if nothing selected)", vim = "d · dd" },
          { mac = "⌘V", keys = { "<D-v>" }, map = { n = '"+P', x = '"+P', i = "<C-r><C-o>+", c = "<C-r>+", t = A.paste_terminal }, desc = "Paste", vim = "p · P" },
          { mac = "⌘A", keys = { "<D-a>" }, map = { n = "ggVG", i = "<Esc>ggVG", x = "<Esc>ggVG" }, desc = "Select all", vim = "ggVG" },
          { mac = "⌘←  ⌘→  ⌥←  ⌥→", desc = "Mac text keys work as usual", vim = "" },
        },
      },
      {
        items = {
          -- macOS text navigation, mapped so it also works outside insert mode.
          { keys = { "<D-Left>" }, map = { n = "^", i = "<C-o>^", x = "^" }, desc = "Line start", hidden = true },
          { keys = { "<D-Right>" }, map = { n = "$", i = "<End>", x = "$" }, desc = "Line end", hidden = true },
          { keys = { "<D-Up>" }, map = { n = "gg", i = "<C-Home>", x = "gg" }, desc = "File top", hidden = true },
          { keys = { "<D-Down>" }, map = { n = "G", i = "<C-End>", x = "G" }, desc = "File bottom", hidden = true },
          { keys = { "<M-Left>" }, map = { n = "b", i = "<C-Left>", x = "b" }, desc = "Word left", hidden = true },
          { keys = { "<M-Right>" }, map = { n = "w", i = "<C-Right>", x = "w" }, desc = "Word right", hidden = true },
          { keys = { "<M-BS>" }, map = { i = "<C-w>" }, desc = "Delete word", hidden = true },
          { keys = { "<D-BS>" }, map = { i = "<C-u>" }, desc = "Delete to line start", hidden = true },
        },
      },
    },
  },
  {
    name = "View",
    sections = {
      {
        items = {
          { mac = "⌘⇧[  ⌘⇧]", keys = { "<D-{>", "<D-S-[>" }, mode = NI, run = A.prev_buffer, desc = "Previous / next open file", vim = "H · L" },
          { keys = { "<D-}>", "<D-S-]>" }, mode = NI, run = A.next_buffer, desc = "Next open file", hidden = true },
          { mac = "⌘1…⌘9", desc = "Jump to open file 1…9", vim = "" },
          { mac = "⌘\\", keys = { "<D-\\>" }, mode = NI, run = A.split_right, desc = "Split editor right", vim = ":vsplit" },
          { mac = "⌃H/J/K/L", desc = "Move between splits", vim = "Ctrl-h j k l" },
        },
      },
      {
        title = "Folds: read a big file top-down",
        items = {
          { mac = "⌘K ⌘0", keys = { "<D-k><D-0>" }, mode = NI, run = A.fold_overview, desc = "Overview: fold everything", vim = "zM" },
          { mac = "⌘K ⌘]", keys = { "<D-k><D-]>" }, mode = NI, run = A.fold_deeper, desc = "One level deeper", vim = "zr" },
          { mac = "⌘K ⌘[", keys = { "<D-k><D-[>" }, mode = NI, run = A.fold_shallower, desc = "One level shallower", vim = "zm" },
          { mac = "⌘K ⌘J", keys = { "<D-k><D-j>" }, mode = NI, run = A.unfold_all, desc = "Unfold everything", vim = "zR" },
          { mac = "⌥⌘]  ⌥⌘[", keys = { "<M-D-]>", "<D-M-]>" }, map = { n = "zo", i = "<C-o>zo" }, desc = "Open / close fold here", vim = "zo · zc" },
          { keys = { "<M-D-[>", "<D-M-[>" }, map = { n = "zc", i = "<C-o>zc" }, desc = "Close fold here", hidden = true },
          { mac = "↩", desc = "On a folded line: open it", vim = "za" },
        },
      },
      {
        title = "Look",
        items = {
          { mac = "⌘K Z", keys = { "<D-k>z" }, mode = NI, run = A.zen, desc = "Zen: just the page", vim = "Space u z" },
          { mac = "⌘K D", keys = { "<D-k>d" }, mode = NI, run = A.toggle_dim, desc = "Dim the desktop behind the window", vim = "" },
          { mac = "⌘K ⌘T", keys = { "<D-k><D-t>" }, mode = NI, run = A.theme, desc = "Colour theme (previews as you browse)", vim = "Space u C" },
          { mac = "⌥Z", keys = { "<M-z>" }, mode = NI, run = A.toggle_wrap, desc = "Word wrap on / off", vim = "Space u w" },
          { mac = "⌘=  ⌘-  ⌘0", keys = { "<D-=>", "<D-+>" }, mode = { "n", "i", "t" }, run = A.zoom_in, desc = "Text size: larger / smaller / reset", vim = "" },
          { keys = { "<D-->" }, mode = { "n", "i", "t" }, run = A.zoom_out, desc = "Smaller text", hidden = true },
          { keys = { "<D-0>" }, mode = { "n", "i", "t" }, run = A.zoom_reset, desc = "Reset text size", hidden = true },
          { mac = "⌘K M", keys = { "<D-k>m" }, mode = NI, run = A.toggle_sound, desc = "Typing sounds on / off", vim = "Space u M" },
          { mac = "⌃⌘F", desc = "Full screen", vim = "" },
        },
      },
    },
  },
  {
    name = "Vim",
    columns = 2,
    sections = {
      {
        title = "Modes",
        items = {
          { vim = "i  a", desc = "Type before / after the cursor" },
          { vim = "I  A", desc = "Type at line start / end" },
          { vim = "o  O", desc = "New line below / above" },
          { vim = "Esc", desc = "Back to Normal mode" },
          { vim = "v  V", desc = "Select characters / lines" },
          { vim = ":", desc = "Command line" },
        },
      },
      {
        title = "Move",
        items = {
          { vim = "h j k l", desc = "← ↓ ↑ →" },
          { vim = "w  b  e", desc = "Next word · back · word end" },
          { vim = "0  ^  $", desc = "Line start · first char · end" },
          { vim = "gg  G", desc = "File top · bottom" },
          { vim = "{  }", desc = "Paragraph up · down" },
          { vim = "Ctrl-d  Ctrl-u", desc = "Half page down · up" },
          { vim = "zz", desc = "Centre this line" },
        },
      },
      {
        title = "Edit",
        items = {
          { vim = "x", desc = "Delete character" },
          { vim = "dd  yy", desc = "Cut · copy line" },
          { vim = "p  P", desc = "Paste after · before" },
          { vim = "u  Ctrl-r", desc = "Undo · redo" },
          { vim = ".", desc = "Repeat the last change" },
          { vim = "r{c}", desc = "Replace one character" },
          { vim = "J", desc = "Join line below" },
        },
      },
      {
        title = "Verb + noun",
        items = {
          { vim = "d c y v", desc = "delete · change · copy · select" },
          { vim = "dw  d2w", desc = "delete word · two words" },
          { vim = "ciw", desc = "change inner word" },
          { vim = "ci\"  ci(", desc = "change inside quotes · parens" },
          { vim = "dt,", desc = "delete up to the comma" },
          { vim = "yap", desc = "copy a paragraph" },
        },
      },
      {
        title = "Jump",
        items = {
          { vim = "gd  gr", desc = "Definition · references" },
          { vim = "Ctrl-o  Ctrl-i", desc = "Back · forward" },
          { vim = "*  #", desc = "Next · previous of this word" },
          { vim = "f{c}", desc = "To character c; ; repeats" },
          { vim = "%", desc = "Matching bracket" },
        },
      },
      {
        title = "Search",
        items = {
          { vim = "/text", desc = "Search; n · N next · previous" },
          { vim = ":%s/a/b/g", desc = "Replace a with b everywhere" },
          { vim = "sa iw \"", desc = "Surround word with quotes" },
          { vim = "sd \"  sr \" '", desc = "Delete · replace surrounding" },
        },
      },
    },
  },
}
