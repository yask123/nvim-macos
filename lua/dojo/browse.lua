-- ⌘O — Open Folder, inside the window (no macOS dialog).
--
-- Two columns: the folders here on the left, what's inside the highlighted
-- one on the right. j k (or the arrows) move, l steps into a folder, h steps
-- back out, / narrows the list as you type, and Enter opens the highlighted
-- folder as the project. It starts beside the project you last worked in,
-- and folders you've had open before carry a small mark.

local M = {}

local api, uv = vim.api, vim.uv
local draw = require("dojo.draw")
local ns = api.nvim_create_namespace("dojo_browse")
local Line, push, fit, width_of, color = draw.line, draw.push, draw.fit, draw.width, draw.color

local ROWS_ABOVE = 3 -- blank, the path, blank
local MARGIN, GAP = 2, 3

-- One browser at a time: where it is, what it lists, which row is lit.
local state

function M.highlights()
  local accent = color("Function", "fg") or color("Special", "fg")
  local set = function(name, spec)
    spec.default = true -- a colour theme may set its own (colors/phosphor.lua does)
    api.nvim_set_hl(0, name, spec)
  end
  set("DojoBrowsePath", { link = "Comment" })
  set("DojoBrowseHere", { link = "NormalFloat" })
  set("DojoBrowseFolder", { link = "NormalFloat" })
  set("DojoBrowseSelected", { link = "Visual" })
  set("DojoBrowseInside", { link = "Comment" })
  set("DojoBrowseQuiet", { link = "Comment" })
  set("DojoBrowseTyped", { fg = accent, bold = true })
  set("DojoBrowseOpen", { link = "FloatTitle" })
  set("DojoBrowseKnown", { fg = accent })
  set("DojoBrowseKnownSelected", { fg = accent, bg = color("Visual", "bg") })
end

local function join(dir, name)
  return dir == "/" and "/" .. name or dir .. "/" .. name
end

local function by_name(a, b)
  local la, lb = a:lower(), b:lower()
  if la ~= lb then
    return la < lb
  end
  return a < b
end

