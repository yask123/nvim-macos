-- Vim reports trouble in codes: "E37: No write since last change (add ! to
-- override)", "E486: Pattern not found: foo", a Lua stack trace. Code says the
-- same thing in plain words, once, and keeps the original in a log you can
-- open (⌘⇧P › Show Log). Every notification passes through M.filter (it is
-- the notifier's filter, lua/plugins/ui.lua).

local M = {}

M.log = {} -- { time, text } of everything softened or hidden, oldest first
local max_log = 300

local INFO, WARN = vim.log.levels.INFO, vim.log.levels.WARN

-- pattern → what to say instead. false hides it. A function gets the captures.
-- First match wins.
local rules = {
  -- Something broke inside the editor or a plugin: never a stack trace on screen.
  { "stack traceback:", "internal" },
  { "^E5108:", "internal" },
  { "^E5113:", "internal" },
  { "^E5107:", "internal" },
  { "Error executing", "internal" },
  { "Error detected while processing", "internal" },
  { "^Lua:", "internal" },
  { "^Lua callback:", "internal" },
  { "attempt to index", "internal" },
  { "attempt to call", "internal" },
  { "attempt to compare", "internal" },
  { "attempt to perform arithmetic", "internal" },
  { "attempt to concatenate", "internal" },
  { "^Failed to run `config` for", "internal" },
  { "^Failed to source", "internal" },

  -- Searching.
  { "^E486: Pattern not found: (.*)", "No matches for “%1”", INFO },
  { "^E486:", "No matches", INFO },
  { "^E38[45]: [Ss]earch hit %u+ without match for: (.*)", "No more matches for “%1”", INFO },
  { "^E35:", "Nothing searched for yet. ⌘F finds text.", INFO },
  { "^E34[89]:", "Put the cursor on a word first", INFO },
  { "^search hit %u+, continuing at %u+", false },

  -- Saving and closing.
  { "^E37:", "Unsaved changes here. ⌘S saves them.", INFO },
  { "^E89:", "Unsaved changes here. ⌘S saves them.", INFO },
  { "^E162:", "Unsaved changes here. ⌘S saves them.", INFO },
  { "^E32:", "This page has no name yet. ⌘S saves it somewhere.", INFO },
  { "^E45:", "This file is read-only", INFO },
  { "^W10:", "This file is read-only", INFO },
  { "^E21:", "This view can't be edited", INFO },
  { "^E212:", "Can't save there: no permission, or no such folder", WARN },
  { "^E13:", "A file with that name already exists", INFO },
  { "^E139:", "That file is already open here", INFO },
  { "^E948:", "A program is still running in that terminal", INFO },
  { "^E676:", "This view isn't a file, so there is nothing to save", INFO },
  { "^E382:", "This view isn't a file, so there is nothing to save", INFO },
  { "^W1[12]:", false }, -- changed on disk: lua/dojo/disk.lua speaks for these
  { "^WARNING: The file has been changed since reading it", false },
  { "^E32[156]:", false }, -- swap files: off
  { "^E303:", false },

  -- Commands and moving around.
  { "^E492: Not an editor command: (.*)", "No command called “%1”. ⌘⇧P lists them all.", INFO },
  { "^E471:", "That command needs something after it", INFO },
  { "^E20:", "No mark set there", INFO },
  { "^E490:", false }, -- no fold here
  { "^E73:", "Nowhere further back to go", INFO },
  { "^E55[56]:", "Nowhere further to go", INFO },
  { "^E36:", "Not enough room for another split", INFO },
  { "^E94:", false },
  { "^E51[56]:", false },
  { "^E84:", false },
  { "^E444:", "This is the only window", INFO },
  { "^E1[0-9]?: ?Already at %a+ change", false },
  { "^Already at %a+ change", false },

  -- Language help.
  {
    "[Cc]lient (%S+) quit with exit code",
    "Code help for this language stopped. Reopen the file to restart it.",
    WARN,
  },
  {
    "^Spawning language server with cmd: `?([^`]+)`? failed",
    "Code help isn't installed for this language (%1)",
    INFO,
  },
  { "is not supported by any of the servers", "Nothing here for that", INFO },
  { "^No information available", "No documentation here", INFO },
  { "^No code actions available", "No quick fixes here", INFO },
  { "^No results for", "Nothing found", INFO },
  { "^%[LSP%] Format request failed", false },
  { "^Formatter failed", false },
  { "^No formatter available", false },
  { "method textDocument/", false },

  -- Installing language support in the background.
  { "^%[mason[%w%-%.]*%]%s*(.-) was successfully installed", false },
  { "^%[mason[%w%-%.]*%]%s*installing", false },
  {
    "^%[mason[%w%-%.]*%].-[Ff]ailed",
    "Couldn't finish installing language support. Are you offline? It tries again next launch.",
    WARN,
  },
  { "^%[nvim%-treesitter", false },
}

local internal_text = "Something went wrong inside Code. ⌘⇧P › Show Log has the details."

function M.record(text)
  M.log[#M.log + 1] = { time = os.date("%H:%M:%S"), text = text }
  if #M.log > max_log then
    table.remove(M.log, 1)
  end
end

--- What to show for a message. Returns text and level; nil text hides it.
---@param msg string
---@param level? integer
function M.soften(msg, level)
  local first = vim.trim((msg:match("^[^\n]*") or msg))
  for _, rule in ipairs(rules) do
    local captures = { msg:match(rule[1]) }
    if #captures > 0 then
      local say = rule[2]
      if say == false then
        return nil
      elseif say == "internal" then
        return internal_text, WARN
      end
      for index, capture in ipairs(captures) do
        if type(capture) == "string" then
          say = say:gsub("%%" .. index, function()
            return (vim.trim(capture):match("^[^\n]*") or "")
          end)
        end
      end
      return say, rule[3] or level
    end
  end
  -- Any other Vim error: drop the code and the "(add ! to override)" hint.
  if first:match("^[EW]%d+: ") then
    return (first:gsub("^[EW]%d+: ", ""):gsub("%s*%(add ! to override%)", "")), level
  end
  return msg, level
end

local last_text, last_time = nil, 0

--- The notifier's filter: rewrites the notification in place; false hides it.
function M.filter(notif)
  local original = notif.msg or ""
  local say, level = M.soften(original, notif.level)
  if say ~= original then
    M.record(original)
  end
  if not say then
    return false
  end
  -- Vim often reports one failure twice; say it once.
  local now = vim.uv.now()
  if say == last_text and now - last_time < 1500 then
    return false
  end
  last_text, last_time = say, now
  if say ~= original then
    notif.msg = say
    if type(level) == "number" then
      local name = ({ [INFO] = "info", [WARN] = "warn", [vim.log.levels.ERROR] = "error" })[level]
      if name and name ~= notif.level then
        notif.level = name
        notif.icon = ({ info = " ", warn = " ", error = " " })[name] or notif.icon
      end
    end
  end
  return true
end

--- ⌘⇧P › Show Log: what Code softened or hid, word for word, then Vim's own messages.
function M.show_log()
  local lines = { "# Log", "", "What Code said in plain words (or kept quiet about), exactly as it arrived.", "" }
  if #M.log == 0 then
    lines[#lines + 1] = "Nothing so far."
  end
  for _, entry in ipairs(M.log) do
    for index, line in ipairs(vim.split(entry.text, "\n")) do
      lines[#lines + 1] = (index == 1 and (entry.time .. "  ") or "          ") .. line
    end
  end
  vim.list_extend(lines, { "", "## Vim's messages", "" })
  vim.list_extend(lines, vim.split(vim.api.nvim_exec2("messages", { output = true }).output, "\n"))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_height(0, math.min(#lines + 1, math.floor(vim.o.lines * 0.4)))
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
end

return M
