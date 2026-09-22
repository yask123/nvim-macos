local function assert_equal(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    label .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)
  )
end

local version = vim.version()
local version_supported = version.major > 0 or version.minor > 11 or (version.minor == 11 and version.patch >= 2)
assert(version_supported, "Neovim 0.11.2+ is required")
assert(vim.g.colors_name:match("^rose%-pine"), "default colorscheme: got " .. tostring(vim.g.colors_name))
assert_equal(require("config.theme").default, "rose-pine", "theme follows macOS light/dark")

local runner = require("config.runner")
local path = "/tmp/a folder/hello world;touch should-not-run.py"
local command, cwd = runner.command_for(path, "python")
assert_equal(command, { "python3", path }, "path-safe Python runner")
assert_equal(cwd, "/tmp/a folder", "runner working directory")

local typescript_command = runner.command_for(path, "typescript")
assert_equal(typescript_command, { "npx", "--yes", "tsx@4.19.3", path }, "pinned TypeScript runner")

local lazy_config = require("lazy.core.config")
assert(lazy_config.plugins["mini.comment"] == nil, "native gc + ts-comments handle commenting")
assert(lazy_config.plugins["vim-visual-multi"] == nil, "multicursor.nvim replaces vim-visual-multi")
assert(lazy_config.plugins["fzf-lua"] == nil, "snacks.picker is the only picker")
assert(lazy_config.plugins["nvim-cmp"] == nil, "Blink should be the only completion engine")
-- Kept minimal on purpose: no AI panels, note-taking or training plugins.
for _, name in ipairs({
  "claudecode.nvim",
  "obsidian.nvim",
  "render-markdown.nvim",
  "precognition.nvim",
  "hardtime.nvim",
  "yanky.nvim",
}) do
  assert(lazy_config.plugins[name] == nil, name .. " should not be installed")
end
assert_equal(
  lazy_config.plugins["nvim-treesitter"].commit,
  vim.fn.has("nvim-0.12") == 0 and "7caec274fd19c12b55902a5b795100d21531391f" or nil,
  "Treesitter compatibility pin only on Neovim 0.11"
)

local lsp_opts = LazyVim.opts("nvim-lspconfig")
assert_equal(lsp_opts.diagnostics.virtual_text, false, "quiet inline diagnostics")
assert_equal(lsp_opts.diagnostics.signs.severity, { min = vim.diagnostic.severity.ERROR }, "errors-only signs")
assert_equal(vim.o.textwidth, 0, "no hard wrap while typing")
local fake_client = { server_capabilities = { hoverProvider = true, diagnosticProvider = true } }
local diagnostics_before = vim.diagnostic.is_enabled({ bufnr = 0 })
assert(lsp_opts.servers.ruff.init_options.settings.lint.enable == false, "Ruff linting should be disabled")
lsp_opts.servers.ruff.on_attach(fake_client, 0)
assert(fake_client.server_capabilities.hoverProvider == false, "Ruff hover should be disabled")
assert(fake_client.server_capabilities.diagnosticProvider == false, "Ruff diagnostics should be disabled")
assert(vim.diagnostic.is_enabled({ bufnr = 0 }) == diagnostics_before, "Other diagnostics must remain enabled")

print("Neovim smoke test passed")
