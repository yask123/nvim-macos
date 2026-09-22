-- Languages that just work: common treesitter parsers up front, any other
-- parser installed the first time you open that kind of file, and Swift with
-- Xcode's own language server.

-- Open a file whose parser is missing: install it in the background, then
-- re-run FileType so LazyVim switches on highlighting, indents and folds.
local function auto_install()
  local ok, ts = pcall(require, "nvim-treesitter")
  if not ok then
    return
  end
  local available = {}
  for _, lang in ipairs(ts.get_available()) do
    available[lang] = true
  end
  local pending = {}
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("DojoParserAutoInstall", { clear = true }),
    callback = function(ev)
      local lang = vim.treesitter.language.get_lang(ev.match)
      if not lang or not available[lang] or pending[lang] or vim.bo[ev.buf].buftype ~= "" then
        return
      end
      if vim.tbl_contains(ts.get_installed(), lang) then
        return
      end
      pending[lang] = true
      vim.notify("Installing " .. lang .. " support…", vim.log.levels.INFO, { title = "Dojo" })
      ts.install({ lang }, { summary = false }):await(function(err)
        vim.schedule(function()
          if err or vim.v.exiting ~= vim.NIL then
            return
          end
          pcall(LazyVim.treesitter.get_installed, true) -- refresh LazyVim's cache
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buf) and vim.treesitter.language.get_lang(vim.bo[buf].filetype) == lang then
              vim.api.nvim_exec_autocmds("FileType", { buffer = buf })
            end
          end
          require("dojo.folds").refresh()
        end)
      end)
    end,
  })
end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      -- Everything else installs itself the first time you open such a file.
      ensure_installed = { "swift", "gitcommit", "diff" },
    },
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        once = true,
        callback = auto_install,
      })
    end,
  },

  -- Swift / Objective-C: sourcekit-lsp ships with Xcode (not via Mason).
  -- Go to definition, references, rename and hover work in Swift packages;
  -- for .xcodeproj apps, run `xcode-build-server config` once for full results.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        sourcekit = {
          mason = false,
          filetypes = { "swift", "objc", "objcpp" },
        },
      },
    },
  },
}
