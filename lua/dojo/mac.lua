-- Selecting text the Mac way, on top of Vim.
--
-- Two kinds of selection live side by side:
--   * made the Vim way (v, V, Ctrl-v): Visual mode, where keys are commands;
--   * made the Mac way (Shift+arrows, the mouse, ⌘A, ⌘D, ⌘L): Select mode,
--     where typing replaces the selection, Backspace deletes it and an arrow
--     key lets go of it. That is what every other Mac editor does.
-- Ctrl-g flips a selection between the two.
--
-- Shift+arrow selection is computed here rather than left to 'keymodel': Vim
-- counts the character under a block cursor, a caret sits between characters,
-- and the built-in version selects one character too many from Insert mode.
-- Here a selection is always "from one caret to another".

local M = {}

-- Typing started in Insert mode: go back to it when the selection is let go.
local from_insert = false

local function line_len(row)
  return #(vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or "")
end

local function last_row()
  return vim.api.nvim_buf_line_count(0)
end

-- A caret: { row (1-based), col (0-based byte; the caret sits before it) }.
local function before(a, b)
  return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
end

local function same(a, b)
  return a[1] == b[1] and a[2] == b[2]
end

-- Step over one whole character (UTF-8 aware).
local function step(row, col, direction)
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
  if direction > 0 then
    return col + #vim.fn.strcharpart(line:sub(col + 1), 0, 1)
  end
  local head = line:sub(1, col)
  return col - #vim.fn.strcharpart(head, vim.fn.strchars(head) - 1, 1)
end

-- The character just before a caret, as a Visual-mode position. Before the
-- start of a line that is the line break above it.
local function char_before(caret)
  if caret[2] == 0 then
    return { caret[1] - 1, line_len(caret[1] - 1) }
  end
  return { caret[1], step(caret[1], caret[2], -1) }
end

local is_word = function(char)
  return char:match("[%w_]") ~= nil or char:byte() > 127
end

local motions = {}

function motions.left(c)
  if c[2] > 0 then
    return { c[1], step(c[1], c[2], -1) }
  elseif c[1] > 1 then
    return { c[1] - 1, line_len(c[1] - 1) }
  end
  return c
end

function motions.right(c)
  if c[2] < line_len(c[1]) then
    return { c[1], step(c[1], c[2], 1) }
  elseif c[1] < last_row() then
    return { c[1] + 1, 0 }
  end
  return c
end

-- Up and down keep the column you started in, as far as each line allows.
local want_col
local function vertical(c, delta)
  local row = c[1] + delta
  if row < 1 then
    return { 1, 0 }
  elseif row > last_row() then
    return { last_row(), line_len(last_row()) }
  end
  want_col = want_col
    or vim.fn.strdisplaywidth((vim.api.nvim_buf_get_lines(0, c[1] - 1, c[1], false)[1] or ""):sub(1, c[2]))
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
  local col = 0
  while col < #line do
    local next_col = col + #vim.fn.strcharpart(line:sub(col + 1), 0, 1)
    if vim.fn.strdisplaywidth(line:sub(1, next_col)) > want_col then
      break
    end
    col = next_col
  end
  return { row, col }
end

function motions.up(c)
  return vertical(c, -1)
end

function motions.down(c)
  return vertical(c, 1)
end

function motions.page_up(c)
  return vertical(c, -math.max(1, vim.api.nvim_win_get_height(0) - 2))
end

function motions.page_down(c)
  return vertical(c, math.max(1, vim.api.nvim_win_get_height(0) - 2))
end

-- ⌥→ : to the end of this word, or of the next one.
function motions.word_right(c)
  local line = vim.api.nvim_buf_get_lines(0, c[1] - 1, c[1], false)[1] or ""
  local col = c[2]
  if col >= #line then
    return motions.right(c)
  end
  while col < #line and not is_word(line:sub(col + 1, col + 1)) do
    col = col + 1
  end
  while col < #line and is_word(line:sub(col + 1, col + 1)) do
    col = col + 1
  end
  return { c[1], col }
end

