local M = {}

local output_buf
local output_win
local active_job

local function clear_output()
  if output_win and vim.api.nvim_win_is_valid(output_win) then
    vim.api.nvim_win_close(output_win, true)
  end
  if output_buf and vim.api.nvim_buf_is_valid(output_buf) then
    vim.api.nvim_buf_delete(output_buf, { force = true })
  end
  output_win = nil
  output_buf = nil
end

function M.close()
  if active_job then
    pcall(active_job.kill, active_job, 15)
    active_job = nil
  end
  clear_output()
end

local function show_output(lines, title)
  clear_output()

  output_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, lines)
  vim.bo[output_buf].buftype = "nofile"
  vim.bo[output_buf].bufhidden = "wipe"
  vim.bo[output_buf].modifiable = false
  vim.bo[output_buf].filetype = "text"

  local width = math.max(math.min(vim.o.columns - 4, 120), 20)
  local height = math.max(math.min(math.floor(vim.o.lines * 0.3), vim.o.lines - 4), 5)
  local row = math.max(vim.o.lines - height - 3, 0)
  local col = math.max(math.floor((vim.o.columns - width) / 2), 0)

  output_win = vim.api.nvim_open_win(output_buf, false, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "single",
    title = " " .. (title or "Output") .. " ",
    title_pos = "left",
  })

  vim.wo[output_win].wrap = true
  vim.wo[output_win].cursorline = false
  vim.keymap.set("n", "q", M.close, { buffer = output_buf, silent = true })
  vim.keymap.set("n", "<Esc>", M.close, { buffer = output_buf, silent = true })
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

local function output_lines(result)
  local chunks = {}
  if result.stdout and result.stdout ~= "" then
    table.insert(chunks, result.stdout)
  end
  if result.stderr and result.stderr ~= "" then
    table.insert(chunks, result.stderr)
  end
  local text = table.concat(chunks, "\n")
  local lines = vim.split(text, "\n", { plain = true, trimempty = true })
  return #lines > 0 and lines or { "(no output)" }
end

function M.run()
  local file = vim.api.nvim_buf_get_name(0)
  local command, cwd, err = M.command_for(file, vim.bo.filetype)
  if not command then
    vim.notify(err, vim.log.levels.WARN)
    return
  end
  if vim.fn.executable(command[1]) ~= 1 then
    vim.notify("Runner executable not found: " .. command[1], vim.log.levels.ERROR)
    return
  end

  vim.cmd.write()

  M.close()
  show_output({ "Running…" }, "Output")

  local job
  job = vim.system(command, { cwd = cwd, text = true }, function(result)
    vim.schedule(function()
      if active_job ~= job then
        return
      end
      active_job = nil
      local title = result.code == 0 and "Output" or ("Output (exit: " .. result.code .. ")")
      show_output(output_lines(result), title)
    end)
  end)
  active_job = job
end

return M