-- The folders directly inside `dir`, by name. Dot-folders only when asked.
local function folders(dir, hidden)
  local names = {}
  local handle = uv.fs_scandir(dir)
  while handle do
    local name, kind = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if hidden or name:sub(1, 1) ~= "." then
      if kind ~= "directory" and kind ~= "file" then -- a link (or unknown): ask what it points at
        local stat = uv.fs_stat(join(dir, name))
        kind = stat and stat.type or kind
      end
      if kind == "directory" then
        names[#names + 1] = name
      end
    end
  end
  table.sort(names, by_name)
  return names
end

-- What's inside a folder, for the right column: folders first, then files.
-- Read off the main loop, so a slow disk (or a macOS permission prompt for
-- Desktop or Documents) never freezes the editor.
local function look_inside(path, hidden, done)
  uv.fs_scandir(path, function(_, handle)
    local dirs, files, count = {}, {}, 0
    while handle and count < 3000 do
      local name, kind = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      count = count + 1
      if hidden or name:sub(1, 1) ~= "." then
        table.insert(kind == "directory" and dirs or files, name)
      end
    end
    table.sort(dirs, by_name)
    table.sort(files, by_name)
    local items = {}
    for _, name in ipairs(dirs) do
      items[#items + 1] = name .. "/"
    end
    vim.list_extend(items, files)
    vim.schedule(function()
      done(items)
    end)
  end)
end

-- "~ › dev › practice", shortened from the left when it runs out of room.
-- While you type (after /), what you've typed follows as the next name.
-- Returns the line and where the typed part starts.
local function path_line(dir, typed, typing, width)
  local shown = vim.fn.fnamemodify(dir, ":~")
  local parts = vim.split(shown, "/", { plain = true, trimempty = true })
  if shown:sub(1, 1) == "/" then
    table.insert(parts, 1, "/")
  end
  local reserve = typing and 20 or 0 -- room to type; fixed, so the path holds still
  local function total()
    local cells = reserve
    for index, part in ipairs(parts) do
      cells = cells + width_of(part) + (index > 1 and 3 or 0)
    end
    return cells
  end
  while #parts > 2 and total() > width do
    table.remove(parts, 1)
    parts[1] = "…"
  end
  local line = Line()
  push(line, string.rep(" ", MARGIN + 1))
  for index, part in ipairs(parts) do
    if index > 1 then
      push(line, " › ", "DojoBrowseQuiet")
    end
    push(line, part, (index == #parts and not typing) and "DojoBrowseHere" or "DojoBrowsePath")
  end
  if typing then
    push(line, " › ", "DojoBrowseQuiet")
  end
  local from = #line.text
  if typing then
    push(line, typed, "DojoBrowseTyped")
  end
  return line, from
end

local function selected()
  return state.shown[state.sel]
end

-- The folder Enter would open: the lit one, or this folder when it has none.
local function target()
  local name = selected()
  if name then
    return join(state.dir, name)
  end
  return state.filter == "" and state.dir or nil
end

-- Folders you've had open before come first ("/py ↩" is learn-python, not
-- PycharmProjects); within each group, names that start with what you typed
-- come before names that only contain it.
local function narrow()
  local s = state
  local typed = s.filter:lower()
  if typed == "" then
    s.shown = s.all
    return
  end
  local ranks = { {}, {}, {}, {} }
  for _, name in ipairs(s.all) do
    local at = name:lower():find(typed, 1, true)
    if at then
      local rank = (s.known[join(s.dir, name)] and 0 or 2) + (at == 1 and 1 or 2)
      table.insert(ranks[rank], name)
    end
  end
  s.shown = {}
  for _, names in ipairs(ranks) do
    vim.list_extend(s.shown, names)
  end
end

local function select(name)
  local s = state
  s.sel = #s.shown > 0 and 1 or 0
  for index, shown in ipairs(s.shown) do
    if shown == name then
      s.sel = index
      break
    end
  end
  s.top = math.max(1, s.sel - math.floor(s.rows / 2)) -- render() keeps it in range
end

local render

-- Fill the right column for the lit folder. Seen folders come back at once;
-- new ones are read after a short pause, so holding j doesn't read every
-- folder it passes.
local function preview()
  local s = state
  local path = selected() and join(s.dir, selected()) or s.dir
  s.want = path
  if s.seen[path] then
    s.inside = s.seen[path]
    return
  end
  s.timer = s.timer or assert(uv.new_timer())
  s.timer:stop()
  s.timer:start(
    s.inside and 45 or 0,
    0,
    vim.schedule_wrap(function()
      if state ~= s or s.want ~= path then
        return
      end
      look_inside(path, s.hidden, function(items)
        s.seen[path] = items
        if state == s and s.want == path then
          s.inside = items
          render()
        end
      end)
    end)
  )
end

local function footer()
  local s = state
  local open = target()
  local chunks = {}
  if open then
    local name = open == s.dir and vim.fn.fnamemodify(open, ":~") or vim.fs.basename(open)
    chunks[#chunks + 1] = { " ↩ open " .. fit(name, math.min(width_of(name), 28)), "DojoBrowseOpen" }
    chunks[#chunks + 1] = { " · ", "FloatFooter" }
  else
    chunks[#chunks + 1] = { " ", "FloatFooter" }
  end
  local rest = s.typing and "⇥ into · esc back to the list " or "l into · h back · / find · esc close "
  chunks[#chunks + 1] = { rest, "FloatFooter" }
  return chunks
end

function render()
  local s = state
  if not s or not s.win:valid() then
    return
  end
  -- Keep the lit row in view, with a line or two of what comes next.
  local rows = s.rows
  local edge = math.min(2, math.floor((rows - 1) / 2))
  if s.sel > 0 then
    s.top = math.max(1, math.min(s.top, s.sel - edge))
    s.top = math.max(s.top, s.sel + edge - rows + 1)
    s.top = math.max(1, math.min(s.top, math.max(1, #s.shown - rows + 1)))
  else
    s.top = 1
  end

  local path, typed_from = path_line(s.dir, s.filter, s.typing, s.width - 2 * MARGIN - 2)
  s.before = path.text:sub(1, typed_from) -- the path line up to what you type
  local lines = { Line(), path, Line() }
  local inside = s.inside or {}
  for row = 1, rows do
    local line = Line()
    push(line, string.rep(" ", MARGIN))
    local index = s.top + row - 1
    local name = s.shown[index]
    if name then
      local lit = index == s.sel
      if s.known[join(s.dir, name)] then
        -- a folder you've had open as a project: a small mark at the edge
        push(line, " " .. fit(name, s.left - 4), lit and "DojoBrowseSelected" or "DojoBrowseFolder")
        push(line, " • ", lit and "DojoBrowseKnownSelected" or "DojoBrowseKnown")
      else
        push(line, " " .. fit(name, s.left - 2) .. " ", lit and "DojoBrowseSelected" or "DojoBrowseFolder")
      end
    elseif row == 1 and #s.shown == 0 then
      local why = s.filter ~= "" and "No folder called that here" or "No folders in here"
      push(line, " " .. fit(why, s.left - 2) .. " ", "DojoBrowseQuiet")
    else
      push(line, string.rep(" ", s.left))
    end
    push(line, string.rep(" ", GAP))
    local item = inside[row]
    if item then
      if row == rows and #inside > rows then
        item = ("+ %d more"):format(#inside - rows + 1)
      end
      push(line, fit(item, s.right), "DojoBrowseInside")
    end
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = Line()

  local buf = s.win.buf
  local text = draw.text(lines)
  vim.bo[buf].modifiable = true
  -- While you type, the path line is yours: leave it alone unless it has
  -- drifted from what it should say (a paste with line breaks, say).
  local now = api.nvim_buf_get_lines(buf, 0, -1, false)
  if s.typing and #now == #text and now[2] == text[2] then
    api.nvim_buf_set_lines(buf, 2, -1, false, vim.list_slice(text, 3))
  else
    api.nvim_buf_set_lines(buf, 0, -1, false, text)
  end
  vim.bo[buf].modifiable = s.typing
  draw.paint(buf, ns, lines)
  local at = s.sel > 0 and (s.sel - s.top + 1) or 1
  local cursor = s.typing and { 2, #text[2] } or { ROWS_ABOVE + at, MARGIN + 1 }
  pcall(api.nvim_win_set_cursor, s.win.win, cursor)
  pcall(api.nvim_win_set_config, s.win.win, { footer = footer(), footer_pos = "center" })
end

local function show()
  preview()
  render()
end

-- While you type, the path line is the source of truth: read back what has
-- been typed. Keys can arrive faster than the editor reports the change
-- ("pyt" and Enter in one burst), so every action reads it first.
local function catch_up()
  local s = state
  if not s or not s.typing then
    return
  end
  local line = api.nvim_buf_get_lines(s.win.buf, 1, 2, false)[1] or ""
  local text = s.filter
  if api.nvim_buf_line_count(s.win.buf) == s.rows + ROWS_ABOVE + 1 then
    if line:sub(1, #s.before) == s.before then
      text = line:sub(#s.before + 1)
    elseif #line < #s.before then
      text = "" -- deleted back into the path itself (⌘⌫, say): nothing typed
    end
  end
  if text ~= s.filter then
    s.filter = text
    narrow()
    select()
    preview()
  end
end

-- The path line changed under the caret.
local function typed()
  catch_up()
  render() -- also puts the path line back if an edit strayed into it
end

local function move(delta)
  local s = state
  catch_up()
  if #s.shown == 0 then
    return
  end
  s.sel = math.max(1, math.min(#s.shown, s.sel + delta))
  show()
end

-- Holding j or k picks up speed, as it does in a file (lua/dojo/hold.lua).
local function step(key, delta)
  local ok, hold = pcall(require, "dojo.hold")
  local count = ok and math.min(3, hold.steps(key, uv.hrtime() / 1e6)) or 1
  move(delta * count)
end

-- Typing ends; the folder that was lit stays lit in the full list.
local function stop_typing()
  local s = state
  if not s.typing then
    return
  end
  local name = selected()
  s.typing, s.filter = false, ""
  vim.cmd.stopinsert()
  narrow()
  select(name)
end

local function go(dir, name)
  local s = state
  local was = selected()
  stop_typing()
  s.lit[s.dir] = was or s.lit[s.dir]
  s.dir = dir
  s.all = folders(dir, s.hidden)
  narrow()
  select(name or s.lit[dir])
  show()
end

local function into()
  catch_up()
  local name = selected()
  if name then
    go(join(state.dir, name))
  end
end

local function out()
  local s = state
  if s.dir ~= "/" then
    go(vim.fs.dirname(s.dir), vim.fs.basename(s.dir))
  end
end

local function accept()
  catch_up()
  local path = target()
  if not path then
    return
  end
  M.close()
  vim.schedule(function()
    require("dojo.project").open(path)
  end)
end

local function toggle_hidden()
  local s = state
  local name = selected()
  s.hidden = not s.hidden
  s.seen = {}
  s.all = folders(s.dir, s.hidden)
  narrow()
  select(name)
  show()
end

-- / — type part of a name; the list narrows to the folders that have it.
-- You type into the path line itself, with the editor's own caret.
local function find()
  local s = state
  if s.typing then
    return
  end
  s.typing, s.filter = true, ""
  show()
  vim.cmd("startinsert!")
end

function M.close()
  local s = state
  state = nil
  if s then
    if s.timer then
      s.timer:stop()
      s.timer:close()
    end
    if s.win:valid() then
      if api.nvim_get_current_win() == s.win.win then
        vim.cmd.stopinsert() -- typing a name is over
      end
      s.win:close()
    end
  end
end

function M.is_open()
  return state ~= nil
end

-- For tests and scripts: where the browser is and what it shows.
function M.peek()
  local s = state
  return s
      and {
        dir = s.dir,
        shown = vim.deepcopy(s.shown),
        selected = selected(),
        target = target(),
        typing = s.typing,
        filter = s.filter,
        inside = vim.deepcopy(s.inside or {}),
        buf = s.win.buf,
      }
    or nil
end

-- For tests and scripts: as if you pressed / and typed `text`.
function M.type(text)
  local s = state
  find()
  api.nvim_buf_set_lines(s.win.buf, 1, 2, false, { s.before .. text })
  typed()
end

--- Open the browser, or close it if it is showing.
---@param opts? { dir?: string, select?: string }
function M.open(opts)
  if state then
    return M.close()
  end
  opts = opts or {}
  M.highlights()

  -- Start beside the project you're in, or the one you opened last.
  local dir, name = opts.dir, opts.select
  if not dir then
    local cwd = vim.fn.getcwd()
    local latest = require("dojo.recent").list(1)[1]
    local beside = (cwd ~= vim.env.HOME and cwd ~= "/") and cwd or (latest and latest.path)
    if beside then
      dir, name = vim.fs.dirname(beside), vim.fs.basename(beside)
    else
      dir = vim.env.HOME
    end
  end
  dir = uv.fs_realpath(dir) or vim.env.HOME

  local width = math.max(40, math.min(vim.o.columns - 8, 84))
  local height = math.max(8, math.min(vim.o.lines - 8, 22))
  local left = math.floor((width - 2 * MARGIN - GAP) * 0.46)

  state = {
    dir = dir,
    all = {},
    shown = {},
    sel = 0,
    top = 1,
    filter = "",
    typing = false,
    hidden = false,
    before = "",
    lit = {}, -- the row that was lit in each folder you've been through
    seen = {}, -- folders already read for the right column
    known = {}, -- folders you've had open as projects
    width = width,
    rows = height - ROWS_ABOVE - 1,
    left = left,
    right = width - 2 * MARGIN - GAP - left,
  }
  local s = state
  for _, entry in ipairs(require("dojo.recent").list()) do
    s.known[entry.path] = true
  end
  s.win = Snacks.win({
    width = width,
    height = height,
    border = "rounded",
    backdrop = 55,
    title = " Open Folder ",
    title_pos = "center",
    footer = " ",
    footer_pos = "center",
    enter = true,
    fixbuf = true,
    zindex = 60,
    bo = { filetype = "dojo_browse", modifiable = false },
    wo = {
      cursorline = false,
      wrap = false,
      number = false,
      relativenumber = false,
      signcolumn = "no",
    },
    on_close = function()
      if state == s then
        M.close()
      end
    end,
  })
  local buf = s.win.buf
  vim.b[buf].completion = false -- no completion menu or auto-pairs while you type a name
  vim.b[buf].minipairs_disable = true

  local function map(modes, keys, run)
    for _, lhs in ipairs(type(keys) == "table" and keys or { keys }) do
      vim.keymap.set(modes, lhs, function()
        if state == s then
          run()
        end
      end, { buffer = buf, nowait = true, silent = true })
    end
  end
  local both = { "n", "i" }
  map("n", { "q", "<Esc>" }, M.close)
  map(both, "<D-w>", M.close)
  map(both, "<CR>", accept)
  map("n", { "l", "<2-LeftMouse>" }, into)
  map(both, { "<Right>", "<Tab>" }, into)
  map("n", { "h", "<Left>", "<BS>", "-" }, out)
  map("n", "j", function()
    step("j", 1)
  end)
  map("n", "k", function()
    step("k", -1)
  end)
  map(both, { "<Down>", "<C-n>", "<C-j>" }, function()
    move(1)
  end)
  map(both, { "<Up>", "<C-p>", "<C-k>" }, function()
    move(-1)
  end)
  map("n", "<C-d>", function()
    move(math.floor(s.rows / 2))
  end)
  map("n", "<C-u>", function()
    move(-math.floor(s.rows / 2))
  end)
  map(both, "<ScrollWheelDown>", function()
    move(2)
  end)
  map(both, "<ScrollWheelUp>", function()
    move(-2)
  end)
  map("n", "g", function() -- gg: the first g already goes to the top (no waiting for the second)
    move(-math.huge)
  end)
  map("n", "G", function()
    move(math.huge)
  end)
  map("n", "~", function()
    go(vim.env.HOME)
  end)
  map("n", ".", toggle_hidden)
  map("n", { "/", "i", "a", "A", "I" }, find)
  -- Nothing here is text to edit: the other editing keys do nothing.
  local inert = { "v", "V", "o", "O", "s", "S", "c", "C", "x", "X", "d", "D", "p", "P", "r", "R", "u", "J" }
  map({ "n", "x" }, inert, function() end)
  -- A click lights a folder (a double click steps into it); a click
  -- anywhere outside closes the browser.
  map(both, "<LeftMouse>", function()
    local mouse = vim.fn.getmousepos()
    if mouse.winid ~= s.win.win then
      return M.close()
    end
    local index = s.top + mouse.line - ROWS_ABOVE - 1
    if mouse.line > ROWS_ABOVE and s.shown[index] and mouse.column <= MARGIN + s.left then
      s.sel = index
      show()
    end
  end)

  -- While typing: Esc goes back to the list, ⌫ on nothing does too, and the
  -- caret stays at the end of what you've typed.
  map("i", "<Esc>", function()
    stop_typing()
    show()
  end)
  vim.keymap.set("i", "<BS>", function()
    local line = api.nvim_buf_get_lines(buf, 1, 2, false)[1] or ""
    if state == s and #line <= #s.before then
      vim.schedule(function()
        if state == s then
          stop_typing()
          show()
        end
      end)
      return ""
    end
    return "<BS>"
  end, { buffer = buf, expr = true, nowait = true, silent = true })
  map("i", { "<Left>", "<Home>", "<End>", "<PageUp>", "<PageDown>", "<C-a>", "<C-e>" }, function() end)
  s.win:on("TextChangedI", typed, { buf = true })
  s.win:on("CursorMovedI", function()
    if state == s and s.typing then
      local line = api.nvim_buf_get_lines(buf, 1, 2, false)[1] or ""
      local at = api.nvim_win_get_cursor(s.win.win)
      if at[1] ~= 2 or at[2] ~= #line then
        pcall(api.nvim_win_set_cursor, s.win.win, { 2, #line })
      end
    end
  end, { buf = true })
  -- The cursor marks the lit row. Any other Vim motion (w, }, a slow gg)
  -- would walk it off the list: put it back.
  s.win:on("CursorMoved", function()
    if state == s and not s.typing then
      local at = api.nvim_win_get_cursor(s.win.win)
      local row = ROWS_ABOVE + math.max(1, s.sel - s.top + 1)
      if at[1] ~= row or at[2] ~= MARGIN + 1 then
        pcall(api.nvim_win_set_cursor, s.win.win, { row, MARGIN + 1 })
      end
    end
  end, { buf = true })
  -- Leaving insert mode nudges the cursor one cell left: draw once more after.
  s.win:on("InsertLeave", function()
    vim.schedule(function()
      if state == s then
        stop_typing()
        show()
      end
    end)
  end, { buf = true })
  -- Focus moved elsewhere (another window, a click): put the browser away.
  s.win:on("WinLeave", function()
    vim.schedule(function()
      if state == s then
        M.close()
      end
    end)
  end, { buf = true })

  s.all = folders(dir, false)
  narrow()
  select(name)
  show()
  return s.win
end

return M
