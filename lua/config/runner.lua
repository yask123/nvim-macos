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

local function set_title(text)
  if valid_win(panel.win) then
    local title = text:gsub("%%", "%%%%") -- a file name may contain %
    vim.wo[panel.win].winbar = "%#Comment#  " .. title .. "%=q or ⌘J close  ·  ⌘R run again  "
  end
end

function M.is_open()
  return valid_win(panel.win)
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
  if filetype == "python" then
    return { "python3", file }, cwd
  elseif filetype == "javascript" or filetype == "javascriptreact" then
    return { "node", file }, cwd
  elseif filetype == "typescript" or filetype == "typescriptreact" then
    return { "npx", "--yes", "tsx@4.19.3", file }, cwd
  elseif filetype == "lua" then
    return { "lua", file }, cwd
  elseif filetype == "sh" then
    return { "bash", file }, cwd
  elseif filetype == "go" then
    return { "go", "run", file }, cwd
  elseif filetype == "rust" then
    local root = vim.fs.root(file, "Cargo.toml")
    if not root then
      return nil, nil, "Rust runner needs a Cargo.toml project"
    end
    return { "cargo", "run" }, root
  end

  return nil, nil, "No run command for filetype: " .. filetype
end

local function finished(job, code, name, source)
  if job ~= panel.job then
    return -- replaced by a newer run, or closed
  end
  panel.job = nil
  set_title(code == 0 and (name .. " finished") or (name .. " exited with code " .. code))
  -- Back to the code, unless you've already moved on yourself.
  if vim.api.nvim_get_current_win() == panel.win then
    vim.cmd.stopinsert()
    if valid_win(source) then
      vim.api.nvim_set_current_win(source)
    end
  end
  require("dojo.sfx").run_result(code)
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
  if vim.fn.executable(command[1]) ~= 1 then
    vim.notify("Runner executable not found: " .. command[1], vim.log.levels.ERROR, { title = "Run" })
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
  set_title("Running " .. name .. "…")
  if #vim.api.nvim_list_uis() > 0 then
    vim.cmd.startinsert() -- keys go to the program, for input()
  end
end

return M
