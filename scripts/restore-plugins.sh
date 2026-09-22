#!/usr/bin/env bash
# Restore the exact plugin commits pinned in lazy-lock.json.
#
# On a fresh data directory lazy.nvim resolves LazyVim's own plugin specs only
# after LazyVim itself is installed, and it rewrites the lockfile after that
# first pass without them — so a single restore leaves those plugins (neo-tree,
# mini.*, …) at upstream HEAD. Restore twice, putting the pristine lockfile
# back in between. Extra arguments are passed to the second nvim run.
#
# Usage: restore-plugins.sh <config-dir> ["+Lazy! load mason.nvim" …]

set -Eeuo pipefail

config_dir="${1:?usage: restore-plugins.sh <config-dir> [nvim args…]}"
shift
lock="$config_dir/lazy-lock.json"
saved="$(mktemp "${TMPDIR:-/tmp}/lazy-lock.XXXXXX")"
trap 'rm -f -- "$saved"' EXIT

cp -- "$lock" "$saved"
nvim --headless "+Lazy! restore" "+qa"
cp -- "$saved" "$lock"
nvim --headless "+Lazy! restore" "$@" "+qa"

# The lock records the Neovim 0.12 nvim-treesitter. On 0.11 the spec pins the
# last compatible commit instead; move to it without rewriting the lock.
if [[ "$(nvim --headless --clean -c 'lua io.write(vim.fn.has("nvim-0.12"))' -c 'qa' 2>&1)" == "0" ]]; then
  nvim --headless "+Lazy! update nvim-treesitter" "+qa"
  cp -- "$saved" "$lock"
fi
