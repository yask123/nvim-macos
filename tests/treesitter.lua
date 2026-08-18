local function fail(message)
  error("Treesitter compatibility check failed: " .. message, 0)
end

local data_dir = vim.fn.stdpath("data")
local plugin_dir = vim.fs.joinpath(data_dir, "lazy", "nvim-treesitter")
if not (vim.uv or vim.loop).fs_stat(plugin_dir) then
  fail("nvim-treesitter is not installed at " .. plugin_dir)
end

vim.opt.runtimepath:prepend(plugin_dir)

local install_dir = vim.fs.joinpath(data_dir, "site")
local treesitter = require("nvim-treesitter")
treesitter.setup({ install_dir = install_dir })

local task = treesitter.install({ "vim" }, { force = true, summary = true })
local completed, installed_or_error = task:pwait(300000)
if not completed then
  fail("Vim parser installation did not finish: " .. tostring(installed_or_error))
elseif not installed_or_error then
  fail("Vim parser installation returned false")
end

local parser_config = require("nvim-treesitter.parsers").vim
local expected_revision = parser_config and parser_config.install_info and parser_config.install_info.revision
local revision_file = vim.fs.joinpath(install_dir, "parser-info", "vim.revision")
local revision_lines = vim.fn.readfile(revision_file)
local installed_revision = vim.trim(table.concat(revision_lines, "\n"))
if installed_revision ~= expected_revision then
  fail(("Vim parser revision is %s, expected %s"):format(installed_revision, tostring(expected_revision)))
end

if vim.treesitter.language.add("vim") == false then
  fail("the installed Vim parser could not be loaded")
end

local query_ok, query_or_error = pcall(vim.treesitter.query.get, "vim", "highlights")
if not query_ok then
  fail("the bundled Vim highlight query does not compile: " .. tostring(query_or_error))
elseif not query_or_error then
  fail("no Vim highlight query was found")
end

-- This token was added to the Vim highlight query before older installed
-- parsers learned it. Keep the focused assertion so that exact regression is
-- obvious even if the larger highlight query changes later.
local tab_ok, tab_error = pcall(vim.treesitter.query.parse, "vim", [["tab" @keyword]])
if not tab_ok then
  fail('the Vim parser does not recognize the "tab" node: ' .. tostring(tab_error))
end

print("Treesitter Vim parser/query compatibility passed")
