# nvim-macos

My reproducible Neovim setup for macOS, based on
[LazyVim](https://www.lazyvim.org/) with every plugin commit locked.

It includes **Dojo**: Neovim as a quiet desktop editor. You open it like
Sublime Text or VS Code, it uses the Cmd shortcuts you already know, and it
stays out of the way: no sidebars you didn't ask for, no badges, no chatter.

## Dojo in one minute

- **Open it** from Spotlight ("Dojo"), the Dock, or a terminal. `dojo ~/code/app`
  (or `v .` in zsh) opens a folder as the project. You can also drop a folder
  onto the Dojo icon.
- **The window opens centred** on the screen under your mouse, and the desktop
  behind it dims while you work (⌘K D turns that off).
- **Open a folder** with ⌘O, the native macOS picker, or ⌘⌥O for recent
  projects. Each project reopens where you left it.
- **See the shortcuts** with ⌘K ⌘S (or `Space ?`): five short pages, including
  one with the Vim basics. ⌘⇧P searches every action.

| You want to… | Press | The Vim way |
| --- | --- | --- |
| Find a file | ⌘P | `Space Space` |
| Search in this file / whole project | ⌘F / ⌘⇧F | `/text` / `Space /` |
| Go to definition / references | F12 (or ⌘-click) / ⇧F12 | `gd` / `gr` |
| Rename a symbol · quick fix | F2 · ⌘. | `Space c r` · `Space c a` |
| Show / hide the file tree | ⌘B | `Space e` |
| Run this file · terminal panel | ⌘R · ⌘J | `Space r r` · `Ctrl-/` |
| Fold a big file, one level at a time | ⌘K ⌘0 · ⌘K ⌘] | `zM` · `zr` |
| Comment · multi-cursor | ⌘/ · ⌘D | `gcc` · `Ctrl-n` |
| Colour theme (previews as you browse) | ⌘K ⌘T | `Space u C` |
| Zen: just the page | ⌘K Z | `Space u z` |

Neovide's own menu keeps ⌘N (new window), ⌘H, ⌘M, ⌘Q and ⌃⌘F.

### Look and feel

- **Type:** Monaspace Neon (the Nerd Font build, "Monaspice") at 15 pt with
  about 1.4 line height. No italics; comments are simply quieter in colour.
- **Colour:** Rosé Pine, Moon when macOS is dark and Dawn when it is light.
  ⌘K ⌘T offers a short list (Catppuccin, Kanso, Tokyo Night and a few pinned
  variants) and recolours the editor live as you move through it.
- **Quiet chrome:** plain tabs, a one-line status bar in the editor's own
  background (file · line and column · language · branch), one tone for file
  icons, no gutter marks, no progress spinners, an instant cursor.
- **Focus:** while Dojo is the active app, a click-through veil dims the rest
  of the screen. A tiny Swift helper (`extras/dojo/dim.swift`) draws it; it
  builds itself on first launch with `swiftc`.
- **Wide screens:** long lines soft-wrap with their indent kept; nothing
  hard-wraps while you type.
- **Sound:** a soft mechanical "thock" while typing and a quiet bell on save
  and run. Toggle with ⌘K M; `NVIM_SFX=0` disables it.

### Terminal (Ghostty)

`extras/ghostty/config` gives Ghostty the same font and theme. Cmd keys reach
Neovim too, through the kitty keyboard protocol, so the table above also works
in `nvim` inside Ghostty. The exceptions are ⌘F, ⌘D, ⌘W, ⌘T and ⌘N, which stay
Ghostty's own; use `/` to search. Don't run nvim inside tmux if you want Cmd
keys.

## Install on a fresh Mac

With Homebrew:

```bash
brew install --cask yask123/dojo/dojo
```

