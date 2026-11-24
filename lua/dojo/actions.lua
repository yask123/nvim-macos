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

-- The selected text, whether it was selected the Vim way or the Mac way.
local function visual_text()
  local mode = vim.fn.mode()
  if not mode:match("^[vV\22sS\19]") then
    return nil
  end
  mode = ({ s = "v", S = "V", ["\19"] = "\22" })[mode] or mode
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

-- ⌘P takes the same first characters as VS Code's: > runs a command,
-- @ lists this file's symbols, # searches every symbol in the project and
-- : goes to a line. They count only as the very first thing typed.
local function quick_open_prefixes()
  local jump = {
    [">"] = function()
      M.palette()
    end,
    ["@"] = function()
      M.symbols()
    end,
    ["#"] = function()
      M.workspace_symbols()
    end,
    [":"] = function()
      vim.api.nvim_feedkeys(":", "n", false)
    end,
  }
  local actions, keys = {}, {}
  for char, go in pairs(jump) do
    local name = "dojo_prefix_" .. char:byte()
    actions[name] = function(picker)
      if picker.input:get() == "" then
        picker:close()
        vim.schedule(go)
      else
        vim.api.nvim_feedkeys(char, "n", false)
      end
    end
    keys[char] = { name, mode = "i" }
  end
  return actions, keys
end

function M.find_file()
  normal_mode()
  local actions, keys = quick_open_prefixes()
  local opts = { layout = { preset = "vscode" }, actions = actions, win = { input = { keys = keys } } }
  -- Outside a project (your home folder) scanning every file is slow and
  -- noisy, so offer recent files instead; ⌘O opens a project.
  if vim.fn.getcwd() == vim.env.HOME then
    opts.title = "Recent Files — ⌘O opens a folder"
    Snacks.picker.recent(opts)
    return
  end
  opts.title = "Go to File   > command   @ symbol   # in project   : line"
  Snacks.picker.smart(opts)
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

-- ⌘N: an empty page with the caret in it, like every Mac editor.
function M.new_file()
  normal_mode()
  focus_editor()
  vim.cmd.enew()
  if #vim.api.nvim_list_uis() > 0 then
    vim.cmd.startinsert()
  end
end

local function ask_save_path(buf, on_done)
  local name = vim.api.nvim_buf_get_name(buf)
  local default = name ~= "" and name or (vim.fn.getcwd() .. "/")
  vim.ui.input({ prompt = "Save as: ", default = default, completion = "file" }, function(path)
    if not path or vim.trim(path) == "" or path == vim.fn.getcwd() .. "/" then
      return
    end
    path = vim.fn.fnamemodify(vim.fn.expand(vim.trim(path)), ":p")
    local ok, err = pcall(function()
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("silent keepalt saveas! " .. vim.fn.fnameescape(path))
        if vim.bo.filetype == "" then
          vim.cmd("filetype detect") -- a new name can mean a new language
        end
      end)
    end)
    if not ok then
      vim.notify(tostring(err), vim.log.levels.ERROR)
      return
    end
    if on_done then
      on_done(path)
    end
  end)
end

function M.save_as()
  normal_mode()
  if vim.bo.buftype == "" then
    ask_save_path(vim.api.nvim_get_current_buf())
  end
end

function M.save()
  normal_mode()
  if vim.bo.buftype ~= "" then
    return
  end
  if vim.api.nvim_buf_get_name(0) ~= "" then
    -- Always write, even if auto-save got there first: ⌘S should visibly do
    -- something (it formats the file and plays the save sound). The ! writes
    -- over a file that changed on disk meanwhile: ⌘S means "keep mine".
    local ok, err = pcall(vim.cmd, "silent write!")
    if not ok then
      vim.notify(tostring(err), vim.log.levels.ERROR)
    end
    vim.b.dojo_changed_on_disk = nil
    return
  end
  ask_save_path(vim.api.nvim_get_current_buf())
end

function M.save_all()
  normal_mode()
  vim.cmd("silent! wall")
end

local closed = {}

