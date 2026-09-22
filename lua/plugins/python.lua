return {
  -- Quiet, learner-friendly diagnostics. These go through LazyVim's own
  -- opts.diagnostics; calling vim.diagnostic.config() directly gets overwritten.
  {
    "neovim/nvim-lspconfig",
    opts = {
      inlay_hints = { enabled = false }, -- no type annotations sprinkled in the code
      folds = { enabled = false }, -- treesitter folds: instant, no language server needed
      diagnostics = {
        virtual_text = false, -- no inline messages; hover or `Space c d` shows them
        signs = { severity = { min = vim.diagnostic.severity.ERROR } }, -- errors only in the gutter
        underline = true,
        update_in_insert = false,
        severity_sort = true,
        float = { border = "rounded", source = "if_many" },
      },
      servers = {
        basedpyright = {
          settings = {
            basedpyright = {
              analysis = {
                typeCheckingMode = "off", -- Turn off type checking to reduce noise
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                diagnosticMode = "openFilesOnly", -- Only check current file
                autoImportCompletions = true,
                -- Only report syntax errors
                diagnosticSeverityOverrides = {
                  reportUndefinedVariable = "error",
                  reportGeneralTypeIssues = "none",
                  reportOptionalMemberAccess = "none",
                  reportOptionalSubscript = "none",
                  reportPrivateImportUsage = "none",
                },
              },
            },
          },
        },
        ruff = {
          -- Keep basedpyright diagnostics; use Ruff only as a formatter.
          init_options = {
            settings = {
              lint = {
                enable = false,
              },
            },
          },
          on_attach = function(client)
            client.server_capabilities.hoverProvider = false
            client.server_capabilities.diagnosticProvider = false
          end,
        },
      },
    },
  },
}
