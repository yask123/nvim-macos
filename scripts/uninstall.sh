#!/usr/bin/env bash

set -Eeuo pipefail

user_home="${HOME:?HOME is not set}"
config_home="${XDG_CONFIG_HOME:-$user_home/.config}"
data_home="${XDG_DATA_HOME:-$user_home/.local/share}"
state_home="${XDG_STATE_HOME:-$user_home/.local/state}"
cache_home="${XDG_CACHE_HOME:-$user_home/.cache}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_root="$state_home/nvim-bootstrap/uninstalled/$timestamp"
found=0

move_path() {
  path="$1"
  label="$2"
  if [[ -e "$path" || -L "$path" ]]; then
    mkdir -p "$backup_root"
    mv -- "$path" "$backup_root/$label"
    found=1
  fi
}

move_path "$config_home/nvim" config
move_path "$data_home/nvim" data
move_path "$state_home/nvim" state
move_path "$cache_home/nvim" cache

if [[ $found -eq 1 ]]; then
  printf 'Neovim files moved to %s\n' "$backup_root"
  printf 'Homebrew packages and fonts were left installed because they may be shared.\n'
else
  printf 'No Neovim files were found.\n'
fi
