#!/usr/bin/env bash
# Opt-in desktop setup for Dojo (safe to re-run):
#   - links extras/neovide/config.toml → ~/.config/neovide/config.toml
#   - links extras/ghostty/config      → ~/.config/ghostty/config (only if you have none)
#   - sources extras/zsh/dojo.zsh from ~/.zshrc (`v <path>` opens it in Dojo)
#   - builds ~/Applications/Dojo.app and links the `dojo` command
# Existing files are never overwritten; the script tells you what it skipped.

set -Eeuo pipefail

config_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
xdg="${XDG_CONFIG_HOME:-$HOME/.config}"

link() {
  local source="$1" target="$2"
  mkdir -p "$(dirname -- "$target")"
  if [[ -L "$target" && "$(realpath "$target")" == "$(realpath "$source")" ]]; then
    printf '[ok]   %s\n' "$target"
  elif [[ -e "$target" || -L "$target" ]]; then
    printf '[skip] %s exists; merge %s by hand if you want it\n' "$target" "$source"
  else
    ln -s "$source" "$target"
    printf '[new]  %s → %s\n' "$target" "$source"
  fi
}

link "$config_dir/extras/neovide/config.toml" "$xdg/neovide/config.toml"
link "$config_dir/extras/ghostty/config" "$xdg/ghostty/config"

zsh_line='[[ -r ~/.config/nvim/extras/zsh/dojo.zsh ]] && source ~/.config/nvim/extras/zsh/dojo.zsh'
if grep -qF "extras/zsh/dojo.zsh" "$HOME/.zshrc" 2>/dev/null; then
  printf '[ok]   ~/.zshrc sources dojo.zsh\n'
else
  printf '\n# Dojo (Neovim) shell helpers: v <path> opens it in Dojo\n%s\n' "$zsh_line" >>"$HOME/.zshrc"
  printf '[new]  ~/.zshrc now sources dojo.zsh (open a new terminal)\n'
fi

"$config_dir/scripts/make-app.sh"
