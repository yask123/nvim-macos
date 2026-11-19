#!/usr/bin/env bash
# Code: install or upgrade on a Mac, in one command.
#
#   bash -c "$(curl -fsSL https://yask.dev/code/install)"
#
# In order: checks this Mac, installs the tools the editor needs (Homebrew
# does the work), puts the editor's files in ~/.config/nvim, restores the
# pinned plugins, builds ~/Applications/Code.app and runs a health check.
#
# An earlier install (Code, or Dojo as the app was first called) is upgraded
# in place: the old app is removed, and your sessions, recent projects and
# settings stay. Any other Neovim setup is moved to a backup, never deleted.
#
# Written for the bash 3.2 that ships with macOS.

set -Eeuo pipefail

repo_url="${NVIM_BOOTSTRAP_REPO:-https://github.com/yask123/nvim-macos.git}"
repo_ref="${NVIM_BOOTSTRAP_REF:-main}"
skip_brew=0
skip_plugins=0
with_app=1
fresh=0
assume_yes=0
open_after=1
temporary_root=""
user_home="${HOME:?HOME is not set}"

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Installs Code (a quiet code editor built on Neovim) on macOS, or upgrades an
earlier install in place.

  --fresh          Start clean even over an earlier install (everything from
                   before is moved to a backup, including sessions and settings)
  --no-app         Set up Neovim only; skip Code.app
  --no-open        Don't open Code when the install finishes
  --yes            Answer yes to questions (quit a running Code, for example)
  --skip-brew      Don't install tools with Homebrew (they must be there already)
  --skip-plugins   Don't restore plugins or language tools
  --ref <tag>      Install a specific version (default: main)
  -h, --help       Show this help

