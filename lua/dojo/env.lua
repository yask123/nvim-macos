-- The app sees the same tools your terminal does.
--
-- Started from the Dock, Spotlight or `code .`, a Mac app doesn't get your
-- shell's environment: no nvm Node, no Homebrew Ruby, no rbenv, pyenv, cargo
-- or Go that ~/.zshrc sets up. So language servers and ⌘R would not find
-- them. Like VS Code, ask your login shell once in the background and take
-- its environment. The PATH from last time is applied at once at the next
-- start (only PATH is written to disk: other variables may hold secrets).

local M = {}

M.ready = false

local function cache_file()
  return vim.fn.stdpath("state") .. "/dojo-path"
end

-- Never taken from the shell: where this Neovim lives and how it was started.
local keep = {
  PWD = true,
  OLDPWD = true,
  SHLVL = true,
  _ = true,
  HOME = true,
  USER = true,
  LOGNAME = true,
  TMPDIR = true,
  SHELL = true,
  TERM = true,
  TERM_PROGRAM = true,
  TERM_PROGRAM_VERSION = true,
  TERM_SESSION_ID = true,
  COLORTERM = true,
  COLUMNS = true,
  LINES = true,
  VIM = true,
  VIMRUNTIME = true,
  MYVIMRC = true,
  NVIM = true,
  NVIM_LOG_FILE = true,
  NVIM_LISTEN_ADDRESS = true,
  NEOVIDE_FRAME = true,
}

local function ours(name)
  return keep[name] or name:match("^XDG_") or name:match("^DOJO_") or name:match("^NVIM_") or name:match("^NEOVI")
end

-- The shell's PATH first (its order is the one you chose), then whatever this
-- process had that the shell didn't (Mason's tools, Homebrew fallbacks).
local function merged_path(shell_path)
  local seen, out = {}, {}
  for _, list in ipairs({ shell_path, vim.env.PATH or "" }) do
    for dir in list:gmatch("[^:]+") do
      if not seen[dir] then
        seen[dir] = true
        out[#out + 1] = dir
      end
    end
  end
  -- Mason's own bin directory stays in front, where Mason put it.
  local mason = vim.fn.stdpath("data") .. "/mason/bin"
  if seen[mason] then
    out = vim.tbl_filter(function(dir)
      return dir ~= mason
    end, out)
    table.insert(out, 1, mason)
  end
  return table.concat(out, ":")
end

local function apply(env)
  for name, value in pairs(env) do
    if name == "PATH" then
      vim.env.PATH = merged_path(value)
    elseif not ours(name) and vim.env[name] ~= value then
      vim.env[name] = value
    end
  end
end

local function parse(output)
  local body = output:match("__DOJO_ENV_BEGIN__%z?(.-)__DOJO_ENV_END__")
  if not body then
    return nil
  end
  local env = {}
  for entry in body:gmatch("[^%z]+") do
    local name, value = entry:match("^([%a_][%w_]*)=(.*)$")
    if name then
      env[name] = value
    end
  end
  return env.PATH and env or nil
end

function M.refresh()
  local shell = vim.env.SHELL
  if not shell or shell == "" or vim.fn.executable(shell) ~= 1 then
    shell = "/bin/zsh"
  end
  local script = "printf '__DOJO_ENV_BEGIN__\\0'; command env -0; printf '__DOJO_ENV_END__'"
  local ok = pcall(
    vim.system,
    { shell, "-ilc", script },
    { text = false, timeout = 10000, stdin = false },
    function(result)
      local env = result.stdout and parse(result.stdout) or nil
      vim.schedule(function()
        if env and vim.v.exiting == vim.NIL then
          apply(env)
          local file = io.open(cache_file(), "w")
          if file then
            file:write(env.PATH)
            file:close()
          end
        end
        M.ready = true
        pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "DojoEnvReady" })
      end)
    end
  )
  if not ok then
    M.ready = true
  end
end

function M.setup()
  -- In a terminal (nvim, Ghostty) the environment is already your shell's.
  if not vim.g.neovide or vim.env.DOJO_NO_SHELL_ENV == "1" then
    M.ready = true
    return
  end
  local file = io.open(cache_file(), "r")
  if file then
    local path = file:read("*a")
    file:close()
    if path and path ~= "" then
      vim.env.PATH = merged_path(path)
    end
  end
  vim.schedule(M.refresh)
end

return M
