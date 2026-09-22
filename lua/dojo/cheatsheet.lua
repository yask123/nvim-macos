-- ⌘K ⌘S / Space ? — the Dojo cheatsheet. Renders lua/dojo/keys.lua as a
-- tabbed floating sheet: macOS chord, what it does, and the Vim-native way.

local M = {}

local ns = vim.api.nvim_create_namespace("dojo_cheatsheet")
local state = { tab = 1 }

local function color(group, attr)
  local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
  return hl[attr]
end

function M.highlights()
  local accent = color("Function", "fg") or color("Special", "fg")
  local chip_bg = color("CursorLine", "bg") or color("Visual", "bg")
  vim.api.nvim_set_hl(0, "DojoKey", { fg = accent, bg = chip_bg, bold = true })
  vim.api.nvim_set_hl(0, "DojoVim", { fg = color("String", "fg"), bg = chip_bg })
  vim.api.nvim_set_hl(0, "DojoLesson", { fg = color("String", "fg"), bold = true })
  vim.api.nvim_set_hl(0, "DojoKeyText", { fg = accent, bold = true })
  vim.api.nvim_set_hl(0, "DojoVimText", { fg = color("String", "fg") })
  vim.api.nvim_set_hl(0, "DojoDesc", { link = "NormalFloat" })
  vim.api.nvim_set_hl(0, "DojoMuted", { link = "Comment" })
  vim.api.nvim_set_hl(0, "DojoSection", { fg = color("Title", "fg") or accent, bold = true })
  vim.api.nvim_set_hl(0, "DojoTab", { link = "Comment" })
  vim.api.nvim_set_hl(0, "DojoTabActive", { fg = accent, bg = chip_bg, bold = true })
end

local function width_of(text)
  return vim.fn.strdisplaywidth(text)
end

local function pad(text, width)
  local gap = width - width_of(text)
  return gap > 0 and (text .. string.rep(" ", gap)) or text
end

-- A line builder that tracks byte offsets for highlights.
local function Line()
  return { text = "", marks = {} }
end

