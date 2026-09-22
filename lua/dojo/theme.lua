-- Colour theme picker (⌘K ⌘T). Remembers the choice across restarts.
-- The "auto" entries follow macOS light/dark; flavour-pinned names do not.

local M = {}

M.auto = {
  ["rose-pine"] = "Rosé Pine — Moon / Dawn, follows macOS (default)",
  ["catppuccin-nvim"] = "Catppuccin — Mocha / Latte, follows macOS",
  kanso = "Kanso — zen Ink / Pearl, follows macOS",
  tokyonight = "Tokyo Night — neon Moon / Day, follows macOS",
}

function M.pick()
  local current = vim.g.colors_name
  local names = vim.fn.getcompletion("", "color")
  table.sort(names, function(a, b)
    local fa, fb = M.auto[a] ~= nil, M.auto[b] ~= nil
    if fa ~= fb then
      return fa
    end
    return a < b
  end)
  Snacks.picker.select(names, {
    prompt = "Colour theme",
    format_item = function(name)
      return M.auto[name] and ("★ " .. M.auto[name]) or ("  " .. name)
    end,
  }, function(choice)
    if choice then
      vim.cmd.colorscheme(choice)
      require("config.theme").save(choice)
    elseif current then
      vim.cmd.colorscheme(current)
    end
  end)
end

return M
