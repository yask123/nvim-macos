-- The folders you've opened as projects, newest first. Code keeps its own
-- list (any folder counts, not only git repositories), so the welcome screen
-- and ⌘⌥O can take you straight back to where you were working.

local M = {}

M.file = vim.fn.stdpath("state") .. "/dojo-projects.json"
M.max = 40

local uv = vim.uv

local function is_dir(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

-- Not projects: your home folder itself, the disk root, scratch folders.
M.scratch = { "/tmp/", "/private/tmp/", "/private/var/", "/var/folders/" }

local function skip(path)
  if path == vim.env.HOME or path == "/" or path == "" then
    return true
  end
  for _, prefix in ipairs(M.scratch) do
    if vim.startswith(path, prefix) then
      return true
    end
  end
  return false
end

-- The first time, fill the list from the sessions Code has already saved:
-- every folder you worked in has one (stdpath("state")/sessions/%Users%me%app.vim,
-- with %%branch after the folder for git branches).
local function seed(dir)
  dir = dir or (vim.fn.stdpath("state") .. "/sessions")
  local settings = uv.fs_realpath(vim.fn.stdpath("config")) or vim.fn.stdpath("config")
  local found, seen = {}, {}
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" and name:sub(-4) == ".vim" then
      local path = name:sub(1, -5):gsub("%%%%.*$", ""):gsub("%%", "/")
      local stat = uv.fs_stat(dir .. "/" .. name)
      local own = path == settings or vim.startswith(path, settings .. "/") -- Code's settings, not a project
      if stat and not seen[path] and not own and not skip(path) and is_dir(path) then
        seen[path] = true
        table.insert(found, { path = path, at = stat.mtime.sec })
      end
    end
  end
  table.sort(found, function(a, b)
    if a.at ~= b.at then
      return a.at > b.at
    end
    return a.path < b.path
  end)
  return found
end

M.seed = seed

local function write(list)
  vim.fn.mkdir(vim.fs.dirname(M.file), "p")
  local ok, text = pcall(vim.json.encode, vim.list_slice(list, 1, M.max))
  if ok then
    pcall(vim.fn.writefile, { text }, M.file)
  end
end

local function read()
  local ok, lines = pcall(vim.fn.readfile, M.file)
  if ok then
    local decoded, list = pcall(vim.json.decode, table.concat(lines, "\n"))
    if decoded and type(list) == "table" then
      return vim.tbl_filter(function(entry)
        return type(entry) == "table" and type(entry.path) == "string"
      end, list)
    end
  end
  local list = seed()
  if #list > 0 then
    write(list)
  end
  return list
end

-- "~/Documents/Codex/2026-10-07/so-x20/outputs" → "~/Documents/…/outputs"
local function shorten(path, width)
  if vim.fn.strdisplaywidth(path) <= width then
    return path
  end
  local parts = vim.split(path, "/", { plain = true })
  if #parts > 2 then
    local short = parts[1] .. "/" .. (parts[1] == "~" and parts[2] .. "/" or "") .. "…/" .. parts[#parts]
    if vim.fn.strdisplaywidth(short) <= width then
      return short
    end
    path = "…/" .. parts[#parts]
  end
  if vim.fn.strdisplaywidth(path) <= width then
    return path
  end
  return vim.fn.strcharpart(path, 0, math.max(1, width - 1)) .. "…"
end

--- What to call a folder: its name, and where it lives ("~/dev").
---@param path string
---@param width? number room for the "where" part
function M.label(path, width)
  local where = vim.fn.fnamemodify(vim.fs.dirname(path), ":~")
  return vim.fs.basename(path), shorten(where, width or 24)
end

--- Folders that still exist, newest first.
---@param limit? number
---@return { path: string, at: number, name: string, where: string }[]
function M.list(limit)
  local list = {}
  for _, entry in ipairs(read()) do
    if is_dir(entry.path) then
      local name, where = M.label(entry.path)
      table.insert(list, { path = entry.path, at = entry.at or 0, name = name, where = where })
      if limit and #list >= limit then
        break
      end
    end
  end
  return list
end

--- A folder was opened as the project: it moves to the top.
function M.touch(path)
  if skip(path) then
    return
  end
  local list = vim.tbl_filter(function(entry)
    return entry.path ~= path
  end, read())
  table.insert(list, 1, { path = path, at = os.time() })
  write(list)
end

--- Take a folder off the list (the folder itself is not touched).
function M.forget(path)
  write(vim.tbl_filter(function(entry)
    return entry.path ~= path
  end, read()))
end

return M
