#!/usr/bin/env bash

set -uo pipefail

failures=0
warnings=0
skip_plugins=0
strict=0
user_home="${HOME:?HOME is not set}"

usage() {
  cat <<'EOF'
Usage: ./scripts/doctor.sh [--skip-plugins] [--strict]

  --skip-plugins  Check only the system dependencies and config files.
  --strict        Treat optional-tool warnings as failures.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-plugins) skip_plugins=1 ;;
    --strict) strict=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

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

for command_name in brew nvim git rg fd fzf lazygit tree-sitter node python3 lua cc; do
  if command -v "$command_name" >/dev/null 2>&1; then
    ok "$command_name"
  else
    fail "$command_name is missing"
  fi
done

if command -v nvim >/dev/null 2>&1; then
  if nvim --clean --headless "+lua local v=vim.version(); assert(v.major > 0 or v.minor > 11 or (v.minor == 11 and v.patch >= 2), 'Neovim 0.11.2+ required'); assert(jit, 'LuaJIT required')" "+qa" >/dev/null 2>&1; then
    ok "Neovim 0.11.2+ with LuaJIT"
  else
    fail "Neovim 0.11.2+ with LuaJIT is required"
  fi
fi

if command -v git >/dev/null 2>&1; then
  git_version="$(git --version | awk '{ print $3 }')"
  git_major="${git_version%%.*}"
  git_remainder="${git_version#*.}"
  git_minor="${git_remainder%%.*}"
  if [[ "$git_major" =~ ^[0-9]+$ && "$git_minor" =~ ^[0-9]+$ ]] &&
    ((git_major > 2 || (git_major == 2 && git_minor >= 19))); then
    ok "Git $git_version"
  else
    fail "Git 2.19+ is required (found $git_version)"
  fi
fi

font_file_exists() {
  local pattern="$1"
  local font_dir
  local match
  for font_dir in "$user_home/Library/Fonts" /Library/Fonts; do
    [[ -d "$font_dir" ]] || continue
    match="$(find "$font_dir" -maxdepth 1 -type f -iname "$pattern" -print -quit 2>/dev/null)"
    if [[ -n "$match" ]]; then
      return 0
    fi
  done
  return 1
}

if { command -v brew >/dev/null 2>&1 && brew list --cask font-jetbrains-mono >/dev/null 2>&1; } ||
  font_file_exists '*JetBrainsMono*'; then
  ok "JetBrains Mono font"
else
  fail "JetBrains Mono font is missing"
fi

if { command -v brew >/dev/null 2>&1 && brew list --cask font-0xproto-nerd-font >/dev/null 2>&1; } ||
  font_file_exists '*0xProto*'; then
  ok "0xProto Nerd Font"
else
  fail "0xProto Nerd Font is missing"
fi

config_home="${XDG_CONFIG_HOME:-$user_home/.config}"
config_dir="$config_home/nvim"

if [[ -f "$config_dir/init.lua" && -f "$config_dir/lazy-lock.json" ]]; then
  ok "Neovim config and plugin lock"
else
  fail "expected config at $config_dir"
fi

if [[ $skip_plugins -eq 1 ]]; then
  ok "plugin and Mason checks skipped"
elif command -v nvim >/dev/null 2>&1 && [[ -f "$config_dir/init.lua" ]]; then
  if startup_output="$(NVIM_DOCTOR=1 NVIM_MASON_AUTO_INSTALL=0 nvim --headless "+lua local c=require('lazy.core.config'); local missing={}; for name,p in pairs(c.plugins) do if not p._.installed then table.insert(missing,name) end end; assert(#missing == 0, 'missing plugins: '..table.concat(missing, ', ')); print('startup ok')" "+qa" 2>&1)"; then
    ok "headless startup and pinned plugins"
  else
    fail "Neovim startup failed: $startup_output"
  fi

  if mason_output="$(NVIM_DOCTOR=1 NVIM_MASON_AUTO_INSTALL=0 nvim --headless "+Lazy! load mason.nvim" "+lua local r=require('mason-registry'); local names={'basedpyright','black','json-lsp','lua-language-server','prettier','ruff','shfmt','stylua','vtsls'}; local missing={}; for _,n in ipairs(names) do if not r.is_installed(n) then table.insert(missing,n) end end; assert(#missing == 0, 'missing Mason tools: '..table.concat(missing, ', ')); print('mason ok')" "+qa" 2>&1)"; then
    ok "Mason language and formatting tools"
  else
    fail "$mason_output"
  fi
fi

if git -C "$config_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [[ -z "$(git -C "$config_dir" status --porcelain=v1 -- lazy-lock.json)" ]]; then
    ok "plugin lock matches the checkout"
  else
    fail "lazy-lock.json changed during startup"
  fi
else
  warn "$config_dir is not a Git checkout"
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
if [[ $failures -gt 0 || ($strict -eq 1 && $warnings -gt 0) ]]; then
  exit 1
fi
