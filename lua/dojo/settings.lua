-- ⌘, — Settings: the few choices worth making, on one small sheet. Each row
-- says what it is set to now, and the shortcut that changes it without the
-- sheet. Choices are remembered between launches. The config files are still
-- there for tinkering, one row down.

local M = {}

local api = vim.api
local draw = require("dojo.draw")
local ns = api.nvim_create_namespace("dojo_settings")
local Line, push, fit = draw.line, draw.push, draw.fit

M.file = vim.fn.stdpath("state") .. "/dojo-settings.json"

-- What's remembered ---------------------------------------------------------

local saved

local function load()
  if not saved then
    saved = {}
    local ok, lines = pcall(vim.fn.readfile, M.file)
    if ok then
      local decoded, values = pcall(vim.json.decode, table.concat(lines, "\n"))
      if decoded and type(values) == "table" then
        saved = values
      end
    end
  end
  return saved
end

function M.get(key, default)
  local value = load()[key]
  if value == nil then
    return default
  end
  return value
end

function M.set(key, value)
  load()[key] = value
  vim.fn.mkdir(vim.fs.dirname(M.file), "p")
  pcall(vim.fn.writefile, { vim.json.encode(saved) }, M.file)
end

-- The sheet -----------------------------------------------------------------

local state

local function theme_name()
  local name = vim.g.colors_name or ""
  for _, theme in ipairs(require("dojo.theme").themes) do
    if theme.name == name then
      return theme.label
    end
  end
  return name
end

