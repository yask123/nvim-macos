local M = {}

M.default = "phosphor" -- Dojo's own dark theme; ⌘K ⌘T for light & dark ones
M.path = vim.fn.stdpath("state") .. "/colorscheme"

function M.get()
  local ok, lines = pcall(vim.fn.readfile, M.path)
  local saved = ok and lines[1] or nil
  -- Neovim 0.12 bundles a Vim-script "catppuccin"; the plugin's alias avoids it.
  if saved == "catppuccin" then
    saved = "catppuccin-nvim"
  end
  if saved and saved:match("^[%w_.-]+$") then
    return saved
  end
  return M.default
end

function M.save(colorscheme)
  if not colorscheme:match("^[%w_.-]+$") then
    error("Invalid colorscheme name")
  end
  vim.fn.mkdir(vim.fs.dirname(M.path), "p")
  vim.fn.writefile({ colorscheme }, M.path)
end

return M
