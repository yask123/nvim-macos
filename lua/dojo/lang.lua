-- Languages set themselves up. Open a Go, Rust, Ruby, C, HTML, CSS, YAML,
-- shell, … file and its code help (completion, go to definition, rename,
-- problems, formatting) installs in the background the first time, then
-- starts. Nothing to configure, and nothing is installed for a language you
-- never open. Python, TypeScript/JavaScript, JSON, Lua and Swift are set up
-- by lua/plugins (they were here first); highlighting for every language is
-- lua/plugins/languages.lua.
--
-- A language whose own toolchain is missing (no `go`, no `cargo`) is left
-- alone: you still get highlighting, and no error.

local M = {}

---@class dojo.Lang
---@field name string            what to call it in messages
---@field server string          its nvim-lspconfig name
---@field filetypes string[]
---@field needs? string          a program that must exist for the server to be any use
---@field system? string         a server that ships with the Mac's developer tools
---@field config? vim.lsp.Config

---@type dojo.Lang[]
M.languages = {
  { name = "Go", server = "gopls", filetypes = { "go", "gomod", "gowork", "gotmpl" }, needs = "go" },
  { name = "Rust", server = "rust_analyzer", filetypes = { "rust" }, needs = "cargo" },
  -- clangd comes with Xcode's command line tools.
  {
    name = "C and C++",
    server = "clangd",
    filetypes = { "c", "cpp" },
    system = "clangd",
    config = { filetypes = { "c", "cpp" } },
  },
  { name = "HTML", server = "html", filetypes = { "html" }, needs = "node" },
  { name = "CSS", server = "cssls", filetypes = { "css", "scss", "less" }, needs = "node" },
  { name = "YAML", server = "yamlls", filetypes = { "yaml" }, needs = "node" },
  { name = "TOML", server = "taplo", filetypes = { "toml" } },
  { name = "Shell", server = "bashls", filetypes = { "sh", "bash" }, needs = "node" },
  { name = "Docker", server = "dockerls", filetypes = { "dockerfile" }, needs = "node" },
  { name = "PHP", server = "intelephense", filetypes = { "php" }, needs = "node" },
  { name = "Svelte", server = "svelte", filetypes = { "svelte" }, needs = "node" },
  { name = "Zig", server = "zls", filetypes = { "zig" }, needs = "zig" },
  { name = "Java", server = "jdtls", filetypes = { "java" }, needs = "java" },
}

local by_filetype = {} ---@type table<string, dojo.Lang>
local state = {} ---@type table<string, "installing"|"ready"|"failed"|"skipped">

local function notify(text, level)
  vim.notify(text, level or vim.log.levels.INFO, { title = require("dojo").name })
end

local function off()
  return vim.env.NVIM_SKIP_MASON_INSTALL == "1" or vim.env.NVIM_MASON_AUTO_INSTALL == "0"
end

local function enable(lang)
  if lang.config then
    vim.lsp.config(lang.server, lang.config)
  end
  vim.lsp.enable(lang.server)
  state[lang.server] = "ready"
end

local function install(lang)
  local ok, registry = pcall(require, "mason-registry")
  local map_ok, mappings = pcall(require, "mason-lspconfig.mappings")
  if not ok or not map_ok then
    state[lang.server] = "skipped"
    return
  end
  local package_name = mappings.get_mason_map().lspconfig_to_package[lang.server]
  if not package_name then
    state[lang.server] = "skipped"
    return
  end
  state[lang.server] = "installing"
  registry.refresh(function()
    local found, package = pcall(registry.get_package, package_name)
    if not found then
      state[lang.server] = "failed"
      return
    end
    vim.schedule(function()
      if package:is_installed() then
        return enable(lang)
      end
      notify("Setting up " .. lang.name .. " for the first time…")
      package:install({}, function(success)
        vim.schedule(function()
          if vim.v.exiting ~= vim.NIL then
            return
          end
          if success then
            enable(lang)
            notify(lang.name .. " is ready")
          else
            state[lang.server] = "failed"
            notify(
              "Couldn't set up " .. lang.name .. " (offline?). Highlighting still works; it tries again next launch.",
              vim.log.levels.WARN
            )
          end
        end)
      end)
    end)
  end)
end

-- Ruby ------------------------------------------------------------------------
-- Ruby's language server has to run on the Ruby the project runs on (rbenv,
-- mise, asdf and chruby pick one per folder), so it is installed as a gem for
-- that Ruby and started from the project's folder: not through Mason.
-- In a Rails app it adds its Rails support by itself.

local ruby = {} ---@type table<string, {state: string, bin?: string}>

