-- Quitting never asks and never loses anything, like VS Code's "hot exit":
-- files with a name are saved, untitled pages are put away and come back the
-- next time this folder is open, and running terminals are closed.

local M = {}

local function store()
  return vim.fn.stdpath("state") .. "/dojo-untitled.json"
end

local function read()
  local file = io.open(store(), "r")
  if not file then
    return {}
  end
  local ok, data = pcall(vim.json.decode, file:read("*a"))
  file:close()
  return ok and type(data) == "table" and data or {}
end

local function write(data)
  local file = io.open(store(), "w")
  if file then
    file:write(vim.json.encode(next(data) and data or vim.empty_dict()))
    file:close()
  end
end

local function is_untitled(buf)
  return vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) == ""
end

--- Put the untitled pages away under this folder's name. Returns how many.
function M.stash()
  local pages = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if is_untitled(buf) then
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      if vim.bo[buf].modified and vim.trim(table.concat(lines, "\n")) ~= "" then
        pages[#pages + 1] = { lines = lines, filetype = vim.bo[buf].filetype }
      end
      vim.bo[buf].modified = false -- nothing left for Vim to ask about
    end
  end
  local data = read()
  data[vim.fn.getcwd()] = #pages > 0 and pages or nil
  write(data)
  return #pages
end

--- Bring this folder's untitled pages back (once).
function M.restore()
  local data = read()
  local cwd = vim.fn.getcwd()
  local pages = data[cwd]
  if type(pages) ~= "table" or #pages == 0 then
    return 0
  end
  data[cwd] = nil
  write(data)
  for _, page in ipairs(pages) do
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, page.lines or {})
    if page.filetype and page.filetype ~= "" then
      vim.bo[buf].filetype = page.filetype
    end
    vim.bo[buf].modified = true
  end
  return #pages
end

local leaving = false

function M.before_exit()
  if leaving then
    return -- Vim announces an exit more than once; the pages are already put away
  end
  leaving = true
  vim.defer_fn(function()
    leaving = false -- still here: the exit was called off
  end, 1000)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local bo = vim.bo[buf]
      if
        bo.buftype == ""
        and bo.modified
        and vim.api.nvim_buf_get_name(buf) ~= ""
        and not vim.b[buf].dojo_changed_on_disk
      then
        vim.api.nvim_buf_call(buf, function()
          pcall(vim.cmd, "silent! write")
        end)
        if vim.bo[buf].modified then
          vim.bo[buf].modified = false -- can't be written (no permission): don't block quitting
        end
      elseif bo.buftype == "terminal" then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end
  M.stash()
end

function M.setup()
  local group = vim.api.nvim_create_augroup("DojoExit", { clear = true })
  vim.api.nvim_create_autocmd("ExitPre", { group = group, callback = M.before_exit })
  -- Opened straight into a folder: its untitled pages come back with it.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "DojoProjectOpened",
    callback = function()
      vim.schedule(M.restore)
    end,
  })
end

return M
