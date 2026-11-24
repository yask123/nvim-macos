-- The other end of the `code` command (scripts/dojo): it writes what was asked
-- for to a small file, one tab-separated line per item, and this runs it in
-- the window that is already open.
--
--   dir    <folder>                     open as the project
--   file   <path> <line> <column>       open, optionally at a position
--   diff   <a> <b>                      compare two files
--   stdin  <path>                       piped text → an untitled page
--   wait   <token>                      the command stays until these files close

local M = {}

local waits = {} ---@type table<string, table<integer, boolean>>

local function parse(path)
  local request = { files = {} }
  local file = io.open(path, "r")
  if not file then
    return request
  end
  for line in file:lines() do
    local parts = vim.split(line, "\t", { plain = true })
    local kind = parts[1]
    if kind == "dir" then
      request.dir = parts[2]
    elseif kind == "file" then
      table.insert(request.files, { path = parts[2], line = tonumber(parts[3]), column = tonumber(parts[4]) })
    elseif kind == "diff" then
      request.diff = { parts[2], parts[3] }
    elseif kind == "stdin" then
      request.stdin = parts[2]
    elseif kind == "wait" then
      request.wait = parts[2]
    end
  end
  file:close()
  os.remove(path)
  return request
end

local function editor_window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_win_get_config(win).relative == "" and vim.bo[buf].buftype == "" then
      return win
    end
  end
end

local function focus_editor()
  -- Leave the welcome screen, the tree or a sheet: files open in the editor.
  local mode = vim.api.nvim_get_mode().mode
  if mode:match("^[iRt]") then
    vim.cmd.stopinsert()
  end
  local win = editor_window()
  if win then
    vim.api.nvim_set_current_win(win)
  end
end

local function track(token, buf)
  if not token then
    return
  end
  waits[token] = waits[token] or {}
  waits[token][buf] = true
  -- Closing the file ends the wait (⌘W). So do :wq, :x and :q, which here
  -- close this one file instead of the whole app: what `git commit` expects.
  for abbreviation, command in pairs({ wq = "write <bar> bdelete", x = "write <bar> bdelete", q = "bdelete" }) do
    vim.api.nvim_buf_call(buf, function()
      vim.cmd(
        ("cnoreabbrev <buffer> <expr> %s (getcmdtype() ==# ':' && getcmdline() ==# '%s') ? '%s' : '%s'"):format(
          abbreviation,
          abbreviation,
          command,
          abbreviation
        )
      )
    end)
  end
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout", "BufUnload" }, {
    buffer = buf,
    once = true,
    callback = function()
      if waits[token] then
        waits[token][buf] = nil
      end
    end,
  })
end

local function open_file(item, token)
  focus_editor()
  vim.cmd.edit(vim.fn.fnameescape(item.path))
  local buf = vim.api.nvim_get_current_buf()
  if item.line then
    local last = vim.api.nvim_buf_line_count(buf)
    local row = math.max(1, math.min(item.line, last))
    local text = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    pcall(vim.api.nvim_win_set_cursor, 0, { row, math.max(0, math.min((item.column or 1) - 1, #text)) })
    vim.cmd("normal! zz")
  end
  track(token, buf)
end

local function open_stdin(path, token)
  local file = io.open(path, "r")
  if not file then
    return
  end
  local text = file:read("*a")
  file:close()
  os.remove(path)
  focus_editor()
  vim.cmd.enew()
  local lines = vim.split((text:gsub("\n$", "")), "\n", { plain = true })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.modified = true
  track(token, vim.api.nvim_get_current_buf())
end

local function open_diff(left, right, token)
  focus_editor()
  vim.cmd("tabnew " .. vim.fn.fnameescape(right))
  local right_buf = vim.api.nvim_get_current_buf()
  vim.cmd("leftabove vertical diffsplit " .. vim.fn.fnameescape(left))
  vim.cmd("wincmd l")
  track(token, right_buf)
end

--- Run a request file written by the `code` command.
---@param path string
---@param startup? boolean the app has only just started
function M.run(path, startup)
  local request = parse(path)
  local has_files = #request.files > 0 or request.stdin ~= nil or request.diff ~= nil
  local function files()
    for _, item in ipairs(request.files) do
      open_file(item, request.wait)
    end
    if request.stdin then
      open_stdin(request.stdin, request.wait)
    end
    if request.diff then
      open_diff(request.diff[1], request.diff[2], request.wait)
    end
  end
  if request.wait then
    waits[request.wait] = waits[request.wait] or {}
  end
  if not request.dir then
    files()
    return 1
  end
  local here = vim.uv.fs_realpath(vim.fn.getcwd()) or vim.fn.getcwd()
  local same = (vim.uv.fs_realpath(request.dir) or request.dir) == here
  if not same or startup then
    -- Another project, or the app has only just come up: open it whole (its
    -- session, its file tree), let that settle, then the files and lines.
    require("dojo.project").open(request.dir)
    vim.defer_fn(files, 150)
  elseif has_files then
    files() -- already in this project: just the files
  else
    require("dojo.project").open(request.dir) -- `code .` again: offers the file finder
  end
  return 1
end

--- 1 while files opened with `code --wait` under this token are still open.
---@param token string
function M.waiting(token)
  local open = waits[token]
  if open and next(open) then
    return 1
  end
  waits[token] = nil
  return 0
end

--- At startup: the request the `code` command left for a cold start.
function M.startup()
  local path = vim.env.DOJO_REQUEST
  if not path or path == "" then
    return false
  end
  vim.env.DOJO_REQUEST = nil
  if not vim.uv.fs_stat(path) then
    return false
  end
  M.run(path, true)
  return true
end

return M
