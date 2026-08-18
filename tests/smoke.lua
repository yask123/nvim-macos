local function assert_equal(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    label .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)
  )
end

local version = vim.version()
assert(version.major > 0 or version.minor >= 11, "Neovim 0.11+ is required")
assert_equal(vim.g.colors_name, "catppuccin-latte", "default colorscheme")

local runner = require("config.runner")
local path = "/tmp/a folder/hello world;touch should-not-run.py"
local command, cwd = runner.command_for(path, "python")
assert_equal(command, { "python3", path }, "path-safe Python runner")
assert_equal(cwd, "/tmp/a folder", "runner working directory")

local lazy_config = require("lazy.core.config")
assert(lazy_config.plugins["mini.comment"].url == "https://github.com/nvim-mini/mini.comment.git", "mini.comment URL")
assert(lazy_config.plugins["nvim-cmp"] == nil, "Blink should be the only completion engine")

local lsp_opts = LazyVim.opts("nvim-lspconfig")
local fake_client = { server_capabilities = { hoverProvider = true, diagnosticProvider = true } }
local diagnostics_before = vim.diagnostic.is_enabled({ bufnr = 0 })
lsp_opts.servers.ruff.on_attach(fake_client, 0)
assert(fake_client.server_capabilities.hoverProvider == false, "Ruff hover should be disabled")
assert(fake_client.server_capabilities.diagnosticProvider == false, "Ruff diagnostics should be disabled")
assert(vim.diagnostic.is_enabled({ bufnr = 0 }) == diagnostics_before, "Other diagnostics must remain enabled")

print("Neovim smoke test passed")
