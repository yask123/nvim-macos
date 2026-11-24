-- ⌘R: save and run the current file in a panel at the bottom, like VS Code.
-- The panel is a real terminal, so programs that ask for input just work.
-- When the program ends, the cursor goes back to your code and the output
-- stays in view. q or ⌘J closes the panel; ⌘R runs again.

local M = {}

local panel = { win = nil, buf = nil, job = nil }

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function is_file_win(win)
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.api.nvim_win_get_config(win).relative == ""
    and vim.bo[buf].buftype == ""
    and vim.api.nvim_buf_get_name(buf) ~= ""
end

-- The file to run: the current window's, or (from the panel or a terminal)
-- the file you were just in.
local function source_window()
  local current = vim.api.nvim_get_current_win()
  if is_file_win(current) then
    return current
  end
  local previous = vim.fn.win_getid(vim.fn.winnr("#"))
  if previous ~= 0 and is_file_win(previous) then
    return previous
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_file_win(win) then
      return win
    end
  end
end

local function set_title(text, running)
  if valid_win(panel.win) then
    local title = text:gsub("%%", "%%%%") -- a file name may contain %
    local hint = running and "⌃C stop  ·  ⌘J close  " or "q or ⌘J close  ·  ⌘R run again  "
    vim.wo[panel.win].winbar = "%#Comment#  " .. title .. "%=" .. hint
  end
end

function M.is_open()
  return valid_win(panel.win)
end

function M.is_running()
  return panel.job ~= nil
end

--- Stop the running program (an infinite loop, a server) and keep its output.
function M.stop()
  if panel.job then
    panel.stopped = true
    pcall(vim.fn.jobstop, panel.job)
  end
end