function motions.word_left(c)
  local line = vim.api.nvim_buf_get_lines(0, c[1] - 1, c[1], false)[1] or ""
  local col = c[2]
  if col == 0 then
    return motions.left(c)
  end
  while col > 0 and not is_word(line:sub(col, col)) do
    col = col - 1
  end
  while col > 0 and is_word(line:sub(col, col)) do
    col = col - 1
  end
  return { c[1], col }
end

-- ⌘← : the first character of the line, then the very start (like Home in VS Code).
function motions.line_start(c)
  local line = vim.api.nvim_buf_get_lines(0, c[1] - 1, c[1], false)[1] or ""
  local indent = #(line:match("^%s*") or "")
  return { c[1], c[2] == indent and 0 or indent }
end

function motions.line_end(c)
  return { c[1], line_len(c[1]) }
end

function motions.file_start()
  return { 1, 0 }
end

function motions.file_end()
  return { last_row(), line_len(last_row()) }
end

local function mode()
  return vim.api.nvim_get_mode().mode
end

local function selecting(m)
  return (m or mode()):match("^[vVsS\22\19]") ~= nil
end

-- The last selection made here: a one-character selection doesn't say which
-- way it is growing, so remember (it is trusted only while it still matches).
local last

-- The selection as two carets: where it started, and the moving end.
local function carets()
  local m = mode()
  local cursor = vim.api.nvim_win_get_cursor(0)
  if not selecting(m) then
    return { cursor[1], cursor[2] }, { cursor[1], cursor[2] }
  end
  local anchor = vim.fn.getpos("v")
  anchor = { anchor[2], anchor[3] - 1 }
  local head = { cursor[1], cursor[2] }
  if last and last.buf == vim.api.nvim_get_current_buf() and same(last.anchor, anchor) and same(last.head, head) then
    return last.from, last.to
  end
  if m:match("^[VS]") then -- whole lines
    if before(head, anchor) then
      return { math.min(anchor[1] + 1, last_row() + 1), 0 }, { head[1], 0 }
    end
    return { anchor[1], 0 }, { head[1], line_len(head[1]) }
  end
  local function after(pos)
    if pos[2] >= line_len(pos[1]) then
      return pos[1] < last_row() and { pos[1] + 1, 0 } or { pos[1], line_len(pos[1]) }
    end
    return { pos[1], step(pos[1], pos[2], 1) }
  end
  if before(head, anchor) then
    return after(anchor), head
  end
  return anchor, after(head)
end

-- Ahead of anything already typed, so a fast typist's next key lands after it.
local function keys(text)
  vim.api.nvim_feedkeys(vim.keycode(text), "ni", false)
end

local pending

-- Runs in Normal mode, right after the keys that left the old mode.
function M._apply()
  local job = pending
  pending = nil
  if not job then
    return
  end
  if job.caret then
    local caret, len = job.caret, line_len(job.caret[1])
    if from_insert then
      from_insert = false
      vim.api.nvim_win_set_cursor(0, { caret[1], math.min(caret[2], math.max(len - 1, 0)) })
      if caret[2] >= len then
        vim.cmd("startinsert!")
      else
        vim.cmd("startinsert")
      end
    else
      vim.api.nvim_win_set_cursor(0, { caret[1], math.min(caret[2], math.max(len - 1, 0)) })
    end
    return
  end
  vim.api.nvim_win_set_cursor(0, job.anchor)
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(0, job.head)
  if not job.visual then
    vim.cmd("normal! \7") -- Ctrl-g: Visual → Select
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  last = job.from
    and {
      buf = vim.api.nvim_get_current_buf(),
      anchor = job.anchor,
      head = { cursor[1], cursor[2] },
      from = job.from,
      to = job.to,
    }
end

local function run(job)
  pending = job
  local m = mode()
  if m:match("^[iR]") then
    from_insert = true
    keys("<Esc><Cmd>lua require('dojo.mac')._apply()<CR>")
  elseif selecting(m) then
    keys("<Esc><Cmd>lua require('dojo.mac')._apply()<CR>")
  else
    M._apply()
  end
end

-- Text you can type into: a file, an untitled page, a scratch note. Not the
-- file tree, a picker's list, a terminal or a prompt line.
local function editable()
  return vim.bo.modifiable and (vim.bo.buftype == "" or vim.bo.buftype == "nofile" or vim.bo.buftype == "acwrite")
