#!/usr/bin/env bash

set -Eeuo pipefail

repo_url="${NVIM_BOOTSTRAP_REPO:-https://github.com/yask123/nvim-macos.git}"
repo_ref="${NVIM_BOOTSTRAP_REF:-main}"
skip_brew=0
skip_plugins=0
temporary_root=""
user_home="${HOME:?HOME is not set}"

usage() {
  cat <<'EOF'
Usage: ./install.sh [--skip-brew] [--skip-plugins]

Installs this Neovim setup on macOS. Existing Neovim config, data, state, and
cache are moved to a timestamped backup before the clean clone is activated.

Environment overrides:
  NVIM_BOOTSTRAP_REPO  Git repository URL
  NVIM_BOOTSTRAP_REF   Git branch or tag (default: main)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-brew) skip_brew=1 ;;
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

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'This bootstrap is for macOS. The Neovim config itself is portable.\n' >&2
  exit 1
fi

cleanup() {
  if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
    rm -rf -- "$temporary_root"
  fi
}
trap cleanup EXIT

load_brew() {
  if command -v brew >/dev/null 2>&1; then
    return
  fi
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

load_brew
if [[ $skip_brew -eq 0 ]] && ! command -v brew >/dev/null 2>&1; then
  printf 'Homebrew is not installed; starting the official installer.\n'
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_brew
fi

if ! command -v git >/dev/null 2>&1; then
  printf 'Git is required. Install Apple Command Line Tools, then rerun this command.\n' >&2
  xcode-select --install >/dev/null 2>&1 || true
  exit 1
fi

script_source="${BASH_SOURCE[0]:-}"
source_dir=""
if [[ -n "$script_source" && -f "$script_source" ]]; then
  candidate_dir="$(CDPATH='' cd -- "$(dirname -- "$script_source")" && pwd)"
  if [[ -f "$candidate_dir/Brewfile" && -f "$candidate_dir/init.lua" ]]; then
    source_dir="$candidate_dir"
  fi
fi

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/nvim-bootstrap.XXXXXX")"
staged_config=""
if [[ -z "$source_dir" ]]; then
  staged_config="$temporary_root/source"
  printf 'Fetching %s (%s)…\n' "$repo_url" "$repo_ref"
  git clone --quiet --depth 1 --branch "$repo_ref" "$repo_url" "$staged_config"
  source_dir="$staged_config"
fi

font_file_exists() {
  local pattern="$1"
  local font_dir
  local match
  for font_dir in "$user_home/Library/Fonts" /Library/Fonts; do
    [[ -d "$font_dir" ]] || continue
    match="$(find "$font_dir" -maxdepth 1 -type f -iname "$pattern" -print -quit 2>/dev/null)"
    if [[ -n "$match" ]]; then
      return 0
    fi
  done
  return 1
}

append_cask_skip() {
  local name="$1"
  case " $cask_skip " in
    *" $name "*) ;;
    *) cask_skip="${cask_skip:+$cask_skip }$name" ;;
  esac
}

if [[ $skip_brew -eq 0 ]]; then
  if ! command -v brew >/dev/null 2>&1; then
    printf 'Homebrew installation did not become available in PATH.\n' >&2
    exit 1
  fi

  cask_skip="${HOMEBREW_BUNDLE_CASK_SKIP:-}"
  if ! brew list --cask font-jetbrains-mono >/dev/null 2>&1 && font_file_exists '*JetBrainsMono*'; then
    append_cask_skip font-jetbrains-mono
  fi
  if ! brew list --cask font-0xproto-nerd-font >/dev/null 2>&1 && font_file_exists '*0xProto*'; then
    append_cask_skip font-0xproto-nerd-font
  fi
  if [[ "$cask_skip" != "${HOMEBREW_BUNDLE_CASK_SKIP:-}" ]]; then
    printf 'Matching manually installed fonts found; keeping them in place.\n'
  fi

  printf 'Installing command-line tools and fonts…\n'
  HOMEBREW_BUNDLE_CASK_SKIP="$cask_skip" brew bundle install --no-upgrade --file="$source_dir/Brewfile"
fi

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

if [[ -z "$staged_config" ]]; then
  staged_config="$temporary_root/nvim"
  git clone --quiet "$source_dir" "$staged_config"
  git -C "$staged_config" remote set-url origin "$repo_url"
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_parent="$state_home/nvim-bootstrap/backups"
backup_root=""
made_backup=0

backup_path() {
  local path="$1"
  local label="$2"
  if [[ -e "$path" || -L "$path" ]]; then
    if [[ -z "$backup_root" ]]; then
      mkdir -p "$backup_parent"
      backup_root="$(mktemp -d "$backup_parent/$timestamp.XXXXXX")"
    fi
    mv -- "$path" "$backup_root/$label"
    made_backup=1
  fi
}

backup_path "$target_config" config
backup_path "$target_data" data
backup_path "$target_state" state
backup_path "$target_cache" cache

mkdir -p "$config_home" "$data_home" "$state_home" "$cache_home" "$user_home/notes/dailies"
mv -- "$staged_config" "$target_config"

if [[ $made_backup -eq 1 ]]; then
  printf 'Previous Neovim files backed up to %s\n' "$backup_root"
fi

if [[ $skip_plugins -eq 0 ]]; then
  printf 'Restoring pinned plugins and installing editor tools…\n'
  nvim --headless \
    "+Lazy! restore" \
    "+Lazy! load mason.nvim" \
    "+lua dofile(vim.fn.stdpath('config') .. '/scripts/bootstrap.lua')" \
    "+qa"
fi

doctor_args=()
if [[ $skip_plugins -eq 1 ]]; then
  doctor_args+=(--skip-plugins)
fi
"$target_config/scripts/doctor.sh" "${doctor_args[@]}"

printf '\nNeovim is ready. Launch it with: nvim\n'
printf 'For matching icons, choose JetBrains Mono plus 0xProto Nerd Font fallback in your terminal.\n'
