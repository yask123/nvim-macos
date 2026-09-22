-- Colour theme picker (⌘K ⌘T). A short, curated list; the editor recolours
-- live as you move through it, Enter keeps the theme, Esc puts yours back.
-- "Light & dark" themes follow macOS; the others are pinned to one look.

local M = {}

M.themes = {
  { name = "rose-pine", label = "Rosé Pine", note = "light & dark" },
  { name = "catppuccin-nvim", label = "Catppuccin", note = "light & dark" },
  { name = "kanso", label = "Kanso", note = "light & dark" },
  { name = "tokyonight", label = "Tokyo Night", note = "light & dark" },
  { name = "rose-pine-moon", label = "Rosé Pine Moon", note = "dark" },
  { name = "rose-pine-main", label = "Rosé Pine Main", note = "dark, deeper" },
  { name = "catppuccin-mocha", label = "Catppuccin Mocha", note = "dark" },
  { name = "catppuccin-frappe", label = "Catppuccin Frappé", note = "dark, softer" },
  { name = "kanso-ink", label = "Kanso Ink", note = "dark" },
  { name = "kanso-zen", label = "Kanso Zen", note = "dark, deepest" },
  { name = "tokyonight-moon", label = "Tokyo Night Moon", note = "dark" },
  { name = "rose-pine-dawn", label = "Rosé Pine Dawn", note = "light" },
  { name = "catppuccin-latte", label = "Catppuccin Latte", note = "light" },
  { name = "kanso-pearl", label = "Kanso Pearl", note = "light" },
  { name = "tokyonight-day", label = "Tokyo Night Day", note = "light" },
  { name = "default", label = "Neovim", note = "light & dark, plain" },
}

local function apply(name)
  pcall(vim.cmd.colorscheme, name)
end

function M.pick()
  local before = { name = vim.g.colors_name or require("config.theme").get(), background = vim.o.background }
  local chosen, closed = false, false
  local items, current = {}, 1
  for index, theme in ipairs(M.themes) do
    table.insert(items, { text = theme.label .. " " .. theme.note, theme = theme })
    if theme.name == before.name then
      current = index
    end
  end
  local previewing
  Snacks.picker({
    title = "Colour Theme",
    items = items,
    layout = { preset = "select", layout = { width = 44, min_width = 44 } },
    on_show = function(picker)
      picker.list:view(current)
    end,
    format = function(item)
      local theme = item.theme
      return {
        { Snacks.picker.util.align(theme.label, 22) },
        { theme.note, "SnacksPickerComment" },
      }
    end,
    -- Live preview: recolour on every move (deferred a tick so fast scrolling stays smooth).
    on_change = function(_, item)
      if not item or closed then
        return
      end
      previewing = item.theme.name
      vim.schedule(function()
        if not closed and previewing == item.theme.name and vim.g.colors_name ~= item.theme.name then
          apply(item.theme.name)
        end
      end)
    end,
    on_close = function()
      closed = true
      if chosen then
        return
      end
      previewing = nil
      vim.schedule(function()
        vim.o.background = before.background
        apply(before.name)
      end)
    end,
    confirm = function(picker, item)
      chosen = item ~= nil
      picker:close()
      if item then
        previewing = nil
        vim.schedule(function()
          apply(item.theme.name)
          require("config.theme").save(item.theme.name)
        end)
      end
    end,
  })
end

return M
