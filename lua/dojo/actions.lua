-- Actions behind the Dojo registry (lua/dojo/keys.lua). Each one leaves
-- insert/visual mode itself when that makes sense, so a Cmd chord behaves the
-- same no matter which mode you pressed it in.

local M = {}

local function normal_mode()
  local mode = vim.api.nvim_get_mode().mode
  if mode:match("^[iR]") then
    vim.cmd.stopinsert()
  elseif mode:match("^[vVsS\22\19]") then
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  end
end

local function visual_text()
  local mode = vim.fn.mode()
  if not mode:match("^[vV\22]") then
    return nil
  end
  local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
  return table.concat(lines, "\n")
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "n", false)
end

local function root()
  return LazyVim.root()
end

-- The window holding the file you're editing (not the tree, a terminal or a float).
local function editor_win()
  local function is_editor(win)
    local buf = vim.api.nvim_win_get_buf(win)
    return vim.api.nvim_win_get_config(win).relative == "" and vim.bo[buf].buftype == ""
  end
  local current = vim.api.nvim_get_current_win()
  if is_editor(current) then
    return current
  end
  local previous = vim.fn.win_getid(vim.fn.winnr("#"))
  if previous ~= 0 and is_editor(previous) then
    return previous
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_editor(win) then
      return win
    end
  end
end

local function focus_editor()
  local win = editor_win()
  if win then
    vim.api.nvim_set_current_win(win)
  end
end

-- Essentials --------------------------------------------------------------

function M.find_file()
  normal_mode()
  -- Outside a project (your home folder) scanning every file is slow and
  -- noisy, so offer recent files instead; ⌘O opens a project.
  if vim.fn.getcwd() == vim.env.HOME then
    Snacks.picker.recent({ layout = { preset = "vscode" }, title = "Recent Files — ⌘O opens a folder" })
    return
  end
  Snacks.picker.smart({ layout = { preset = "vscode" }, title = "Go to File" })
end

function M.palette()
  normal_mode()
  require("dojo.palette").open()
end

function M.cheatsheet()
  normal_mode()
  require("dojo.cheatsheet").open()
end

function M.open_folder()
  normal_mode()
  require("dojo.project").choose_folder()
end

function M.recent_projects()
  normal_mode()
  require("dojo.project").recent()
end

function M.recent_files()
  normal_mode()
  Snacks.picker.recent({ layout = { preset = "vscode" }, filter = { cwd = true } })
end

function M.new_file()
  normal_mode()
  vim.cmd.enew()
end

function M.save()
  normal_mode()
  if vim.bo.buftype ~= "" then
    return
  end
  if vim.api.nvim_buf_get_name(0) ~= "" then
    vim.cmd("silent! update")
    return
  end
  vim.ui.input({ prompt = "Save as: ", default = vim.fn.getcwd() .. "/", completion = "file" }, function(path)
    if path and vim.trim(path) ~= "" then
      vim.fn.mkdir(vim.fs.dirname(vim.fn.fnamemodify(path, ":p")), "p")
      vim.cmd.saveas(vim.fn.fnameescape(path))
    end
  end)
end

function M.save_all()
  normal_mode()
  vim.cmd("silent! wall")
end

local closed = {}

function M.close_file()
  normal_mode()
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" and vim.bo.buftype == "" then
    table.insert(closed, name)
  end
  Snacks.bufdelete()
end

function M.reopen_closed()
  normal_mode()
  while #closed > 0 do
    local name = table.remove(closed)
    if vim.uv.fs_stat(name) then
      vim.cmd.edit(vim.fn.fnameescape(name))
      return
    end
  end
  vim.notify("No recently closed files", vim.log.levels.INFO, { title = "Dojo" })
end

function M.settings()
  normal_mode()
  Snacks.picker.files({ cwd = vim.fn.stdpath("config"), title = "Settings" })
end

function M.paste_terminal()
  -- nvim_paste uses bracketed paste, so a pasted command doesn't run on its own
  vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
end

-- Navigate ----------------------------------------------------------------

