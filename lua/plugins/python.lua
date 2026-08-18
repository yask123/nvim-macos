return {
  -- Minimal diagnostic configuration - only show errors
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      -- Disable inline virtual text (type hints)
      vim.diagnostic.config({
        virtual_text = false, -- No inline hints
        signs = true, -- Keep gutter signs for errors
        underline = true, -- Keep underline for errors
        update_in_insert = false,
        severity_sort = true,
      })

      -- Only show errors in signs, hide warnings
      local signs = {
        { name = "DiagnosticSignError", text = "●" },
        { name = "DiagnosticSignWarn", text = "" }, -- Empty to hide
        { name = "DiagnosticSignHint", text = "" },
        { name = "DiagnosticSignInfo", text = "" },
      }
      for _, sign in ipairs(signs) do
        vim.fn.sign_define(sign.name, { texthl = sign.name, text = sign.text, numhl = "" })
      end

      return opts
    end,
  },

  -- Virtual environment selector for Python
  {
    "linux-cultist/venv-selector.nvim",
    cmd = "VenvSelect",
    opts = {
      -- Auto-select virtualenv when opening Python files
      auto_refresh = true,
      notify_user_on_venv_activation = true,
    },
    keys = {
      { "<leader>cv", "<cmd>VenvSelect<cr>", desc = "Select VirtualEnv" },
    },
  },

  -- Configure basedpyright with minimal checking
  {
    "neovim/nvim-lspconfig",
    opts = {
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
          -- Disable inlay hints from basedpyright
          on_attach = function(client, bufnr)
            -- Disable inlay hint provider capability
            client.server_capabilities.inlayHintProvider = false

            -- Also explicitly disable inlay hints for this buffer
            if vim.lsp.inlay_hint then
              vim.lsp.inlay_hint.enable(false, { bufnr = bufnr })
            end
          end,
        },
        ruff = {
          -- Disable Ruff diagnostics completely, only use for formatting
          on_attach = function(client)
            client.server_capabilities.hoverProvider = false
            client.server_capabilities.diagnosticProvider = false
          end,
        },
      },
    },
  },
}
