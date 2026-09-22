-- nvim-treesitter `main` dropped Neovim 0.11 (c82bf96). On 0.11 pin the last
-- compatible commit, exactly like LazyVim 16 does; on 0.12+ follow the lockfile.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    commit = vim.fn.has("nvim-0.12") == 0 and "7caec274fd19c12b55902a5b795100d21531391f" or nil,
  },
}
