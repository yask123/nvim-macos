#!/usr/bin/env bash
# Put the terminal command on the PATH: ~/.local/bin/code and ~/.local/bin/dojo
# both point at scripts/dojo. A `code` that belongs to something else at that
# spot is left alone. (VS Code's own `code`, usually /usr/local/bin/code, is
# never touched; extras/zsh/dojo.zsh makes `code` mean this editor in your
# shell and keeps VS Code's reachable as `vscode`.)

set -Eeuo pipefail

config_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bin_dir="${DOJO_BIN_DIR:-$HOME/.local/bin}"
target="$config_dir/scripts/dojo"
mkdir -p "$bin_dir"

for name in code dojo; do
  bin="$bin_dir/$name"
  if [[ -e "$bin" && ! -L "$bin" ]] || { [[ -L "$bin" ]] && [[ "$(realpath "$bin" 2>/dev/null)" != "$(realpath "$target")" ]]; }; then
    printf 'Skipping %s: it belongs to something else\n' "$bin"
  else
    ln -sf "$target" "$bin"
  fi
done

# Another program's `code` comes first on the PATH and ~/.zshrc doesn't yet
# make this one win: say how.
first="$(PATH="$PATH" command -v code 2>/dev/null || true)"
if [[ -n "$first" && "$(realpath "$first" 2>/dev/null)" != "$(realpath "$target")" ]] &&
  ! grep -qF "extras/zsh/dojo.zsh" "$HOME/.zshrc" 2>/dev/null; then
  # shellcheck disable=SC2016 # backticks are part of the sentence
  printf '`code` in new terminals: source %s from ~/.zshrc (the installer does), or put %s first on your PATH.\n' \
    "$config_dir/extras/zsh/dojo.zsh" "$bin_dir"
fi