end

--- Shift + a movement key: start a selection, or stretch the one there is.
function M.extend(name)
  if not editable() then
    return
  end
  local anchor, head = carets()
  if name ~= "up" and name ~= "down" and name ~= "page_up" and name ~= "page_down" then
    want_col = nil
  end
  local moved = motions[name](head)
  if same(moved, anchor) then
    if selecting() then
      run({ caret = anchor }) -- back to nothing selected
    end
    return
  end
  local visual = mode():match("^[vV\22]") ~= nil -- a Vim selection stays one
  if before(anchor, moved) then
    run({ anchor = anchor, head = char_before(moved), visual = visual, from = anchor, to = moved })
  else
    run({ anchor = char_before(anchor), head = moved, visual = visual, from = anchor, to = moved })
  end
end

--- A plain movement key while text is selected: let go of the selection.
--- ← lands at its start and → at its end, like everywhere else on a Mac.
function M.collapse(name)
  local anchor, head = carets()
  local low, high = anchor, head
  if before(head, anchor) then
    low, high = head, anchor
  end
  want_col = nil
  local caret
  if name == "left" then
    caret = low
  elseif name == "right" then
    caret = high
  else
    caret = motions[name](head)
  end
  run({ caret = caret })
end

--- ⌘A: everything, as a selection you can type over.
function M.select_all()
  local rows = last_row()
  run({ anchor = { 1, 0 }, head = { rows, math.max(line_len(rows) - 1, 0) } })
end

--- ⌘L: this line; again takes the next one too.
function M.select_line()
  local m = mode()
  if m == "S" or m == "V" then
    keys(m == "S" and "<C-g>j<C-g>" or "j")
    return
  end
  if m:match("^[iR]") then
    from_insert = true
  end
  keys((selecting(m) or m:match("^[iR]")) and "<Esc>V<C-g>" or "V<C-g>")
end

--- Delete the selection (Backspace / Delete), staying in the mode you came from.
function M.delete()
  if from_insert then
    from_insert = false
    keys('<C-g>"_c')
  else
    keys('<C-g>"_d')
  end
end

--- ⌘C: copy and keep the selection, as a Mac does.
function M.copy()
  local m = mode()
  local kind = ({ s = "v", S = "V", ["\19"] = "\22" })[m] or m
  local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = kind })
  vim.fn.setreg("+", lines, kind == "V" and "V" or "v")
  pcall(function()
    local sfx = require("sfx") -- the same small sound as any other copy
    if sfx.opts.enabled and sfx.opts.events.yank then
      sfx.emit("yank")
    end
  end)
end

--- ⌘X: cut, and stay in the mode you came from.
function M.cut()
  if from_insert then
    from_insert = false
    keys('<C-g>"+c')
  else
    keys('<C-g>"+d')
  end
end

--- Paste over the selection and carry on typing after it.
function M.paste()
  from_insert = false
  keys('<C-g>"_c<C-r><C-o>+')
end

function M.in_select()
  return mode():match("^[sS\19]") ~= nil
end

local shifted = {
  ["<S-Left>"] = "left",
  ["<S-Right>"] = "right",
  ["<S-Up>"] = "up",
  ["<S-Down>"] = "down",
  ["<S-PageUp>"] = "page_up",
  ["<S-PageDown>"] = "page_down",
  ["<S-Home>"] = "line_start",
  ["<S-End>"] = "line_end",
  ["<D-S-Left>"] = "line_start",
  ["<D-S-Right>"] = "line_end",
  ["<D-S-Up>"] = "file_start",
  ["<D-S-Down>"] = "file_end",
  ["<M-S-Left>"] = "word_left",
  ["<M-S-Right>"] = "word_right",
}

local plain = {
  ["<Left>"] = "left",
  ["<Right>"] = "right",
  ["<Up>"] = "up",
  ["<Down>"] = "down",
  ["<Home>"] = "line_start",
  ["<End>"] = "line_end",
  ["<D-Left>"] = "line_start",
  ["<D-Right>"] = "line_end",
  ["<D-Up>"] = "file_start",
  ["<D-Down>"] = "file_end",
  ["<M-Left>"] = "word_left",
  ["<M-Right>"] = "word_right",
  ["<PageUp>"] = "page_up",
  ["<PageDown>"] = "page_down",
}

