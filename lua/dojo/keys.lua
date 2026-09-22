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
--   vim   the Vim-native way to do the same thing (taught side by side)
--   desc  what it does; tip = one extra sentence for the palette
-- Entries without `keys` are display-only lessons.

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
          { mac = "⌘⇧P", keys = { "<D-P>", "<D-S-p>", "<F1>" }, mode = NIV, run = A.palette, desc = "Command palette", vim = "Space :", tip = "Every Dojo action, searchable, with its shortcut. F1 works too." },
          { mac = "⌘K ⌘S", keys = { "<D-k><D-s>", "<leader>?" }, run = A.cheatsheet, desc = "Keyboard shortcuts (this sheet)", vim = "Space ?" },
          { mac = "⌘O", keys = { "<D-o>" }, mode = NIV, run = A.open_folder, desc = "Open folder…", vim = ":cd path", tip = "Native macOS folder picker; restores that project's last session." },
          { mac = "⌘⌥O", keys = { "<D-M-o>", "<M-D-o>" }, mode = NIV, run = A.recent_projects, desc = "Recent projects", vim = "Space f p" },
          { mac = "⌘E", keys = { "<D-e>" }, mode = NIV, run = A.recent_files, desc = "Recent files", vim = "Space f r" },
          { mac = "⌘N", desc = "New window (another project side by side)", vim = "" },
          { vim = "Space f n", run = A.new_file, desc = "New file" },
          { mac = "⌘S", keys = { "<D-s>" }, mode = NIV, run = A.save, desc = "Save (asks for a name if new)", vim = ":w" },
          { mac = "⌘⌥S", keys = { "<D-M-s>", "<M-D-s>" }, mode = NIV, run = A.save_all, desc = "Save all", vim = ":wa" },
          { mac = "⌘W", keys = { "<D-w>" }, mode = NIV, run = A.close_file, desc = "Close file", vim = "Space b d" },
          { mac = "⌘⇧T", keys = { "<D-T>", "<D-S-t>" }, mode = NIV, run = A.reopen_closed, desc = "Reopen closed file", vim = "Space f r" },
          { mac = "⌘,", keys = { "<D-,>" }, mode = NIV, run = A.settings, desc = "Settings (config files)", vim = "Space f c" },
          { mac = "⌘Q", desc = "Quit (saves the session)", vim = ":qa" },
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
        },
      },
    },
  },
  {
    name = "Navigate",
    sections = {
      {
        items = {
          { mac = "⌘B", keys = { "<D-b>" }, mode = NIV, run = A.toggle_explorer, desc = "Toggle file explorer", vim = "Space e" },
          { mac = "⌘⇧[  ⌘⇧]", keys = { "<D-{>", "<D-S-[>" }, mode = NI, run = A.prev_buffer, desc = "Previous / next open file", vim = "H · L" },
          { keys = { "<D-}>", "<D-S-]>" }, mode = NI, run = A.next_buffer, desc = "Next open file", hidden = true },
          { mac = "⌘1…⌘9", desc = "Jump to open file 1…9", vim = "Space b b (last)" },
          { mac = "⌃G", keys = { "<C-g>" }, mode = NI, run = A.goto_line, desc = "Go to line", vim = ":42 · 42G" },
          { mac = "⌘⇧O", keys = { "<D-O>", "<D-S-o>" }, mode = NIV, run = A.symbols, desc = "Go to symbol in file", vim = "Space s s" },
          { mac = "⌘T", keys = { "<D-t>" }, mode = NIV, run = A.workspace_symbols, desc = "Go to symbol in project", vim = "Space s S" },
          { mac = "⌘\\", keys = { "<D-\\>" }, mode = NI, run = A.split_right, desc = "Split editor right", vim = "Space | · :vsplit" },
          { mac = "⌃H/J/K/L", desc = "Move between splits", vim = "Ctrl-h j k l" },
        },
      },
      {
        title = "Folds: read a big file top-down",
        items = {
          { mac = "⌘K ⌘0", keys = { "<D-k><D-0>" }, mode = NI, run = A.fold_overview, desc = "Overview: fold everything", vim = "zM" },
          { mac = "⌘K ⌘]", keys = { "<D-k><D-]>" }, mode = NI, run = A.fold_deeper, desc = "One level deeper (whole file)", vim = "zr" },
          { mac = "⌘K ⌘[", keys = { "<D-k><D-[>" }, mode = NI, run = A.fold_shallower, desc = "One level shallower (whole file)", vim = "zm" },
          { mac = "⌘K ⌘J", keys = { "<D-k><D-j>" }, mode = NI, run = A.unfold_all, desc = "Unfold everything", vim = "zR" },
          { mac = "⌥⌘]  ⌥⌘[", keys = { "<M-D-]>", "<D-M-]>" }, map = { n = "zo", i = "<C-o>zo" }, desc = "Open / close fold here", vim = "zo · zc" },
          { keys = { "<M-D-[>", "<D-M-[>" }, map = { n = "zc", i = "<C-o>zc" }, desc = "Close fold here", hidden = true },
          { mac = "↩", desc = "On a folded line: open it one level", vim = "za toggle" },
          { vim = "zj  zk", desc = "Jump to next / previous fold" },
          { vim = "zO", desc = "Open everything under the cursor" },
          { vim = "", mac = "300+ lines", desc = "Big files open as an outline automatically" },
        },
      },
      {
        title = "Jump like a native",
        items = {
          { vim = "Ctrl-o  Ctrl-i", desc = "Back / forward through jump history (VS Code ⌃- ⌃⇧-)" },
          { vim = "gd  gr  gI", desc = "Definition · references · implementation" },
          { vim = "``", desc = "Back to where you jumped from" },
          { vim = "gf", desc = "Open the file path under the cursor" },
          { vim = "]d  [d", desc = "Next / previous problem" },
          { vim = "]]  [[", desc = "Next / previous reference of this word" },
        },
      },
    },
  },
  {
    name = "Edit",
    sections = {
      {
        items = {
          { mac = "⌘/", keys = { "<D-/>" }, map = { n = "gcc", x = "gc", i = "<C-o>gcc" }, remap = true, desc = "Toggle comment", vim = "gcc · gc{motion}" },
          { mac = "⌘D", keys = { "<D-d>" }, mode = { "n", "x" }, run = A.add_next_occurrence, desc = "Add next occurrence (multi-cursor)", vim = "Ctrl-n", tip = "Then edit with normal Vim keys; every cursor follows. Esc clears. The pure-Vim way: * then cgn, then . to repeat." },
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
          { mac = "F2", keys = { "<F2>" }, mode = NI, run = A.rename, desc = "Rename symbol everywhere", vim = "Space c r" },
          { mac = "⇧⌥F", keys = { "<M-F>", "<M-S-f>" }, mode = NIV, run = A.format, desc = "Format document", vim = "Space c f" },
        },
      },
      {
        title = "macOS text keys (work in insert mode)",
        items = {
          { mac = "⌘←  ⌘→", keys = { "<D-Left>" }, map = { n = "^", i = "<C-o>^", x = "^" }, desc = "Line start / end", vim = "^ · $" },
          { keys = { "<D-Right>" }, map = { n = "$", i = "<End>", x = "$" }, desc = "Line end", hidden = true },
          { mac = "⌘↑  ⌘↓", keys = { "<D-Up>" }, map = { n = "gg", i = "<C-Home>", x = "gg" }, desc = "File top / bottom", vim = "gg · G" },
          { keys = { "<D-Down>" }, map = { n = "G", i = "<C-End>", x = "G" }, desc = "File bottom", hidden = true },
          { mac = "⌥←  ⌥→", keys = { "<M-Left>" }, map = { n = "b", i = "<C-Left>", x = "b" }, desc = "Word left / right", vim = "b · w" },
          { keys = { "<M-Right>" }, map = { n = "w", i = "<C-Right>", x = "w" }, desc = "Word right", hidden = true },
          { mac = "⌥⌫  ⌘⌫", keys = { "<M-BS>" }, map = { i = "<C-w>" }, desc = "Delete word / to line start", vim = "db · d0" },
          { keys = { "<D-BS>" }, map = { i = "<C-u>" }, desc = "Delete to line start", hidden = true },
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
          { mac = "⌘K ⌘I", keys = { "<D-k><D-i>" }, mode = NI, run = A.hover, desc = "Show docs for symbol", vim = "K" },
          { mac = "⌘.", keys = { "<D-.>" }, mode = NIV, run = A.code_action, desc = "Quick fix / code action", vim = "Space c a" },
          { mac = "F8  ⇧F8", keys = { "<F8>" }, mode = NI, run = A.next_problem, desc = "Next / previous problem", vim = "]d · [d" },
          { keys = { "<S-F8>" }, mode = NI, run = A.prev_problem, desc = "Previous problem", hidden = true },
          { mac = "⌘⇧M", keys = { "<D-M>", "<D-S-m>" }, mode = NI, run = A.problems, desc = "Problems panel", vim = "Space x x" },
          { mac = "⌃Space", desc = "Trigger completion (insert mode)", vim = "Ctrl-Space" },
          { mac = "⇥  ↩", desc = "Accept completion / snippet jump", vim = "Tab · Enter" },
        },
      },
      {
        title = "AI & learning",
        items = {
          { mac = "⌘I", keys = { "<D-i>" }, mode = NIV, run = A.tutor, desc = "Ask Tutor about selection / file", vim = "Space t a" },
          { mac = "⌘L", keys = { "<D-l>" }, mode = NIV, run = A.claude, desc = "Toggle Claude Code", vim = "Space a c" },
        },
      },
    },
  },
  {
    name = "Search",
    sections = {
      {
        items = {
          { mac = "⌘F", keys = { "<D-f>" }, mode = NIV, run = A.find_in_file, desc = "Find in file (type, then ↩)", vim = "/text", tip = "This IS Vim's / search. ⌘G / ⌘⇧G (or n / N) hop between matches." },
          { mac = "⌘G  ⌘⇧G", keys = { "<D-g>" }, map = { n = "n", i = "<C-o>n" }, desc = "Next / previous match", vim = "n · N" },
          { keys = { "<D-G>", "<D-S-g>" }, map = { n = "N", i = "<C-o>N" }, desc = "Previous match", hidden = true },
          { mac = "⌘⌥F", keys = { "<D-M-f>", "<M-D-f>" }, mode = NIV, run = A.replace_in_file, desc = "Replace in file", vim = ":%s/old/new/g", tip = "Prefills a :substitute for the word under the cursor. Add c at the end to confirm each." },
          { mac = "⌘⇧F", keys = { "<D-F>", "<D-S-f>" }, mode = NIV, run = A.find_in_project, desc = "Find in project (grep)", vim = "Space /" },
          { mac = "⌘⇧H", keys = { "<D-H>", "<D-S-h>" }, mode = NIV, run = A.replace_in_project, desc = "Replace in project", vim = "Space s r" },
          { mac = "Esc", desc = "Clear search highlight", vim = "Esc" },
        },
      },
      {
        title = "Search like a native",
        items = {
          { vim = "*  #", desc = "Search word under cursor forward / backward" },
          { vim = "f{c}  t{c}", desc = "Jump to / before character c on this line; ; and , repeat" },
          { vim = "%", desc = "Jump to matching bracket" },
          { vim = ":s/a/b/g", desc = "Replace on this line; :%s for the whole file" },
          { vim = "&", desc = "Repeat the last :s on this line" },
        },
      },
    },
  },
  {
    name = "Run",
    sections = {
      {
        items = {
          { mac = "⌘R  F5", keys = { "<D-r>", "<F5>" }, mode = NIV, run = A.run_file, desc = "Save & run this file", vim = "Space r r", tip = "Python, JS/TS, Lua, shell, Go, Rust. q closes the output." },
          { mac = "⌘⇧R", keys = { "<D-R>", "<D-S-r>" }, mode = NI, run = A.close_output, desc = "Close run output", vim = "Space r q" },
          { mac = "⌃`  ⌘J", keys = { "<C-`>", "<D-j>" }, mode = { "n", "i", "t" }, run = A.toggle_terminal, desc = "Toggle terminal panel", vim = "Ctrl-/" },
          { mac = "⌃\\", desc = "Floating terminal", vim = "Ctrl-\\" },
          { mac = "⌃⇧G", keys = { "<C-S-g>" }, mode = NI, run = A.lazygit, desc = "Source control (lazygit)", vim = "Space g g" },
          { mac = "Space r i", desc = "Python REPL", vim = "Space r i" },
          { mac = "Esc Esc", desc = "Leave terminal typing mode", vim = "Ctrl-\\ Ctrl-n" },
        },
      },
    },
  },
  {
    name = "View",
    sections = {
      {
        items = {
          { mac = "⌘K Z", keys = { "<D-k>z" }, mode = NI, run = A.zen, desc = "Zen mode: a calm, centred page", vim = "Space u z" },
          { mac = "⌥Z", keys = { "<M-z>" }, mode = NI, run = A.toggle_wrap, desc = "Toggle word wrap", vim = "Space u w" },
          { mac = "⌘⇧V", keys = { "<D-V>", "<D-S-v>" }, mode = NI, run = A.markdown_preview, desc = "Markdown: rendered ↔ raw", vim = "Space u m" },
          { mac = "⌘K ⌘T", keys = { "<D-k><D-t>" }, mode = NI, run = A.theme, desc = "Choose colour theme", vim = "Space u C" },
          { mac = "⌘=  ⌘-  ⌘0", keys = { "<D-=>", "<D-+>" }, mode = { "n", "i", "t" }, run = A.zoom_in, desc = "Zoom in / out / reset", vim = "" },
          { keys = { "<D-->" }, mode = { "n", "i", "t" }, run = A.zoom_out, desc = "Zoom out", hidden = true },
          { keys = { "<D-0>" }, mode = { "n", "i", "t" }, run = A.zoom_reset, desc = "Reset zoom", hidden = true },
          { mac = "⌃⌘F", desc = "Full screen (macOS)", vim = "" },
          { vim = "Space u V", keys = { "<leader>uV" }, run = A.toggle_vfx, desc = "Cursor particles on / off" },
          { mac = "⌘K M", keys = { "<D-k>m" }, mode = NI, run = A.toggle_sound, desc = "Sound effects on / off", vim = "Space u M" },
        },
      },
    },
  },
  {
    name = "Write",
    sections = {
      {
        items = {
          { mac = "Space n n", desc = "New note in ~/notes", vim = "Space n n" },
          { mac = "Space n d", desc = "Today's daily note", vim = "Space n d" },
          { mac = "Space n f", desc = "Find a note", vim = "Space n f" },
          { mac = "Space n s", desc = "Search inside notes", vim = "Space n s" },
          { mac = "Space c h", desc = "Toggle checkbox", vim = "Space c h" },
          { mac = "gf", desc = "Follow [[wiki link]]", vim = "gf" },
        },
      },
      {
        title = "Prose motions",
        items = {
          { vim = "(  )", desc = "Previous / next sentence" },
          { vim = "{  }", desc = "Previous / next paragraph" },
          { vim = "cis  dap", desc = "Change sentence · delete paragraph" },
          { vim = "gqap", desc = "Re-wrap paragraph (hard wrap)" },
          { vim = "z=  ]s", desc = "Spelling suggestions · next misspelling" },
        },
      },
    },
  },
  {
    name = "Learn",
    sections = {
      {
        items = {
          { vim = ":VimTutor", run = A.vim_tutor, desc = "Vim's own interactive lesson (30 min)" },
          { vim = ":DojoLearn", run = A.learn_menu, desc = "Learn & practise menu" },
          { vim = ":VimBeGood", run = A.motions_game, desc = "Motions game" },
          { vim = ":Typr", run = A.typing_game, desc = "Typing practice" },
        },
      },
      {
        title = "Training wheels",
        items = {
          { vim = "Space u P", keys = { "<leader>uP" }, run = A.toggle_hints, desc = "Motion hints: where w b e ^ $ would land" },
          { vim = "Space u K", keys = { "<leader>uK" }, run = A.toggle_showkeys, desc = "Show the keys you press on screen" },
          { vim = "Space u H", keys = { "<leader>uH" }, run = A.toggle_hardtime, desc = "Habit hints (e.g. try 5j instead of jjjjj)" },
          { vim = ":Hardtime report", run = A.hardtime_report, desc = "Your most repeated inefficient keys" },
        },
      },
      {
        title = "How to learn here",
        items = {
          { vim = "1", desc = "Keep using ⌘ keys — each one shows its Vim twin in ⌘⇧P" },
          { vim = "2", desc = "Pick one Vim twin a day (the dashboard suggests one)" },
          { vim = "3", desc = "Grammar beats memory: verb + noun, e.g. ciw, dap, yi(" },
          { vim = "4", desc = "Repeat with . — the most powerful key in Vim" },
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
          { vim = "i  a", desc = "Insert before / after cursor" },
          { vim = "I  A", desc = "Insert at line start / end" },
          { vim = "o  O", desc = "New line below / above" },
          { vim = "Esc", desc = "Back to Normal mode" },
          { vim = "v  V", desc = "Select characters / lines" },
          { vim = "Ctrl-v", desc = "Select a block (column)" },
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
          { vim = "zz", desc = "Center this line on screen" },
          { vim = "H  M  L", desc = "Screen top · middle · bottom" },
        },
      },
      {
        title = "Edit",
        items = {
          { vim = "x", desc = "Delete character" },
          { vim = "dd  yy", desc = "Delete (cut) · copy line" },
          { vim = "p  P", desc = "Paste after · before" },
          { vim = "u  Ctrl-r", desc = "Undo · redo" },
          { vim = ".", desc = "Repeat last change ★" },
          { vim = "r{c}", desc = "Replace one character" },
          { vim = "J", desc = "Join line below" },
          { vim = ">>  <<", desc = "Indent · outdent" },
          { vim = "~", desc = "Toggle case" },
        },
      },
      {
        title = "Grammar: verb + noun",
        items = {
          { vim = "d c y v", desc = "delete · change · copy · select" },
          { vim = "dw  d2w", desc = "delete word · two words" },
          { vim = "ciw", desc = "change inner word" },
          { vim = "ci\"  ci(", desc = "change inside quotes · parens" },
          { vim = "da{", desc = "delete around braces" },
          { vim = "dt,", desc = "delete up to the comma" },
          { vim = "yap", desc = "copy a paragraph" },
          { vim = "vif  vac", desc = "select function · class" },
        },
      },
      {
        title = "Nouns (text objects)",
        items = {
          { vim = "w s p", desc = "word · sentence · paragraph" },
          { vim = "\" ' `", desc = "quoted string" },
          { vim = "( [ { <", desc = "bracket pairs (b = any)" },
          { vim = "t", desc = "HTML/XML tag" },
          { vim = "f  c  a", desc = "function · class · argument" },
          { vim = "i  vs  a", desc = "inner (inside) vs around" },
        },
      },
      {
        title = "Surround",
        items = {
          { vim = "sa iw \"", desc = "add quotes around word" },
          { vim = "sd \"", desc = "delete surrounding quotes" },
          { vim = "sr \" '", desc = "replace \" with '" },
        },
      },
    },
  },
}
