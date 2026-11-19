-- What the call you are typing takes: one quiet line above the brackets, with
-- the argument you are on lit up.
--
--                      (default_factory, map, /, **kwargs)
--   cache = defaultdict(▏)
--
-- Names and defaults only. A type shows just for the argument you are on, and
-- only when it is short and plain (`list[int]`, not a type stub's
-- `SupportsRichComparisonT`). Language servers answer with raw stubs
-- (`_VT@defaultdict`, eight overloads, the first of them empty); this shows
-- one way to call the function, and ⌃K lists the others.

local M = {}

local api = vim.api
local ns = api.nvim_create_namespace("dojo.signature")
local METHOD = "textDocument/signatureHelp"

local TYPE_MAX = 28 -- a longer type than this stays out of the hint
local DEFAULT_MAX = 16 -- a longer default value is shown as …
local ROWS_MAX = 8 -- ⌃K lists at most this many ways to call it
local LOOK_BACK = 30 -- lines searched upwards for the call's opening bracket

local QUIET, DIM, TYPE, ACTIVE = "DojoSignature", "DojoSignatureDim", "DojoSignatureType", "DojoSignatureActive"

local state = {
  win = nil, -- the hint window, while it is up
  buf = nil,
  drawn = nil, -- what the window shows (identical redraws are skipped)
  rows = nil, -- the same, as chunks
  anchor = nil, -- { buf, line, col } of the call's opening bracket
  shape = nil, -- the way of calling it on show; kept while it fits what you type
  none = nil, -- the bracket the language server had nothing to say about
  all = false, -- ⌃K: every way to call it
  seq = 0, -- the newest request; older answers are dropped
  cancel = nil,
  timer = nil,
}

-- Reading the server's answer ---------------------------------------------

-- Worth showing: short, and none of the names type stubs use among
-- themselves (`_T`, `SupportsIndex`) or that say nothing (`Any`, `None`).
local function plain(kind)
  if #kind > TYPE_MAX or kind == "Any" or kind == "None" or kind == "object" or kind == "Unknown" then
    return false
  end
  for name in kind:gmatch("[%a_][%w_]*") do
    if name:sub(1, 1) == "_" or name:find("^Supports") then
      return false
    end
  end
  return true
end