--- Close the panel (stopping the program if it's still running).
function M.close()
  if panel.job then
    pcall(vim.fn.jobstop, panel.job)
  end
  panel.job = nil
  if valid_win(panel.win) then
    pcall(vim.api.nvim_win_close, panel.win, true)
  end
  if panel.buf and vim.api.nvim_buf_is_valid(panel.buf) then
    pcall(vim.api.nvim_buf_delete, panel.buf, { force = true })
  end
  panel.win, panel.buf = nil, nil
end

---@param file string
---@param filetype string
---@return string[]? command
---@return string? cwd
---@return string? error_message
function M.command_for(file, filetype)
  if file == "" then
    return nil, nil, "Save the file before running it"
  end

  local cwd = vim.fs.dirname(file)
  local name = vim.fs.basename(file)
  if filetype == "python" then
    -- A project's own environment first (.venv, venv), then python3.
    local root = vim.fs.root(file, { ".venv", "venv", "pyproject.toml", ".git" })
    for _, venv in ipairs({ ".venv", "venv" }) do
      local python = root and (root .. "/" .. venv .. "/bin/python")
      if python and vim.uv.fs_stat(python) then
        return { python, file }, cwd
      end
    end
    return { "python3", file }, cwd
  elseif filetype == "javascript" or filetype == "javascriptreact" then
    return { "node", file }, cwd
  elseif filetype == "typescript" or filetype == "typescriptreact" then
    return { "npx", "--yes", "tsx@4.19.3", file }, cwd
  elseif filetype == "lua" then
    return { vim.fn.executable("lua") == 1 and "lua" or "luajit", file }, cwd
  elseif filetype == "sh" or filetype == "bash" then
    return { "bash", file }, cwd
  elseif filetype == "zsh" then
    return { "zsh", file }, cwd
  elseif filetype == "ruby" then
    -- In a Rails app (or any app with a Gemfile) a test runs as a test, and
    -- everything runs with the app's own gems.
    local root = vim.fs.root(file, "Gemfile")
    local relative = root and file:sub(#root + 2) or file
    if root and name:match("_spec%.rb$") then
      return { "bundle", "exec", "rspec", relative }, root
    elseif root and name:match("_test%.rb$") then
      if vim.uv.fs_stat(root .. "/bin/rails") then
        return { "bin/rails", "test", relative }, root
      end
      return { "bundle", "exec", "ruby", "-Itest", relative }, root
    elseif root and vim.uv.fs_stat(root .. "/bin/rails") and vim.uv.fs_stat(root .. "/config/application.rb") then
      return { "bin/rails", "runner", relative }, root
    elseif root then
      return { "bundle", "exec", "ruby", relative }, root
    end
    return { "ruby", file }, cwd
  elseif filetype == "go" then
    if name:match("_test%.go$") then
      return { "go", "test", "./..." }, cwd
    end
    return { "go", "run", file }, cwd
  elseif filetype == "rust" then
    local root = vim.fs.root(file, "Cargo.toml")
    if not root then
      return nil, nil, "Rust needs a Cargo project to run (cargo new)"
    end
    return { "cargo", "run" }, root
  elseif filetype == "swift" then
    local root = vim.fs.root(file, "Package.swift")
    if root then
      return { "swift", "run" }, root
    end
    return { "swift", file }, cwd
  elseif filetype == "c" or filetype == "cpp" then
    -- Build next to the temp files, run, and leave nothing behind.
    local compiler = filetype == "c" and "cc" or "c++"
    local standard = filetype == "c" and "-std=c17" or "-std=c++20"
    local out = vim.fn.tempname()
    return {
      "sh",
      "-c",
      ('%s %s -o "$1" "$2" && "$1"; code=$?; rm -f "$1"; exit $code'):format(compiler, standard),
      "run",
      out,
      file,
    },
      cwd
  elseif filetype == "java" then
    return { "java", file }, cwd -- single-file programs, Java 11+
  elseif filetype == "php" then
    return { "php", file }, cwd
  elseif filetype == "perl" then
    return { "perl", file }, cwd
  elseif filetype == "elixir" then
    return { "elixir", file }, cwd
  elseif filetype == "zig" then
    return { "zig", "run", file }, cwd
  elseif filetype == "html" then
    return { "open", file }, cwd -- in your browser
  end

  local label = filetype ~= "" and filetype or "this kind of file"
  return nil, nil, "⌘R doesn't know how to run " .. label .. " yet"
end

local function finished(job, code, name, source)
  if job ~= panel.job then
    return -- replaced by a newer run, or closed
  end
  panel.job = nil
  if panel.stopped or code == 130 then -- 130: interrupted with ⌃C in the panel
    set_title(name .. " stopped")
  else
    set_title(code == 0 and (name .. " finished") or (name .. " exited with code " .. code))
  end
  -- Back to the code, unless you've already moved on yourself.
  if vim.api.nvim_get_current_win() == panel.win then
    vim.cmd.stopinsert()
    if valid_win(source) then
      vim.api.nvim_set_current_win(source)
    end
  end
  if not panel.stopped then
    require("dojo.sfx").run_result(code)
  end
end

function M.run()
  local source = source_window()
  if not source then
    vim.notify("Open a file to run it", vim.log.levels.WARN, { title = "Run" })
    return
  end
  local buf = vim.api.nvim_win_get_buf(source)
  local file = vim.api.nvim_buf_get_name(buf)
  local command, cwd, err = M.command_for(file, vim.bo[buf].filetype)
  if not command then
    vim.notify(err, vim.log.levels.WARN, { title = "Run" })
    return
  end
  if not command[1]:find("/") and vim.fn.executable(command[1]) ~= 1 then
    vim.notify(
      ("%s isn't installed, so this can't run yet (brew install %s)"):format(command[1], command[1]),
      vim.log.levels.WARN,
      { title = "Run" }
    )
    return
  end
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("silent update")
  end)

  -- One bottom panel at a time: the run replaces the old run and hides the terminal.
  M.close()
  for _, term in ipairs(Snacks.terminal.list()) do
    if term:valid() then
      term:hide()
    end
  end

  panel.buf = vim.api.nvim_create_buf(false, true)
  panel.win = vim.api.nvim_open_win(panel.buf, true, {
    split = "below",
    win = -1, -- full width, along the bottom
    height = math.max(6, math.floor(vim.o.lines * 0.3)),
  })
  local wo = vim.wo[panel.win]
  wo.number, wo.relativenumber, wo.cursorline = false, false, false
  wo.signcolumn, wo.foldcolumn, wo.statuscolumn = "no", "0", ""
  wo.winfixheight = true

  local name = vim.fn.fnamemodify(file, ":t")
  local job
  job = vim.fn.jobstart(command, {
    term = true,
    cwd = cwd,
    on_exit = function(_, code)
      vim.schedule(function()
        finished(job, code, name, source)
      end)
    end,
  })
  panel.job = job
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      M.close()
      if valid_win(source) then
        vim.api.nvim_set_current_win(source)
      end
    end, { buffer = panel.buf, silent = true, desc = "Close run output" })
  end
  panel.stopped = false
  set_title("Running " .. name .. "…", true)
  if #vim.api.nvim_list_uis() > 0 then
    vim.cmd.startinsert() -- keys go to the program, for input()
  end
end

return M
