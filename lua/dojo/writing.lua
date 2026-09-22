-- Reading & writing comfort for prose (notes, commit messages): soft wrap,
-- hanging list indents, spelling. Code wrapping lives in config/options.lua;
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
      vim.opt_local.colorcolumn = ""
      vim.opt_local.spell = true
      vim.opt_local.spelllang = { "en_us" }
      vim.opt_local.showbreak = "NONE" -- an empty local value would fall back to the global ↪
      vim.opt_local.breakindentopt = "list:-1,min:40" -- wrapped list items hang after "- " / "1. "
    end,
  })
end

return M