-- Like VS Code's sidebar: ⌘B shows or hides the tree; your cursor stays in the file.
function M.toggle_explorer()
  normal_mode()
  local open = Snacks.picker.get({ source = "explorer" })
  if #open > 0 then
    for _, picker in ipairs(open) do
      picker:close()
    end
    focus_editor()
  else
    require("dojo.project").show_explorer(root(), false)
  end
end

function M.prev_buffer()
  normal_mode()
  vim.cmd.bprevious()
end

function M.next_buffer()
  normal_mode()
  vim.cmd.bnext()
end

function M.goto_buffer(index)
  normal_mode()
  local ok = pcall(vim.cmd, "BufferLineGoToBuffer " .. index)
  if not ok then
    local listed = vim.tbl_filter(function(buf)
      return vim.bo[buf].buflisted
    end, vim.api.nvim_list_bufs())
    if listed[index] then
      vim.api.nvim_set_current_buf(listed[index])
    end
  end
end

function M.goto_line()
  normal_mode()
  -- Teach the native way: `:42` then Enter.
  feed(":")
end

function M.symbols()
  normal_mode()
  Snacks.picker.lsp_symbols({ layout = { preset = "vscode", preview = "main" }, title = "Go to Symbol" })
end

function M.workspace_symbols()
  normal_mode()
  Snacks.picker.lsp_workspace_symbols({ title = "Go to Symbol in Project" })
end

function M.split_right()
  normal_mode()
  vim.cmd.vsplit()
end

-- Edit --------------------------------------------------------------------

-- multicursor.nvim: edit with normal Vim commands, every cursor follows; Esc clears.
function M.add_next_occurrence()
  require("multicursor-nvim").matchAddCursor(1)
end

function M.select_all_occurrences()
  require("multicursor-nvim").matchAllAddCursors()
end

function M.rename()
  normal_mode()
  if package.loaded["inc_rename"] or pcall(require, "inc_rename") then
    feed(":IncRename " .. vim.fn.expand("<cword>"))
  else
    vim.lsp.buf.rename()
  end
end

function M.format()
  normal_mode()
  LazyVim.format({ force = true })
end

-- Code --------------------------------------------------------------------

function M.definition()
  normal_mode()
  Snacks.picker.lsp_definitions()
end

function M.references()
  normal_mode()
  Snacks.picker.lsp_references()
end

function M.implementation()
  normal_mode()
  Snacks.picker.lsp_implementations()
end

function M.hover()
  vim.lsp.buf.hover()
end

function M.code_action()
  vim.lsp.buf.code_action()
end

function M.next_problem()
  normal_mode()
  vim.diagnostic.jump({ count = 1, float = true })
end

function M.prev_problem()
  normal_mode()
  vim.diagnostic.jump({ count = -1, float = true })
end

function M.problems()
  normal_mode()
  vim.cmd("Trouble diagnostics toggle")
end

function M.tutor()
  local mode = vim.fn.mode()
  local tutor = require("config.tutor")
  if mode:match("^[vV\22]") then
    tutor.ask_selection()
  else
    normal_mode()
    tutor.ask_file()
  end
end

function M.claude()
  normal_mode()
  if vim.fn.exists(":ClaudeCode") == 2 then
    vim.cmd("ClaudeCode")
  else
    vim.notify("Claude Code is not installed (`claude` command)", vim.log.levels.WARN, { title = "Dojo" })
  end
end

-- Search ------------------------------------------------------------------

-- Type text into the command line literally (no <Key> translation).
local function feed_literal(text)
  vim.api.nvim_feedkeys(text, "n", true)
end

function M.find_in_file()
  local text = visual_text()
  normal_mode()
  if text and not text:find("\n") then
    feed_literal("/\\V" .. vim.fn.escape(text, "\\/"))
  else
    feed("/")
  end
end

function M.replace_in_file()
  local text = visual_text()
  normal_mode()
  local word = text and not text:find("\n") and text or vim.fn.expand("<cword>")
  if word == "" then
    feed(":%s//g<Left><Left><Left>")
    return
  end
  local pattern = text and ("\\V" .. vim.fn.escape(word, "\\/")) or ("\\<" .. vim.fn.escape(word, "\\/") .. "\\>")
  feed_literal(":%s/" .. pattern .. "//g")
  feed("<Left><Left>")
