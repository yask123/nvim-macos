-- Files that change on disk change on screen, straight away: a git checkout,
-- a formatter, or an agent (Claude Code, Codex) editing next to you. Vim only
-- looks when you come back to the window, and then asks what to do; here each
-- open file is watched and the answer is always the same:
--   * nothing unsaved in it → show the new version;
--   * unsaved edits in it   → keep yours, say so once; ⌘S writes yours,
--                             ⌘⇧P › Revert File takes the one on disk.

local M = {}

local watchers = {} ---@type table<integer, uv.uv_fs_event_t>
local timers = {} ---@type table<integer, uv.uv_timer_t>

local function stop(buf)
  if watchers[buf] then
    pcall(function()
      watchers[buf]:stop()
      watchers[buf]:close()
    end)
    watchers[buf] = nil
  end
  if timers[buf] then
    pcall(function()
      timers[buf]:stop()
      timers[buf]:close()
    end)
    timers[buf] = nil
  end
end

local function watch(buf)
  stop(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return
  end
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or not vim.uv.fs_stat(path) then
    return
  end
  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end
  watchers[buf] = handle
  local ok = pcall(handle.start, handle, path, {}, function()
    -- Editors and tools often save by writing a new file over the old one,
    -- which ends this watch: look again in a moment, then watch the new file.
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return stop(buf)
      end
      timers[buf] = timers[buf] or vim.uv.new_timer()
      timers[buf]:stop()
      timers[buf]:start(120, 0, function()
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) and vim.v.exiting == vim.NIL then
            pcall(vim.cmd, "silent! checktime " .. buf)
            watch(buf)
          end
        end)
      end)
    end)
  end)
  if not ok then
    stop(buf)
  end
end

local function notify(text)
  vim.notify(text, vim.log.levels.INFO, { title = require("dojo").name })
end

function M.revert()
  if vim.bo.buftype ~= "" or vim.api.nvim_buf_get_name(0) == "" then
    return
  end
  vim.b.dojo_changed_on_disk = nil
  vim.cmd("silent edit!")
  notify("Showing " .. vim.fn.expand("%:t") .. " as it is on disk")
end

function M.setup()
  local group = vim.api.nvim_create_augroup("DojoDisk", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "BufFilePost" }, {
    group = group,
    callback = function(ev)
      if ev.event == "BufWritePost" then
        vim.b[ev.buf].dojo_changed_on_disk = nil
      end
      watch(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(ev)
      stop(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("FileChangedShell", {
    group = group,
    callback = function(ev)
      local name = vim.fn.fnamemodify(ev.file, ":t")
      if vim.v.fcs_reason == "deleted" then
        vim.v.fcs_choice = ""
        if not vim.b[ev.buf].dojo_deleted_on_disk then
          vim.b[ev.buf].dojo_deleted_on_disk = true
          notify(name .. " was deleted on disk. It is still open here; ⌘S puts it back.")
        end
      elseif vim.bo[ev.buf].modified and vim.v.fcs_reason ~= "mode" and vim.v.fcs_reason ~= "time" then
        vim.v.fcs_choice = ""
        if not vim.b[ev.buf].dojo_changed_on_disk then
          vim.b[ev.buf].dojo_changed_on_disk = true
          notify(
            name
              .. " changed on disk. Your unsaved edits are kept: ⌘S writes them, ⌘⇧P › Revert File takes the disk's."
          )
        end
      else
        vim.v.fcs_choice = vim.v.fcs_reason == "mode" and "" or "reload"
      end
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      watch(buf)
    end
  end
end

return M
