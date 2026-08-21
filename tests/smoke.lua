local function assert_equal(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    label .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)
  )
end

local version = vim.version()
local version_supported = version.major > 0 or version.minor > 11 or (version.minor == 11 and version.patch >= 2)
assert(version_supported, "Neovim 0.11.2+ is required")
assert_equal(vim.g.colors_name, "catppuccin-latte", "default colorscheme")

local runner = require("config.runner")
local path = "/tmp/a folder/hello world;touch should-not-run.py"
local command, cwd = runner.command_for(path, "python")
assert_equal(command, { "python3", path }, "path-safe Python runner")
assert_equal(cwd, "/tmp/a folder", "runner working directory")

local typescript_command = runner.command_for(path, "typescript")
assert_equal(typescript_command, { "npx", "--yes", "tsx@4.19.3", path }, "pinned TypeScript runner")

local tutor = require("config.tutor")
assert_equal(tutor._constants.default_model, "gpt-5.6-sol", "Tutor default model")
assert(tutor._constants.instructions:find("Do not edit files", 1, true), "Tutor must not edit learner files")
assert(tutor._constants.instructions:find("two to five short sentences", 1, true), "Tutor answers should be brief")

local tutor_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(tutor_buf, "/tmp/tutor example.py")
vim.bo[tutor_buf].filetype = "python"
vim.api.nvim_buf_set_lines(tutor_buf, 0, -1, false, { "def total(values):", "    return sum(values)" })
local source_before = vim.api.nvim_buf_get_lines(tutor_buf, 0, -1, false)
local tutor_context = tutor._context_from_buffer(tutor_buf, 1, 2, "selection")
assert_equal(tutor_context.text, "def total(values):\n    return sum(values)", "Tutor selection context")
assert_equal(vim.api.nvim_buf_get_lines(tutor_buf, 0, -1, false), source_before, "Tutor context is read-only")

local payload = tutor._build_payload(tutor_context, {
  { role = "user", content = "Why use sum?" },
}, "test-model")
assert_equal(payload.model, "test-model", "Tutor model override")
assert_equal(payload.store, false, "Tutor API storage disabled")
assert_equal(payload.text.verbosity, "low", "Tutor API verbosity")
assert_equal(payload.reasoning.context, "current_turn", "Tutor uses stateless reasoning context")
assert_equal(payload.tools, {}, "Tutor has no model tools")
assert(payload.input[1].content:find("def total", 1, true), "Tutor payload includes source context")

local parsed_answer, parsed_error = tutor._parse_response(vim.json.encode({
  output = {
    {
      type = "message",
      content = { { type = "output_text", text = "It delegates the loop to Python." } },
    },
  },
}))
assert_equal(parsed_answer, "It delegates the loop to Python.", "Tutor response parsing")
assert_equal(parsed_error, nil, "Tutor response has no error")

local request_command = tutor._request_command()
assert_equal(request_command[1], "python3", "Tutor uses the local Python transport")
assert_equal(request_command[2], tutor._constants.helper_path, "Tutor uses the installed helper")
if vim.env.OPENAI_API_KEY and vim.env.OPENAI_API_KEY ~= "" then
  assert(
    not table.concat(request_command, " "):find(vim.env.OPENAI_API_KEY, 1, true),
    "Tutor argv must not embed the key"
  )
end
vim.api.nvim_buf_delete(tutor_buf, { force = true })

local lazy_config = require("lazy.core.config")
assert(lazy_config.plugins["mini.comment"].url == "https://github.com/nvim-mini/mini.comment.git", "mini.comment URL")
assert(lazy_config.plugins["nvim-cmp"] == nil, "Blink should be the only completion engine")
assert(
  lazy_config.plugins["nvim-treesitter"].commit == "7caec274fd19c12b55902a5b795100d21531391f",
  "Treesitter compatibility pin"
)

local lsp_opts = LazyVim.opts("nvim-lspconfig")
local fake_client = { server_capabilities = { hoverProvider = true, diagnosticProvider = true } }
local diagnostics_before = vim.diagnostic.is_enabled({ bufnr = 0 })
assert(lsp_opts.servers.ruff.init_options.settings.lint.enable == false, "Ruff linting should be disabled")
lsp_opts.servers.ruff.on_attach(fake_client, 0)
assert(fake_client.server_capabilities.hoverProvider == false, "Ruff hover should be disabled")
assert(fake_client.server_capabilities.diagnosticProvider == false, "Ruff diagnostics should be disabled")
assert(vim.diagnostic.is_enabled({ bufnr = 0 }) == diagnostics_before, "Other diagnostics must remain enabled")

print("Neovim smoke test passed")
