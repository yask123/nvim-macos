#!/usr/bin/env bash

set -Eeuo pipefail

user_home="${HOME:?HOME is not set}"
config_home="${XDG_CONFIG_HOME:-$user_home/.config}"
data_home="${XDG_DATA_HOME:-$user_home/.local/share}"
state_home="${XDG_STATE_HOME:-$user_home/.local/state}"
cache_home="${XDG_CACHE_HOME:-$user_home/.cache}"
target_config="$config_home/nvim"
target_data="$data_home/nvim"
target_state="$state_home/nvim"
target_cache="$cache_home/nvim"

for target in "$target_config" "$target_data" "$target_state" "$target_cache"; do
  case "$target" in
    "" | / | "$user_home" | "$config_home" | "$data_home" | "$state_home" | "$cache_home")
      printf 'Refusing unsafe target: %s\n' "$target" >&2
      exit 1
      ;;
  esac
done

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_parent="$state_home/nvim-bootstrap/uninstalled"
backup_root=""
found=0

move_path() {
  local path="$1"
  local label="$2"
  if [[ -e "$path" || -L "$path" ]]; then
    if [[ -z "$backup_root" ]]; then
      mkdir -p "$backup_parent"
      backup_root="$(mktemp -d "$backup_parent/$timestamp.XXXXXX")"
    fi
    mv -- "$path" "$backup_root/$label"
    found=1
  fi
}

# Dojo's desktop pieces: only links and files this setup created.
points_into_config() {
  [[ -L "$1" && "$(readlink "$1")" == "$target_config"/* ]]
}
for link in "$config_home/neovide/config.toml" "$config_home/ghostty/config" "$user_home/.local/bin/dojo"; do
  if points_into_config "$link"; then
    rm -f -- "$link"
    printf 'Removed %s\n' "$link"
  fi
done
updater="$user_home/.local/bin/nvim-update"
if [[ -f "$updater" ]] && grep -q "restore-plugins.sh" "$updater"; then
  rm -f -- "$updater"
  printf 'Removed %s\n' "$updater"
fi
app="$user_home/Applications/Dojo.app"
if [[ -d "$app" && -x /usr/libexec/PlistBuddy ]] &&
  [[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist" 2>/dev/null)" == "dev.dojo.launcher" ]]; then
  rm -rf -- "$app"
  printf 'Removed %s\n' "$app"
fi

move_path "$target_config" config
move_path "$target_data" data
move_path "$target_state" state
move_path "$target_cache" cache

if [[ $found -eq 1 ]]; then
  printf 'Neovim files moved to %s\n' "$backup_root"
  printf 'Homebrew packages and fonts were left installed because they may be shared.\n'
else
  printf 'No Neovim files were found.\n'
fi