function M.close_file()
  normal_mode()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= "" then
    -- A panel (terminal, run output, a sheet): ⌘W closes the panel.
    if vim.api.nvim_win_get_config(0).relative ~= "" or #vim.api.nvim_tabpage_list_wins(0) > 1 then
      pcall(vim.api.nvim_win_close, 0, true)
    end
    return
  end
  if name ~= "" then
    table.insert(closed, name)
    if vim.bo[buf].modified then
      pcall(vim.cmd, "silent write!") -- named files are always saved, never asked about
    end
    Snacks.bufdelete({ buf = buf, force = true })
    return
  end
  -- An untitled page: nothing typed, just close; otherwise ask once, plainly.
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  if not vim.bo[buf].modified or vim.trim(text) == "" then
    Snacks.bufdelete({ buf = buf, force = true })
    return
  end
  vim.ui.select({ "Save…", "Don't Save", "Cancel" }, { prompt = "Keep this untitled page?" }, function(choice)
    if choice == "Save…" then
      ask_save_path(buf, function()
        Snacks.bufdelete({ buf = buf, force = true })
      end)
    elseif choice == "Don't Save" then
      Snacks.bufdelete({ buf = buf, force = true })
    end
  end)
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
  vim.notify("No recently closed files", vim.log.levels.INFO, { title = require("dojo").name })
end

function M.settings()
  normal_mode()
  require("dojo.settings").open()
end

function M.revert_file()
  normal_mode()
  require("dojo.disk").revert()
end

function M.close_other_files()
  normal_mode()
  local current = vim.api.nvim_get_current_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= current and vim.bo[buf].buflisted and vim.bo[buf].buftype == "" then
      if vim.api.nvim_buf_get_name(buf) ~= "" then
        if vim.bo[buf].modified then
          vim.api.nvim_buf_call(buf, function()
            pcall(vim.cmd, "silent write!")
          end)
        end
        pcall(Snacks.bufdelete.delete, { buf = buf, force = true })
      end
    end
  end
end

function M.reveal_in_finder()
  require("dojo.menu").reveal()
end

function M.copy_path()
  require("dojo.menu").copy_path()
end

function M.show_log()
  normal_mode()
  require("dojo.calm").show_log()
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

-- ⌘D, as in VS Code and Sublime: the first press selects the word, each
-- further press selects its next occurrence too; then type, and every copy
-- changes. The selections are Mac-style (Select mode, lua/dojo/mac.lua).
-- Started from a Vim selection (v…), they stay Visual: every Vim command
-- then runs at each cursor.
local function set_cursor_modes(from, to)
  require("multicursor-nvim").action(function(ctx)
    ctx:forEachCursor(function(cursor)
      if cursor:mode() == from then
        cursor:setMode(to)
      end
    end)
  end)
end

function M.add_next_occurrence()
  local mc = require("multicursor-nvim")
  local mode = vim.fn.mode()
  if mode == "n" and not mc.hasCursors() then
    if vim.fn.expand("<cword>") ~= "" then
      vim.cmd("normal! viw\7") -- the word, as a Mac-style selection
    end
    return
  end
  local vim_style = mode:match("^[vV\22]") ~= nil
  if mode == "s" then
    set_cursor_modes("s", "v") -- the plugin works on Visual selections
  end
  mc.matchAddCursor(1)
  if not vim_style then
    set_cursor_modes("v", "s")
  end
end

-- ⌘⇧L: every occurrence at once, each one selected, ready to type over.
function M.select_all_occurrences()
  local mc = require("multicursor-nvim")
  local mode = vim.fn.mode()
  local vim_style = mode:match("^[vV\22]") ~= nil
  local text = visual_text() or vim.fn.expand("<cword>")
  if text == "" then
    return
  end
  if mode == "n" then
    vim.cmd("normal! viw")
  elseif mode == "s" then
    set_cursor_modes("s", "v")
  end
  mc.matchAllAddCursors()
  if text:find("\n") then
    return -- several lines: the cursors sit at each match, Vim-style
  end
  -- The plugin leaves a bare cursor at the start of each match: select them.
  local chars = vim.fn.strchars(text)
  mc.action(function(ctx)
    ctx:forEachCursor(function(cursor)
      if not cursor:hasSelection() then
        cursor:feedkeys(chars > 1 and ("v" .. (chars - 1) .. "l") or "v")
      end
      if not vim_style then
        cursor:setMode("s")
      end
    end)
  end)
end