local function push(line, text, group)
  local start = #line.text
  line.text = line.text .. text
  if group then
    table.insert(line.marks, { start, #line.text, group })
  end
end

local function visible(items)
  return vim.tbl_filter(function(item)
    return not item.hidden
  end, items)
end

local function action_rows(group, width)
  local rows = {}
  local key_w, vim_w = 13, 16
  local desc_w = math.max(20, width - key_w - vim_w - 6)
  for _, section in ipairs(group.sections) do
    if section.title then
      table.insert(rows, { line = Line() })
      local title = Line()
      push(title, "   ")
      push(title, section.title, "DojoSection")
      table.insert(rows, { line = title })
    end
    for _, item in ipairs(visible(section.items)) do
      local line = Line()
      push(line, "   ")
      if item.mac then
        push(line, item.mac, "DojoKeyText")
        push(line, string.rep(" ", math.max(2, key_w - width_of(item.mac))))
        push(line, pad(item.desc, desc_w), "DojoDesc")
        if item.vim and item.vim ~= "" and item.vim ~= item.mac then
          push(line, item.vim, "DojoVimText")
        end
      else
        push(line, item.vim, "DojoVimText")
        push(line, string.rep(" ", math.max(2, key_w - width_of(item.vim))))
        push(line, item.desc, "DojoDesc")
      end
      table.insert(rows, { line = line, item = item })
    end
  end
  return rows
end

local function lesson_block(section, col_w)
  local block = {}
  local title = Line()
  push(title, section.title, "DojoSection")
  table.insert(block, { line = title })
  for _, item in ipairs(visible(section.items)) do
    local line = Line()
    push(line, pad(item.vim, 16), "DojoLesson")
    push(line, item.desc:sub(1, col_w * 2), "DojoDesc")
    table.insert(block, { line = line, item = item })
  end
  table.insert(block, { line = Line() })
  return block
end

local function column_rows(group, width)
  local col_w = math.floor((width - 6) / 2)
  local blocks, total = {}, 0
  for _, section in ipairs(group.sections) do
    local block = lesson_block(section, col_w)
    table.insert(blocks, block)
    total = total + #block
  end
  local left, right, used = {}, {}, 0
  for _, block in ipairs(blocks) do
    local target = used < total / 2 and left or right
    vim.list_extend(target, block)
    if target == left then
      used = used + #block
    end
  end
  local rows = {}
  for i = 1, math.max(#left, #right) do
    local line = Line()
    push(line, "  ")
    local l, r = left[i], right[i]
    if l then
      for _, mark in ipairs(l.line.marks) do
        table.insert(line.marks, { mark[1] + #line.text, mark[2] + #line.text, mark[3] })
      end
      line.text = line.text .. l.line.text
    end
    line.text = pad(line.text, col_w + 4)
    if r then
      for _, mark in ipairs(r.line.marks) do
        table.insert(line.marks, { mark[1] + #line.text, mark[2] + #line.text, mark[3] })
      end
      line.text = line.text .. r.line.text
    end
    table.insert(rows, { line = line })
  end
  return rows
end

local function build(width)
  local groups = require("dojo.keys")
  local rows = {}
  local tabs = Line()
  push(tabs, "  ")
  for index, group in ipairs(groups) do
    push(tabs, " " .. group.name .. " ", index == state.tab and "DojoTabActive" or "DojoTab")
    push(tabs, " ")
  end
  table.insert(rows, { line = tabs })
  table.insert(rows, { line = Line() })
  local group = groups[state.tab]
  local body = (group.columns or 1) > 1 and column_rows(group, width) or action_rows(group, width)
  vim.list_extend(rows, body)
  return rows
end

local function max_height(width)
  local saved, height = state.tab, 0
  for index in ipairs(require("dojo.keys")) do
    state.tab = index
    height = math.max(height, #build(width))
  end
  state.tab = saved
  return height
end

local function draw(win)
  local buf = win.buf
  local width = vim.api.nvim_win_get_width(win.win)
  local rows = build(width)
  local lines = vim.tbl_map(function(row)
    return row.line.text
  end, rows)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  win.dojo_items = {}
  for index, row in ipairs(rows) do
    for _, mark in ipairs(row.line.marks) do
      vim.api.nvim_buf_set_extmark(buf, ns, index - 1, mark[1], { end_col = mark[2], hl_group = mark[3] })
    end
    if row.item and row.item.run then
      win.dojo_items[index] = row.item
    end
  end
  vim.api.nvim_win_set_cursor(win.win, { math.min(3, #lines), 0 })
end

local function switch(win, delta, absolute)
  local count = #require("dojo.keys")
  state.tab = absolute or ((state.tab - 1 + delta) % count) + 1
  draw(win)
end

function M.open(tab)
  M.highlights()
  if tab then
    state.tab = tab
  end
  local width = math.min(vim.o.columns - 6, 100)
  local height = math.min(vim.o.lines - 6, max_height(width))
  local keys = {
    q = "close",
    ["<Esc>"] = "close",
    ["<D-w>"] = "close",
    ["<Tab>"] = function(self)
      switch(self, 1)
    end,
    ["<S-Tab>"] = function(self)
      switch(self, -1)
    end,
    l = function(self)
      switch(self, 1)
    end,
    h = function(self)
      switch(self, -1)
    end,
    ["/"] = function(self)
      self:close()
      require("dojo.palette").open({ lessons = true })
    end,
    ["<CR>"] = function(self)
      local item = self.dojo_items and self.dojo_items[vim.api.nvim_win_get_cursor(self.win)[1]]
      if item then
        self:close()
        vim.schedule(item.run)
      end
    end,
  }
  for index = 1, math.min(9, #require("dojo.keys")) do
    keys[tostring(index)] = function(self)
      switch(self, 0, index)
    end
  end

  local win = Snacks.win({
    width = width,
    height = height,
    border = "rounded",
    backdrop = 55,
    title = " Dojo · Keyboard Shortcuts ",
    title_pos = "center",
    footer = " Tab next · 1–9 jump · Enter run · / search · q close  —  Space is your leader key ",
    footer_pos = "center",
    enter = true,
    fixbuf = true,
    zindex = 60,
    bo = { filetype = "dojo_cheatsheet", modifiable = false },
    wo = {
      cursorline = true,
      wrap = false,
      number = false,
      relativenumber = false,
      signcolumn = "no",
      winhighlight = "CursorLine:Visual",
    },
    keys = keys,
  })
  draw(win)
  require("dojo.sfx").play("open")
  return win
end

return M