Environment overrides:
  NVIM_BOOTSTRAP_REPO  Git repository URL
  NVIM_BOOTSTRAP_REF   Git branch or tag (default: main)
  NO_COLOR             Plain output
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-brew) skip_brew=1 ;;
    --skip-plugins) skip_plugins=1 ;;
    --no-app) with_app=0 ;;
    --no-open) open_after=0 ;;
    --fresh) fresh=1 ;;
    --yes | -y) assume_yes=1 ;;
    --ref)
      [[ $# -ge 2 ]] || {
        usage >&2
        exit 2
      }
      repo_ref="$2"
      shift
      ;;
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

# ---- How it looks -----------------------------------------------------------
# One line per step. On a terminal, long steps show a spinner, the time so far
# and what they are doing; everything they print goes to a log instead.

live=0
[[ -t 1 && "${TERM:-dumb}" != dumb ]] && live=1
neon="" dim="" bold="" amber="" red="" off=""
if [[ $live -eq 1 && -z "${NO_COLOR:-}" ]]; then
  neon=$'\033[38;5;84m' dim=$'\033[2m' bold=$'\033[1m'
  amber=$'\033[38;5;215m' red=$'\033[38;5;203m' off=$'\033[0m'
fi
frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

log="$user_home/Library/Logs/code-install.log"
mkdir -p "$(dirname -- "$log")" 2>/dev/null || log="${TMPDIR:-/tmp}/code-install.log"
: >"$log" 2>/dev/null || log=/dev/null

heading() { printf '\n  %s%s%s\n' "$bold" "$1" "$off"; }
ok() { printf '  %s✓%s %s%s%s\n' "$neon" "$off" "$1" "${2:+  $dim$2$off}" ""; }
note() { printf '  %s·%s %s%s%s\n' "$dim" "$off" "$dim" "$1" "$off"; }
warn() { printf '  %s!%s %s\n' "$amber" "$off" "$1"; }

show_cursor() { [[ $live -eq 1 ]] && printf '\033[?25h' || true; }

# Stop with a reason and, when it helps, what to do next (one line each).
die() {
  show_cursor
  printf '\n  %s✗%s %s\n' "$red" "$off" "$1" >&2
  shift
  while [[ $# -gt 0 ]]; do
    printf '    %s\n' "$1" >&2
    shift
  done
  printf '\n' >&2
  exit 1
}

took() {
  local seconds=$((SECONDS - $1))
  if [[ $seconds -ge 60 ]]; then
    printf '%dm %02ds' $((seconds / 60)) $((seconds % 60))
  elif [[ $seconds -ge 3 ]]; then
    printf '%ds' "$seconds"
  fi
}

# step "What is happening" command args…
# Runs the command with its output in the log. Returns the command's status.
step() {
  local label="$1"
  shift
  local started=$SECONDS status=0
  printf '\n=== %s\n' "$label" >>"$log"
  if [[ $live -eq 1 ]]; then
    "$@" >>"$log" 2>&1 &
    local pid=$! frame=0 detail="" columns
    columns="$(tput cols 2>/dev/null || printf '80')"
    printf '\033[?25l'
    while kill -0 "$pid" 2>/dev/null; do
      if [[ $((frame % 5)) -eq 0 && "$log" != /dev/null ]]; then
        # The last thing the step said, as a quiet hint of progress.
        detail="$(tail -n 1 "$log" 2>/dev/null | LC_ALL=C sed $'s/\033\\[[0-9;?]*[a-zA-Z]//g' |
          LC_ALL=C tr -d '\000-\037\177' | tr -s ' ' | cut -c1-$((columns > 60 ? 44 : 16)))"
        [[ "$detail" == "=== "* ]] && detail=""
      fi
      printf '\r\033[K  %s%s%s %s  %s%s%s%s' "$neon" "${frames[frame % 10]}" "$off" "$label" \
        "$dim" "$(took "$started")" "${detail:+  $detail}" "$off"
      frame=$((frame + 1))
      sleep 0.1
    done
    wait "$pid" || status=$?
    printf '\r\033[K'
    show_cursor
  else
    "$@" >>"$log" 2>&1 || status=$?
  fi
  if [[ $status -eq 0 ]]; then
    ok "$label" "$(took "$started")"
  else
    printf '  %s✗%s %s\n' "$red" "$off" "$label" >&2
  fi
  return $status
}

# A step that must work. On failure: the end of what it printed, and the log.
must() {
  if ! step "$@"; then
    show_cursor
    if [[ "$log" != /dev/null ]]; then
      printf '\n' >&2
      tail -n 12 "$log" | sed 's/^/    /' >&2
      printf '\n    The full log is in %s\n' "$log" >&2
    fi
    printf '    Nothing is lost: fix the problem above and run the same command again.\n\n' >&2
    exit 1
  fi
}

# Ask a yes/no question on the terminal (the default is yes). Without a
# terminal to ask on, the answer is --yes or no.
confirm() {
  [[ $assume_yes -eq 1 ]] && return 0
  [[ $live -eq 1 && -r /dev/tty ]] || return 1
  local answer=""
  printf '  %s?%s %s %s[Y/n]%s ' "$neon" "$off" "$1" "$dim" "$off"
  read -r answer </dev/tty || return 1
  case "$answer" in
    "" | y | Y | yes | Yes | YES) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup() {
  show_cursor
  if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
    rm -rf -- "$temporary_root"
  fi
}
trap cleanup EXIT
trap 'show_cursor; printf "\n\n  Stopped.\n\n" >&2; exit 130' INT TERM

printf '\n  %s%sc o d e%s\n  %sA quiet code editor for the Mac, built on Neovim.%s\n' "$neon" "$bold" "$off" "$dim" "$off"

# ---- This Mac ---------------------------------------------------------------

heading "Checking this Mac"

[[ "$(uname -s)" == "Darwin" ]] || die "Code is a Mac app; this is $(uname -s)." \
  "The Neovim config itself is portable: clone the repository into ~/.config/nvim."

macos_version="$(sw_vers -productVersion 2>/dev/null || printf '0')"
if [[ "${macos_version%%.*}" -lt 13 ]]; then
  die "macOS 13 (Ventura) or newer is needed; this Mac has $macos_version." \
    "Update macOS in System Settings › General › Software Update."
fi
chip="Apple silicon"
[[ "$(uname -m)" == "arm64" ]] || chip="Intel"
ok "macOS $macos_version" "$chip"

# Room for the tools, plugins and language servers (about 2 GB on a new Mac).
free_gb="$(df -g "$user_home" 2>/dev/null | awk 'NR == 2 { print $4 }')"
if [[ "$free_gb" =~ ^[0-9]+$ ]]; then
  if [[ $free_gb -lt 2 ]]; then
    die "Only $free_gb GB of disk space is free; Code needs about 2 GB." \
      "Free some space, then run this again."
  elif [[ $free_gb -lt 5 ]]; then
    warn "$free_gb GB of disk space free: enough, but it is getting tight"
  else
    ok "Disk space" "$free_gb GB free"
  fi
fi

# The network is needed unless every piece is already on this Mac.
needs_network=1
if [[ $skip_brew -eq 1 && $skip_plugins -eq 1 && "$repo_url" != http* && "$repo_url" != git@* ]]; then
  needs_network=0
fi
if [[ $needs_network -eq 1 ]]; then
  if curl -fsI --max-time 10 https://github.com >/dev/null 2>&1; then
    ok "Internet" "github.com answers"
  else
    die "Can't reach github.com." "Check the internet connection, then run this again."
  fi
fi

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
if [[ $skip_brew -eq 0 ]]; then
  if command -v brew >/dev/null 2>&1; then
    ok "Homebrew"
  else
    [[ $live -eq 1 || $assume_yes -eq 1 ]] ||
      die "Homebrew isn't installed, and its installer needs a terminal." \
        "Open Terminal and run this command there."
    note "Homebrew isn't installed yet. Its own installer runs next; it asks for"
    note "your Mac password and takes a few minutes."
    printf '\n'
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" ||
      die "Homebrew's installer didn't finish." "Run this command again once it does (see https://brew.sh)."
    printf '\n'
    load_brew
    command -v brew >/dev/null 2>&1 ||
      die "Homebrew was installed but isn't on the PATH." "Open a new Terminal window and run this again."
    ok "Homebrew" "just installed"
  fi
fi

# Login shells need Homebrew on PATH too: Neovide (the Code app) starts
# Neovim through one, and it only reads ~/.zprofile. Homebrew's installer
# only suggests this line, so add it (once) if it's missing.
persist_brew_path() {
  local brew_bin profile line
  brew_bin="$(command -v brew || true)"
  [[ -n "$brew_bin" ]] || return 0
  line="eval \"\$($brew_bin shellenv)\""
  for profile in "$user_home/.zprofile" "$user_home/.bash_profile"; do
    [[ "$profile" == */.bash_profile && "${SHELL:-}" != */bash ]] && continue
    if ! grep -qs "brew shellenv" "$profile"; then
      printf '\n# Homebrew (added by the Code installer so apps can find its tools)\n%s\n' "$line" >>"$profile"
      note "Added Homebrew to ${profile/#$user_home/~} so apps can find its tools"
    fi
  done
}
persist_brew_path

# Git comes with Apple's Command Line Tools (Homebrew's installer adds them).
if ! command -v git >/dev/null 2>&1 || ! git --version >/dev/null 2>&1; then
  xcode-select --install >/dev/null 2>&1 || true
  die "Apple's Command Line Tools are missing (Git comes with them)." \
    "A system window just asked to install them. When it finishes, run this again."
fi
ok "Command Line Tools" "$(git --version | awk '{ print "git " $3 }')"

# ---- What is here already ---------------------------------------------------

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
      die "Refusing unsafe target: $target"
      ;;
  esac
done

apps_dir="${DOJO_APP_DIR:-$user_home/Applications}"

# "earlier": Code (or Dojo, its first name) is installed; upgrade in place.
# "other":   some other Neovim setup; it moves to a backup.
# "none":    a Mac without Neovim files.
existing="none"
if [[ -f "$target_config/lua/dojo/init.lua" ]]; then
  existing="earlier"
elif [[ -e "$target_config" || -L "$target_config" || -e "$target_data" || -e "$target_state" ]]; then
  existing="other"
fi
[[ $fresh -eq 1 && "$existing" == "earlier" ]] && existing="other"

case "$existing" in
  earlier)
    if [[ -d "$apps_dir/Dojo.app" ]]; then
      ok "Found Dojo, the app's earlier name" "it becomes Code"
    else
      ok "Found an earlier install" "upgrading it"
    fi
    ;;
  other) ok "Found another Neovim setup" "it will be saved in a backup" ;;
