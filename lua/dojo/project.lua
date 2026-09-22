-- Folder-as-project, VS Code style: ⌘O shows the native macOS folder picker,
-- ⌘⌥O lists recent projects. Opening one saves the current session, switches
-- the working directory, and restores that project's last session if any.

local M = {}

M.dev_dirs = { "~/dev", "~/code", "~/projects", "~/src", "~/Developer" }

-- Deferred work must not run once Neovim is quitting: callbacks that load
-- modules during exit teardown can crash it (seen as SIGBUS at quit).
local function later(fn)
  vim.schedule(function()
    if vim.v.exiting == vim.NIL then
      fn()
    end
  end)
end
M.later = later

-- Show the file tree for a project (Snacks.explorer() would toggle it closed
-- if it's already open). `enter = false` keeps focus on your file.
local explorer_pending = false
function M.show_explorer(dir, enter)
  -- The picker registers asynchronously; the flag stops a second call in the
  -- same moment (project open + session restore) from opening a second tree.
  if explorer_pending or #Snacks.picker.get({ source = "explorer" }) > 0 then
    return
  end
  explorer_pending = true
  Snacks.explorer({ cwd = dir or vim.fn.getcwd(), enter = enter == true })
  vim.defer_fn(function()
    explorer_pending = false
  end, 300)
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Dojo" })
end

local function session_file()
  local ok, persistence = pcall(require, "persistence")
  if not ok then
    return nil
  end
  local file = persistence.current()
  if file and vim.uv.fs_stat(file) then
    return file
  end
  -- persistence falls back to the branch-less name when a branch session is missing
  local plain = persistence.current({ branch = false })
  return plain and vim.uv.fs_stat(plain) and plain or nil
end

local function close_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
      if vim.bo[buf].modified and vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("silent! write")
        end)
      end
      if not vim.bo[buf].modified then
        pcall(Snacks.bufdelete.delete, { buf = buf, force = vim.bo[buf].buftype == "terminal" })
      end
    end
  end
end

function M.title()
  local cwd = vim.fn.getcwd()
  local name = cwd ~= vim.env.HOME and vim.fn.fnamemodify(cwd, ":t") or ""
  vim.o.title = true
  vim.o.titlestring = name ~= "" and (name .. " — Dojo") or "Dojo"
end

---@param dir string
---@param file? string open this file in the project and keep focus on it
function M.open(dir, file)
  -- Expand only a leading ~ (folder names may contain $ or braces), then compare
  -- real paths so symlinked folders count as the same project.
  dir = vim.fs.normalize(vim.fn.fnamemodify(dir:gsub("^~", vim.env.HOME), ":p"), { expand_env = false }):gsub("/$", "")
  dir = vim.uv.fs_realpath(dir) or dir
  local cwd = vim.uv.fs_realpath(vim.fn.getcwd()) or vim.fn.getcwd()
  local stat = vim.uv.fs_stat(dir)
  if not stat or stat.type ~= "directory" then
    notify("Not a folder: " .. dir, vim.log.levels.WARN)
    return
  end
  -- A file inside the project that's already open: just open it, keep everything else.
  local real_file = file and (vim.uv.fs_realpath(file) or file)
  if real_file and (dir == cwd or vim.startswith(real_file, cwd .. "/")) then
    vim.cmd.edit(vim.fn.fnameescape(real_file))
    return
  end
  if dir == cwd and #vim.fn.getbufinfo({ buflisted = 1 }) > 0 then
    if file then
      vim.cmd.edit(vim.fn.fnameescape(file))
    else
      Snacks.picker.smart({ layout = { preset = "vscode" } })
    end
    return
  end

  local ok, persistence = pcall(require, "persistence")
  local has_files = #vim.tbl_filter(function(info)
    return info.name ~= "" and vim.bo[info.bufnr].buftype == ""
  end, vim.fn.getbufinfo({ buflisted = 1 })) > 0
  if ok and has_files and persistence.active() then -- respect Space q d
    pcall(persistence.save)
  end
  close_buffers()
  vim.fn.chdir(dir)
  M.title() -- the DirChanged event plays the "new level" jingle

  if ok and session_file() then
    persistence.load()
    if file then
      vim.cmd.edit(vim.fn.fnameescape(file))
    end
    -- the PersistenceLoadPost handler (lua/dojo/init.lua) shows the file tree
    notify("Restored " .. vim.fn.fnamemodify(dir, ":~"))
  else
    if file then
      vim.cmd.edit(vim.fn.fnameescape(file))
    end
    later(function()
      M.show_explorer(dir, file == nil) -- keep focus on the file
    end)
    notify("Opened " .. vim.fn.fnamemodify(dir, ":~") .. (file and "" or " — ⌘P to find a file"))
  end
end

function M.choose_folder()
  local start = vim.fn.getcwd()
  local script = {
    "tell me to activate",
    string.format(
      'POSIX path of (choose folder with prompt "Open a folder in Dojo" default location POSIX file "%s")',
      start:gsub('"', '\\"')
    ),
  }
  local cmd = { "osascript" }
  for _, line in ipairs(script) do
    vim.list_extend(cmd, { "-e", line })
  end
  vim.system(cmd, { text = true }, function(result)
    later(function()
      local path = vim.trim(result.stdout or "")
      if result.code == 0 and path ~= "" then
        M.open(path)
      end
    end)
  end)
end

function M.recent()
  local dev = vim.tbl_filter(function(dir)
    return vim.uv.fs_stat(vim.fn.expand(dir)) ~= nil
  end, M.dev_dirs)
  Snacks.picker.projects({
    title = "Recent Projects",
    dev = dev,
    layout = { preset = "vscode" },
    confirm = function(picker, item)
      picker:close()
      if item then
        M.open(item.file)
      end
    end,
  })
end

return M
