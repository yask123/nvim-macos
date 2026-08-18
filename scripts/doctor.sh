#!/usr/bin/env bash

set -uo pipefail

failures=0
warnings=0

ok() { printf '[ok]   %s\n' "$1"; }
fail() {
  printf '[fail] %s\n' "$1" >&2
  failures=$((failures + 1))
}
warn() {
  printf '[warn] %s\n' "$1"
  warnings=$((warnings + 1))
}

if [[ "$(uname -s)" == "Darwin" ]]; then
  ok "macOS $(sw_vers -productVersion) ($(uname -m))"
else
  fail "macOS is required by the bootstrap"
fi

for command_name in brew nvim git rg fd fzf lazygit tree-sitter node python3 lua; do
  if command -v "$command_name" >/dev/null 2>&1; then
    ok "$command_name"
  else
    fail "$command_name is missing"
  fi
done

if command -v nvim >/dev/null 2>&1; then
  if nvim --clean --headless "+lua local v=vim.version(); assert(v.major > 0 or v.minor >= 11, 'Neovim 0.11+ required')" "+qa" >/dev/null 2>&1; then
    ok "Neovim version is supported"
  else
    fail "Neovim 0.11+ is required"
  fi
fi

if command -v brew >/dev/null 2>&1; then
  for font in font-jetbrains-mono font-0xproto-nerd-font; do
    if brew list --cask "$font" >/dev/null 2>&1; then
      ok "$font"
    else
      fail "$font is missing"
    fi
  done
fi

user_home="${HOME:?HOME is not set}"
config_home="${XDG_CONFIG_HOME:-$user_home/.config}"
config_dir="$config_home/nvim"

if [[ -f "$config_dir/init.lua" && -f "$config_dir/lazy-lock.json" ]]; then
  ok "Neovim config and plugin lock"
else
  fail "expected config at $config_dir"
fi

if command -v nvim >/dev/null 2>&1 && [[ -f "$config_dir/init.lua" ]]; then
  if startup_output="$(nvim --headless "+lua local c=require('lazy.core.config'); local missing={}; for name,p in pairs(c.plugins) do if not p._.installed then table.insert(missing,name) end end; assert(#missing == 0, 'missing plugins: '..table.concat(missing, ', ')); print('startup ok')" "+qa" 2>&1)"; then
    ok "headless startup and pinned plugins"
  else
    fail "Neovim startup failed: $startup_output"
  fi

  if mason_output="$(nvim --headless "+Lazy! load mason.nvim" "+lua local r=require('mason-registry'); local names={'basedpyright','black','json-lsp','lua-language-server','prettier','ruff','shfmt','stylua','vtsls'}; local missing={}; for _,n in ipairs(names) do if not r.is_installed(n) then table.insert(missing,n) end end; assert(#missing == 0, 'missing Mason tools: '..table.concat(missing, ', ')); print('mason ok')" "+qa" 2>&1)"; then
    ok "Mason language and formatting tools"
  else
    fail "$mason_output"
  fi
fi

if [[ -d "$user_home/notes" ]]; then
  ok "notes workspace"
else
  warn "$user_home/notes is absent; Obsidian commands will have no workspace"
fi

for optional_command in claude go cargo; do
  if command -v "$optional_command" >/dev/null 2>&1; then
    ok "$optional_command (optional)"
  else
    warn "$optional_command is optional and not installed"
  fi
done

printf '\nDoctor finished: %d failure(s), %d warning(s).\n' "$failures" "$warnings"
[[ $failures -eq 0 ]]
