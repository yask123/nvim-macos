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

fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$fake_bin/pgrep"
export PATH="$fake_bin:$PATH"

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

first_run="$("$repo_root/install.sh" --skip-brew --skip-plugins --no-app)"
# Someone else's Neovim setup: said so, and moved to a backup.
grep -q "Found another Neovim setup" <<<"$first_run"
grep -q "Neovim is ready" <<<"$first_run"

[[ -f "$XDG_CONFIG_HOME/nvim/init.lua" ]]
[[ -x "$HOME/.local/bin/nvim-update" ]]
[[ -f "$HOME/Documents/Folio/keep.txt" ]]
[[ -f "$HOME/.vim/keep.txt" ]]

backup_root="$(find "$XDG_STATE_HOME/nvim-bootstrap/backups" -mindepth 1 -maxdepth 1 -type d -print -quit)"
[[ -n "$backup_root" ]]
for label in config data state cache; do
  [[ -f "$backup_root/$label/sentinel" ]]
done

# Running it again is an upgrade: the config is replaced (the old one set
# aside), and sessions, recent projects and settings stay where they are.
mkdir -p "$XDG_STATE_HOME/nvim" "$XDG_DATA_HOME/nvim"
printf 'mine\n' >"$XDG_STATE_HOME/nvim/dojo-projects.json"
printf 'plugins\n' >"$XDG_DATA_HOME/nvim/keep"
printf 'edited\n' >"$XDG_CONFIG_HOME/nvim/local-edit"
second_run="$("$repo_root/install.sh" --skip-brew --skip-plugins --no-app)"
grep -q "Found an earlier install" <<<"$second_run"
[[ "$(cat "$XDG_STATE_HOME/nvim/dojo-projects.json")" == "mine" ]]
[[ -f "$XDG_DATA_HOME/nvim/keep" ]]
[[ ! -e "$XDG_CONFIG_HOME/nvim/local-edit" ]]
replaced_root="$(find "$XDG_STATE_HOME/nvim-bootstrap/replaced" -mindepth 1 -maxdepth 1 -type d -print -quit)"
[[ -f "$replaced_root/config/local-edit" ]]
[[ ! -e "$replaced_root/state" ]]

# --fresh starts clean even over an earlier install.
"$repo_root/install.sh" --skip-brew --skip-plugins --no-app --fresh >/dev/null
[[ ! -e "$XDG_STATE_HOME/nvim/dojo-projects.json" ]]

# A Mac too old for the app, or an option that doesn't exist, stops early.
if "$repo_root/install.sh" --no-such-option >/dev/null 2>&1; then
  printf 'An unknown option should fail\n' >&2
  exit 1
fi

"$XDG_CONFIG_HOME/nvim/scripts/uninstall.sh"

[[ ! -e "$XDG_CONFIG_HOME/nvim" ]]
[[ -f "$HOME/Documents/Folio/keep.txt" ]]
[[ -f "$HOME/.vim/keep.txt" ]]

uninstalled_root="$(find "$XDG_STATE_HOME/nvim-bootstrap/uninstalled" -mindepth 1 -maxdepth 1 -type d -print -quit)"
[[ -f "$uninstalled_root/config/init.lua" ]]

printf 'Installer backup, upgrade and uninstall test passed\n'
