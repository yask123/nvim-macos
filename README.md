# nvim-macos

My reproducible, learning-friendly Neovim setup for macOS. It is based on
[LazyVim](https://www.lazyvim.org/) and keeps the current plugin commits locked.

## Install on a fresh Mac

One command:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/yask123/nvim-macos/main/install.sh)"
```

The first run may ask for Apple Command Line Tools or Homebrew permissions.
Rerun the same command after completing an Apple system prompt.

The installer:

- installs Neovim, Git, search tools, Node, Python, Lua, and the matching fonts;
- moves any existing Neovim config, plugins, state, and cache to a timestamped
  backup under `~/.local/state/nvim-bootstrap/backups/`;
- clones this repository to `~/.config/nvim`;
- restores the exact plugin commits in `lazy-lock.json`;
- installs the configured LSP servers and formatters through Mason;
- runs a read-only doctor at the end.

It does not copy credentials, Claude authentication, note contents, sessions,
undo history, shell configuration, or terminal preferences.

### Inspect before running

```bash
git clone https://github.com/yask123/nvim-macos.git
cd nvim-macos
less install.sh
./install.sh
```

Useful installer switches:

```bash
./install.sh --skip-brew      # dependencies are already installed
./install.sh --skip-plugins   # clone only; install plugins on first launch
```

Re-running the installer is safe: the current Neovim directories are moved to
a new backup before a clean copy is installed.

## Matching terminal appearance

The Brewfile installs:

- JetBrains Mono, matching the current terminal text;
- 0xProto Nerd Font, which supplies the icons used by LazyVim.

In Warp or another terminal, select **JetBrains Mono** and use **0xProto Nerd
Font Mono** as a fallback if the terminal supports fallback fonts. The current
Warp appearance is 15 pt, 1.4 line height, compact spacing, and Catppuccin
Mocha. Terminal preferences are left alone because overwriting them can affect
unrelated profiles and newer settings.

## What is configured

- Python: basedpyright, Ruff, Black, virtual-environment selection
- TypeScript/JavaScript: vtsls, Prettier, path-safe file runner
- JSON and Lua language support
- Blink completion, FZF search, Neo-tree, Lazygit
- Obsidian-style Markdown notes rooted at `~/notes`
- rendered Markdown and several light/dark themes
- Claude Code integration when the separate `claude` command is installed
- debounced auto-save for normal named files only
- a focused learning view with quiet diagnostics and minimal chrome

### Main custom keys

Leader is the space bar.

| Key | Action |
| --- | --- |
| `Space r r` | Save and run the current Python, JS/TS, Lua, shell, Go, or Rust file |
| `Space r c` | Run again with fresh output |
| `Space r q` | Close the output panel |
| `Space r i` | Open a Python REPL |
| `Space z l` | Toggle the focused learning view |
| `Ctrl+\` | Toggle a floating terminal |
| `Ctrl+W` | Close the current buffer (intentional VS Code-style override) |
| `Tab` / `Shift+Tab` | Next / previous buffer |
| `Ctrl+A` | Select the whole file |
| `gc` | Comment using Mini Comment |
| `Space u C` | Choose and remember a colorscheme |
| `Space n H` | Notes menu |
| `Space a c` | Toggle Claude Code, when installed |

All normal LazyVim keys remain available except where explicitly overridden.

The run command uses argument arrays rather than a shell string, so filenames
with spaces or shell punctuation are handled safely. TypeScript uses `npx tsx`;
Go and Rust runners additionally require `go` and `cargo`.

## Check or develop the setup

```bash
~/.config/nvim/scripts/doctor.sh
make format-check
make test
```

`make test` creates isolated temporary XDG directories, restores the pinned
plugins there, checks the runner and Ruff behavior, and verifies that the test
did not mutate the source repository.

To apply repository changes on another Mac without replacing local state:

```bash
cd ~/.config/nvim
git pull --ff-only
nvim --headless "+Lazy! restore" "+qa"
```

Use `:Lazy update` only when intentionally refreshing plugin versions, then
review and commit the resulting `lazy-lock.json`.

## Reproducibility boundary

Plugin commits are pinned. Homebrew formulae and Mason packages install their
current compatible releases, so system tools can move forward over time. The
doctor and CI smoke test catch compatibility drift; this is intentionally more
maintainable than committing machine binaries or personal authentication.

## Remove or restore

The uninstall is recoverable and does not remove shared Homebrew packages:

```bash
~/.config/nvim/scripts/uninstall.sh
```

It moves the four Neovim directories to
`~/.local/state/nvim-bootstrap/uninstalled/<timestamp>/`. Installer backups use
the same `config`, `data`, `state`, and `cache` labels, so individual directories
can be moved back to their original XDG locations if needed.

## License

Apache-2.0. See [LICENSE](LICENSE).