esac

# Nothing can be replaced under a running editor. Offer to quit the app;
# a Neovim left in a terminal is yours to close.
app_open() {
  pgrep -qf -- "$apps_dir/Code.app/Contents/MacOS/" || pgrep -qf -- "$apps_dir/Dojo.app/Contents/MacOS/"
}
quit_app() {
  osascript -e 'tell application id "dev.dojo.editor" to quit' >/dev/null 2>&1 || true
  local waited=0
  while app_open && [[ $waited -lt 100 ]]; do
    sleep 0.1
    waited=$((waited + 1))
  done
  ! app_open
}
if app_open; then
  if confirm "Code is open. Quit it and carry on?"; then
    quit_app || die "Code didn't quit." "Quit it yourself (⌘Q), then run this again."
    ok "Quit Code"
  else
    die "Code is open." "Quit it (⌘Q), then run this again."
  fi
fi
if pgrep -x nvim >/dev/null 2>&1; then
  die "Neovim is running, probably in a terminal." \
    "Save your work and quit it (:qa), then run this again."
fi

# ---- The editor's files -----------------------------------------------------

if [[ "$existing" == "earlier" ]]; then
  heading "Upgrading"
else
  heading "Installing"
fi

script_source="${BASH_SOURCE[0]:-}"
source_dir=""
if [[ -n "$script_source" && -f "$script_source" ]]; then
  candidate_dir="$(CDPATH='' cd -- "$(dirname -- "$script_source")" && pwd)"
  # Use this copy only if it is a Git checkout of its own; a release archive
  # (the Homebrew cask) installs the matching tag from GitHub instead.
  if [[ -f "$candidate_dir/Brewfile" && -f "$candidate_dir/init.lua" ]] &&
    [[ "$(git -C "$candidate_dir" rev-parse --show-toplevel 2>/dev/null)" == "$(cd -P -- "$candidate_dir" && pwd)" ]]; then
    source_dir="$candidate_dir"
  fi
