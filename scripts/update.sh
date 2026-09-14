#!/usr/bin/env bash

set -Eeuo pipefail

skip_plugins=0
user_home="${HOME:?HOME is not set}"
config_home="${XDG_CONFIG_HOME:-$user_home/.config}"
config_dir="${NVIM_UPDATE_CONFIG_DIR:-$config_home/nvim}"
bin_dir="${NVIM_UPDATE_BIN_DIR:-$user_home/.local/bin}"

usage() {
  cat <<'EOF'
Usage: nvim-update [--skip-plugins]

Fast-forwards the installed Neovim config from its tracked Git branch, restores
the pinned plugins and editor tools, and runs the config doctor.

Options:
  --skip-plugins  Update config files only
  -h, --help      Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-plugins) skip_plugins=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$config_dir" in
  "" | / | "$user_home" | "$config_home")
    printf 'Refusing unsafe config directory: %s\n' "$config_dir" >&2
    exit 1
    ;;
esac

if ! git -C "$config_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf '%s is not a Git checkout. Run the installer first.\n' "$config_dir" >&2
  exit 1
fi

if [[ -n "$(git -C "$config_dir" status --porcelain --untracked-files=all)" ]]; then
  printf 'Your Neovim config has local changes. Commit or stash them before updating.\n' >&2
  git -C "$config_dir" status --short >&2
  exit 1
fi

branch="$(git -C "$config_dir" symbolic-ref --quiet --short HEAD || true)"
if [[ -z "$branch" ]]; then
  printf 'Your Neovim config is on a detached Git commit; switch to a branch first.\n' >&2
  exit 1
fi

upstream="$(git -C "$config_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
if [[ -z "$upstream" ]]; then
  printf 'Branch %s does not track a remote branch. Set an upstream before updating.\n' "$branch" >&2
  exit 1
fi

remote="${upstream%%/*}"
printf 'Fetching %s and updating %s…\n' "$remote" "$branch"
git -C "$config_dir" fetch --quiet "$remote"
git -C "$config_dir" merge --ff-only "$upstream"

mkdir -p "$bin_dir"
install -m 0755 "$config_dir/scripts/update.sh" "$bin_dir/nvim-update"

if [[ $skip_plugins -eq 1 ]]; then
  printf 'Neovim config updated. Plugin restoration was skipped.\n'
  exit 0
fi

if pgrep -x nvim >/dev/null 2>&1; then
  printf 'Neovim config updated. Quit Neovim, then run nvim-update again to restore plugins and tools.\n'
  exit 0
fi

if ! command -v nvim >/dev/null 2>&1; then
  printf 'Neovim config updated, but nvim is not available in PATH.\n' >&2
  exit 1
fi

printf 'Restoring pinned plugins and editor tools…\n'
NVIM_DOCTOR=1 NVIM_MASON_AUTO_INSTALL=0 nvim --headless \
  "+Lazy! restore" \
  "+Lazy! load mason.nvim" \
  "+lua dofile(vim.fn.stdpath('config') .. '/scripts/bootstrap.lua')" \
  "+qa"

"$config_dir/scripts/doctor.sh"

printf '\nNeovim is up to date. Restart it to load the new config.\n'