-- Chords the app's own menu owns (⌘Q, ⌘H, ⌘M, ⌘⇧N) never reach Neovim. Any
-- other ⌘ chord nothing is bound to must do nothing: left alone, Neovim would
-- drop the ⌘ and run the bare key (⌘U would undo, ⌘I start typing) or, in
-- Insert mode, type "<D-u>" into the file. Every key passes through here
-- after mappings have had their say; a ⌘ chord that is still itself had none,
-- and is dropped.
local swallow_ns = vim.api.nvim_create_namespace("dojo_swallow")

function M.unbound_chord(key, typed)
  if key == "" or key ~= typed or key:byte(1) ~= 0x80 then
    return false -- produced by a mapping, or not a special key at all
  end
  local name = vim.fn.keytrans(key)
  return name:match("^<%a?%-?%a?%-?%a?%-?D%-[^>]+>$") ~= nil and not name:find("Mouse") and not name:find("ScrollWheel")
end

function M.swallow_unbound()
  vim.on_key(function(key, typed)
    if M.unbound_chord(key, typed) then
      return "" -- discard
    end
  end, swallow_ns)
end

-- Printable keys must replace a selection, so nothing may be mapped to them in
-- Select mode. Plugins that map with mode "v" get this wrong (it means Visual
-- *and* Select); clear such maps whenever a selection starts.
local checked = {} ---@type table<integer, boolean>  buffers already looked at
local function clear_printable_maps()
  local buf = vim.api.nvim_get_current_buf()
  if checked[buf] then
    return
  end
  checked[buf] = true
  local function printable(lhs)
    return lhs ~= "" and not lhs:match("^<") or lhs:match("^<lt>") or lhs:match("^<Space>") or lhs:match("^<Bar>")
  end
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, "s")) do
    if printable(map.lhs) then
      pcall(vim.keymap.del, "s", map.lhs, { buffer = 0 })
    end
  end
  for _, map in ipairs(vim.api.nvim_get_keymap("s")) do
    if printable(map.lhs) then
      pcall(vim.keymap.del, "s", map.lhs)
    end
  end
end

function M.setup()
  -- The mouse selects the Mac way too (drag, double-click a word, triple-click
  -- a line), wherever there is text to type over. In the file tree, a
  -- terminal or a list, a drag stays a plain Vim selection you can copy.
  vim.opt.keymodel = ""
  local function follow()
    vim.o.selectmode = editable() and "mouse" or ""
  end
  follow()
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "TermLeave" }, {
    group = vim.api.nvim_create_augroup("DojoMacMouse", { clear = true }),
    callback = follow,
  })

  local set = vim.keymap.set
  for lhs, name in pairs(shifted) do
    set({ "n", "i", "x", "s" }, lhs, function()
      M.extend(name)
    end, { desc = "Select: " .. name:gsub("_", " "), silent = true })
  end
  for lhs, name in pairs(plain) do
    set("s", lhs, function()
      M.collapse(name)
    end, { desc = "Let go of the selection", silent = true })
  end
  set("s", "<BS>", M.delete, { desc = "Delete the selection", silent = true })
  set("s", "<Del>", M.delete, { desc = "Delete the selection", silent = true })

  local group = vim.api.nvim_create_augroup("DojoMacSelect", { clear = true })
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "*:[sS\19]*",
    callback = clear_printable_maps,
  })
  -- A language server attaching (or the buffer going away) can bring new maps: look again.
  vim.api.nvim_create_autocmd({ "LspAttach", "BufWipeout", "FileType" }, {
    group = group,
    callback = function(ev)
      checked[ev.buf] = nil
    end,
  })
  -- The selection is gone and you're back in Normal or Insert: forget where it began.
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "[sS\19vV\22]*:[ni]*",
    callback = function()
      if not pending then
        from_insert = false
      end
    end,
  })
end

return M
