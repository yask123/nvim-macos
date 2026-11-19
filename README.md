# nvim-macos

My reproducible Neovim setup for macOS, based on
[LazyVim](https://www.lazyvim.org/) with every plugin commit locked.

It includes **Code**: Neovim as a quiet desktop editor. You open it like
Sublime Text or VS Code, it uses the Cmd shortcuts you already know, and it
stays out of the way: no sidebars you didn't ask for, no badges, no chatter.
(The app was called Dojo until November 2026. The `dojo` command and the code
keep that name: `code` in a terminal already belongs to VS Code.)

## Code in one minute

- **Open it** from Spotlight ("Code"), the Dock, or a terminal. `dojo ~/code/app`
  (or `v .` in zsh) opens a folder as the project. You can also drop a folder
  onto the Code icon.
- **The window opens centred** on the screen under your mouse, and the desktop
  behind it dims while you work (⌘K D turns that off).
- **Open a folder** with ⌘O: a two-column browser inside the window (`h j k l`
  or the arrows, `/` to find, Enter opens). The welcome screen lists your
  recent projects (press 1-9), and ⌘⌥O does the same from anywhere. Each
  project reopens where you left it.
- **Settings** (⌘,) is one small sheet: theme, text size, typing sounds,
  desktop dimming. The config files are a row below, for tinkering.
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
- **Focus:** while Code is the active app, a click-through veil dims the rest
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

## Install

One command, on any Mac running macOS 13 or newer:

```bash
bash -c "$(curl -fsSL https://yask.dev/code/install)"
```

Or with Homebrew:

```bash
brew install yask123/tap/code
```

When it finishes, open **Code** from Spotlight.

The installer checks the Mac first (macOS version, disk space, the network,
Apple's Command Line Tools) and stops with a plain reason if something is in
the way. Then it:

- installs Homebrew if it is missing, and with it Neovim, Git, the search
  tools, Node, Python, Lua, Neovide and the Monaspace font (a font or Neovide
  you installed by hand is left as it is; nothing you already have is upgraded);
- clones this repository to `~/.config/nvim`;
- restores the exact plugin commits in `lazy-lock.json`, and installs the
  language servers and formatters through Mason;
- links the Neovide config (and the Ghostty one, if you use Ghostty), adds the
  zsh helpers, and builds `~/Applications/Code.app`;
- installs `nvim-update` in `~/.local/bin` for safe future updates;
- runs a health check (`scripts/doctor.sh`) and tells you only what needs
  attention.

Each step is one line; everything the tools print goes to
`~/Library/Logs/code-install.log`. If a step fails you see the end of that log
and can run the same command again.

### Upgrading, and what happens to what you had

Run the same command.

- **An earlier Code, or Dojo (its first name):** upgraded in place. The old
  `Dojo.app` and its Homebrew entry are removed, `Code.app` takes their place,
  and your sessions, recent projects, theme and settings stay. The previous
  config folder is set aside under `~/.local/state/nvim-bootstrap/replaced/`
  in case you had edited it. If Code is open, the installer offers to quit it.
- **Some other Neovim setup:** its config, plugins, state and cache move to a
  timestamped backup under `~/.local/state/nvim-bootstrap/backups/`. Nothing
  is deleted.

`--fresh` starts clean even over an earlier install (everything moves to the
backup). Day to day, `nvim-update` is the lighter way to get a new version.

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
./install.sh --no-app         # terminal only: skip the Code app
./install.sh --no-open        # don't open Code when it finishes
./install.sh --yes            # don't ask before quitting a running Code
./install.sh --skip-brew      # the tools and fonts are already installed
./install.sh --skip-plugins   # clone only; install plugins on first launch
```

## What is configured

- Python: basedpyright, Ruff, Black, virtual-environment selection
- TypeScript/JavaScript: vtsls, Prettier, path-safe file runner
- JSON, Lua and Swift (Xcode's sourcekit-lsp) language support; other
  languages install their syntax support the first time you open such a file
- Blink completion (Tab or Enter accepts), Snacks picker and explorer, Lazygit
- a one-line hint of what a call takes while you type it, the argument you
  are on lit up (⌃K lists every way to call it)
- hold `h` `j` `k` `l` and the cursor picks up speed; taps and counts stay exact
- folds that open big files as an outline
- debounced auto-save for normal named files only
- quiet diagnostics: errors only, no inline text

### Main custom keys

Leader is the space bar. The full, searchable list is in the app itself
(⌘K ⌘S or `Space ?`); these are the extra keys from before the app:

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
~/.config/nvim/scripts/doctor.sh           # the health check, in full
~/.config/nvim/scripts/doctor.sh --strict  # warnings count as failures
make format-check
make test
```

`make test` creates isolated temporary XDG directories, restores the pinned
plugins there, checks the runner and Ruff behavior, and verifies that the test
did not mutate the source repository. It also exercises backup-first install,
the in-place upgrade and recoverable uninstall in a temporary home directory.

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
brew uninstall --cask code              # if you installed with Homebrew
~/.config/nvim/scripts/uninstall.sh     # otherwise
```

It removes `Code.app` and moves the four Neovim directories to
`~/.local/state/nvim-bootstrap/uninstalled/<timestamp>.<unique>/`. Installer
backups use the same `config`, `data`, `state`, and `cache` labels, so individual
directories can be moved back to their original XDG locations if needed.

## License

Apache-2.0. See [LICENSE](LICENSE).
