#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/nvim-macos-install.XXXXXX")"

cleanup() {
  if [[ -n "$test_root" && -d "$test_root" ]]; then
    rm -rf -- "$test_root"
  fi
}
trap cleanup EXIT

export HOME="$test_root/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export NVIM_BOOTSTRAP_REPO="$repo_root"

mkdir -p \
  "$XDG_CONFIG_HOME/nvim" \
  "$XDG_DATA_HOME/nvim" \
  "$XDG_STATE_HOME/nvim" \
  "$XDG_CACHE_HOME/nvim" \
  "$HOME/Library/Fonts" \
  "$HOME/Documents/Folio" \
  "$HOME/.vim"

printf 'config\n' >"$XDG_CONFIG_HOME/nvim/sentinel"
printf 'data\n' >"$XDG_DATA_HOME/nvim/sentinel"
printf 'state\n' >"$XDG_STATE_HOME/nvim/sentinel"
printf 'cache\n' >"$XDG_CACHE_HOME/nvim/sentinel"
printf 'keep\n' >"$HOME/Documents/Folio/keep.txt"
printf 'keep\n' >"$HOME/.vim/keep.txt"
touch "$HOME/Library/Fonts/JetBrainsMono-Regular.ttf"
touch "$HOME/Library/Fonts/0xProtoNerdFontMono-Regular.ttf"

"$repo_root/install.sh" --skip-brew --skip-plugins

[[ -f "$XDG_CONFIG_HOME/nvim/init.lua" ]]
[[ -d "$HOME/notes/dailies" ]]
[[ -f "$HOME/Documents/Folio/keep.txt" ]]
[[ -f "$HOME/.vim/keep.txt" ]]

backup_root="$(find "$XDG_STATE_HOME/nvim-bootstrap/backups" -mindepth 1 -maxdepth 1 -type d -print -quit)"
[[ -n "$backup_root" ]]
for label in config data state cache; do
  [[ -f "$backup_root/$label/sentinel" ]]
done

"$XDG_CONFIG_HOME/nvim/scripts/uninstall.sh"

[[ ! -e "$XDG_CONFIG_HOME/nvim" ]]
[[ -f "$HOME/Documents/Folio/keep.txt" ]]
[[ -f "$HOME/.vim/keep.txt" ]]

uninstalled_root="$(find "$XDG_STATE_HOME/nvim-bootstrap/uninstalled" -mindepth 1 -maxdepth 1 -type d -print -quit)"
[[ -f "$uninstalled_root/config/init.lua" ]]

printf 'Installer backup and uninstall test passed\n'
