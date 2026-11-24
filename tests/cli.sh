#!/usr/bin/env bash
# The `code` command against a running editor: folders, files at a line,
# standard input, comparing, waiting. Needs the config and its plugins in
# place (tests/isolated.sh runs it inside its sandbox).

set -Eeuo pipefail

config="${1:?usage: cli.sh <config dir>}"
work="$(mktemp -d "${TMPDIR:-/tmp}/code-cli.XXXXXX")"
socket="$work/s.sock"
editor=""

cleanup() {
  [[ -n "$editor" ]] && kill "$editor" 2>/dev/null || true
  rm -rf -- "$work"
}
trap cleanup EXIT

fail() {
  printf 'cli: %s\n' "$1" >&2
  exit 1
}

# An "app" to find: the command checks one is installed before anything else.
mkdir -p "$work/Fake.app/Contents/MacOS"
printf '#!/bin/sh\nexit 0\n' >"$work/Fake.app/Contents/MacOS/Fake"
chmod +x "$work/Fake.app/Contents/MacOS/Fake"
export DOJO_NEOVIDE_APP="$work/Fake.app" DOJO_SOCKET="$socket" DOJO_NO_FOCUS=1 TMPDIR="$work"
code="$config/scripts/dojo"

mkdir -p "$work/one/sub" "$work/two"
git -C "$work/one" init -q
printf 'a\nb\nc\nd\ne\n' >"$work/one/sub/notes.txt"
printf 'x\ny\n' >"$work/one/left.txt"
printf 'x\nY\n' >"$work/one/right.txt"
printf 'hello\n' >"$work/two/loose.txt"

(cd "$work/two" && NVIM_SFX=0 exec nvim --headless -u "$config/init.lua" --listen "$socket") >/dev/null 2>&1 &
editor=$!
for _ in $(seq 1 100); do
  [[ -S "$socket" ]] && break
  sleep 0.1
done
[[ -S "$socket" ]] || fail "the editor did not start"
ask() { nvim --server "$socket" --remote-expr "$1"; }
ask "execute('doautocmd User VeryLazy')" >/dev/null
sleep 0.5

[[ "$("$code" --version | head -n 1)" == "Code $(cat "$config/VERSION")" ]] || fail "--version"
"$code" --help | grep -q -- "--wait" || fail "--help"
"$code" --bogus >/dev/null 2>&1 && fail "an unknown option should fail"
"$code" "$work/missing/dir/file" >/dev/null 2>&1 && fail "a path that can't exist should fail"

# A file in a git repository brings the repository along, at the line asked for.
"$code" "$work/one/sub/notes.txt:3:1"
sleep 0.6
[[ "$(ask "fnamemodify(getcwd(), ':t')")" == "one" ]] || fail "the repository should be the project"
[[ "$(ask "expand('%:t') . ':' . line('.')")" == "notes.txt:3" ]] || fail "file:line should open at the line"

# A folder becomes the project.
"$code" "$work/two"
sleep 0.6
[[ "$(ask "fnamemodify(getcwd(), ':t')")" == "two" ]] || fail "a folder should open as the project"
ask "execute('lua for _, p in ipairs(Snacks.picker.get()) do p:close() end')" >/dev/null

# Piped text is an untitled page.
printf 'piped\n' | "$code" -
sleep 0.4
[[ "$(ask "getline(1) . '/' . &modified")" == "piped/1" ]] || fail "standard input should become an untitled page"

# Two files side by side.
"$code" --diff "$work/one/left.txt" "$work/one/right.txt"
sleep 0.4
[[ "$(ask "&diff . '/' . tabpagenr('\$')")" == "1/2" ]] || fail "--diff should compare in a tab of its own"
ask "execute('tabclose')" >/dev/null

# --wait returns when the file is closed, and not before; the project stays put.
"$code" --wait "$work/one/sub/notes.txt" &
waiter=$!
sleep 1.2
kill -0 "$waiter" 2>/dev/null || fail "--wait returned while the file was open"
[[ "$(ask "fnamemodify(getcwd(), ':t')")" == "two" ]] || fail "--wait must not switch project"
ask "execute('bdelete')" >/dev/null
for _ in $(seq 1 30); do
  kill -0 "$waiter" 2>/dev/null || break
  sleep 0.2
done
kill -0 "$waiter" 2>/dev/null && fail "--wait did not return after the file was closed"

printf 'cli: ok\n'