Or without Homebrew (the script installs it):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/yask123/nvim-macos/main/install.sh)"
```

If Neovide or the Monaspice font is already installed by hand, let Homebrew
adopt it first: `brew install --cask --adopt neovide-app font-monaspice-nerd-font`.

The first run may ask for Apple Command Line Tools or Homebrew permissions.
Rerun the same command after completing an Apple system prompt. When it
finishes, open **Dojo** from Spotlight.

The installer:

- installs Neovim, Neovide, Git, search tools, Node, Python, Lua, and the fonts;
- moves any existing Neovim config, plugins, state, and cache to a timestamped
  unique backup under `~/.local/state/nvim-bootstrap/backups/`;
- clones this repository to `~/.config/nvim`;
- restores the exact plugin commits in `lazy-lock.json`;
- installs the configured LSP servers and formatters through Mason;
- links the Neovide and Ghostty configs (never overwriting existing ones),
  adds the zsh helpers, and builds `~/Applications/Dojo.app`;
- installs `nvim-update` in `~/.local/bin` for safe future updates;
- runs a non-destructive doctor at the end.

It does not copy credentials, sessions, undo history, or terminal preferences.

### Inspect before running

```bash
git clone https://github.com/yask123/nvim-macos.git
cd nvim-macos
less install.sh
./install.sh
```

When run from this checkout, the installer uses its committed contents. This
makes the inspected route match what gets installed.

Useful installer switches:

```bash
./install.sh --skip-brew      # Brewfile dependencies and fonts already exist
./install.sh --skip-plugins   # clone only; install plugins on first launch
./install.sh --no-app         # terminal only: skip the Dojo app setup
```

Re-running the installer is safe: the current Neovim directories are moved to
a unique backup before a clean copy is installed. Existing shared Homebrew
packages are not upgraded during the bootstrap.

## What is configured

- Python: basedpyright, Ruff, Black, virtual-environment selection
- TypeScript/JavaScript: vtsls, Prettier, path-safe file runner
- JSON, Lua and Swift (Xcode's sourcekit-lsp) language support; other
  languages install their syntax support the first time you open such a file
- Blink completion (Tab or Enter accepts), Snacks picker and explorer, Lazygit
- folds that open big files as an outline
- debounced auto-save for normal named files only
- quiet diagnostics: errors only, no inline text

### Main custom keys

Leader is the space bar. The full, searchable list is in the app itself
(⌘K ⌘S or `Space ?`); these are the extra keys from before Dojo:

| Key | Action |
| --- | --- |
| `Space r r` | Save and run the current Python, JS/TS, Lua, shell, Go, or Rust file |
| `Space r q` | Close the output panel |
| `Space r i` | Open a Python REPL |
| `Ctrl+\` | Toggle a floating terminal |
| `Ctrl+W` | Close the current buffer (intentional VS Code-style override) |
| `Tab` / `Shift+Tab` | Next / previous buffer |
| `Ctrl+A` / `Ctrl+E` | Line start / end (as in every Mac text field; select all is ⌘A) |
| `Ctrl+N` | Add a cursor at the next match (multicursor.nvim; `Esc` clears) |

All normal LazyVim keys remain available except where explicitly overridden.

The run command uses argument arrays rather than a shell string, so filenames
with spaces or shell punctuation are handled safely. TypeScript uses
`npx --yes tsx@4.19.3` and may download that pinned version on first use. Go
and Rust runners additionally require `go` and `cargo`.

## Check or develop the setup

```bash
~/.config/nvim/scripts/doctor.sh
~/.config/nvim/scripts/doctor.sh --strict  # include optional tools
make format-check
make test
```

`make test` creates isolated temporary XDG directories, restores the pinned
plugins there, checks the runner and Ruff behavior, and verifies that the test
did not mutate the source repository. It also exercises backup-first install
and recoverable uninstall behavior in a temporary home directory.

To apply repository changes on this or another installed Mac without replacing
local state, quit Neovim and run:

```bash
nvim-update
```

The command fast-forwards the tracked Git branch, refuses to overwrite local
config changes, restores the plugin commits pinned in `lazy-lock.json`, installs
the configured editor tools, and runs the doctor. If `~/.local/bin` is not in
your shell's `PATH`, run `~/.local/bin/nvim-update` or add that directory to
`PATH`. Use `nvim-update --skip-plugins` when you only want the config files.

Use `:Lazy update` only when intentionally refreshing plugin versions, then
review and commit the resulting `lazy-lock.json`.

## Reproducibility boundary

Plugin commits are pinned. Homebrew formulae and Mason packages install their
current compatible releases, so system tools can move forward over time. The
doctor and CI smoke test catch compatibility drift. The minimum supported
editor is Neovim 0.11.2 with LuaJIT; the setup is tested on 0.11.5 and 0.12.5.
On 0.11 nvim-treesitter stays pinned to its last compatible commit.

Plugin restores run twice (`scripts/restore-plugins.sh`). lazy.nvim resolves
LazyVim's own plugins only after LazyVim itself is installed, and rewrites the
lockfile in between. A single restore therefore left those plugins at upstream
HEAD. This boundary is intentionally more
maintainable than committing machine binaries or personal authentication.

## Remove or restore

The uninstall is recoverable and does not remove shared Homebrew packages:

```bash
~/.config/nvim/scripts/uninstall.sh
```

It moves the four Neovim directories to
`~/.local/state/nvim-bootstrap/uninstalled/<timestamp>.<unique>/`. Installer
backups use the same `config`, `data`, `state`, and `cache` labels, so individual
directories can be moved back to their original XDG locations if needed.

## License

Apache-2.0. See [LICENSE](LICENSE).
