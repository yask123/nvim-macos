-- Review a pull request without leaving the editor (⌘K ⌘P).
--
-- Pick one (this repository's, or the ones waiting for you anywhere, or paste
-- a link) and it takes over the editor (the file tree steps aside and comes
-- back when you close it):
--   * the page: what it is, the trace (one request drawn as a line through
--     the system, before and after; Claude draws it and never reviews), and
--     the diff sorted into reading order;
--   * the code: a file's changes in the file's own colours, with the comments
--     already on GitHub under their lines.
-- h l walk the trace, ↩ opens the code, c writes a comment, S sends the
-- review. Everything else is Vim: / searches, the cursor moves as usual.
--
-- lua/dojo/review/: github (gh), diff (parser), reading (Claude), trace
-- (the drawing), page, code.

local M = {}

local draw = require("dojo.draw")
local github = require("dojo.review.github")
local page = require("dojo.review.page")
local code = require("dojo.review.code")

local ns = vim.api.nvim_create_namespace("dojo_review")

---@type table<integer, table>  window → review state
local reviews = {}

local function notify(text, level)
  vim.notify(text, level or vim.log.levels.INFO, { title = "Review" })
end

function M.highlights()
  local blend = require("dojo.polish").blend
  local function color(group, attr)
    return draw.color(group, attr)
  end
  local bg = color("Normal", "bg") or 0x101010
  local fg = color("Normal", "fg") or 0xd0d0d0
  local added = color("Added", "fg") or color("DiagnosticOk", "fg") or color("String", "fg") or 0x5ef2a0
  local removed = color("Removed", "fg") or color("DiagnosticError", "fg") or 0xff7b86
  local changed = color("DiagnosticWarn", "fg") or color("Number", "fg") or 0xeec27d
  local accent = color("Function", "fg") or added
  local set = function(name, value)
    vim.api.nvim_set_hl(0, name, value)
  end
  set("DojoReviewTitle", { fg = fg, bold = true })
  set("DojoReviewText", { fg = fg })
  set("DojoReviewPart", { fg = blend(fg, bg, 0.72) })
  set("DojoReviewQuiet", { fg = blend(fg, bg, 0.45) })
  set("DojoReviewRail", { fg = blend(fg, bg, 0.22) })
  set("DojoReviewHeading", { fg = blend(fg, bg, 0.6), bold = true })
  set("DojoReviewAccent", { fg = accent })
  set("DojoReviewFocus", { fg = blend(fg, 0xffffff, 0.75), bold = true })
  set("DojoReviewSame", { fg = blend(fg, bg, 0.5) })
  set("DojoReviewAdded", { fg = added })
  set("DojoReviewChanged", { fg = changed })
  set("DojoReviewRemoved", { fg = removed })
  set("DojoReviewAddedLine", { bg = blend(added, bg, 0.11) })
  set("DojoReviewRemovedLine", { bg = blend(removed, bg, 0.11) })
  -- A new theme, new colours (set up once).
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("DojoReviewColours", { clear = true }),
    callback = function()
      vim.schedule(M.highlights)
    end,
  })
end

-- Comments not sent yet are kept, per pull request, across restarts.
local function drafts_file()
  return vim.fn.stdpath("state") .. "/dojo-review-drafts.json"
end

local function drafts_key(pr)
  return ("%s/%s#%d"):format(pr.owner or "", pr.repo or "", pr.number or 0)
end

local function load_drafts(pr)
  local file = io.open(drafts_file(), "r")
  if not file then
    return {}
  end
  local ok, data = pcall(vim.json.decode, file:read("*a"))
  file:close()
  local saved = ok and type(data) == "table" and data[drafts_key(pr)] or nil
  return type(saved) == "table" and saved or {}
end

local function save_drafts(state)
  local data = {}
  local file = io.open(drafts_file(), "r")
  if file then
    local ok, saved = pcall(vim.json.decode, file:read("*a"))
    file:close()
    data = ok and type(saved) == "table" and saved or {}
  end
  data[drafts_key(state.pr)] = #state.pending > 0 and state.pending or nil
  file = io.open(drafts_file(), "w")
  if file then
    file:write(vim.json.encode(next(data) and data or vim.empty_dict()))
    file:close()
  end
end

local function current()
  return reviews[vim.api.nvim_get_current_win()]
end

-- The page ---------------------------------------------------------------------

