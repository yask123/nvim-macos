#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/nvim-macos-update.XXXXXX")"

cleanup() {
  if [[ -n "$test_root" && -d "$test_root" ]]; then
    rm -rf -- "$test_root"
  fi
}
trap cleanup EXIT

seed="$test_root/seed"
origin="$test_root/origin.git"
publisher="$test_root/publisher"
test_home="$test_root/home"
test_config="$test_home/.config/nvim"
fake_bin="$test_root/bin"

mkdir -p "$seed" "$fake_bin"
rsync -a --exclude .git "$repo_root/" "$seed/"

cat >"$seed/scripts/doctor.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
: >"${UPDATE_TEST_DOCTOR:?}"
EOF
chmod +x "$seed/scripts/doctor.sh" "$seed/scripts/update.sh"

git -C "$seed" init --quiet --initial-branch main
git -C "$seed" config user.name "nvim-macos test"
git -C "$seed" config user.email "nvim-macos@example.invalid"
git -C "$seed" add .
git -C "$seed" commit --quiet -m initial

git clone --quiet --bare "$seed" "$origin"
git clone --quiet "$origin" "$test_config"
git clone --quiet "$origin" "$publisher"
git -C "$publisher" config user.name "nvim-macos test"
git -C "$publisher" config user.email "nvim-macos@example.invalid"

printf 'updated\n' >"$publisher/update-marker"
git -C "$publisher" add update-marker
git -C "$publisher" commit --quiet -m update
git -C "$publisher" push --quiet origin main

cat >"$fake_bin/nvim" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >"${UPDATE_TEST_NVIM:?}"
EOF
cat >"$fake_bin/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$fake_bin/nvim" "$fake_bin/pgrep"

export HOME="$test_home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export UPDATE_TEST_DOCTOR="$test_root/doctor-ran"
export UPDATE_TEST_NVIM="$test_root/nvim-ran"
export PATH="$fake_bin:$PATH"

"$test_config/scripts/update.sh"

[[ -f "$test_config/update-marker" ]]
[[ -x "$HOME/.local/bin/nvim-update" ]]
[[ -f "$UPDATE_TEST_DOCTOR" ]]
[[ -f "$UPDATE_TEST_NVIM" ]]
git -C "$test_config" diff --quiet HEAD origin/main

printf 'local change\n' >>"$test_config/update-marker"
if "$test_config/scripts/update.sh" --skip-plugins >/dev/null 2>&1; then
  printf 'Updater should refuse a dirty config checkout\n' >&2
  exit 1
fi

printf 'Updater fast-forward and dirty-check test passed\n'