local ruby_probe = [[
v = RUBY_VERSION.split(".").map(&:to_i)
exit 4 if (v <=> [3, 0, 0]) < 0
begin
  wrapper = File.join(Gem.bindir, "ruby-lsp")
  print(File.exist?(wrapper) ? wrapper : Gem.bin_path("ruby-lsp", "ruby-lsp"))
rescue Gem::Exception, LoadError
  exit 3
end
]]

local function ruby_attach(root, buf)
  local entry = ruby[root]
  if not entry or entry.state ~= "ready" or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local config = vim.deepcopy(vim.lsp.config.ruby_lsp or {})
  config.name = "ruby_lsp"
  config.cmd = { entry.bin }
  config.cmd_cwd = root
  config.root_dir = root
  config.root_markers = nil
  config.reuse_client = nil
  vim.lsp.start(config, { bufnr = buf })
end

local function ruby_buffers(root)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and (vim.bo[buf].filetype == "ruby" or vim.bo[buf].filetype == "eruby") then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and (vim.fs.root(buf, { "Gemfile", ".git" }) or vim.fs.dirname(name)) == root then
        ruby_attach(root, buf)
      end
    end
  end
end

local function ruby_setup(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or off() then
    return
  end
  local root = vim.fs.root(buf, { "Gemfile", ".git" }) or vim.fs.dirname(name)
  local entry = ruby[root]
  if entry then
    if entry.state == "ready" then
      ruby_attach(root, buf)
    end
    return
  end
  if vim.fn.executable("ruby") ~= 1 then
    return -- may appear once the shell environment is in (DojoEnvReady)
  end
  ruby[root] = { state = "checking" }
  local function probe(after_install)
    vim.system({ "ruby", "-e", ruby_probe }, { cwd = root, text = true }, function(result)
      vim.schedule(function()
        if vim.v.exiting ~= vim.NIL then
          return
        end
        if result.code == 0 and result.stdout and vim.trim(result.stdout) ~= "" then
          ruby[root] = { state = "ready", bin = vim.trim(result.stdout) }
          if after_install then
            notify("Ruby is ready")
          end
          ruby_buffers(root)
        elseif result.code == 4 then
          ruby[root] = { state = "old" }
          if not M._told_old_ruby then
            M._told_old_ruby = true
            notify(
              "Code help for Ruby needs Ruby 3 or newer (this folder uses an older one). Highlighting still works."
            )
          end
        elseif result.code == 3 and not after_install then
          ruby[root] = { state = "installing" }
          notify("Setting up Ruby for the first time…")
          vim.system({ "gem", "install", "ruby-lsp", "--no-document" }, { cwd = root, text = true }, function(done)
            vim.schedule(function()
              if done.code == 0 then
                probe(true)
              else
                ruby[root] = { state = "failed" }
                notify(
                  "Couldn't set up Ruby (offline?). Highlighting still works; it tries again next launch.",
                  vim.log.levels.WARN
                )
                require("dojo.calm").record("gem install ruby-lsp:\n" .. (done.stderr or ""))
              end
            end)
          end)
        else
          ruby[root] = { state = "failed" }
        end
      end)
    end)
  end
  probe(false)
end

-- ------------------------------------------------------------------------------

--- Make sure the language of this buffer is set up.
function M.ensure(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return
  end
  local filetype = vim.bo[buf].filetype
  if filetype == "ruby" or filetype == "eruby" then
    return ruby_setup(buf)
  end
  local lang = by_filetype[filetype]
  if not lang or state[lang.server] then
    return
  end
  if lang.system and vim.fn.executable(lang.system) == 1 then
    return enable(lang)
  end
  if lang.needs and vim.fn.executable(lang.needs) ~= 1 then
    return -- no toolchain (yet): looked at again when the shell environment arrives
  end
  if off() then
    state[lang.server] = "skipped"
    return
  end
  install(lang)
end

function M.status()
  return vim.deepcopy(state), vim.deepcopy(ruby)
end

function M.setup()
  for _, lang in ipairs(M.languages) do
    for _, filetype in ipairs(lang.filetypes) do
      by_filetype[filetype] = lang
    end
  end
  local group = vim.api.nvim_create_augroup("DojoLanguages", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(ev)
      M.ensure(ev.buf)
    end,
  })
  local function all()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        M.ensure(buf)
      end
    end
  end
  -- Tools from your shell (nvm's node, a version manager's ruby) may only be
  -- on the PATH once the shell environment is in: look again then.
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "DojoEnvReady", callback = all })
  all()
end

return M
