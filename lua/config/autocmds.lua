-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

-- Disable inlay hints globally when LSP attaches
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("DisableInlayHints", { clear = true }),
  callback = function(args)
    local bufnr = args.buf
    local client = vim.lsp.get_client_by_id(args.data.client_id)

    -- Disable inlay hints for this buffer
    if vim.lsp.inlay_hint then
      vim.lsp.inlay_hint.enable(false, { bufnr = bufnr })
    end

    -- Also disable the capability if possible
    if client and client.server_capabilities then
      client.server_capabilities.inlayHintProvider = false
    end
  end,
})

-- Disable autoformat for markdown files
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown" },
  callback = function()
    vim.b.autoformat = false
  end,
})