fi

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/nvim-bootstrap.XXXXXX")"
staged_config=""
if [[ -z "$source_dir" ]]; then
  staged_config="$temporary_root/source"
  must "Fetching Code" git clone --quiet --depth 1 --branch "$repo_ref" "$repo_url" "$staged_config"
  source_dir="$staged_config"
fi
version="$(tr -d '[:space:]' <"$source_dir/VERSION" 2>/dev/null || true)"

# ---- Tools ------------------------------------------------------------------

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
  # A font or Neovide put there by hand stays as it is.
  cask_skip="${HOMEBREW_BUNDLE_CASK_SKIP:-}"
  if ! brew list --cask font-monaspice-nerd-font >/dev/null 2>&1 && font_file_exists '*MonaspiceNeNerdFont*'; then
    append_cask_skip font-monaspice-nerd-font
  fi
  if ! brew list --cask neovide-app >/dev/null 2>&1 && [[ -d /Applications/Neovide.app ]]; then
    append_cask_skip neovide-app
  fi
  export HOMEBREW_BUNDLE_CASK_SKIP="$cask_skip"
  export HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1
  must "Tools, font and window" \
    brew bundle install --no-upgrade --file="$source_dir/Brewfile"
fi

# Whoever installed them, the tools the editor can't work without must be here.
missing=""
for tool in nvim git rg fd fzf node python3; do
  command -v "$tool" >/dev/null 2>&1 || missing="${missing:+$missing, }$tool"
done
if [[ -n "$missing" ]]; then
  die "Still missing: $missing." "Install them with Homebrew (brew bundle --file=Brewfile), then run this again."
fi
# (Asked with scratch folders, so the question leaves no Neovim files behind.)
if ! XDG_STATE_HOME="$temporary_root/probe" XDG_DATA_HOME="$temporary_root/probe" XDG_CACHE_HOME="$temporary_root/probe" \
  nvim --clean --headless "+lua local v=vim.version(); assert(v.major > 0 or v.minor > 11 or (v.minor == 11 and v.patch >= 2))" "+qa" >/dev/null 2>&1; then
  die "Neovim 0.11.2 or newer is needed; $(command -v nvim) is older." "Update it: brew upgrade neovim"
fi

# ---- Swap the files in ------------------------------------------------------

if [[ -z "$staged_config" ]]; then
  staged_config="$temporary_root/nvim"
  git clone --quiet "$source_dir" "$staged_config" >>"$log" 2>&1
  git -C "$staged_config" remote set-url origin "$repo_url"
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_parent="$state_home/nvim-bootstrap/backups"
backup_root=""

# An earlier install keeps its plugins, sessions, recent projects and settings
# where they are; only its config folder is set aside (it may hold edits).
if [[ "$existing" == "earlier" ]]; then
  backup_parent="$state_home/nvim-bootstrap/replaced"
fi

backup_path() {
  local path="$1"
  local label="$2"
  if [[ -e "$path" || -L "$path" ]]; then
    if [[ -z "$backup_root" ]]; then
      mkdir -p "$backup_parent"
      backup_root="$(mktemp -d "$backup_parent/$timestamp.XXXXXX")"
    fi
    mv -- "$path" "$backup_root/$label"
  fi
}

