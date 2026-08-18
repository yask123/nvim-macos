#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/nvim-macos-test.XXXXXX")"
source_status_before="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"

cleanup() {
  if [[ -n "$test_root" && -d "$test_root" ]]; then
    rm -rf -- "$test_root"
  fi
}
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/data" "$test_root/state" "$test_root/cache"
cp -R "$repo_root" "$test_root/config/nvim"
test_config="$test_root/config/nvim"

export XDG_CONFIG_HOME="$test_root/config"
export XDG_DATA_HOME="$test_root/data"
export XDG_STATE_HOME="$test_root/state"
export XDG_CACHE_HOME="$test_root/cache"
export NVIM_SKIP_MASON_INSTALL=1

restore_log="$test_root/lazy-restore.log"
if ! nvim --headless "+Lazy! restore" "+qa" >"$restore_log" 2>&1; then
  printf 'Lazy restore failed:\n' >&2
  tail -n 200 "$restore_log" >&2
  exit 1
fi
nvim --headless "+luafile $test_config/tests/smoke.lua" "+qa"

if ! cmp -s "$repo_root/lazy-lock.json" "$test_config/lazy-lock.json"; then
  printf 'Fresh restore changed lazy-lock.json:\n' >&2
  diff -u "$repo_root/lazy-lock.json" "$test_config/lazy-lock.json" >&2 || true
  exit 1
fi

source_status_after="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"
if [[ "$source_status_after" != "$source_status_before" ]]; then
  printf 'Smoke test mutated the source repository:\n' >&2
  diff -u <(printf '%s\n' "$source_status_before") <(printf '%s\n' "$source_status_after") >&2 || true
  exit 1
fi
