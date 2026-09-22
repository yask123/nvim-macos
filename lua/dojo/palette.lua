-- ⌘⇧P — every Dojo action, searchable by name, macOS chord, or Vim keys.
-- Each row teaches its shortcut, so the palette slowly makes itself obsolete.

local M = {}

local align = function(text, width)
  return Snacks.picker.util.align(text, width, { truncate = true })
end

local extras = {
  {
    desc = "All Neovim commands…",
    vim = ":",
    run = function()
      Snacks.picker.commands()
    end,
  },
  {
    desc = "Search every keymap…",
    vim = "Space s k",
    run = function()
      Snacks.picker.keymaps()
    end,
  },
  {
    desc = "Plugins (Lazy)",
    vim = "Space l",
    run = function()
      vim.cmd("Lazy")
    end,
  },
  {
    desc = "Health check",
    vim = ":checkhealth",
    run = function()
      vim.cmd("checkhealth")
    end,
  },
}

function M.items(opts)
  opts = opts or {}
  local items = {}
  local function add(entry, group)
    table.insert(items, {
      text = table.concat({ entry.desc, entry.mac or "", entry.vim or "", group or "" }, " "),
      entry = entry,
      group = group,
    })
  end
  for _, group in ipairs(require("dojo.keys")) do
    for _, section in ipairs(group.sections) do
      for _, entry in ipairs(section.items) do
        if not entry.hidden and (entry.run or opts.lessons) then
          add(entry, group.name)
        end
      end
    end
  end
  for _, entry in ipairs(extras) do
    add(entry, "More")
  end
  return items
end

function M.open(opts)
  opts = opts or {}
  Snacks.picker({
    title = opts.lessons and "Shortcuts & Lessons" or "Command Palette",
    items = M.items(opts),
    layout = { preset = "vscode", layout = { width = 0.5, min_width = 90 } },
    matcher = { frecency = true },
    format = function(item)
      local entry = item.entry
      -- Fixed columns: what it does · macOS chord · the Vim way.
      local mac = entry.mac or ""
      local vim_way = (entry.vim and entry.vim ~= mac) and entry.vim or ""
      return {
        { align(entry.desc, 44), entry.run and "SnacksPickerLabel" or "Normal" },
        { align(mac, 12), "DojoKeyText" },
        { "  " },
        { vim_way, "DojoVimText" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      local entry = item.entry
      if entry.run then
        vim.schedule(entry.run)
      else
        vim.notify(entry.vim .. "   " .. entry.desc, vim.log.levels.INFO, { title = "Vim lesson" })
      end
    end,
  })
end

return M
