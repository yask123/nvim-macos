-- LazyVim 16 conditionally selects this compatibility commit on Neovim 0.11.
-- Keep it explicit so 0.11 and 0.12 restore the same reproducible plugin graph.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    commit = "7caec274fd19c12b55902a5b795100d21531391f",
  },
}
