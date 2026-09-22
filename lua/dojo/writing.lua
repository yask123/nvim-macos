-- Reading & writing comfort for prose (notes, commit messages): soft wrap
-- and hanging list indents. Code wrapping lives in config/options.lua;
-- ⌘K Z (zen) gives a calm centred page when you want one.

local M = {}

M.prose = { "markdown", "text", "gitcommit", "tex", "typst", "rst", "norg", "org" }

function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("DojoWriting", { clear = true }),
    pattern = M.prose,
    callback = function()
      vim.opt_local.wrap = true
      vim.opt_local.linebreak = true
      vim.opt_local.breakindentopt = "list:-1,min:40" -- wrapped list items hang after "- " / "1. "
    end,
  })
end

return M