local function render(state)
  if not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  local win = vim.fn.bufwinid(state.buf)
  local width = win ~= -1 and vim.api.nvim_win_get_width(win) or vim.o.columns
  local built = page.build(state, width)
  state.built = built
  draw.put(state.buf, ns, built.lines)
end

-- Put the cursor on the focused step's dot.
local function to_focus(state)
  local built = state.built
  local win = vim.fn.bufwinid(state.buf)
  if win == -1 or not built or not built.steps or not built.steps[state.focus] then
    return
  end
  local spot = built.steps[state.focus]
  local line = built.trace_top + spot.row - 1
  local text = built.lines[line].text
  local col = vim.fn.byteidx(text, spot.col - 1 + 3) -- cells → bytes, past the margin
  pcall(vim.api.nvim_win_set_cursor, win, { line, math.max(col, 0) })
end

local function step_by(state, delta)
  local built = state.built
  if not built or not built.visible or #built.visible == 0 then
    return
  end
  local position = 1
  for index, step in ipairs(built.visible) do
    if step == state.focus then
      position = index
    end
  end
  position = math.max(1, math.min(#built.visible, position + delta))
  state.focus = built.visible[position]
  render(state)
  to_focus(state)
end

local function set_telling(state, telling)
  if not state.reading or state.reading.plain then
    return
  end
  state.telling = telling
  local visible = require("dojo.review.trace").visible(state.reading, telling)
  if not vim.tbl_contains(visible, state.focus) then
    state.focus = visible[1]
  end
  render(state)
  to_focus(state)
end

-- The line draws itself, a step at a time.
local function reveal(state)
  local total = #require("dojo.review.trace").visible(state.reading, state.telling)
  if vim.g.dojo_review_instant or #vim.api.nvim_list_uis() == 0 then
    state.reveal = nil
    return render(state)
  end
  state.reveal = 0
  local timer = vim.uv.new_timer()
  timer:start(0, 70, function()
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(state.buf) or not state.reveal then
        timer:stop()
        timer:close()
        return
      end
      state.reveal = state.reveal + 1
      if state.reveal >= total then
        state.reveal = nil
        timer:stop()
        timer:close()
      end
      render(state)
    end)
  end)
end

local function read(state, fresh)
  local reading = require("dojo.review.reading")
  if not reading.engine() and not fresh then
    -- A saved reading still opens without Claude at hand.
    reading.read(state.pr, state.diff, {}, function(saved)
      state.reading = saved
      state.reading_state = saved and "ready" or "none"
      state.focus = saved and require("dojo.review.trace").visible(saved, state.telling)[1] or nil
      render(state)
    end)
    return
  end
  state.reading_state = "reading"
  state.reading = nil
  render(state)
  local ticker = vim.uv.new_timer()
  ticker:start(400, 400, function()
    vim.schedule(function()
      if state.reading_state ~= "reading" or not vim.api.nvim_buf_is_valid(state.buf) then
        ticker:stop()
        if not ticker:is_closing() then
          ticker:close()
        end
        return
      end
      state.tick = (state.tick or 0) + 1
      if state.view == "page" then
        render(state)
      end
    end)
  end)
  state.job = reading.read(state.pr, state.diff, { fresh = fresh }, function(result, problem, cached)
    state.job = nil
    if not vim.api.nvim_buf_is_valid(state.buf) then
      return
    end
    if result then
      state.reading, state.reading_state = result, "ready"
      state.focus = require("dojo.review.trace").visible(result, state.telling)[1]
      -- Notes and step labels belong above the hunks: rebuild the code buffers.
      for _, buf in pairs(state.code_bufs or {}) do
        if vim.api.nvim_buf_is_valid(buf) and vim.fn.bufwinid(buf) == -1 then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
      state.code_bufs, state.code_files = {}, {}
      if cached then
        render(state)
      else
        reveal(state)
      end
    elseif problem == "no-engine" then
      state.reading_state = "none"
      render(state)
    else
      state.reading_state, state.problem = "failed", problem
      require("dojo.calm").record("Review: " .. tostring(problem))
      render(state)
    end
  end)
end

-- The code ---------------------------------------------------------------------

local function show_page(state)
  local win = vim.api.nvim_get_current_win()
  state.view = "page"
  vim.api.nvim_win_set_buf(win, state.buf)
  M.dress_page(win)
  render(state)
  if state.page_cursor then
    pcall(vim.api.nvim_win_set_cursor, win, state.page_cursor)
  end
end

local function order(state)
  -- Every file row of the page, in reading order, as { hunk, file }.
  local list = {}
  for _, chapter in ipairs(page.reading_order(state)) do
    for _, entry in ipairs(chapter.rows) do
      if #entry.hunks > 0 then
        list[#list + 1] = { hunk = entry.hunks[1], file = entry.file }
      end
    end
  end
  return list
end

local function show_code(state, hunk_id)
  local hunk = state.diff.hunks[hunk_id]
  if not hunk then
    return
  end
  local win = vim.api.nvim_get_current_win()
  if state.view == "page" then
    state.page_cursor = vim.api.nvim_win_get_cursor(win)
  end
  local buf = code.buffer(state, hunk.file)
  M.code_keys(state, buf)
  state.view = "code"
  vim.api.nvim_win_set_buf(win, buf)
  code.dress(win)
  local file = hunk.file
  local where = ("%%#DojoReviewQuiet#  %s%%#DojoReviewText#%s"):format(
    (file.path:match("^(.*/)") or ""):gsub("%%", "%%%%"),
    (file.path:match("([^/]*)$") or file.path):gsub("%%", "%%%%")
  )
  vim.wo[win].winbar = where
    .. "%#DojoReviewRail#%=] next change   [ previous   ⇥ next file   c comment   S send review   ⌫ back  "
  local line = code.line_of(buf, hunk_id)
  pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
  -- The hunk's heading is drawn above its first line: bring it into view.
  vim.cmd("normal! zt")
  pcall(vim.fn.winrestview, { topfill = 2 })
end

local function open_target(state)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local target = state.built and state.built.targets[line]
  if not target and state.reading and state.focus and state.built and state.built.trace_top then
    -- Anywhere on the trace: the step in focus.
    local step = state.reading.flow[state.focus]
    if step and step.hunk and line >= state.built.trace_top - 2 then
      target = { hunk = step.hunk }
    end
  end
  if target and target.hunk then
    show_code(state, target.hunk)
  elseif
    state.reading
    and state.focus
    and state.reading.flow[state.focus]
    and not state.reading.flow[state.focus].hunk
  then
    notify("This step's code doesn't change in the pull request")
  end
end

-- Comments and the review ----------------------------------------------------------

local function comment_count(state)
  return function(path)
    local count = 0
    for _, thread in ipairs(state.threads or {}) do
      if thread.path == path and not thread.resolved then
        count = count + #thread.comments
      end
    end
    for _, comment in ipairs(state.pending or {}) do
      if comment.path == path then
        count = count + 1
      end
    end
    return count
  end
end

local function compose(state)
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local spot = code.at(state, buf, line)
  if not spot or not spot.line then
    return notify("Put the cursor on a line of the diff to comment on it")
  end
  local existing
  for index, comment in ipairs(state.pending) do
    if comment.path == spot.path and comment.line == spot.line and comment.side == spot.side then
      existing = index
    end
  end
  local width = math.min(88, vim.o.columns - 8)
  local box = vim.api.nvim_create_buf(false, true)
  vim.bo[box].filetype = "markdown"
  vim.bo[box].bufhidden = "wipe"
  vim.b[box].completion = false
  if existing then
    vim.api.nvim_buf_set_lines(box, 0, -1, false, vim.split(state.pending[existing].body, "\n", { plain = true }))
  end
  local win = vim.api.nvim_open_win(box, true, {
    relative = "cursor",
    row = 1,
    col = 4,
    width = width,
    height = 6,
    style = "minimal",
    border = "rounded",
    title = (" Comment on %s:%d "):format(vim.fs.basename(spot.path), spot.line),
    title_pos = "left",
    footer = " ⌘↩ or Ctrl-s keeps it for the review   ·   Esc Esc cancels ",
    footer_pos = "right",
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.cmd.startinsert({ bang = true })
  local function close()
    vim.cmd.stopinsert()
    pcall(vim.api.nvim_win_close, win, true)
  end
  local function keep()
    local body = vim.trim(table.concat(vim.api.nvim_buf_get_lines(box, 0, -1, false), "\n"))
    close()
    if existing then
      table.remove(state.pending, existing)
    end
    if body ~= "" then
      table.insert(state.pending, { path = spot.path, line = spot.line, side = spot.side, body = body })
    end
    save_drafts(state)
    code.annotate(state, buf)
  end
  for _, lhs in ipairs({ "<D-CR>", "<C-s>", "<C-CR>", "<D-s>" }) do
    vim.keymap.set({ "n", "i" }, lhs, keep, { buffer = box, silent = true, nowait = true })
  end
  vim.keymap.set("n", "<Esc>", close, { buffer = box, silent = true, nowait = true })
  vim.keymap.set("n", "q", close, { buffer = box, silent = true, nowait = true })
end

local function send(state)
  local pending = #state.pending
  local choices = {
    {
      label = "Comment" .. (pending > 0 and (" (%d line comment%s)"):format(pending, pending == 1 and "" or "s") or ""),
      event = "COMMENT",
    },
    { label = "Approve", event = "APPROVE" },
    { label = "Request changes", event = "REQUEST_CHANGES" },
  }
  vim.ui.select(choices, {
    prompt = "Send a review of #" .. state.pr.number,
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    vim.ui.input({ prompt = "A sentence to go with it (optional): " }, function(body)
      if body == nil then
        return -- Esc
      end
      if choice.event ~= "APPROVE" and vim.trim(body) == "" and pending == 0 then
        return notify("Nothing to send yet: write a sentence, or comment on a line with c")
      end
      github.login(function(login)
        local summary = ("Post to GitHub as %s: %s%s"):format(
          login or "you",
          choice.label:gsub(" %(.*", ""),
          pending > 0 and (" · %d line comment%s"):format(pending, pending == 1 and "" or "s") or ""
        )
        vim.ui.select(
          { summary, "Not yet" },
          { prompt = ("%s/%s #%d"):format(state.pr.owner, state.pr.repo, state.pr.number) },
          function(answer)
            if answer ~= summary then
              return
            end
            github.submit(state.pr, choice.event, body, state.pending, function(ok, err)
              if ok then
                state.pending = {}
                save_drafts(state)
                notify("Review sent")
                github.threads(state.pr, function(threads)
                  state.threads = threads
                  for _, buf in pairs(state.code_bufs or {}) do
                    code.annotate(state, buf)
                  end
                  if state.view == "page" then
                    render(state)
                  end
                end)
              else
                require("dojo.calm").record("Review: " .. tostring(err))
                notify("GitHub didn't take the review: " .. github.explain(err), vim.log.levels.WARN)
              end
            end)
          end
        )
      end)
    end)
  end)
end

-- Keys -------------------------------------------------------------------------

local function close(state)
  if state.job then
    pcall(function()
      state.job:kill(15)
    end)
  end
  reviews[state.win] = nil
  local win = state.win
  if vim.api.nvim_win_is_valid(win) then
    -- Back to what was there before the review.
    vim.wo[win].winbar = ""
    vim.wo[win].statuscolumn = state.window.statuscolumn
    for name, value in pairs(state.window) do
      pcall(function()
        vim.wo[win][name] = value
      end)
    end
    if state.return_buf and vim.api.nvim_buf_is_valid(state.return_buf) then
      vim.api.nvim_win_set_buf(win, state.return_buf)
    else
      vim.api.nvim_win_call(win, function()
        vim.cmd("enew")
      end)
    end
  end
  for _, buf in pairs(state.code_bufs or {}) do
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  if state.had_tree then
    require("dojo.project").show_explorer(nil, false)
  end
end

function M.dress_page(win)
  local wo = vim.wo[win]
  wo.statuscolumn = ""
  wo.number, wo.relativenumber = false, false
  wo.signcolumn, wo.foldcolumn = "no", "0"
  wo.cursorline = false
  wo.wrap = false
  wo.list = false
  wo.spell = false
  wo.winbar = ""
  wo.foldenable = false
end

local function page_keys(state)
  local function map(lhs, fn, desc)
    for _, key in ipairs(type(lhs) == "table" and lhs or { lhs }) do
      vim.keymap.set("n", key, fn, { buffer = state.buf, silent = true, nowait = true, desc = desc })
    end
  end
  map({ "l", "<Right>", "<Tab>" }, function()
    step_by(state, 1)
  end, "Next step")
  map({ "h", "<Left>", "<S-Tab>" }, function()
    step_by(state, -1)
  end, "Previous step")
  map({ "<CR>", "<2-LeftMouse>" }, function()
    open_target(state)
  end, "Read the code")
  map("d", function()
    set_telling(state, "diff")
  end, "The change")
  map("b", function()
    set_telling(state, "before")
  end, "Before")
  map("a", function()
    set_telling(state, "after")
  end, "After")
  map("S", function()
    send(state)
  end, "Send review")
  map("o", function()
    vim.ui.open(state.pr.url)
  end, "Open on GitHub")
  map("r", function()
    read(state, true)
  end, "Read again")
  map({ "q", "<D-w>" }, function()
    close(state)
  end, "Close the review")
end

function M.code_keys(state, buf)
  if vim.b[buf].dojo_review_keys then
    return
  end
  vim.b[buf].dojo_review_keys = true
  local function map(lhs, fn, desc, modes)
    for _, key in ipairs(type(lhs) == "table" and lhs or { lhs }) do
      vim.keymap.set(modes or "n", key, fn, { buffer = buf, silent = true, nowait = true, desc = desc })
    end
  end
  local function jump(direction)
    local line = code.next_change(buf, vim.api.nvim_win_get_cursor(0)[1], direction)
    if line then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      vim.cmd("normal! zz")
    end
  end
  map({ "]", "]c" }, function()
    jump(1)
  end, "Next change")
  map({ "[", "[c" }, function()
    jump(-1)
  end, "Previous change")
  local function file_by(delta)
    local list, here = order(state), nil
    local file = state.code_files[buf]
    for index, entry in ipairs(list) do
      if entry.file.index == file.index then
        here = here or index
      end
    end
    local target = list[(here or 0) + delta]
    if target then
      show_code(state, target.hunk)
    else
      notify(delta > 0 and "That was the last file" or "This is the first file")
    end
  end
  map("<Tab>", function()
    file_by(1)
  end, "Next file")
  map("<S-Tab>", function()
    file_by(-1)
  end, "Previous file")
  map({ "<BS>", "-", "q" }, function()
    show_page(state)
  end, "Back to the page")
  map("c", function()
    compose(state)
  end, "Comment on this line")
  map("S", function()
    send(state)
  end, "Send review")
  map("o", function()
    vim.ui.open(state.pr.url .. "/files")
  end, "Open on GitHub")
  map("<D-w>", function()
    close(state)
  end, "Close the review")
end

-- Opening ------------------------------------------------------------------------

--- Open a pull request: a number (in this repository) or a link.
---@param ref string|integer
---@param cwd? string
function M.open(ref, cwd)
  local problem = github.problem()
  if problem then
    return notify(problem, vim.log.levels.WARN)
  end
  ref = tostring(ref):gsub("^#", "")
  cwd = cwd or vim.fn.getcwd() -- the project, wherever the cursor happens to be
  notify("Opening " .. (ref:match("^%d+$") and ("#" .. ref) or "the pull request") .. "…")
  github.fetch(ref, cwd, function(result, err)
    if not result then
      return notify(github.explain(err), vim.log.levels.WARN)
    end
    M.highlights()
    local diff = require("dojo.review.diff").parse(result.diff)
    -- The review takes the editor's place; the file tree steps aside.
    local trees = Snacks.picker.get({ source = "explorer" })
    for _, tree in ipairs(trees) do
      tree:close()
    end
    local win = vim.api.nvim_get_current_win()
    for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local shown = vim.api.nvim_win_get_buf(candidate)
      if vim.api.nvim_win_get_config(candidate).relative == "" and vim.bo[shown].buftype == "" then
        win = candidate
        break
      end
    end
    vim.api.nvim_set_current_win(win)
    if reviews[win] then
      close(reviews[win]) -- one review at a time in a window
    end
    local return_buf = vim.api.nvim_win_get_buf(win)
    local saved = {}
    for _, name in ipairs({
      "statuscolumn",
      "number",
      "relativenumber",
      "signcolumn",
      "foldcolumn",
      "cursorline",
      "wrap",
      "list",
      "spell",
      "foldenable",
      "conceallevel",
    }) do
      saved[name] = vim.wo[win][name]
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, buf)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.bo[buf].buflisted = false
    vim.bo[buf].filetype = "dojo_review"
    vim.b[buf].completion = false
    pcall(
      vim.api.nvim_buf_set_name,
      buf,
      ("review://%s/%s#%d"):format(result.pr.owner or "", result.pr.repo or "", result.pr.number)
    )
    local state = {
      win = win,
      return_buf = return_buf,
      window = saved,
      had_tree = #trees > 0,
      buf = buf,
      pr = result.pr,
      diff = diff,
      telling = "diff",
      view = "page",
      pending = load_drafts(result.pr),
      threads = {},
      reading_state = "reading",
    }
    state.comment_count = comment_count(state)
    reviews[win] = state
    M.dress_page(win)
    page_keys(state)
    render(state)
    read(state, false)
    github.threads(state.pr, function(threads)
      state.threads = threads
      for _, code_buf in pairs(state.code_bufs or {}) do
        code.annotate(state, code_buf)
      end
      if state.view == "page" then
        render(state)
      end
    end)
    vim.api.nvim_create_autocmd("VimResized", {
      buffer = buf,
      callback = function()
        if state.view == "page" then
          render(state)
        end
      end,
    })
  end)
end

local function age(iso)
  local year, month, day, hour, minute = (iso or ""):match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
  if not year then
    return ""
  end
  local then_utc = os.time({ year = year, month = month, day = day, hour = hour, min = minute })
  local seconds = os.difftime(os.time(os.date("!*t")), then_utc)
  if seconds < 3600 then
    return math.max(1, math.floor(seconds / 60)) .. "m"
  elseif seconds < 86400 then
    return math.floor(seconds / 3600) .. "h"
  end
  return math.floor(seconds / 86400) .. "d"
end

--- ⌘K ⌘P: choose a pull request to review.
function M.pick()
  local problem = github.problem()
  if problem then
    return notify(problem, vim.log.levels.WARN)
  end
  local cwd = vim.fn.getcwd() -- the project, wherever the cursor happens to be
  local here, waiting
  local function show()
    if here == nil or waiting == nil then
      return
    end
    local items, seen = {}, {}
    for _, pr in ipairs(here or {}) do
      seen[pr.url] = true
      items[#items + 1] = {
        text = ("#%d %s %s"):format(pr.number, pr.title, vim.tbl_get(pr, "author", "login") or ""),
        pr = pr,
        ref = pr.url,
        where = "",
      }
    end
    for _, pr in ipairs(waiting or {}) do
      if not seen[pr.url] then
        items[#items + 1] = {
          text = ("#%d %s %s %s"):format(
            pr.number,
            pr.title,
            vim.tbl_get(pr, "repository", "nameWithOwner") or "",
            "waiting"
          ),
          pr = pr,
          ref = pr.url,
          where = vim.tbl_get(pr, "repository", "nameWithOwner") or "",
          waiting = true,
        }
      end
    end
    items[#items + 1] = { text = "Paste a pull request link or number…", paste = true }
    Snacks.picker({
      title = "Review a Pull Request",
      items = items,
      layout = { preset = "vscode", layout = { width = 0.6, min_width = 96 } },
      format = function(item)
        if item.paste then
          return { { "      Paste a pull request link or number…", "SnacksPickerComment" } }
        end
        local pr = item.pr
        local row = {
          { Snacks.picker.util.align("#" .. pr.number, 6), "DojoReviewAccent" },
          { Snacks.picker.util.align(pr.title, 54, { truncate = true }) },
          { "  " },
          {
            Snacks.picker.util.align(vim.tbl_get(pr, "author", "login") or "", 16, { truncate = true }),
            "SnacksPickerComment",
          },
        }
        if pr.additions then
          row[#row + 1] = { Snacks.picker.util.align("+" .. pr.additions, 6, { align = "right" }), "DojoReviewAdded" }
          row[#row + 1] = { Snacks.picker.util.align(" −" .. pr.deletions, 7), "DojoReviewRemoved" }
        end
        row[#row + 1] = { Snacks.picker.util.align(age(pr.updatedAt), 4, { align = "right" }), "SnacksPickerComment" }
        if item.where ~= "" then
          row[#row + 1] = { "  " .. item.where, "SnacksPickerComment" }
        end
        if item.waiting or pr.reviewDecision == "REVIEW_REQUIRED" then
          row[#row + 1] = { "  waiting for review", "DojoReviewChanged" }
        elseif pr.isDraft then
          row[#row + 1] = { "  draft", "SnacksPickerComment" }
        end
        return row
      end,
      confirm = function(picker, item)
        picker:close()
        if not item then
          return
        end
        if item.paste then
          vim.ui.input({ prompt = "Pull request link or number: " }, function(text)
            if text and vim.trim(text) ~= "" then
              M.open(vim.trim(text), cwd)
            end
          end)
        else
          M.open(item.ref, cwd)
        end
      end,
    })
  end
  M.highlights()
  github.list(cwd, function(prs)
    here = prs or false
    show()
  end)
  github.waiting(function(prs)
    waiting = prs or false
    show()
  end)
end

--- For tests: the state of the review in the current tab.
function M.state()
  return current()
end

return M
