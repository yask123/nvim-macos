local M = {}

M.default = "catppuccin-latte"
M.path = vim.fn.stdpath("state") .. "/colorscheme"

function M.get()
  local ok, lines = pcall(vim.fn.readfile, M.path)
  local saved = ok and lines[1] or nil
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
