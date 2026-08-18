#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/nvim-macos-test.XXXXXX")"

cleanup() {
  if [[ -n "$test_root" && -d "$test_root" ]]; then
    rm -rf -- "$test_root"
  fi
}
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/data" "$test_root/state" "$test_root/cache"
ln -s "$repo_root" "$test_root/config/nvim"

export XDG_CONFIG_HOME="$test_root/config"
export XDG_DATA_HOME="$test_root/data"
export XDG_STATE_HOME="$test_root/state"
export XDG_CACHE_HOME="$test_root/cache"
export NVIM_SKIP_MASON_INSTALL=1

nvim --headless "+Lazy! restore" "+qa"
nvim --headless "+luafile $repo_root/tests/smoke.lua" "+qa"

if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
  printf 'Smoke test mutated the source repository:\n' >&2
  git -C "$repo_root" status --short >&2
  exit 1
fi