local function rows()
  local A = require("dojo.actions")
  local list = {}
  list[#list + 1] = {
    name = "Colour theme",
    value = theme_name(),
    keys = "⌘K ⌘T",
    hint = "↩ choose",
    enter = function()
      M.close()
      vim.schedule(require("dojo.theme").pick)
    end,
  }
  if vim.g.neovide then
    list[#list + 1] = {
      name = "Text size",
      value = ("%d%%"):format(math.floor((vim.g.neovide_scale_factor or 1) * 100 + 0.5)),
      keys = "⌘=  ⌘-",
      hint = "→ larger · ← smaller · 0 reset",
      right = A.zoom_in,
      left = A.zoom_out,
      reset = A.zoom_reset,
    }
  end
  local sound = require("dojo.sfx")
  if sound.available() then
    local on = sound.enabled()
    list[#list + 1] = {
      name = "Typing sounds",
      value = on and "On" or "Off",
      on = on,
      keys = "⌘K M",
      hint = "↩ turn " .. (on and "off" or "on"),
      toggle = function()
        sound.set(not on)
      end,
    }
  end
  if vim.g.neovide and vim.fn.has("mac") == 1 then
    local dim = require("dojo.dim")
    local on = dim.enabled()
    list[#list + 1] = {
      name = "Dim the desktop",
      value = on and "On" or "Off",
      on = on,
      keys = "⌘K D",
      hint = "↩ turn " .. (on and "off" or "on"),
      toggle = function()
        dim.set(not on)
      end,
    }
  end
  list[#list + 1] = { gap = true }
  list[#list + 1] = {
    name = "Keyboard shortcuts",
    keys = "⌘K ⌘S",
    hint = "↩ open",
    enter = function()
      M.close()
      vim.schedule(require("dojo.cheatsheet").open)
    end,
  }
  list[#list + 1] = {
    name = "Config files",
    value = "for tinkering",
    quiet = true,
    hint = "↩ open",
    enter = function()
      M.close()
      vim.schedule(function()
        Snacks.picker.files({ cwd = vim.fn.stdpath("config"), title = "Config Files" })
      end)
    end,
  }
  return list
end

local function render()
  local s = state
  if not s or not s.win:valid() then
    return
  end
  s.rows = rows()
  local name_w, keys_w = 22, 8
  local value_w = s.width - 6 - name_w - keys_w
  local lines = { Line() }
  for index, row in ipairs(s.rows) do
    local line = Line()
    if not row.gap then
      local lit = index == s.sel
      local base = lit and "DojoBrowseSelected" or "DojoBrowseFolder"
      local value = (row.on == false or row.quiet) and "DojoSettingsOff"
        or row.on and "DojoSettingsOn"
        or "DojoSettingsValue"
      push(line, "  ")
      push(line, " " .. fit(row.name, name_w), base)
      push(line, fit(row.value or "", value_w), lit and "DojoBrowseSelected" or value)
      push(line, fit(row.keys or "", keys_w) .. " ", lit and "DojoBrowseSelected" or "DojoBrowseInside")
    end
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = Line()
  draw.put(s.win.buf, ns, lines)
  pcall(api.nvim_win_set_cursor, s.win.win, { s.sel + 1, 3 })
  local row = s.rows[s.sel]
  local footer = " " .. (row and row.hint or "") .. " · esc close "
  pcall(api.nvim_win_set_config, s.win.win, { footer = { { footer, "FloatFooter" } }, footer_pos = "center" })
end

local function move(delta)
  local s = state
  local index = s.sel
  repeat
    index = index + delta
  until not s.rows[index] or not s.rows[index].gap
  if s.rows[index] then
    s.sel = index
    render()
  end
end

-- Enter, or an arrow: change the row the cursor is on.
local function act(how)
  local row = state.rows[state.sel]
  if not row then
    return
  end
  if row.toggle and how ~= "reset" then
    row.toggle()
  elseif row[how] then
    row[how]()
  elseif how == "right" and row.enter then
    row.enter() -- l steps into a row that opens something
  end
  if state then
    render()
  end
end

function M.highlights()
  local accent = draw.color("Function", "fg") or draw.color("Special", "fg")
  local set = function(name, spec)
    spec.default = true
    api.nvim_set_hl(0, name, spec)
  end
  require("dojo.browse").highlights() -- the lit row and quiet text are shared
  set("DojoSettingsValue", { link = "NormalFloat" })
  set("DojoSettingsOn", { fg = accent })
  set("DojoSettingsOff", { link = "Comment" })
end

function M.close()
  local s = state
  state = nil
  if s and s.win:valid() then
    s.win:close()
  end
end

function M.is_open()
  return state ~= nil
end

-- For tests and scripts: the rows as shown.
function M.peek()
  return state
      and vim.deepcopy(vim.tbl_map(function(row)
        return { name = row.name, value = row.value, gap = row.gap }
      end, state.rows))
    or nil
end

--- Open the sheet, or close it if it is showing.
function M.open()
  if state then
    return M.close()
  end
  M.highlights()
  local list = rows()
  local width = math.max(40, math.min(vim.o.columns - 8, 58))
  state = { sel = 1, rows = list, width = width }
  local s = state
  s.win = Snacks.win({
    width = width,
    height = #list + 2,
    border = "rounded",
    backdrop = 55,
    title = " Settings ",
    title_pos = "center",
    footer = " ",
    footer_pos = "center",
    enter = true,
    fixbuf = true,
    zindex = 60,
    bo = { filetype = "dojo_settings", modifiable = false },
    wo = {
      cursorline = false,
      wrap = false,
      number = false,
      relativenumber = false,
      signcolumn = "no",
    },
    on_close = function()
      if state == s then
        state = nil
      end
    end,
  })
  local function map(keys, run)
    for _, lhs in ipairs(keys) do
      vim.keymap.set("n", lhs, function()
        if state == s then
          run()
        end
      end, { buffer = s.win.buf, nowait = true, silent = true })
    end
  end
  map({ "q", "<Esc>", "<D-w>", "<D-,>" }, M.close)
  map({ "j", "<Down>", "<Tab>" }, function()
    move(1)
  end)
  map({ "k", "<Up>", "<S-Tab>" }, function()
    move(-1)
  end)
  map({ "<CR>", "<Space>" }, function()
    act("enter")
  end)
  map({ "l", "<Right>", "+", "=" }, function()
    act("right")
  end)
  map({ "h", "<Left>", "-" }, function()
    act("left")
  end)
  map({ "0" }, function()
    act("reset")
  end)
  map({ "<LeftMouse>" }, function()
    local mouse = vim.fn.getmousepos()
    if mouse.winid ~= s.win.win then
      return M.close()
    end
    local row = s.rows[mouse.line - 1]
    if row and not row.gap then
      s.sel = mouse.line - 1
      render()
    end
  end)
  map({ "<2-LeftMouse>" }, function()
    act("enter")
  end)
  s.win:on("WinLeave", function()
    vim.schedule(function()
      if state == s then
        M.close()
      end
    end)
  end, { buf = true })
  render()
  return s.win
end

return M