-- "target: int = 0" -> { name = "target", type = "int", default = "0" }
local function parse_param(text)
  text = vim.trim((text:gsub("@[%w_]+", ""))) -- _VT@defaultdict -> _VT
  if text == "/" or text == "*" then
    return { name = text, sep = true } -- Python's positional-only / keyword-only marks
  end
  local depth, colon, equals = 0, nil, nil
  for i = 1, #text do
    local ch = text:sub(i, i)
    if ch == "(" or ch == "[" or ch == "{" then
      depth = depth + 1
    elseif ch == ")" or ch == "]" or ch == "}" then
      depth = depth - 1
    elseif depth == 0 and not equals then
      local after = text:sub(i + 1, i + 1)
      if ch == ":" and not colon then
        colon = i
      elseif ch == "=" and after ~= ">" and after ~= "=" then -- not => or ==
        equals = i
      end
    end
  end
  local param = { name = vim.trim(text:sub(1, (colon or equals or #text + 1) - 1)) }
  if colon then
    local kind = vim.trim(text:sub(colon + 1, (equals or #text + 1) - 1))
    param.type = plain(kind) and kind or nil
  end
  if equals then
    local default = vim.trim(text:sub(equals + 1))
    param.default = #default > DEFAULT_MAX and "…" or default
  end
  return param
end

-- A parameter's text: given either as itself or as offsets into the label.
local function param_text(sig, param)
  local label = param.label
  if type(label) ~= "table" then
    return tostring(label)
  end
  local from = vim.str_byteindex(sig.label, "utf-16", label[1], false)
  local to = vim.str_byteindex(sig.label, "utf-16", label[2], false)
  return sig.label:sub(from + 1, to)
end

local function parse(sig, active)
  local params, names, real = {}, {}, {}
  for i, param in ipairs(sig.parameters or {}) do
    params[i] = parse_param(param_text(sig, param))
    names[i] = params[i].name
    if not params[i].sep then
      real[#real + 1] = params[i].name
    end
  end
  if type(sig.activeParameter) == "number" then
    active = sig.activeParameter
  end
  -- Past the last argument (or null): nothing is lit.
  active = type(active) == "number" and params[active + 1] and not params[active + 1].sep and active + 1 or nil
  return { params = params, active = active, names = real, count = #real, shape = table.concat(names, ",") }
end

-- Does `wide` take everything `narrow` does, in the same order?
local function covers(wide, narrow)
  local at = 1
  for _, name in ipairs(narrow.names) do
    while wide.names[at] and wide.names[at] ~= name do
      at = at + 1
    end
    if not wide.names[at] then
      return false
    end
    at = at + 1
  end
  return true
end

local function index_of(sig, name)
  for i, param in ipairs(sig.params) do
    if not param.sep and param.name == name then
      return i
    end
  end
end

-- The rows to show: the way of calling it you are in, or (all) every way.
-- Also returns that way's shape, to pass back as `keep` on the next keystroke.
local function choose(result, all, keep)
  local sigs = type(result) == "table" and result.signatures or nil
  if type(sigs) ~= "table" or #sigs == 0 then
    return nil
  end
  local chosen = type(result.activeSignature) == "number" and result.activeSignature + 1 or 1
  chosen = sigs[chosen] and chosen or 1
  local parsed = {}
  for i, sig in ipairs(sigs) do
    parsed[i] = parse(sig, i == chosen and result.activeParameter or nil)
  end
  local server = parsed[chosen]
  local lit = server.active and server.params[server.active].name
  -- The server re-picks an overload on every keystroke, and the hint would
  -- reshuffle with it. Stay on the form already showing while it still takes
  -- what has been typed: only the lit argument moves.
  local kept = false
  for i, sig in ipairs(keep and parsed or {}) do
    if sig.shape == keep and sig.shape ~= server.shape and covers(sig, server) and (not lit or index_of(sig, lit)) then
      sig.active = lit and index_of(sig, lit) or nil
      chosen, kept = i, true
      break
    end
  end
  -- `defaultdict()` is a valid call, so the server offers the empty form
  -- first. That says nothing: show the fullest form instead.
  if not kept and server.count == 0 then
    for i, sig in ipairs(parsed) do
      if sig.count > parsed[chosen].count then
        chosen = i
      end
    end
    if parsed[chosen].count == 0 then
      return nil -- it takes nothing
    end
  end
  if server.count == 0 and not parsed[chosen].active then
    parsed[chosen].active = index_of(parsed[chosen], parsed[chosen].names[1]) -- nothing typed yet: the first one
  end
  -- Overloads that differ only in types are one way of calling it.
  local shapes, seen = {}, {}
  for i, sig in ipairs(parsed) do
    if not seen[sig.shape] then
      shapes[#shapes + 1] = i
      seen[sig.shape] = #shapes
    elseif i == chosen then
      shapes[seen[sig.shape]] = i
    end
  end
  if not (all and #shapes > 1) then
    return { { sig = parsed[chosen], current = true, more = #shapes - 1 } }, parsed[chosen].shape
  end
  local rows = {}
  for n = 1, math.min(#shapes, ROWS_MAX) do
    rows[n] = { sig = parsed[shapes[n]], current = shapes[n] == chosen, listed = true }
  end
  return rows, parsed[chosen].shape
end

-- Drawing -----------------------------------------------------------------

local function width_of(chunks)
  local width = 0
  for _, chunk in ipairs(chunks) do
    width = width + vim.fn.strdisplaywidth(chunk[1])
  end
  return width
end

-- One row as { text, highlight } chunks, trimmed around the lit argument if
-- the window is too narrow for all of it.
local function chunks_of(row, max_width)
  local sig = row.sig
  local base = row.listed and row.current and TYPE or QUIET
  local function build(with_type, lo, hi)
    local out = { { lo > 1 and "(…, " or "(", DIM } }
    for i = lo, hi do
      local param = sig.params[i]
      if i > lo then
        out[#out + 1] = { ", ", DIM }
      end
      local default = param.default and "=" .. param.default or ""
      if param.sep then
        out[#out + 1] = { param.name, DIM }
      elseif row.current and i == sig.active then
        out[#out + 1] = { param.name, ACTIVE }
        if with_type and param.type then
          default = ": " .. param.type .. (param.default and " = " .. param.default or "")
        end
        if default ~= "" then
          out[#out + 1] = { default, TYPE }
        end
      else
        out[#out + 1] = { param.name .. default, base }
      end
    end
    out[#out + 1] = { hi < #sig.params and ", …)" or ")", DIM }
    if (row.more or 0) > 0 then
      out[#out + 1] = { "  +" .. row.more, DIM }
    end
    return out
  end
  local focus = row.current and sig.active or 1
  local lo, hi = 1, #sig.params
  local out = build(not row.listed, lo, hi)
  if width_of(out) > max_width then
    out = build(false, lo, hi)
  end
  while width_of(out) > max_width and hi > focus do
    hi = hi - 1
    out = build(false, lo, hi)
  end
  while width_of(out) > max_width and lo < focus do
    lo = lo + 1
    out = build(false, lo, hi)
  end
  return out
end

-- A signatureHelp answer as rows of { text, highlight } chunks; nil when
-- there is nothing worth showing. opts: all (every way to call it), width,
-- keep (the shape returned last time, to stay on that way of calling it).
function M.render(result, opts)
  opts = opts or {}
  local rows, shape = choose(result, opts.all, opts.keep)
  if not rows then
    return nil
  end
  local out = {}
  for i, row in ipairs(rows) do
    out[i] = chunks_of(row, opts.width or 80)
  end
  return out, shape
end

-- The rows as plain text (tests, debugging).
function M.text(rows)
  local lines = {}
  for i, row in ipairs(rows or {}) do
    local parts = {}
    for n, chunk in ipairs(row) do
      parts[n] = chunk[1]
    end
    lines[i] = table.concat(parts)
  end
  return lines
end

-- Where it goes -----------------------------------------------------------

-- The opening bracket of the call around the cursor, as a 0-based line and
-- byte column. Brackets that only group (lists, tuples, `if (`) are skipped.
function M.find_call()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local first = math.max(1, row - LOOK_BACK)
  local lines = api.nvim_buf_get_lines(0, first - 1, row, false)
  lines[#lines] = lines[#lines]:sub(1, col)
  local depth = 0
  for i = #lines, 1, -1 do
    local line = lines[i]
    for j = #line, 1, -1 do
      local ch = line:sub(j, j)
      if ch == ")" or ch == "]" or ch == "}" then
        depth = depth + 1
      elseif ch == "(" or ch == "[" or ch == "{" then
        if depth > 0 then
          depth = depth - 1
        elseif ch == "(" and line:sub(1, j - 1):find("[%w_%)%]>?!\128-\255]$") then
          return first + i - 2, j - 1
        end
      end
    end
  end
end

local function screen_row(win, line, col)
  return vim.fn.screenpos(win, line + 1, col + 1).row
end

-- Where the completion menu is on screen (0-based, border included), if open.
local function menu_box()
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if win ~= state.win and vim.bo[api.nvim_win_get_buf(win)].filetype == "blink-cmp-menu" then
      local row, col = unpack(api.nvim_win_get_position(win))
      local border = api.nvim_win_get_config(win).border
      local edge = (type(border) == "table" or (border ~= nil and border ~= "none")) and 2 or 0
      return {
        top = row,
        bottom = row + api.nvim_win_get_height(win) - 1 + edge,
        left = col,
        right = col + api.nvim_win_get_width(win) - 1 + edge,
      }
    end
  end
end

-- Above the line, its bracket over the call's bracket; below it on the first
-- line of a window. The hint has one home and does not wander: where the
-- completion menu needs the same rows (it opens upwards at the bottom of a
-- long file), the hint steps aside until the menu closes.
local function placement(height, width)
  local win = api.nvim_get_current_win()
  local cursor = api.nvim_win_get_cursor(win)
  local line, col = state.anchor.line, state.anchor.col
  if line ~= cursor[1] - 1 then
    -- The call runs over several lines: sit by the line being typed.
    line = cursor[1] - 1
    col = math.min(cursor[2], #api.nvim_get_current_line():match("^%s*"))
  end
  local at = vim.fn.screenpos(win, line + 1, col + 1)
  local top = vim.fn.win_screenpos(win)[1] + (vim.wo[win].winbar ~= "" and 1 or 0)
  local above = at.row == 0 or at.row - top >= height
  -- The rows and columns it will cover (0-based), to compare with the menu.
  local first = above and at.row - 1 - height or screen_row(win, cursor[1] - 1, cursor[2])
  local menu = menu_box()
  local covered = menu ~= nil
    and first <= menu.bottom
    and first + height - 1 >= menu.top
    and at.col - 2 <= menu.right
    and at.col - 2 + width - 1 >= menu.left
  return {
    relative = "win",
    win = win,
    bufpos = { above and line or cursor[1] - 1, col },
    anchor = above and "SW" or "NW",
    row = above and 0 or 1,
    col = -1, -- one cell of padding: the brackets line up
    width = width,
    height = height,
    style = "minimal",
    border = "none",
    focusable = false,
    hide = covered,
    zindex = 45, -- under the completion menu and every other float
  }
end

local function hide()
  if state.win and api.nvim_win_is_valid(state.win) then
    local win = state.win
    if not pcall(api.nvim_win_close, win, true) then
      vim.schedule(function()
        pcall(api.nvim_win_close, win, true)
      end)
    end
  end
  state.win, state.drawn, state.rows = nil, nil, nil
end

local function show(rows)
  local lines, marks, width, key = {}, {}, 0, {}
  for r, row in ipairs(rows) do
    local text = " "
    for _, chunk in ipairs(row) do
      marks[#marks + 1] = { r - 1, #text, #text + #chunk[1], chunk[2] }
      key[#key + 1] = chunk[2] .. chunk[1]
      text = text .. chunk[1]
    end
    lines[r] = text .. " "
    width = math.max(width, vim.fn.strdisplaywidth(lines[r]))
    key[#key + 1] = "\n"
  end
  if not (state.buf and api.nvim_buf_is_valid(state.buf)) then
    state.buf = api.nvim_create_buf(false, true)
    state.drawn = nil
  end
  local drawn = table.concat(key)
  if drawn ~= state.drawn then
    api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
    for _, mark in ipairs(marks) do
      api.nvim_buf_set_extmark(state.buf, ns, mark[1], mark[2], { end_col = mark[3], hl_group = mark[4] })
    end
  end
  state.drawn, state.rows = drawn, rows
  local config = placement(#lines, width)
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_win_set_config(state.win, config)
  else
    config.noautocmd = true
    state.win = api.nvim_open_win(state.buf, false, config)
    api.nvim_set_option_value("winhighlight", "Normal:" .. QUIET .. ",NormalFloat:" .. QUIET, { win = state.win })
    api.nvim_set_option_value("wrap", false, { win = state.win })
  end
end

local function reposition()
  if state.win and api.nvim_win_is_valid(state.win) and state.anchor and state.rows then
    if api.nvim_get_current_buf() == state.anchor.buf then
      show(state.rows)
    end
  end
end

-- Asking ------------------------------------------------------------------

local function cancel()
  state.seq = state.seq + 1
  if state.cancel then
    pcall(state.cancel)
    state.cancel = nil
  end
end

local function typing()
  return api.nvim_get_mode().mode:sub(1, 1) == "i"
end

local function update()
  if not typing() or vim.bo.buftype ~= "" then
    return hide()
  end
  local line, col = M.find_call()
  if not line then
    state.all, state.shape, state.anchor = false, nil, nil
    return hide()
  end
  local buf = api.nvim_get_current_buf()
  local anchor = { buf = buf, line = line, col = col }
  if state.anchor and not vim.deep_equal(state.anchor, anchor) then
    state.all, state.shape = false, nil -- a different call: start afresh
  end
  if state.none and vim.deep_equal(state.none, anchor) then
    return hide() -- not a function call (already asked)
  end
  local client = vim.lsp.get_clients({ bufnr = buf, method = METHOD })[1]
  if not client then
    return hide()
  end
  cancel()
  local seq = state.seq
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  local ok, id = client:request(METHOD, params, function(err, result)
    if seq ~= state.seq then
      return -- you have typed more since
    end
    state.cancel = nil
    if not typing() or api.nvim_get_current_buf() ~= buf then
      return hide()
    end
    local width = math.max(24, api.nvim_win_get_width(0) - 6)
    local rows, shape
    if not err then
      rows, shape = M.render(result, { all = state.all, width = width, keep = state.shape })
    end
    if not rows then
      state.none = not err and anchor or nil
      return hide()
    end
    state.anchor, state.shape, state.none = anchor, shape, nil
    show(rows)
  end, buf)
  if ok and id then
    state.cancel = function()
      client:cancel_request(id)
    end
  end
end

-- Ask a moment after the last keystroke, not on every one.
local function queue()
  state.timer = state.timer or assert(vim.uv.new_timer())
  state.timer:stop()
  state.timer:start(12, 0, vim.schedule_wrap(update))
end

local function leave()
  if state.timer then
    state.timer:stop()
  end
  cancel()
  state.all, state.none, state.anchor, state.shape = false, nil, nil, nil
  hide()
end

-- ⌃K while typing a call: every way to call it, and back to one line.
function M.toggle_all()
  state.all = not state.all
  update()
end

function M.is_open()
  return state.win ~= nil and api.nvim_win_is_valid(state.win)
end

-- The hint's window and the text in it (tests).
function M.shown()
  if M.is_open() then
    return state.win, api.nvim_buf_get_lines(state.buf, 0, -1, false)
  end
end

-- Colours -----------------------------------------------------------------

-- Three steps of quiet in the theme's own text colour, and its accent for
-- the argument you are on. Phosphor sets these by hand.
function M.highlights()
  if vim.g.colors_name == "phosphor" then
    return
  end
  local function get(group, attr)
    return api.nvim_get_hl(0, { name = group, link = false })[attr]
  end
  local fg, bg = get("Normal", "fg"), get("NormalFloat", "bg") or get("Normal", "bg")
  if not fg or not bg then -- transparent theme: borrow its own groups
    for name, link in pairs({ [QUIET] = "Comment", [DIM] = "NonText", [TYPE] = "NormalFloat", [ACTIVE] = "Function" }) do
      api.nvim_set_hl(0, name, { link = link })
    end
    return
  end
  local blend = require("dojo.polish").blend
  api.nvim_set_hl(0, QUIET, { fg = blend(fg, bg, 0.50), bg = bg })
  api.nvim_set_hl(0, DIM, { fg = blend(fg, bg, 0.32) })
  api.nvim_set_hl(0, TYPE, { fg = blend(fg, bg, 0.75) })
  api.nvim_set_hl(0, ACTIVE, { fg = get("Function", "fg") or fg })
end

function M.setup()
  M.highlights()
  local group = api.nvim_create_augroup("DojoSignature", { clear = true })
  api.nvim_create_autocmd({ "InsertEnter", "CursorMovedI", "TextChangedI" }, { group = group, callback = queue })
  api.nvim_create_autocmd({ "InsertLeave", "BufLeave", "WinLeave" }, { group = group, callback = leave })
  -- The completion menu came, went or moved: step aside or come back.
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "BlinkCmpMenuOpen", "BlinkCmpMenuClose", "BlinkCmpMenuPositionUpdate" },
    callback = function()
      if M.is_open() then
        vim.schedule(reposition)
      end
    end,
  })
  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      vim.schedule(M.highlights)
    end,
  })
end

return M
