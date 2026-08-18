if vim.env.NVIM_SKIP_MASON_INSTALL == "1" then
  return {
    { "mason-org/mason.nvim", enabled = false },
    { "mason-org/mason-lspconfig.nvim", enabled = false },
  }
end

return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      for _, tool in ipairs({
        "basedpyright",
        "black",
        "json-lsp",
        "lua-language-server",
        "prettier",
        "ruff",
        "shfmt",
        "stylua",
        "vtsls",
      }) do
        if not vim.tbl_contains(opts.ensure_installed, tool) then
          table.insert(opts.ensure_installed, tool)
        end
      end
    end,
  },
}
