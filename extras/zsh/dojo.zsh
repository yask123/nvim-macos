# Dojo shell helpers. Source from ~/.zshrc:
#   [[ -r ~/.config/nvim/extras/zsh/dojo.zsh ]] && source ~/.config/nvim/extras/zsh/dojo.zsh

# `dojo` lives in ~/.local/bin, which a fresh Mac doesn't have on PATH.
[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || path+=("$HOME/.local/bin")

# `v` edits like `code`: `v` alone opens the current folder in the Dojo app,
# `v file` / `v folder` opens that. `vt` stays in the terminal.
# (`function name` form: immune to an existing `alias v=...`.)
unalias v vt 2>/dev/null
function v { dojo "${@:-.}"; }
function vt { nvim "$@"; }