backup_path "$target_config" config
if [[ "$existing" != "earlier" ]]; then
  backup_path "$target_data" data
  backup_path "$target_state" state
  backup_path "$target_cache" cache
fi

mkdir -p "$config_home" "$data_home" "$state_home" "$cache_home"
mv -- "$staged_config" "$target_config"

user_bin="$user_home/.local/bin"
mkdir -p "$user_bin"
install -m 0755 "$target_config/scripts/update.sh" "$user_bin/nvim-update"

ok "Editor files${version:+ (Code $version)}" "${target_config/#$user_home/~}"
if [[ -n "$backup_root" ]]; then
  if [[ "$existing" == "earlier" ]]; then
    note "The previous version's files are in ${backup_root/#$user_home/~}"
  else
    note "Your previous Neovim setup is safe in ${backup_root/#$user_home/~}"
  fi
fi

# ---- Plugins, the app, a health check ---------------------------------------

if [[ $skip_plugins -eq 0 ]]; then
  must "Plugins and language tools" \
    "$target_config/scripts/restore-plugins.sh" "$target_config" \
    "+Lazy! load mason.nvim" \
    "+lua dofile(vim.fn.stdpath('config') .. '/scripts/bootstrap.lua')"
fi

# The old Homebrew entry (the cask was called dojo): forget it, so a later
# `brew uninstall dojo` can't take the new install with it. Only the record
# goes; nothing it installed is touched.
retire_old_cask() {
  local room
  case "$script_source" in */Caskroom/dojo/*) return 0 ;; esac
  for room in "${HOMEBREW_PREFIX:-/nonexistent}/Caskroom" /opt/homebrew/Caskroom /usr/local/Caskroom; do
    if [[ -d "$room/dojo" ]] && grep -rqs "yask123/nvim-macos" "$room/dojo/.metadata"; then
      rm -rf -- "${room:?}/dojo"
      ok "Retired the old Homebrew entry" "dojo"
      return 0
    fi
  done
}

app_built=0
if [[ $with_app -eq 1 ]]; then
  if [[ -d "${DOJO_NEOVIDE_APP:-/Applications/Neovide.app}" ]]; then
    had_dojo=0
    [[ -d "$apps_dir/Dojo.app" ]] && had_dojo=1
    must "Code.app" "$target_config/scripts/setup-dojo.sh"
    app_built=1
    if [[ $had_dojo -eq 1 && ! -d "$apps_dir/Dojo.app" ]]; then
      ok "Removed Dojo.app" "the old name"
    fi
    retire_old_cask
  else
    warn "Neovide isn't installed, so Code.app wasn't built (brew install --cask neovide-app, then run this again)"
  fi
fi

doctor_args=(--quiet)
[[ $skip_plugins -eq 1 ]] && doctor_args+=(--skip-plugins)
[[ $with_app -eq 0 ]] && doctor_args+=(--no-app)
doctor_status=0
doctor_output="$("$target_config/scripts/doctor.sh" "${doctor_args[@]}" 2>&1)" || doctor_status=$?
printf '\n=== Health check\n%s\n' "$doctor_output" >>"$log"
if [[ $doctor_status -eq 0 && -z "$doctor_output" ]]; then
  ok "Health check" "everything in place"
else
  # The doctor prints only what needs attention; show it as it is.
  printf '%s\n' "$doctor_output"
  if [[ $doctor_status -ne 0 ]]; then
    die "The health check found a problem (above)." \
      "Fix it, then run: nvim-update" "The full log is in $log"
  fi
fi

# ---- Done -------------------------------------------------------------------

printf '\n'
if [[ $app_built -eq 1 ]]; then
  if [[ "$existing" == "earlier" ]]; then
    printf '  %s%sCode is up to date.%s Your projects and settings are as you left them.\n' "$neon" "$bold" "$off"
  else
    printf '  %s%sCode is ready.%s\n' "$neon" "$bold" "$off"
  fi
  printf '  %sOpen it from Spotlight: ⌘Space, then type "Code". Update any time with nvim-update.%s\n\n' "$dim" "$off"
  if [[ $open_after -eq 1 && $live -eq 1 ]]; then
    open "$apps_dir/Code.app" >/dev/null 2>&1 || true
  fi
else
  printf '  %s%sNeovim is ready.%s Start it with: nvim\n' "$neon" "$bold" "$off"
  printf '  %sFor the Code app later, run %s/scripts/setup-dojo.sh. Update with nvim-update.%s\n\n' \
    "$dim" "${target_config/#$user_home/~}" "$off"
fi