function M.select_all()
  require("dojo.mac").select_all()
end

function M.select_line()
  require("dojo.mac").select_line()
end

function M.copy_selection()
  require("dojo.mac").copy()
end

function M.cut_selection()
  require("dojo.mac").cut()
end

function M.paste_over_selection()
  require("dojo.mac").paste()
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

-- Docs for the name under the cursor, written for people: the description
-- first, then one simple way to call it. Language servers often lead with
-- every type-stub overload (map() has six, full of `_T1@__new__`).
function M.readable_docs(markdown)
  local code, doc = markdown:match("^%s*```%w*\n(.-)\n```%s*\n%-%-%-+%s*\n(.*)$")
  if not code then
    return markdown -- nothing to rearrange
  end
  local forms = vim.split(vim.trim(code), "\n%s*\n")
  local first = forms[1]:gsub("@[%w_]+", "") -- _T1@__new__ -> _T1
  local lines = { vim.trim(doc), "", "```python", first, "```" }
  if #forms > 1 then
    table.insert(lines, ("_+%d more way%s to call it_"):format(#forms - 1, #forms > 2 and "s" or ""))
  end
  return table.concat(lines, "\n")
end

function M.hover()
  local params = vim.lsp.util.make_position_params(0, "utf-16")
  vim.lsp.buf_request_all(0, "textDocument/hover", params, function(results)
    local parts = {}
    for _, res in pairs(results) do
      local contents = res.result and res.result.contents
      if contents then
        local text = type(contents) == "table" and (contents.value or contents[1] and contents[1].value) or contents
        if type(text) == "string" and vim.trim(text) ~= "" then
          table.insert(parts, M.readable_docs(text))
        end
      end
    end
    if #parts == 0 then
      vim.notify("No documentation here", vim.log.levels.INFO, { title = "Docs" })
      return
    end
    vim.lsp.util.open_floating_preview(vim.split(table.concat(parts, "\n\n---\n\n"), "\n"), "markdown", {
      focus_id = "dojo_docs",
      max_width = math.min(90, math.floor(vim.o.columns * 0.6)),
      max_height = math.floor(vim.o.lines * 0.5),
    })
  end)
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

-- ⌃C: stop the program ⌘R started (an infinite loop, say). Its output stays.
function M.stop_run()
  local runner = require("config.runner")
  if runner.is_running() then
    runner.stop()
  end
end

function M.close_output()
  normal_mode()
  require("config.runner").close()
  focus_editor()
end

-- ⌘J, like VS Code's panel: hides run output or the terminal, whichever is
-- showing; with neither showing, opens the terminal.
function M.toggle_terminal()
  if vim.api.nvim_get_mode().mode:match("^[iRt]") then
    vim.cmd.stopinsert()
  end
  local runner = require("config.runner")
  if runner.is_open() then
    runner.close()
    vim.schedule(focus_editor)
    return
  end
  local term = Snacks.terminal.toggle(nil, {
    cwd = root(),
    win = { position = "bottom", height = 0.32, wo = { winbar = "%#Comment#  Terminal%=⌘J hide  " } },
  })
  if term and not term:valid() then
    vim.schedule(focus_editor) -- hidden: back to your file, not the tree
  end
end

function M.review()
  normal_mode()
  require("dojo.review").pick()
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
  vim.notify("Word wrap " .. (vim.wo.wrap and "on" or "off"), vim.log.levels.INFO, { title = require("dojo").name })
end

function M.theme()
  normal_mode()
  require("dojo.theme").pick()
end

local function scale(delta)
  if not vim.g.neovide then
    vim.notify(
      "Zoom works in the " .. require("dojo").name .. " app (Neovide). In a terminal use its own ⌘= / ⌘-.",
      vim.log.levels.INFO
    )
    return
  end
  if delta == 0 then
    vim.g.neovide_scale_factor = 1.0
  else
    vim.g.neovide_scale_factor = math.max(0.5, math.min(2.5, (vim.g.neovide_scale_factor or 1.0) * delta))
  end
  require("dojo.settings").set("zoom", vim.g.neovide_scale_factor) -- the same size next launch
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

function M.toggle_dim()
  require("dojo.dim").toggle()
end

function M.toggle_sound()
  require("dojo.sfx").toggle()
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

return M
