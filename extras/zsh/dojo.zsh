# Code shell helpers. Source from ~/.zshrc:
#   [[ -r ~/.config/nvim/extras/zsh/dojo.zsh ]] && source ~/.config/nvim/extras/zsh/dojo.zsh

# The commands live in ~/.local/bin, which a fresh Mac doesn't have on PATH.
[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || path+=("$HOME/.local/bin")

# `code .` opens this folder in the Code app, `code file:42` a file at a line,
# `code -w file` waits (git config --global core.editor "dojo -w"). A function,
# so it wins over VS Code's `code` wherever that sits on the PATH; VS Code's
# stays one word away as `vscode`.
# (`function name` form: immune to an existing `alias code=...`.)
unalias code dojo vscode v vt 2>/dev/null
function code { "$HOME/.local/bin/dojo" "$@"; }
if [[ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
  function vscode { "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" "$@"; }
fi

# `v` is the short form: `v` alone opens the current folder, `v file` /
# `v folder` opens that. `vt` stays in the terminal.
function v { "$HOME/.local/bin/dojo" "${@:-.}"; }
function vt { nvim "$@"; }