end

function M.find_in_project()
  local text = visual_text()
  normal_mode()
  if text and text ~= "" then
    Snacks.picker.grep({ cwd = root(), search = text, regex = false })
  else
    Snacks.picker.grep({ cwd = root() })
  end
end

function M.replace_in_project()
  local text = visual_text()
  normal_mode()
  local grug = require("grug-far")
  grug.open({
    transient = true,
    -- a selection is searched as plain text, a word as a whole word
    prefills = text and { search = text, flags = "--fixed-strings" }
      or { search = vim.fn.expand("<cword>"), flags = "--word-regexp" },
  })
end

-- Run ---------------------------------------------------------------------

function M.run_file()
  normal_mode()
  require("config.runner").run()
end

function M.close_output()
  normal_mode()
  require("config.runner").close()
end

function M.toggle_terminal()
  if vim.api.nvim_get_mode().mode:match("^[iR]") then
    vim.cmd.stopinsert()
  end
  local term = Snacks.terminal.toggle(nil, { cwd = root(), win = { position = "bottom", height = 0.32 } })
  if term and not term:valid() then
    vim.schedule(focus_editor) -- hidden: back to your file, not the tree
  end
end

function M.lazygit()
  normal_mode()
  Snacks.lazygit({ cwd = LazyVim.root.git() })
end

-- View --------------------------------------------------------------------

function M.zen()
  normal_mode()
  focus_editor() -- zen always shows your file, whichever panel had focus
  Snacks.zen()
end

function M.toggle_wrap()
  vim.wo.wrap = not vim.wo.wrap
  vim.notify("Word wrap " .. (vim.wo.wrap and "on" or "off"), vim.log.levels.INFO, { title = "Dojo" })
end

function M.markdown_preview()
  normal_mode()
  if vim.fn.exists(":RenderMarkdown") == 2 then
    vim.cmd("RenderMarkdown toggle")
  end
end

function M.theme()
  normal_mode()
  require("dojo.theme").pick()
end

local function scale(delta)
  if not vim.g.neovide then
    vim.notify("Zoom works in the Dojo app (Neovide). In a terminal use its own ⌘= / ⌘-.", vim.log.levels.INFO)
    return
  end
  if delta == 0 then
    vim.g.neovide_scale_factor = 1.0
  else
    vim.g.neovide_scale_factor = math.max(0.5, math.min(2.5, (vim.g.neovide_scale_factor or 1.0) * delta))
  end
end

function M.zoom_in()
  scale(1.1)
end

function M.zoom_out()
  scale(1 / 1.1)
end

function M.zoom_reset()
  scale(0)
end

function M.toggle_sound()
  require("dojo.sfx").toggle()
end

function M.toggle_vfx()
  require("dojo.gui").toggle_vfx()
end

-- Folds --------------------------------------------------------------------

function M.fold_overview()
  normal_mode()
  require("dojo.folds").overview()
end

function M.fold_deeper()
  normal_mode()
  require("dojo.folds").deeper()
end

function M.fold_shallower()
  normal_mode()
  require("dojo.folds").shallower()
end

function M.unfold_all()
  normal_mode()
  require("dojo.folds").unfold_all()
end

-- Learn --------------------------------------------------------------------

function M.vim_tutor()
  normal_mode()
  require("dojo.learn").vim_tutor()
end

function M.learn_menu()
  normal_mode()
  require("dojo.learn").menu()
end

function M.motions_game()
  normal_mode()
  vim.cmd("VimBeGood")
end

function M.typing_game()
  normal_mode()
  vim.cmd("Typr")
end

function M.toggle_hints()
  require("dojo.learn").toggle_hints()
end

function M.toggle_showkeys()
  require("dojo.learn").toggle_showkeys()
end

function M.toggle_hardtime()
  require("dojo.learn").toggle_hardtime()
end

function M.hardtime_report()
  require("dojo.learn").hardtime_report()
end

return M
